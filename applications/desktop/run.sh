#!/usr/bin/env bash
# Runs the desktop bench by hand: writes it with compose.sh where it is not written, runs it on a local
# Core, grants hw-monitor what its Manifest declares, and starts bench.qml beside it, as a compositor
# starts a shell. Closing the document's window, or an interrupt, stops everything.
#
# Usage: run.sh <QML import path>
#   the directory holding Yoke/Interface, where the C++ family was installed with its QML binding —
#   what find_package(yoke-sdk-cpp COMPONENTS qml) names YOKE_SDK_CPP_QML_IMPORT_PATH
# The project is written into $DESKTOP_BENCH (by default ~/.cache/yoke-desktop-bench).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
imports="${1:?usage: run.sh <QML import path>}"
dir="${DESKTOP_BENCH:-$HOME/.cache/yoke-desktop-bench}"
qml="${QML_RUNTIME:-$(command -v qml || echo /usr/lib/qt6/bin/qml)}"

[[ -f "$dir/yoke.yaml" ]] || bash "$here/compose.sh" yoke-compose "$dir" "$(uname -m)"

log="$(mktemp)"
yoke app run --from "$dir" > "$log" 2>&1 &
app=$!
trap 'kill -INT "$app" 2> /dev/null; wait "$app" 2> /dev/null; rm -f "$log"' EXIT
until grep -q 'is observable' "$log"; do
  kill -0 "$app" 2> /dev/null || { cat "$log" >&2; exit 1; }
  sleep 0.3
done
instance="$(sed -n '1s/ runs .*//p' "$log")"
export YOKE_INSTANCE="$instance"

# A run's instance starts with nothing granted; a grant reaches the unit at its next admission.
for capability in $(sed -n 's/^  - name: //p' "$dir/manifests/com.yoke.hw-monitor.yaml"); do
  yoke plugin grant com.yoke.hw-monitor "$capability" > /dev/null
done
yoke unit restart hw-monitor > /dev/null
echo "run.sh: $instance runs; bench.qml attaches to its channel desktop"
"$qml" -I "$imports" "$here/bench.qml" -- --instance "$instance" --channel desktop
