#!/usr/bin/env bash
# L3: each reference Plugin in Rust and Python, built from the registries, is admitted by the published
# Core of the release its library was cut with, and leaves in order when the Core stops. Prints one
# line per case, as checks/run.sh does, and exits non-zero if any failed.
# Usage: admitted.sh <python> — the interpreter whose environment holds the Python clock's requirements.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python="${1:?usage: admitted.sh <python>}"
release=0.4.0
manifest_url=https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl

case "$(uname -m)" in
  x86_64) architecture=amd64 ;;
  aarch64 | arm64) architecture=arm64 ;;
  *) echo "FAIL  the published Core — no release for $(uname -m)"; exit 1 ;;
esac

work="$(mktemp -d)"
trap 'pkill -f "$work/yoke-core" 2> /dev/null; rm -rf "$work"' EXIT

# The Core, as anyone obtains it: downloaded, and authenticated against the manifest before it runs.
obtain_core() {
  local archive="yoke-conformance-$release-linux-$architecture.tar.gz" want got
  curl -fsSL "https://github.com/yoke-project/yoke/releases/download/v$release/$archive" -o "$work/$archive" || return 1
  curl -fsSL "$manifest_url" -o "$work/manifest.jsonl" || return 1
  want="$(jq -r --arg p "yoke-conformance-linux-$architecture" --arg v "v$release" \
    'select(.line == "publication" and .published == $p and .version == $v) | .digests[0]' "$work/manifest.jsonl")"
  got="sha256:$(sha256sum "$work/$archive" | cut -d' ' -f1)"
  [[ -n "$want" && "$want" == "$got" ]] || { echo "the archive's digest $got is not the manifest's $want"; return 1; }
  tar -xzf "$work/$archive" -C "$work" yoke-core
}

# admitted <name> <executable> <pattern>: an instance whose one unit is the clock, run until the unit runs and
# then stopped; succeeds when the Core admitted it with what it declares withheld, opened its Session,
# saw it run, saw the clock close the Session when stopped, and the clock was gone once the Core stopped.
admitted() {
  local name="$1" executable="$2" pattern="$3" inst run log core waited=0
  inst="$work/$name" run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yr.XXXX")" log="$work/$name.log"
  mkdir -p "$inst/state" "$inst/plugins.d/com.yoke.reference.clock" "$inst/plugins"
  "$executable" manifest > "$inst/plugins.d/com.yoke.reference.clock/manifest.yaml" || { echo "$name printed no Manifest"; return 1; }
  cp "$executable" "$inst/plugins/com.yoke.reference.clock"
  printf 'state_dir: %s\nruntime_dir: %s\nplugins:\n  manifests: %s\n  executables: %s\n' \
    "$inst/state" "$run" "$inst/plugins.d" "$inst/plugins" > "$inst/core.yaml"
  printf 'units:\n  clock:\n    kind: plugin\n    plugin: com.yoke.reference.clock\n' > "$inst/deployment.yaml"
  YOKE_CONFIG="$inst/core.yaml" "$work/yoke-core" --composition "$inst/deployment.yaml" > "$log" 2>&1 &
  core=$!
  until grep -q 'subject=unit:clock#1 .*to=Running' "$log" || (( waited >= 30 )); do sleep 1; ((waited++)); done
  kill -INT "$core"; wait "$core"
  rm -rf "$run"
  local why=""
  grep -q 'msg=admission unit=clock plugin=com.yoke.reference.clock outcome=accepted_with_restrictions ' "$log" \
    || why+=" it was not admitted with what it declares withheld;"
  grep -q 'msg=session unit=clock event=opened' "$log" || why+=" its Session did not open;"
  grep -q 'subject=unit:clock#1 .*to=Running' "$log" || why+=" it did not run;"
  grep -q 'msg=session unit=clock ended=closed' "$log" || why+=" its Session did not end by its closing it;"
  grep -q 'subject=unit:clock#1 .*to=Stopped' "$log" || why+=" it did not stop;"
  pgrep -f "$pattern" > /dev/null && why+=" a clock outlived the Core;"
  [[ -z "$why" ]] || { echo "${why# }"; sed -n '1,200p' "$log" | grep -E 'admission|session|unit:clock|refus|clock:' | head -20; return 1; }
}

# std: yoke-reference:the-rust-clock.04
check_the_published_core_admits_the_rust_clock() {
  cargo build -q --release --locked --manifest-path "$root/plugins/rust/clock/Cargo.toml" || { echo "the Rust clock does not build"; return 1; }
  admitted rust "$root/plugins/rust/clock/target/release/clock" "$work/rust/plugins/"
}

# std: yoke-reference:the-python-clock.04
check_the_published_core_admits_the_python_clock() {
  # The Core executes a file; the file starts the clock under the interpreter its requirements are in.
  local launcher="$work/python-clock"
  printf '#!/bin/sh\nexec %s -I %s "$@"\n' "$python" "$root/plugins/python/clock/clock.py" > "$launcher"
  chmod +x "$launcher"
  admitted python "$launcher" "$root/plugins/python/clock/clock.py"
}

if ! out="$(obtain_core 2>&1)"; then
  for id in yoke-reference:the-rust-clock.04 yoke-reference:the-python-clock.04; do echo "FAIL  $id — the published Core: $out"; done
  exit 1
fi
status=0
for pair in "yoke-reference:the-rust-clock.04 check_the_published_core_admits_the_rust_clock" \
            "yoke-reference:the-python-clock.04 check_the_published_core_admits_the_python_clock"; do
  read -r id fn <<<"$pair"
  if out="$("$fn" 2>&1)"; then echo "pass  $id"; else echo "FAIL  $id — $out"; status=1; fi
done
exit "$status"
