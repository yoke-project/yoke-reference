#!/usr/bin/env bash
# L3: acquire, the example's Plugin on the host, under the published Core of the release its library was
# cut with, driving the instrument on a pseudo-terminal through the device its unit binds. Prints one line
# per case, as checks/run.sh does, and exits non-zero if it failed.
#
# The Core and the program an operator uses are the published host archive of the release named here,
# authenticated against the manifest before they run, as signed-in.sh obtains them.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release=0.7.0
manifest_url=https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl
id=yoke-reference:acquire.09

work="$(mktemp -d)"
run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yr.XXXX")"
trap 'kill "$core" "$instrument" 2> /dev/null; wait 2> /dev/null; rm -rf "$work" "$run"' EXIT
core="" instrument=""

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

# acquire and the instrument, built from this repository against the published library.
CGO_ENABLED=0 go -C "$root/plugins/go/acquire" build -o "$work/acquire" . || fail "acquire does not build"
CGO_ENABLED=0 go -C "$root/plugins/go/acquire" build -o "$work/instrument" ./instrument || fail "the instrument does not build"

# The instrument, its lamp drifting from its tenth reading, at the stable name the unit binds.
"$work/instrument" --link "$work/spectro-head-a" --drift-from 10 > "$work/instrument.log" 2>&1 &
instrument=$!
waited=0
until [[ -e "$work/spectro-head-a" ]] || (( waited >= 50 )); do sleep 0.1; ((waited++)); done
[[ -e "$work/spectro-head-a" ]] || fail "the instrument made no link: $(cat "$work/instrument.log")"

mkdir -p "$work/state" "$work/plugins.d/com.yoke.station.acquire" "$work/plugins"
"$work/acquire" manifest > "$work/plugins.d/com.yoke.station.acquire/manifest.yaml" || fail "acquire printed no Manifest"
cp "$work/acquire" "$work/plugins/com.yoke.station.acquire"
printf 'state_dir: %s/state\nruntime_dir: %s\nplugins:\n  manifests: %s/plugins.d\n  executables: %s/plugins\n' "$work" "$run" "$work" "$work" > "$work/core.yaml"
cat > "$work/deployment.yaml" <<YAML
units:
  acquire:
    kind: plugin
    plugin: com.yoke.station.acquire
    args: [ "--device", "\${bind.instrument}", "--label", "bench a", "--period", "250ms" ]
    bind: { instrument: "$work/spectro-head-a" }
YAML

log="$work/core.log"
yoke() { YOKE_CONFIG="$work/core.yaml" "$work/yoke" "$@"; }
# until_logged <pattern> <seconds>: waits for the Core to log a line matching the pattern.
until_logged() {
  local waited=0
  until grep -qE "$1" "$log" || (( waited >= $2 * 10 )); do sleep 0.1; ((waited++)); done
  grep -qE "$1" "$log"
}

# A beat the Core does not receive ends a Session within this long after it opened.
liveness=40

# std: yoke-reference:acquire.09
check_the_published_core_admits_acquire_on_its_device() {
  YOKE_CONFIG="$work/core.yaml" "$work/yoke-core" --composition "$work/deployment.yaml" > "$log" 2>&1 &
  core=$!
  until_logged 'subject=unit:acquire#1 .*to=Running' 30 || { echo "the first incarnation did not run"; tail -20 "$log"; return 1; }
  yoke plugin grant com.yoke.station.acquire stream.spectra.publish > /dev/null || { echo "the spectra stream could not be granted"; return 1; }
  yoke plugin grant com.yoke.station.acquire occurrence.calibration.drift.report > /dev/null || { echo "the drift could not be granted"; return 1; }
  yoke unit restart acquire > /dev/null || { echo "the unit could not be restarted"; return 1; }
  until_logged 'subject=unit:acquire#2 .*to=Running' 30 || { echo "the second incarnation did not run"; tail -20 "$log"; return 1; }
  yoke stream start acquire station.spectra > /dev/null || { echo "the spectra stream could not be started"; return 1; }
  sleep 2
  yoke stream stop acquire station.spectra > /dev/null || { echo "the spectra stream could not be stopped"; return 1; }
  local refused=no
  yoke stream start acquire station.diagnostics > "$work/diagnostics.out" 2>&1 || refused=yes
  until_logged 'occurrence=calibration.drift' 10
  sleep "$liveness"
  kill -INT "$core"; wait "$core"; core=""

  local why=""
  grep -E 'msg=admission unit=acquire ' "$log" | sed -n 1p | grep -q 'outcome=accepted_with_restrictions' \
    || why+=" the first incarnation was not admitted with what it declares withheld;"
  grep -E 'msg=admission unit=acquire ' "$log" | sed -n 2p | grep -q 'outcome=accepted_with_restrictions' \
    || why+=" the second incarnation was not admitted with restrictions;"
  grep -qE 'msg=stream unit=acquire stream=station.spectra event=stopped reason=asked read=[1-9]' "$log" \
    || why+=" the spectra stream read nothing;"
  grep -qE 'msg=stream unit=acquire stream=station.spectra .*fault=' "$log" && why+=" the spectra stream faulted;"
  [[ "$refused" == yes ]] && grep -q 'scope.withheld' "$work/diagnostics.out" \
    || why+=" starting station.diagnostics was not refused as withheld;"
  grep -qE 'type=unit.occurrence.reported subject=unit:acquire#2 severity=50 .*occurrence=calibration.drift' "$log" \
    || why+=" calibration.drift was not reported with severity 50;"
  grep -q 'msg=session unit=acquire ended=revoked' "$log" && why+=" its Session was revoked;"
  grep -q 'subject=unit:acquire#3 ' "$log" && why+=" it was started a third time;"
  grep -q 'msg=session unit=acquire ended=closed' "$log" || why+=" its Session did not end by its closing it;"
  grep -q 'subject=unit:acquire#2 .*to=Stopped' "$log" || why+=" it did not stop;"
  pgrep -f "$work/plugins/" > /dev/null && why+=" acquire outlived the Core;"
  [[ -z "$why" ]] || { echo "${why# }"; grep -E 'admission|session|stream|occurrence|unit:acquire|refus|acquire:' "$log" | head -30; return 1; }
}

if out="$(check_the_published_core_admits_acquire_on_its_device 2>&1)"; then
  echo "pass  $id"
else
  fail "$out"
fi
