#!/usr/bin/env bash
# Measures the desktop bench on this host and writes the table: the time from a question and from a
# stream's start or stop to its answer; the time from a frame's production to the document's handler,
# where a QML property is set; the wakeups of the Core, of hw-monitor and of the document, at rest and with
# the streams flowing; their resident memory; and the time from starting the application, and from
# starting the document, to the first picture.
#
# Usage: measure.sh <QML import path> [rest seconds] [flowing seconds] [results file]
#   the import path is the directory holding Yoke/Interface, as for run.sh; results go to results.md
#   beside this script unless a file is named
# A wakeup is counted as a context switch, voluntary or not, of any of a process's threads: what a
# process costs a laptop at rest is how often it is scheduled.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
imports="${1:?usage: measure.sh <QML import path> [rest seconds] [flowing seconds] [results file]}"
rest="${2:-30}" flowing="${3:-30}" results="${4:-$here/results.md}"
dir="${DESKTOP_BENCH:-$HOME/.cache/yoke-desktop-bench}"
qml="${QML_RUNTIME:-$(command -v qml || echo /usr/lib/qt6/bin/qml)}"
# With no display, the documents draw offscreen; on a desktop they draw on it, as a shell would.
[[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] || export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
work="$(mktemp -d)"
app="" document=""
trap '[[ -n "$document" ]] && kill "$document" 2> /dev/null; [[ -n "$app" ]] && { kill -INT "$app" 2> /dev/null; wait "$app" 2> /dev/null; }; rm -rf "$work"' EXIT

now_ms() { date +%s%3N; }
# switches <pid>: the context switches of every thread of a process so far.
switches() {
  cat /proc/"$1"/task/*/status 2> /dev/null | awk '/_ctxt_switches/ { n += $2 } END { print n + 0 }'
}
rss_mb() { awk '/^VmRSS/ { printf "%.1f", $2 / 1024 }' /proc/"$1"/status; }
# until_line <file> <pattern> [seconds]: waits for a line, and prints the time it was seen.
until_line() {
  local waited=0 limit=$(( ${3:-60} * 100 ))
  until grep -qE "$2" "$1"; do
    (( waited++ < limit )) || { echo "measure.sh: '$2' never appeared in $1" >&2; tail -5 "$1" >&2; exit 1; }
    sleep 0.01
  done
  now_ms
}

[[ -f "$dir/yoke.yaml" ]] || bash "$here/compose.sh" yoke-compose "$dir" "$(uname -m)"

# The application, from its start to hw-monitor running with what its Manifest declares granted.
started_app="$(now_ms)"
yoke app run --from "$dir" > "$work/app.log" 2>&1 &
app=$!
until_line "$work/app.log" 'is observable' > /dev/null
instance="$(sed -n '1s/ runs .*//p' "$work/app.log")"
export YOKE_INSTANCE="$instance"
for capability in $(sed -n 's/^  - name: //p' "$dir/manifests/com.yoke.hw-monitor.yaml"); do
  yoke plugin grant com.yoke.hw-monitor "$capability" > /dev/null
done
yoke unit restart hw-monitor > /dev/null
sleep 1

# The first picture: bench.qml started, to its snapshot drawn and its first frame of each stream.
started_doc="$(now_ms)"
"$qml" -I "$imports" "$here/bench.qml" -- --instance "$instance" > "$work/bench.log" 2>&1 &
document=$!
attached="$(until_line "$work/bench.log" 'bench: attached ')"
snapshot="$(until_line "$work/bench.log" 'bench: snapshot ')"
first_frame="$(until_line "$work/bench.log" 'bench: hw\.(cpu|memory) [0-9]+')"
kill "$document"; wait "$document" 2> /dev/null || true; document=""
sleep 1

# The measuring document, through its phases, the processes' counters read at each phase's edges.
"$qml" -I "$imports" "$here/measure.qml" -- --instance "$instance" --rest "$rest" --flowing "$flowing" > "$work/measure.log" 2>&1 &
document=$!
core="$(pgrep -n -f -- "yoke-core .*--instance $instance")"
monitor="$(pgrep -n -f -- "components/plugins/hw-monitor")"
declare -A at
for edge in "rest begins" "rest ends" "flowing begins" "flowing ends"; do
  until_line "$work/measure.log" "measure: phase $edge" $(( rest + flowing + 60 )) > /dev/null
  for who in core monitor document; do at["$edge $who"]="$(switches "${!who}")"; done
  at["$edge time"]="$(sed -n "s/.*measure: phase $edge \([0-9]*\)$/\1/p" "$work/measure.log")"
  [[ "$edge" == "flowing ends" ]] && for who in core monitor document; do at["rss $who"]="$(rss_mb "${!who}")"; done
done
wait "$document" 2> /dev/null || true; document=""
grep -q 'measure: failed' "$work/measure.log" && { grep 'measure: failed' "$work/measure.log" >&2; exit 1; }

# per_second <phase> <who>: the wakeups per second of one process across one phase.
per_second() {
  awk -v a="${at["$1 begins $2"]}" -v b="${at["$1 ends $2"]}" -v t0="${at["$1 begins time"]}" -v t1="${at["$1 ends time"]}" \
    'BEGIN { printf "%.1f", (b - a) / ((t1 - t0) / 1000) }'
}
drew="on the desktop"
[[ -n "${QT_QPA_PLATFORM:-}" ]] && drew="on the $QT_QPA_PLATFORM platform of Qt"
[[ -f /run/.containerenv || -f /.dockerenv ]] && drew+=", in a container"
figure() { sed -n "s/.*measure: $1 n=\([0-9]*\) mean=\([0-9.]*\) worst=\([0-9.]*\)$/\2 \/ \3 ms (n=\1)/p" "$work/measure.log"; }

{
  echo "# Desktop bench measurements"
  echo
  echo "$(date -u +%Y-%m-%dT%H:%MZ) on $(hostname), $(uname -r), $(yoke --version 2>&1 | head -1), Qt $("$qml" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)."
  echo "The documents drew $drew."
  echo "Rest $rest s, flowing $flowing s; hw-monitor reads the machine every second. Times are milliseconds on this host's clock, read with a resolution of 1 ms."
  echo
  echo "| Figure | Value |"
  echo "| --- | --- |"
  echo "| Question \`hw.snapshot\`, asked to answered (mean / worst) | $(figure ask) |"
  echo "| Stream start or stop, asked to acknowledged (mean / worst) | $(figure acknowledge) |"
  echo "| Frame, produced to the QML handler that sets a property (mean / worst) | $(figure frame) |"
  echo "| Application started to hw-monitor granted and running | $(( started_doc - started_app - 1000 )) ms |"
  echo "| Document started to attached | $(( attached - started_doc )) ms |"
  echo "| Document started to the snapshot drawn | $(( snapshot - started_doc )) ms |"
  echo "| Document started to the first frame drawn | $(( first_frame - started_doc )) ms |"
  echo
  echo "| Process | Wakeups at rest | Wakeups flowing | Resident memory |"
  echo "| --- | ---: | ---: | ---: |"
  echo "| yoke-core | $(per_second rest core)/s | $(per_second flowing core)/s | ${at["rss core"]} MB |"
  echo "| hw-monitor | $(per_second rest monitor)/s | $(per_second flowing monitor)/s | ${at["rss monitor"]} MB |"
  echo "| the document (\`qml\`) | $(per_second rest document)/s | $(per_second flowing document)/s | ${at["rss document"]} MB |"
} > "$results"
cat "$results"
