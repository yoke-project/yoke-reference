#!/usr/bin/env bash
# L3: pipeline, the example's Plugin in a container, under the published Core of the release its library
# was cut with, its image built here and run by Podman. Prints one line per case, as checks/run.sh does,
# and exits non-zero if it failed.
#
# The Core and the program an operator uses are the published host archive of the release named here,
# authenticated against the manifest before they run, as station.sh obtains them.
# Usage: pipeline.sh <python> — the interpreter whose environment holds pipeline's requirements.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python="${1:?usage: pipeline.sh <python>}"
release=0.6.0
manifest_url=https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl
id=yoke-reference:pipeline.05
image=localhost/yoke-reference-pipeline

work="$(mktemp -d)"
run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yr.XXXX")"
core="" engine=""
trap 'kill "$core" 2> /dev/null; wait "$core" 2> /dev/null; kill "$engine" 2> /dev/null;
      podman rmi -f "$image:l3" > /dev/null 2>&1; rm -rf "$work" "$run"' EXIT

fail() { echo "FAIL  $id — $*"; exit 1; }

case "$(uname -m)" in
  x86_64) architecture=amd64 ;;
  aarch64 | arm64) architecture=arm64 ;;
  *) fail "no release for $(uname -m)" ;;
esac
archive="yoke-$release-linux-$architecture.tar.gz"
curl -fsSL "https://github.com/yoke-project/yoke/releases/download/v$release/$archive" -o "$work/$archive" \
  && curl -fsSL "$manifest_url" -o "$work/manifest.jsonl" || fail "the host archive of $release cannot be obtained"
want="$(jq -r --arg p "yoke-linux-$architecture" --arg v "v$release" \
  'select(.line == "publication" and .published == $p and .version == $v) | .digests[0]' "$work/manifest.jsonl")"
got="sha256:$(sha256sum "$work/$archive" | cut -d' ' -f1)"
[[ -n "$want" && "$want" == "$got" ]] || fail "the archive's digest $got is not the manifest's $want"
tar -xzf "$work/$archive" -C "$work" yoke-core yoke || fail "the archive holds no yoke-core and yoke"

# Podman, serving its API on a socket of the case's own, and pipeline's image, named by its digest.
podman system service --time=0 "unix://$work/podman.sock" > "$work/podman.log" 2>&1 &
engine=$!
waited=0
until curl -fs --unix-socket "$work/podman.sock" http://engine/_ping > /dev/null 2>&1 || (( waited >= 100 )); do sleep 0.1; ((waited++)); done
curl -fs --unix-socket "$work/podman.sock" http://engine/_ping > /dev/null 2>&1 || fail "Podman did not answer: $(cat "$work/podman.log")"
podman build -q -t "$image:l3" "$root/plugins/python/pipeline" > "$work/build.log" 2>&1 || fail "the image does not build: $(tail -5 "$work/build.log")"
digest="$(podman images --digests --format '{{.Digest}}' "$image:l3" | head -n1)"
[[ "$digest" == sha256:* ]] || fail "the image has no digest"

# A container is a unit of the application form: the project's working directory is the bundle, and the
# Core is executed on it with the engine's address, as `yoke app run --from` would.
bundle="$work/station"
mkdir -p "$bundle/manifests" "$work/state"
"$python" -I "$root/plugins/python/pipeline/pipeline.py" manifest > "$bundle/manifests/com.yoke.station.pipeline.yaml" \
  || fail "pipeline printed no Manifest"
cat > "$bundle/yoke.yaml" <<YAML
model: 1
id: com.yoke.station
version: 2.1.0
arch: $( [[ $architecture == amd64 ]] && echo x86_64 || echo aarch64 )
core: ">=0.6.0"
units:
  pipeline:
    kind: plugin
    plugin: com.yoke.station.pipeline
    image: "$image@$digest"
    args: [ "--site", "bench a" ]
YAML

log="$work/core.log"
export XDG_RUNTIME_DIR="$run" XDG_STATE_HOME="$work/state"
yoke() { "$work/yoke" "$@" --instance bench-a; }
until_logged() {
  local waited=0
  until grep -qE "$1" "$log" || (( waited >= $2 * 10 )); do sleep 0.1; ((waited++)); done
  grep -qE "$1" "$log"
}

# std: yoke-reference:pipeline.05
check_the_published_core_runs_pipelines_image_and_it_answers() {
  "$work/yoke-core" --instance bench-a --bundle "$bundle" --unverified --engine "unix://$work/podman.sock" > "$log" 2>&1 &
  core=$!
  until_logged 'subject=unit:pipeline#1 .*to=Running' 120 || { echo "the first incarnation did not run"; tail -20 "$log"; return 1; }
  yoke plugin grant com.yoke.station.pipeline query.identify.answer > /dev/null || { echo "the question could not be granted"; return 1; }
  yoke unit restart pipeline > /dev/null || { echo "the unit could not be restarted"; return 1; }
  until_logged 'subject=unit:pipeline#2 .*to=Running' 120 || { echo "the second incarnation did not run"; tail -20 "$log"; return 1; }
  python3 -c 'import json; print(json.dumps({"label": "bench a", "scan": 1, "counts": [1000 - 10 * (b - 8) ** 2 for b in range(16)]}))' > "$work/spectrum.json"
  yoke unit ask pipeline spectrum.identify --input "$work/spectrum.json" > "$work/answer.out" 2>&1
  local containers
  containers="$(podman --url "unix://$work/podman.sock" ps --format '{{.Image}}' 2>/dev/null)"
  kill -INT "$core"; wait "$core"; core=""

  local why=""
  grep -E 'msg=admission unit=pipeline ' "$log" | sed -n 1p | grep -q 'outcome=accepted_with_restrictions' \
    || why+=" the first incarnation was not admitted with what it declares withheld;"
  grep -E 'msg=admission unit=pipeline ' "$log" | sed -n 2p | grep -q 'outcome=accepted_with_restrictions' \
    || why+=" the second incarnation was not admitted with restrictions;"
  [[ "$containers" == *"$image"* ]] || why+=" it did not run in a container of its image;"
  grep -q '"site": "bench a"' "$work/answer.out" && grep -q '"peak_bin": 8' "$work/answer.out" && grep -q '"line": "lamp"' "$work/answer.out" \
    || why+=" the question was answered: $(tr '\n' ' ' < "$work/answer.out");"
  grep -q 'msg=session unit=pipeline ended=revoked' "$log" && why+=" its Session was revoked;"
  grep -q 'msg=session unit=pipeline ended=closed' "$log" || why+=" its Session did not end by its closing it;"
  grep -q 'subject=unit:pipeline#2 .*to=Stopped' "$log" || why+=" it did not stop;"
  [[ -z "$why" ]] || { echo "${why# }"; grep -E 'admission|session|unit:pipeline|refus|pipeline:|engine' "$log" | head -30; return 1; }
}

if out="$(check_the_published_core_runs_pipelines_image_and_it_answers 2>&1)"; then
  echo "pass  $id"
else
  fail "$out"
fi
