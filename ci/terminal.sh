#!/usr/bin/env bash
# L3: the reference terminal clients in Rust and Python, built from the registries, attach to a channel of the
# published Core, draw its picture, command and ask the Go clock beside them, and follow an event.
# Prints one line per case, as checks/run.sh does, and exits non-zero if any failed.
#
# The Core and the program an operator uses are the published host archive of the newest release the
# manifest names, authenticated against its digest before they run; nothing of the project is built here
# but the clock and the two clients.
# Usage: terminal.sh <python> — the interpreter whose environment holds the Python client's requirements.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python="${1:?usage: terminal.sh <python>}"
manifest_url="${YOKE_MANIFEST:-https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl}"
downloads=https://github.com
ids=(yoke-reference:the-rust-terminal.04 yoke-reference:the-python-terminal.04)

work="$(mktemp -d)"
run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yr.XXXX")"
core=""
trap 'kill "$core" 2> /dev/null; wait "$core" 2> /dev/null; rm -rf "$work" "$run"' EXIT

# fail_all <why>: both cases failed for one reason, before either ran.
fail_all() { for id in "${ids[@]}"; do echo "FAIL  $id — $*"; done; exit 1; }

case "$(uname -m)" in
  x86_64) architecture=amd64 arch=x86_64 ;;
  aarch64 | arm64) architecture=arm64 arch=aarch64 ;;
  *) fail_all "no release for $(uname -m)" ;;
esac
curl -fsSL "$manifest_url" -o "$work/manifest.jsonl" || fail_all "the release manifest cannot be obtained"
host="$(jq -c --arg p "yoke-linux-$architecture" 'select(.line == "publication" and .published == $p)' "$work/manifest.jsonl" \
  | jq -sc 'sort_by(.version | ltrimstr("v") | split(".") | map(tonumber)) | last')"
[[ "$host" != null ]] || fail_all "the manifest names no host archive"
release="$(jq -r .version <<<"$host")"
archive="yoke-${release#v}-linux-$architecture.tar.gz"
curl -fsSL "$downloads/yoke-project/yoke/releases/download/$release/$archive" -o "$work/host.tar.gz" \
  && [[ "sha256:$(sha256sum "$work/host.tar.gz" | cut -d' ' -f1)" == "$(jq -r '.digests[0]' <<<"$host")" ]] \
  || fail_all "the host archive of $release is not the file the manifest names"
tar -xzf "$work/host.tar.gz" -C "$work" yoke-core yoke || fail_all "the host archive holds no yoke-core and yoke"

# The instance: the Go clock beside an attached channel the clients take turns on.
bundle="$work/station"
mkdir -p "$bundle/manifests" "$bundle/components/plugins" "$work/state"
CGO_ENABLED=0 go -C "$root/plugins/go/clock" build -o "$bundle/components/plugins/clock" . || fail_all "the Go clock does not build"
"$bundle/components/plugins/clock" manifest > "$bundle/manifests/com.yoke.reference.clock.yaml" || fail_all "the clock printed no Manifest"
cargo build -q --release --locked --manifest-path "$root/clients/rust/terminal/Cargo.toml" || fail_all "the Rust client does not build"
cat > "$bundle/yoke.yaml" <<YAML
model: 1
id: com.yoke.reference.terminal
version: 1.0.0
arch: $arch
core: ">=0.6.0"
units:
  clock:
    kind: plugin
    plugin: com.yoke.reference.clock
    exec: components/plugins/clock
    digest: "sha256:$(sha256sum "$bundle/components/plugins/clock" | cut -d' ' -f1)"
channels:
  terminal: { transport: local, clients: single }
YAML

export XDG_RUNTIME_DIR="$run" XDG_STATE_HOME="$work/state"
log="$work/core.log"
yoke() { "$work/yoke" "$@" --instance bench-a; }
until_logged() {
  local waited=0
  until grep -qE "$1" "$log" || (( waited >= $2 * 10 )); do sleep 0.1; ((waited++)); done
  grep -qE "$1" "$log"
}

"$work/yoke-core" --instance bench-a --bundle "$bundle" --unverified > "$log" 2>&1 &
core=$!
until_logged 'subject=unit:clock#1 .*to=Running' 60 || fail_all "the clock did not run: $(tail -5 "$log")"
yoke plugin grant com.yoke.reference.clock query.now.answer > /dev/null || fail_all "the question could not be granted"
yoke plugin grant com.yoke.reference.clock command.mark.accept > /dev/null || fail_all "the command could not be granted"
yoke plugin grant com.yoke.reference.clock event.marked.report > /dev/null || fail_all "the occurrence could not be granted"
yoke unit restart clock > /dev/null || fail_all "the clock could not be restarted"
until_logged 'subject=unit:clock#2 .*to=Running' 60 || fail_all "the clock did not run again"

# the_client_is_attached <name> <command…>: the client's output must hold each thing the case requires.
the_client_is_attached() {
  local said why="" status
  said="$("$@" --instance bench-a --channel terminal --command clock:clock.mark --ask clock:clock.now --events 1 2>&1)"
  status=$?
  [[ $status == 0 ]] || why+=" it left with status $status;"
  [[ "$said" == *"terminal: attached to "*"terminal.sock (contract 1)"* ]] || why+=" it did not say it attached;"
  [[ "$said" == *"unit clock Running commands=[clock.mark] queries=[clock.now]"* ]] || why+=" it did not draw the clock with its command and its question;"
  grep -qE 'terminal: command clock:clock.mark OUTCOME_DONE marked at ' <<<"$said" || why+=" the command was not reported done;"
  grep -qE 'terminal: answer clock:clock.now [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' <<<"$said" || why+=" the question was not answered with a time;"
  grep -qE '^event #[0-9]+ unit\.' <<<"$said" || why+=" no event was followed;"
  [[ -z "$why" ]] || { echo "${why# }"; echo "$said" | tail -12; return 1; }
}

status=0
# std: yoke-reference:the-rust-terminal.04
check_the_rust_client() { the_client_is_attached "$root/clients/rust/terminal/target/release/terminal"; }
# std: yoke-reference:the-python-terminal.04
check_the_python_client() { the_client_is_attached "$python" -I "$root/clients/python/terminal/terminal.py"; }
for pair in "${ids[0]} check_the_rust_client" "${ids[1]} check_the_python_client"; do
  read -r id fn <<<"$pair"
  if out="$($fn 2>&1)"; then
    echo "pass  $id"
  else
    echo "FAIL  $id — $out"
    status=1
  fi
done
kill -INT "$core"; wait "$core"; core=""
exit "$status"
