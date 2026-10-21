#!/usr/bin/env bash
# The LVGL panel: built against the C family's newest source release, as any consumer obtains it, and against
# LVGL, by the digest CMake pins; its L1 cases run, and then L3 — the published Core launching it as a managed
# interface beside the Go clock.
# Prints one line per case, as checks/run.sh does, and exits non-zero if any failed.
#
# The Core, the program an operator uses and the C family's source are published artifacts, each
# authenticated against the release manifest before it is used, and nothing of the project is built here
# but the panel and the clock, and LVGL, which CMake takes from its release by its digest.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_url="${YOKE_MANIFEST:-https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl}"
downloads=https://github.com
l3=yoke-reference:the-lvgl-panel.06
l1=(yoke-reference:the-lvgl-panel.01 yoke-reference:the-lvgl-panel.02 yoke-reference:the-lvgl-panel.03 yoke-reference:the-lvgl-panel.04 yoke-reference:the-lvgl-panel.05)

work="$(mktemp -d)"
run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yr.XXXX")"
core=""
trap 'kill "$core" 2> /dev/null; wait "$core" 2> /dev/null; rm -rf "$work" "$run"' EXIT

# fail_all <why>: every case of the panel failed for one reason, before any of them ran.
fail_all() { for id in "${l1[@]}" "$l3"; do echo "FAIL  $id — $*"; done; exit 1; }
fail() { echo "FAIL  $l3 — $*"; exit 1; }

case "$(uname -m)" in
  x86_64) architecture=amd64 arch=x86_64 ;;
  aarch64 | arm64) architecture=arm64 arch=aarch64 ;;
  *) fail_all "no release for $(uname -m)" ;;
esac
curl -fsSL "$manifest_url" -o "$work/manifest.jsonl" || fail_all "the release manifest cannot be obtained"

# newest <published>: the newest version the manifest names for a publication, and its line.
newest() {
  jq -c --arg p "$1" 'select(.line == "publication" and .published == $p)' "$work/manifest.jsonl" \
    | jq -sc 'sort_by(.version | ltrimstr("v") | split(".") | map(tonumber)) | last'
}
# obtain <url> <file> <digest>: a file downloaded and authenticated by the digest its line carries.
obtain() {
  curl -fsSL "$1" -o "$2" || return 1
  [[ "sha256:$(sha256sum "$2" | cut -d' ' -f1)" == "$3" ]]
}

# The C family, as its source release, installed under a prefix of the case's own.
family="$(newest yoke-sdk-c-source)"
[[ "$family" != null ]] || fail_all "the manifest names no source release of the C family"
fver="$(jq -r .version <<<"$family")"
obtain "$(jq -r .where <<<"$family" | sed 's#/releases/tag/#/releases/download/#')/yoke-sdk-c-${fver#v}-source.tar.gz" \
  "$work/sdk.tar.gz" "$(jq -r '.digests[0]' <<<"$family")" || fail_all "the C family's $fver source is not the file the manifest names"
mkdir -p "$work/sdk" && tar -xzf "$work/sdk.tar.gz" -C "$work/sdk" --strip-components=1 || fail_all "the C family's source does not unpack"
{ cmake -S "$work/sdk" -B "$work/sdk-build" -DCMAKE_BUILD_TYPE=Release && cmake --build "$work/sdk-build" --target yoke-c --parallel \
    && cmake --install "$work/sdk-build" --prefix "$work/prefix"; } > "$work/sdk.log" 2>&1 \
  || fail_all "the C family $fver does not build and install: $(tail -5 "$work/sdk.log")"

# The panel, built against it as any consumer builds, and its L1 cases.
{ cmake -S "$root/clients/lvgl/panel" -B "$work/panel" -DCMAKE_PREFIX_PATH="$work/prefix" \
    && cmake --build "$work/panel" --parallel; } > "$work/panel.log" 2>&1 \
  || fail_all "the panel does not build against yoke-sdk-c $fver: $(grep -m3 error "$work/panel.log")"
status=0
"$work/panel/panel_test" 2> /dev/null || status=1

# L3: the published Core, the panel a managed interface on its channel beside the Go clock.
host="$(newest yoke-linux-$architecture)"
release="$(jq -r .version <<<"$host")"
obtain "$downloads/yoke-project/yoke/releases/download/$release/yoke-${release#v}-linux-$architecture.tar.gz" \
  "$work/host.tar.gz" "$(jq -r '.digests[0]' <<<"$host")" || fail "the host archive of $release is not the file the manifest names"
tar -xzf "$work/host.tar.gz" -C "$work" yoke-core yoke || fail "the host archive holds no yoke-core and yoke"

bundle="$work/station"
mkdir -p "$bundle/manifests" "$bundle/components/plugins" "$bundle/components/interfaces" "$work/state"
CGO_ENABLED=0 go -C "$root/plugins/go/clock" build -o "$bundle/components/plugins/clock" . || fail "the Go clock does not build"
"$bundle/components/plugins/clock" manifest > "$bundle/manifests/com.yoke.reference.clock.yaml" || fail "the clock printed no Manifest"
cp "$work/panel/panel" "$bundle/components/interfaces/panel"
digest() { echo "sha256:$(sha256sum "$1" | cut -d' ' -f1)"; }
cat > "$bundle/yoke.yaml" <<YAML
model: 1
id: com.yoke.station
version: 2.1.0
arch: $arch
core: ">=0.6.0"
units:
  clock:
    kind: plugin
    plugin: com.yoke.reference.clock
    exec: components/plugins/clock
    digest: "$(digest "$bundle/components/plugins/clock")"
  panel:
    kind: interface
    exec: components/interfaces/panel
    digest: "$(digest "$bundle/components/interfaces/panel")"
    env: { PANEL_DISPLAY: offscreen }
    depends_on: [ clock ]
channels:
  panel: { unit: panel, transport: local, clients: single }
YAML

export XDG_RUNTIME_DIR="$run" XDG_STATE_HOME="$work/state"
log="$work/core.log"
yoke() { "$work/yoke" "$@" --instance bench-a; }
until_logged() {
  local waited=0
  until grep -qE "$1" "$log" || (( waited >= $2 * 10 )); do sleep 0.1; ((waited++)); done
  grep -qE "$1" "$log"
}

# std: yoke-reference:the-lvgl-panel.06
check_the_published_core_launches_the_panel_on_its_channel() {
  "$work/yoke-core" --instance bench-a --bundle "$bundle" --unverified > "$log" 2>&1 &
  core=$!
  until_logged 'subject=unit:panel#1 .*to=Running' 60 || { echo "the panel did not run"; tail -20 "$log"; return 1; }
  yoke plugin grant com.yoke.reference.clock query.now.answer > /dev/null || { echo "the question could not be granted"; return 1; }
  yoke plugin grant com.yoke.reference.clock command.mark.accept > /dev/null || { echo "the command could not be granted"; return 1; }
  yoke unit restart clock > /dev/null || { echo "the clock could not be restarted"; return 1; }
  until_logged 'subject=unit:clock#2 .*to=Running' 60 || { echo "the clock did not run again"; return 1; }
  local said="" waited=0
  until [[ "$said" == *"updated: unit clock Running commands=[clock.mark] queries=[clock.now]"* ]] || (( waited >= 30 )); do
    sleep 1; ((waited++))
    said="$(yoke log query --unit panel 2>&1)"
  done
  kill -INT "$core"; wait "$core"; core=""

  local why=""
  [[ "$said" == *"panel: attached to "* ]] || why+=" the panel did not say it attached;"
  [[ "$said" == *"composed: unit clock "* ]] || why+=" the panel did not compose the clock from the opening;"
  [[ "$said" == *"updated: unit clock Running commands=[clock.mark] queries=[clock.now]"* ]] \
    || why+=" the panel did not keep the clock current, with its command and its question;"
  grep -q 'subject=unit:panel#1 .*to=Stopped' "$log" || why+=" the panel did not stop;"
  pgrep -f "$bundle/components/interfaces/panel" > /dev/null && why+=" the panel outlived the Core;"
  [[ -z "$why" ]] || { echo "${why# }"; echo "$said" | tail -8; grep -E 'unit:panel|unit:clock|refus' "$log" | head -20; return 1; }
}

if out="$(check_the_published_core_launches_the_panel_on_its_channel 2>&1)"; then
  echo "pass  $l3"
else
  echo "FAIL  $l3 — $out"
  status=1
fi
exit "$status"
