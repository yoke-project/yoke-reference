#!/usr/bin/env bash
# The chain: written by compose.sh with the newest published composer and run under the newest published
# Core — three units, each using the next through a need, and the chain's client asking the first from the
# channel `bench`. Prints one line per case, as checks/run.sh does, and exits non-zero if any failed.
#
# The Core, the program an operator uses and the composer are published artifacts; the chain's Plugins and
# its client are built here, from the published crates.
#   YOKE_PROGRAMS=<dir>  runs it with the programs there instead of the newest release's, for a build of Yoke
#                        not published yet; YOKE_CORE_RANGE=<range> then names the range the chain states,
#                        since such a build calls itself by the version before.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chain="$root/applications/chain"
manifest_url="${YOKE_MANIFEST:-https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl}"
downloads=https://github.com
ids=(yoke-reference:chain.01 yoke-reference:chain.02 yoke-reference:chain.03 yoke-reference:chain.04
  yoke-reference:chain.05)

work="$(mktemp -d)"
run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yc.XXXX")"
core=""
trap 'kill "$core" 2> /dev/null; wait "$core" 2> /dev/null; rm -rf "$work" "$run"' EXIT

# fail_all <why>: every case failed for one reason, before any of them ran.
fail_all() { for id in "${ids[@]}"; do echo "FAIL  $id — $*"; done; exit 1; }

case "$(uname -m)" in
  x86_64) architecture=amd64 arch=x86_64 ;;
  aarch64 | arm64) architecture=arm64 arch=aarch64 ;;
  *) fail_all "no release for $(uname -m)" ;;
esac

if [[ -n "${YOKE_PROGRAMS:-}" ]]; then
  for p in yoke yoke-core yoke-compose; do
    [[ -x "$YOKE_PROGRAMS/$p" ]] || fail_all "$YOKE_PROGRAMS holds no $p"
    ln -s "$YOKE_PROGRAMS/$p" "$work/$p"
  done
  mkdir -p "$work/bin" && ln -s "$YOKE_PROGRAMS/yoke-compose" "$work/bin/yoke-compose"
else
  curl -fsSL "$manifest_url" -o "$work/manifest.jsonl" || fail_all "the release manifest cannot be obtained"
  host="$(jq -c --arg p "yoke-linux-$architecture" 'select(.line == "publication" and .published == $p)' "$work/manifest.jsonl" \
    | jq -sc 'sort_by(.version | ltrimstr("v") | split(".") | map(tonumber)) | last')"
  [[ "$host" != null ]] || fail_all "the manifest names no host archive"
  release="$(jq -r .version <<<"$host")"
  curl -fsSL "$downloads/yoke-project/yoke/releases/download/$release/yoke-${release#v}-linux-$architecture.tar.gz" -o "$work/host.tar.gz" \
    && [[ "sha256:$(sha256sum "$work/host.tar.gz" | cut -d' ' -f1)" == "$(jq -r '.digests[0]' <<<"$host")" ]] \
    || fail_all "the host archive of $release is not the file the manifest names"
  tar -xzf "$work/host.tar.gz" -C "$work" yoke-core yoke || fail_all "the host archive holds no yoke-core and yoke"
  GOBIN="$work/bin" go install "github.com/yoke-project/yoke/cmd/yoke-compose@$release" > "$work/install.log" 2>&1 \
    || fail_all "the composer of $release cannot be obtained: $(tail -3 "$work/install.log")"
fi
cargo build --release --locked --quiet --manifest-path "$chain/client/Cargo.toml" 2> "$work/client.log" \
  || fail_all "the chain's client does not build: $(tail -3 "$work/client.log")"
client="$chain/client/target/release/client"

app="$work/chain"
export XDG_RUNTIME_DIR="$run" XDG_STATE_HOME="$work/state"
log="$work/core.log"
yoke() { "$work/yoke" "$@" --instance chain-a; }
ask() { "$client" --instance chain-a --channel bench "$@"; }
until_logged() {
  local waited=0
  until grep -qE "$1" "$2" || (( waited >= $3 * 10 )); do sleep 0.1; ((waited++)); done
  grep -qE "$1" "$2"
}
# running <unit> <incarnation>: the Core logged the unit's incarnation running.
running() { until_logged "subject=unit:$1#$2 .*to=Running" "$log" 60; }

# std: yoke-reference:chain.01
check_the_chain_is_written_with_the_verbs_alone() {
  bash "$chain/compose.sh" "$work/bin/yoke-compose" "$app" "$arch" 2> "$work/compose.log" \
    || { echo "a verb was refused: $(grep -v '^+' "$work/compose.log" | tail -3)"; return 1; }
  [[ -z "${YOKE_CORE_RANGE:-}" ]] || "$work/bin/yoke-compose" set core "$YOKE_CORE_RANGE" --dir "$app" > /dev/null
  local why="" u
  for u in back middle front; do grep -qE "^  $u:$" "$app/yoke.yaml" || why+=" the unit $u is not there;"; done
  grep -qE '^    plugin: com\.yoke\.reference\.chain\.end$' "$app/yoke.yaml" || why+=" back is not the Plugin end;"
  [[ "$(grep -c '^    plugin: com\.yoke\.reference\.chain\.link$' "$app/yoke.yaml")" == 2 ]] || why+=" middle and front are not both link;"
  sed -n '/^  middle:$/,/^  [a-z]*:$/p' "$app/yoke.yaml" | grep -qE '^      next: back$' || why+=" middle's need is not bound to back;"
  sed -n '/^  front:$/,/^[a-z]/p' "$app/yoke.yaml" | grep -qE '^      next: middle$' || why+=" front's need is not bound to middle;"
  grep -q 'depends_on' "$app/yoke.yaml" && why+=" a unit states an order;"
  [[ -z "$why" ]] || { echo "${why# }"; cat "$app/yoke.yaml"; return 1; }
}

# std: yoke-reference:chain.02
check_the_order_is_derived_from_the_bindings() {
  [[ -f "$app/yoke.yaml" ]] || { echo "the chain was not written"; return 1; }
  "$work/yoke-core" --instance chain-a --bundle "$app" --unverified > "$log" 2>&1 &
  core=$!
  running front 1 || { echo "front did not run"; tail -20 "$log"; return 1; }
  local order
  order="$(sed -n 's/.*subject=unit:\([a-z]*\)#1 .*to=Running.*/\1/p' "$log" | tr '\n' ' ')"
  [[ "$order" == "back middle front " ]] || { echo "the units ran in the order $order"; return 1; }
  # Every Plugin granted what its Manifest declares, and each link started again to hold its grants, in order.
  local m p c
  for m in "$app/manifests/"*.yaml; do
    p="$(sed -n 's/^id: //p' "$m")"
    for c in $(sed -n 's/^  - name: //p' "$m"); do yoke plugin grant "$p" "$c" > /dev/null || { echo "$c could not be granted to $p"; return 1; }; done
  done
  yoke unit restart back > /dev/null && running back 2 || { echo "back did not run again"; return 1; }
  yoke unit restart middle > /dev/null && running middle 2 || { echo "middle did not run again"; return 1; }
  yoke unit restart front > /dev/null && running front 2 || { echo "front did not run again"; return 1; }
}

# std: yoke-reference:chain.03
check_the_deadline_and_the_chain_are_carried() {
  [[ -n "$core" ]] || { echo "the run of .02 is not there to continue"; return 1; }
  local answer why=""
  answer="$(ask ask front)" || { echo "front could not be asked"; return 1; }
  [[ "$(jq -r '[.hops[].unit] | join(" ")' <<<"$answer" 2> /dev/null)" == "front middle back" ]] \
    || { echo "the answer does not hold the three links in order: $answer"; return 1; }
  [[ "$(jq -r '[.hops[].asker] | join(" ")' <<<"$answer")" == "channel:bench unit:front unit:middle" ]] \
    || why+=" the askers are $(jq -c '[.hops[].asker]' <<<"$answer");"
  [[ "$(jq -r '[.hops[].chain] | unique | length' <<<"$answer")" == 1 ]] && jq -e '.hops[0].chain | test("^[0-9a-f]{32}$")' <<<"$answer" > /dev/null \
    || why+=" the chain is not one identity of 32 hex digits: $(jq -c '[.hops[].chain]' <<<"$answer");"
  jq -e '.hops as $h | ($h[0].deadline - $h[1].deadline == 500) and ($h[1].deadline - $h[2].deadline == 500)' <<<"$answer" > /dev/null \
    || why+=" each deadline is not 500 ms short of the one before: $(jq -c '[.hops[].deadline]' <<<"$answer");"
  local chainid now
  chainid="$(jq -r '.hops[0].chain' <<<"$answer")" now="$(date +%s%3N)"
  jq -e --argjson now "$now" '.hops[0].deadline - $now | . > 25000 and . <= 30000' <<<"$answer" > /dev/null \
    || why+=" the first deadline is not about 30 s ahead;"
  until_logged "type=unit.question.chained subject=unit:back#.*$chainid" "$log" 5 || why+=" back's question was not reported chained;"
  until_logged "type=unit.question.chained subject=unit:middle#.*$chainid" "$log" 5 || why+=" middle's question was not reported chained;"
  [[ -z "$why" ]] || { echo "${why# }"; return 1; }
}

# std: yoke-reference:chain.04
check_a_restart_in_the_middle_is_survived() {
  [[ -n "$core" ]] || { echo "the run of .03 is not there to continue"; return 1; }
  local before after answer why=""
  before="$(ask ask front | jq '.hops[0].ticks')"
  yoke unit restart middle > /dev/null && running middle 3 || { echo "middle did not run again"; return 1; }
  sleep 2
  answer="$(ask ask front)"
  [[ "$(jq -r '[.hops[].unit] | join(" ")' <<<"$answer" 2> /dev/null)" == "front middle back" ]] \
    || why+=" front was not answered through middle again: $answer;"
  after="$(jq '.hops[0].ticks' <<<"$answer")"
  (( after > before )) || why+=" front's follow of middle stopped at $before;"
  grep -qE 'subject=unit:front#[3-9] ' "$log" && why+=" front was restarted with middle;"
  [[ -z "$why" ]] || { echo "${why# }"; return 1; }
}

# std: yoke-reference:chain.05
check_a_stream_a_unit_follows_is_held() {
  [[ -n "$core" ]] || { echo "the run of .04 is not there to continue"; return 1; }
  local said why=""
  said="$(ask stop middle chain.ticks)"
  [[ "$said" == "refused stream.held front:"* ]] || why+=" a stop of middle's stream from bench was answered: $said;"
  said="$(ask stop back chain.ticks)"
  [[ "$said" == "refused stream.held middle:"* ]] || why+=" a stop of back's stream from bench was answered: $said;"
  yoke stream stop middle chain.ticks > "$work/stop.out" 2>&1 || why+=" the operator's stop was refused: $(cat "$work/stop.out");"
  [[ -z "$why" ]] || { echo "${why# }"; return 1; }
}

status=0
for pair in "${ids[0]} check_the_chain_is_written_with_the_verbs_alone" \
  "${ids[1]} check_the_order_is_derived_from_the_bindings" \
  "${ids[2]} check_the_deadline_and_the_chain_are_carried" \
  "${ids[3]} check_a_restart_in_the_middle_is_survived" \
  "${ids[4]} check_a_stream_a_unit_follows_is_held"; do
  read -r id fn <<<"$pair"
  # Not in a subshell: the Core of one case is what the next continues.
  if $fn > "$work/out" 2>&1; then
    echo "pass  $id"
  else
    echo "FAIL  $id — $(tr '\n' ' ' < "$work/out")"
    status=1
  fi
done
[[ -n "$core" ]] && { kill -INT "$core"; wait "$core"; core=""; }
exit "$status"
