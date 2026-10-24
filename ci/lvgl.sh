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
l1=(yoke-reference:the-lvgl-panel.01 yoke-reference:the-lvgl-panel.02 yoke-reference:the-lvgl-panel.03 yoke-reference:the-lvgl-panel.04 yoke-reference:the-lvgl-panel.05 yoke-reference:the-lvgl-panel.07 yoke-reference:the-lvgl-panel.08 yoke-reference:the-lvgl-panel.09)

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

# say <id> <why>: one case's line, failing when it names a reason.
say() { if [[ -z "$2" ]]; then echo "pass  $1"; else echo "FAIL  $1 — $2"; status=1; fi; }

# std: yoke-reference:the-lvgl-panel.07
check_the_panel_builds_against_an_lvgl_the_build_provides() {
  local lvgl="$work/lvgl" built
  mkdir -p "$lvgl/conf" && cp "$root/clients/lvgl/panel/lv_conf.h" "$lvgl/conf/"
  obtain https://github.com/lvgl/lvgl/archive/refs/tags/v9.6.0.tar.gz "$lvgl/lvgl.tar.gz" \
    "sha256:$(sed -nE 's/.*SHA256=([0-9a-f]{64}).*/\1/p' "$root/clients/lvgl/panel/CMakeLists.txt")" \
    || { echo "LVGL's release is not the file the panel pins"; return 1; }
  mkdir -p "$lvgl/src" && tar -xzf "$lvgl/lvgl.tar.gz" -C "$lvgl/src" --strip-components=1
  { cmake -S "$lvgl/src" -B "$lvgl/build" -DLV_BUILD_CONF_DIR="$lvgl/conf" -DBUILD_SHARED_LIBS=ON \
      -DCONFIG_LV_BUILD_EXAMPLES=OFF -DCONFIG_LV_BUILD_DEMOS=OFF -DCMAKE_INSTALL_PREFIX="$lvgl/prefix" \
      && cmake --build "$lvgl/build" --parallel && cmake --install "$lvgl/build"; } > "$lvgl/build.log" 2>&1 \
    || { echo "LVGL does not build and install: $(tail -3 "$lvgl/build.log")"; return 1; }
  built="$work/panel-provided"
  { PKG_CONFIG_PATH="$lvgl/prefix/lib/pkgconfig:$lvgl/prefix/share/pkgconfig" \
      cmake -S "$root/clients/lvgl/panel" -B "$built" -DCMAKE_PREFIX_PATH="$work/prefix" -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
      && cmake --build "$built" --parallel --target panel; } > "$built.log" 2>&1 \
    || { echo "the panel does not build against the LVGL provided: $(grep -m3 -iE 'error' "$built.log")"; return 1; }
  readelf -d "$built/panel" | grep -q 'NEEDED.*liblvgl\.so' || { echo "the panel does not link the LVGL provided"; return 1; }
  find "$built" -name 'lvgl*.tar.gz' -o -name '_deps' | grep -q . && { echo "the build downloaded LVGL"; return 1; }
  return 0
}

# std: yoke-reference:the-lvgl-panel.08
check_the_panel_is_refused_with_no_lvgl_and_no_download() {
  local refused="$work/panel-refused"
  if PKG_CONFIG_PATH="$work/nothing" cmake -S "$root/clients/lvgl/panel" -B "$refused" -DCMAKE_PREFIX_PATH="$work/prefix" \
       -DFETCHCONTENT_FULLY_DISCONNECTED=ON > "$refused.log" 2>&1; then
    echo "the configuration was not refused"; return 1
  fi
  grep -A3 'CMake Error' "$refused.log" | grep -q 'LVGL' || { echo "the refusal does not name LVGL: $(grep -m1 -A2 'CMake Error' "$refused.log")"; return 1; }
}

# std: yoke-reference:the-lvgl-panel.09
check_the_panel_is_refused_when_lvgls_headers_do_not_compile() {
  local broken="$work/lvgl-broken" refused="$work/panel-broken"
  mkdir -p "$broken/include/lvgl" "$broken/lib/pkgconfig"
  printf '#include <a_header_that_is_nowhere.h>\n' > "$broken/include/lvgl/lvgl.h"
  printf 'prefix=%s\nincludedir=${prefix}/include/lvgl\nlibdir=${prefix}/lib\n\nName: lvgl\nDescription: a broken LVGL\nVersion: 9.4.0\nCflags: -I${includedir}\nLibs: -L${libdir} -llvgl\n' \
    "$broken" > "$broken/lib/pkgconfig/lvgl.pc"
  if PKG_CONFIG_PATH="$broken/lib/pkgconfig" cmake -S "$root/clients/lvgl/panel" -B "$refused" -DCMAKE_PREFIX_PATH="$work/prefix" \
       -DFETCHCONTENT_FULLY_DISCONNECTED=ON > "$refused.log" 2>&1; then
    echo "the configuration was not refused"; return 1
  fi
  local said
  said="$(grep -A4 'CMake Error' "$refused.log")"
  grep -qi 'headers do not compile' <<<"$said" || { echo "the refusal does not say LVGL's headers do not compile: $said"; return 1; }
  grep -qi 'framebuffer' <<<"$said" && { echo "the refusal says the framebuffer driver is missing: $said"; return 1; }
  return 0
}

for each in "yoke-reference:the-lvgl-panel.07 check_the_panel_builds_against_an_lvgl_the_build_provides" \
            "yoke-reference:the-lvgl-panel.08 check_the_panel_is_refused_with_no_lvgl_and_no_download" \
            "yoke-reference:the-lvgl-panel.09 check_the_panel_is_refused_when_lvgls_headers_do_not_compile"; do
  read -r id fn <<<"$each"
  if out="$("$fn" 2>&1)"; then say "$id" ""; else say "$id" "$out"; fi
done

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
check_the_published_core_launches_the_lvgl_panel_on_its_channel() {
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

if out="$(check_the_published_core_launches_the_lvgl_panel_on_its_channel 2>&1)"; then
  echo "pass  $l3"
else
  echo "FAIL  $l3 — $out"
  status=1
fi
exit "$status"
