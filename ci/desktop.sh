#!/usr/bin/env bash
# The desktop bench: written by compose.sh with the newest published composer, run under the newest
# published Core, and bench.qml attached beside it with the C++ family's QML binding, built from the
# family's newest source release as any consumer obtains it. Prints one line per case, as checks/run.sh
# does, and exits non-zero if any failed.
#
# The Core, the program an operator uses, the composer and the C++ family's source are published
# artifacts; nothing of the project is built here but what the composer builds of the pool's Plugin.
# QML_RUNTIME names Qt's `qml`, where it is not on the PATH under that name.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_url="${YOKE_MANIFEST:-https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl}"
downloads=https://github.com
ids=(yoke-reference:desktop.01 yoke-reference:desktop.02 yoke-reference:desktop.03 yoke-reference:desktop.04
  yoke-reference:desktop.05 yoke-reference:desktop.06)

work="$(mktemp -d)"
run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yr.XXXX")"
core="" documents=()
stop_documents() { for d in "${documents[@]}"; do kill "$d" 2> /dev/null; wait "$d" 2> /dev/null; done; documents=(); }
trap 'stop_documents; kill "$core" 2> /dev/null; wait "$core" 2> /dev/null; rm -rf "$work" "$run"' EXIT

# fail_all <why>: every case failed for one reason, before any of them ran.
fail_all() { for id in "${ids[@]}"; do echo "FAIL  $id — $*"; done; exit 1; }

case "$(uname -m)" in
  x86_64) architecture=amd64 arch=x86_64 ;;
  aarch64 | arm64) architecture=arm64 arch=aarch64 ;;
  *) fail_all "no release for $(uname -m)" ;;
esac
qml="${QML_RUNTIME:-$(command -v qml || echo /usr/lib/qt6/bin/qml)}"
[[ -x "$qml" ]] || fail_all "Qt's qml runtime is not installed"
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

# The C++ family, as its source release, with its QML binding, installed under a prefix of the case's own.
family="$(newest yoke-sdk-cpp-source)"
[[ "$family" != null ]] || fail_all "the manifest names no source release of the C++ family"
fver="$(jq -r .version <<<"$family")"
obtain "$(jq -r .where <<<"$family" | sed 's#/releases/tag/#/releases/download/#')/yoke-sdk-cpp-${fver#v}-source.tar.gz" \
  "$work/sdk.tar.gz" "$(jq -r '.digests[0]' <<<"$family")" || fail_all "the C++ family's $fver source is not the file the manifest names"
mkdir -p "$work/sdk" && tar -xzf "$work/sdk.tar.gz" -C "$work/sdk" --strip-components=1 || fail_all "the C++ family's source does not unpack"
{ cmake -S "$work/sdk" -B "$work/sdk-build" -DCMAKE_BUILD_TYPE=Release -DYOKE_SDK_CPP_QML=ON -DYOKE_SDK_CPP_TESTING=OFF \
    && cmake --build "$work/sdk-build" --parallel && cmake --install "$work/sdk-build" --prefix "$work/prefix"; } > "$work/sdk.log" 2>&1 \
  || fail_all "the C++ family $fver does not build and install with its QML binding: $(tail -5 "$work/sdk.log")"
qmldir="$(find "$work/prefix" -path '*/Yoke/Interface/qmldir' | head -n1)"
imports="${qmldir%/Yoke/Interface/qmldir}"
[[ -n "$qmldir" && -d "$imports/Yoke" ]] || fail_all "the C++ family $fver installs no QML module"

# The newest programs release: its host archive, and its composer through the public module proxy.
host="$(newest yoke-linux-$architecture)"
release="$(jq -r .version <<<"$host")"
obtain "$downloads/yoke-project/yoke/releases/download/$release/yoke-${release#v}-linux-$architecture.tar.gz" \
  "$work/host.tar.gz" "$(jq -r '.digests[0]' <<<"$host")" || fail_all "the host archive of $release is not the file the manifest names"
tar -xzf "$work/host.tar.gz" -C "$work" yoke-core yoke || fail_all "the host archive holds no yoke-core and yoke"
GOBIN="$work/bin" go install "github.com/yoke-project/yoke/cmd/yoke-compose@$release" > "$work/install.log" 2>&1 \
  || fail_all "the composer of $release cannot be obtained: $(tail -3 "$work/install.log")"

bench="$work/desktop"
export XDG_RUNTIME_DIR="$run" XDG_STATE_HOME="$work/state"
log="$work/core.log"
yoke() { "$work/yoke" "$@" --instance bench-a; }
until_logged() {
  local waited=0
  until grep -qE "$1" "$2" || (( waited >= $3 * 10 )); do sleep 0.1; ((waited++)); done
  grep -qE "$1" "$2"
}
# document <file> [<argument>...]: bench.qml started beside the application, its standard error into
# file; its pid in `documents`.
document() {
  local out="$1"; shift
  QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 "$qml" -I "$imports" "$root/applications/desktop/bench.qml" \
    -- --instance bench-a --channel desktop "$@" > "$out" 2>&1 &
  documents+=("$!")
}
# What a case gives the document in place of a person, and looks for where the Core keeps what it keeps.
secret="bench-passphrase-$$-$RANDOM"
# join <network>: ask is told, over the operator's surface, to join a network, which needs a passphrase.
join() { printf '{"network":"%s"}' "$1" | yoke unit command ask ask.join --input - > /dev/null; }
# unseen <case's log>...: the passphrase is in none of the Core's output, its state, the log store as
# `yoke log query` shows it, nor what the document said.
unseen() {
  local where=""
  yoke log query --unit ask > "$work/ask.log" 2>&1
  for f in "$log" "$work/ask.log" "$@"; do grep -qaF "$secret" "$f" && where+=" $(basename "$f")"; done
  grep -rqaF "$secret" "$XDG_STATE_HOME" && where+=" the state directory"
  [[ -z "$where" ]] || echo " the passphrase is in:$where;"
}
# follows <file>: the document said it attached, was answered the snapshot, and followed both streams.
follows() {
  local why=""
  until_logged 'bench: hw.memory [0-9]+' "$1" 30 && until_logged 'bench: hw.cpu [0-9]+' "$1" 30 || true
  sleep 3
  grep -qE 'bench: attached to desktop of bench-a \(contract 1\)' "$1" || why+=" it did not say it attached;"
  grep -qE 'bench: snapshot \{.*"schema":1.*"at_ms":[0-9]+' "$1" || grep -qE 'bench: snapshot \{.*"at_ms":[0-9]+.*"schema":1' "$1" \
    || why+=" it was not answered the snapshot;"
  for s in hw.cpu hw.memory; do
    grep -qE "bench: $s started OUTCOME_" "$1" || why+=" $s was not started;"
    local seqs
    seqs="$(sed -n "s/.*bench: $s \([0-9][0-9]*\)$/\1/p" "$1")"
    (( $(wc -l <<<"$seqs") >= 3 )) && sort -n -c <<<"$seqs" 2> /dev/null || why+=" $s did not deliver three frames in order;"
  done
  [[ -z "$why" ]] || { echo "${why# }"; tail -8 "$1"; return 1; }
}

# std: yoke-reference:desktop.01
check_the_bench_is_written_with_the_verbs_alone() {
  bash "$root/applications/desktop/compose.sh" "$work/bin/yoke-compose" "$bench" "$arch" 2> "$work/compose.log" \
    || { echo "a verb was refused: $(tail -3 "$work/compose.log")"; return 1; }
  local why=""
  grep -qE '^  hw-monitor:$' "$bench/yoke.yaml" && grep -qE '^    plugin: com\.yoke\.hw-monitor$' "$bench/yoke.yaml" \
    || why+=" the unit hw-monitor of com.yoke.hw-monitor is not there;"
  grep -qE '^  ask:$' "$bench/yoke.yaml" && grep -qE '^    plugin: com\.yoke\.reference\.ask$' "$bench/yoke.yaml" \
    || why+=" the unit ask of com.yoke.reference.ask is not there;"
  grep -qE '^    tag: v[0-9]' "$bench/plugins.yaml" || why+=" the Plugin is not recorded at a tag;"
  sed -n '/^channels:/,$p' "$bench/yoke.yaml" > "$work/channels"
  grep -qE '^  desktop:$' "$work/channels" && grep -qE 'transport: local' "$work/channels" && grep -qE 'clients: single' "$work/channels" \
    || why+=" the channel desktop is not local for a single client;"
  grep -qE '^    unit:' "$work/channels" && why+=" the channel desktop names a unit;"
  [[ -z "$why" ]] || { echo "${why# }"; cat "$bench/yoke.yaml"; return 1; }
}

# std: yoke-reference:desktop.02
check_the_document_sees_the_snapshot_and_follows_the_streams() {
  [[ -f "$bench/yoke.yaml" ]] || { echo "the bench was not written"; return 1; }
  "$work/yoke-core" --instance bench-a --bundle "$bench" --unverified > "$log" 2>&1 &
  core=$!
  until_logged 'subject=unit:hw-monitor#1 .*to=Running' "$log" 60 || { echo "hw-monitor did not run"; tail -20 "$log"; return 1; }
  local c
  for c in $(sed -n 's/^  - name: //p' "$bench/manifests/com.yoke.hw-monitor.yaml"); do
    yoke plugin grant com.yoke.hw-monitor "$c" > /dev/null || { echo "$c could not be granted"; return 1; }
  done
  yoke unit restart hw-monitor > /dev/null || { echo "hw-monitor could not be restarted"; return 1; }
  until_logged 'subject=unit:hw-monitor#2 .*to=Running' "$log" 60 || { echo "hw-monitor did not run again"; return 1; }
  # ask, the bench's own Plugin, is granted what it declares as well, for .05 and .06.
  for c in $(sed -n 's/^  - name: //p' "$bench/manifests/com.yoke.reference.ask.yaml"); do
    yoke plugin grant com.yoke.reference.ask "$c" > /dev/null || { echo "$c could not be granted to ask"; return 1; }
  done
  yoke unit restart ask > /dev/null || { echo "ask could not be restarted"; return 1; }
  until_logged 'subject=unit:ask#2 .*to=Running' "$log" 60 || { echo "ask did not run again"; return 1; }
  document "$work/first.log"
  follows "$work/first.log"
}

# std: yoke-reference:desktop.03
check_the_document_is_started_beside_the_application() {
  [[ -n "$core" && ${#documents[@]} == 1 ]] || { echo "the run of .02 is not there to continue"; return 1; }
  local first="${documents[0]}" why=""
  document "$work/second.log"
  until_logged 'bench: ended ' "$work/second.log" 15 || why+=" a second document was not refused the channel;"
  grep -qE 'bench: ended channel\.in_use' "$work/second.log" || why+=" the second was refused for another reason: $(grep -m1 'bench: ended' "$work/second.log");"
  kill "${documents[1]}" 2> /dev/null; wait "${documents[1]}" 2> /dev/null
  local before after
  before="$(grep -cE 'bench: hw.cpu [0-9]+' "$work/first.log")"
  sleep 3
  after="$(grep -cE 'bench: hw.cpu [0-9]+' "$work/first.log")"
  (( after > before )) || why+=" the first stopped following when the second came;"
  kill "$first"; wait "$first" 2> /dev/null; documents=()
  sleep 2
  kill -0 "$core" 2> /dev/null || why+=" the Core went with the document;"
  grep -qE 'subject=unit:hw-monitor#2 .*to=(Stopped|Exited|Failed)' "$log" && why+=" hw-monitor ended with the document;"
  document "$work/third.log"
  follows "$work/third.log" > "$work/third.why" || why+=" the next document did not follow: $(head -1 "$work/third.why");"
  [[ -z "$why" ]] || { echo "${why# }"; return 1; }
}

# std: yoke-reference:desktop.04
check_the_document_joins_the_present_without_a_gap() {
  [[ -n "$core" && ${#documents[@]} == 1 ]] || { echo "the run of .03 is not there to continue"; return 1; }
  local doc="$work/third.log" why="" s at values
  until_logged 'bench: value hw.memory [0-9]+' "$doc" 30 || true
  sleep 3
  for s in hw.cpu hw.memory; do
    at="$(sed -n "s/.*bench: joined $s at \([0-9][0-9]*\),.*/\1/p" "$doc" | head -1)"
    [[ -n "$at" ]] || { why+=" it never joined $s to the snapshot;"; continue; }
    values="$(sed -n "s/.*bench: value $s \([0-9][0-9]*\)$/\1/p" "$doc")"
    (( $(wc -l <<<"$values") >= 3 )) || { why+=" $s brought fewer than three values after the snapshot;"; continue; }
    [[ "$(head -1 <<<"$values")" == "$((at + 1))" ]] || why+=" $s went on at $(head -1 <<<"$values"), not at $((at + 1)) after the snapshot's $at;"
    awk 'NR > 1 && $1 != prev + 1 { bad = 1 } { prev = $1 } END { exit bad }' <<<"$values" || why+=" $s skipped a value;"
  done
  grep -q 'bench: gap ' "$doc" && why+=" it said: $(grep -m1 'bench: gap ' "$doc");"
  [[ -z "$why" ]] || { echo "${why# }"; grep -E 'bench: (joined|value|snapshot)' "$doc" | head -12; return 1; }
}

# std: yoke-reference:desktop.05
check_the_document_answers_what_a_plugin_asks() {
  [[ -n "$core" && ${#documents[@]} == 1 ]] || { echo "the run of .04 is not there to continue"; return 1; }
  stop_documents
  local doc="$work/fourth.log" why=""
  document "$doc" --answer "$secret"
  until_logged 'bench: joined asks at 0, 0 held dropped' "$doc" 30 || { echo "the document did not join ask's present"; tail -8 "$doc"; return 1; }
  join bench || { echo "ask.join was refused"; return 1; }
  until_logged 'bench: settled a1 ' "$doc" 30 || true
  grep -qE 'bench: asked a1 for bench \(sequence 1\)' "$doc" || why+=" the document was not told of the ask;"
  grep -qE 'bench: a1 answer OUTCOME_DONE' "$doc" || why+=" its answer was not acknowledged done;"
  grep -qE 'bench: settled a1 accepted \(sequence 2\)' "$doc" || why+=" the ask was not settled as accepted;"
  why+="$(unseen "$doc")"
  [[ -z "$why" ]] || { echo "${why# }"; grep -E 'bench: (joined asks|asked|answering|a1|settled)' "$doc"; return 1; }
}

# std: yoke-reference:desktop.06
check_a_document_that_comes_after_the_ask_answers_it() {
  [[ -n "$core" && ${#documents[@]} == 1 ]] || { echo "the run of .05 is not there to continue"; return 1; }
  stop_documents
  local doc="$work/fifth.log" why=""
  join late || { echo "ask.join was refused"; return 1; }
  sleep 1
  document "$doc" --answer "$secret"
  until_logged 'bench: settled a2 ' "$doc" 30 || true
  grep -qE 'bench: joined asks at 3, ' "$doc" || why+=" the document did not join ask's present at its sequence 3;"
  grep -qE 'bench: asked a2 for late \(sequence 3\)' "$doc" || why+=" the present did not tell it of the ask;"
  grep -qE 'bench: asked a1 ' "$doc" && why+=" it was told again of an ask already settled;"
  grep -qE 'bench: a2 answer OUTCOME_DONE' "$doc" || why+=" its answer was not acknowledged done;"
  grep -qE 'bench: settled a2 accepted \(sequence 4\)' "$doc" || why+=" the ask was not settled as accepted;"
  why+="$(unseen "$doc" "$work/fourth.log")"
  [[ -z "$why" ]] || { echo "${why# }"; grep -E 'bench: (joined asks|asked|answering|a2|settled)' "$doc"; return 1; }
}

status=0
for pair in "${ids[0]} check_the_bench_is_written_with_the_verbs_alone" \
  "${ids[1]} check_the_document_sees_the_snapshot_and_follows_the_streams" \
  "${ids[2]} check_the_document_is_started_beside_the_application" \
  "${ids[3]} check_the_document_joins_the_present_without_a_gap" \
  "${ids[4]} check_the_document_answers_what_a_plugin_asks" \
  "${ids[5]} check_a_document_that_comes_after_the_ask_answers_it"; do
  read -r id fn <<<"$pair"
  # Not in a subshell: the Core and the document of one case are what the next continues.
  if $fn > "$work/out" 2>&1; then
    echo "pass  $id"
  else
    echo "FAIL  $id — $(tr '\n' ' ' < "$work/out")"
    status=1
  fi
done
stop_documents
[[ -n "$core" ]] && { kill -INT "$core"; wait "$core"; core=""; }
exit "$status"
