#!/usr/bin/env bash
# Assembles the record of one level of a run from what that run left behind, and writes it to standard
# output. It runs nothing: a record is evidence of a run that already happened. One run of `test`
# performs L1 and L3, and each level's record takes the cases declared at it.
#
# The tool is the one `develop` put on PATH, and the record names it by the build information the
# binary carries: the version it states, and nothing learnt from where it was installed.
# A level whose predecessor blocked was not reached: PREDECESSOR names that record — L1 for L3, since no suite runs here.
# Usage: [PREDECESSOR=<record>] record.sh [level] [results directory] — the level is L1 unless named.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
level=L1
[[ "${1:-}" =~ ^L[0-9]$ ]] && { level="$1"; shift; }
results="${1:-$root/.results}"

for each in checks.txt started finished; do
  [[ -f "$results/$each" ]] || { echo "record: the run left no $each in $results" >&2; exit 1; }
done

# A run of a module's tests leaves a Go runner's own output beside the checks' lines.
go_results=()
[[ -s "$results/go.json" ]] && go_results=(--results "$results/go.json")
# And a run of a package's tests leaves the same form, written by ci/node-results.mjs.
[[ -s "$results/node.json" ]] && go_results+=(--results "$results/node.json")
# The Rust and Python tests leave it too, written by ci/cargo-results.sh and ci/unittest-results.py.
[[ -s "$results/cargo.json" ]] && go_results+=(--results "$results/cargo.json")
[[ -s "$results/python.json" ]] && go_results+=(--results "$results/python.json")
# And the L3 cases leave lines in the checks' form.
[[ -s "$results/admitted.txt" ]] && go_results+=(--results "$results/admitted.txt")
if [[ -n "${PREDECESSOR:-}" ]]; then
  blocked="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("blocks") is not False)' "$PREDECESSOR" 2>/dev/null)"
  # A predecessor whose record cannot be read did not pass either.
  [[ "$blocked" == False ]] || go_results+=(--not-reached)
fi

# The architecture as the environment's dimension names it.
case "$(uname -m)" in
  x86_64) architecture=amd64 ;;
  aarch64 | arm64) architecture=arm64 ;;
  *) architecture="$(uname -m)" ;;
esac

tool="$(command -v yoke-verify)" || { echo "record: yoke-verify is not on PATH; \`just develop\` puts it there" >&2; exit 1; }
version="$(grep -aoE $'mod\tgithub\\.com/yoke-project/yoke\t[^\t]+' "$tool" | head -n 1 | cut -f3)"
revision="$(grep -aoE 'vcs\.revision=[0-9a-f]{40}' "$tool" | head -n 1 | cut -d= -f2)"

yoke-verify record \
  --level "$level" \
  --tier reference \
  --repository yoke-reference \
  --environment "architecture=$architecture" \
  --started "$(tr -d '[:space:]' < "$results/started")" \
  --finished "$(tr -d '[:space:]' < "$results/finished")" \
  --ran "yoke-verify=${version:-unknown}@${revision:0:12}" \
  --results "$results/checks.txt" \
  "${go_results[@]}" \
  "$root"
