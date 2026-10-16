#!/usr/bin/env bash
# The example application written by compose.sh with the newest published composer, checked and built at
# both its versions. Prints one line per case, as checks/run.sh does, and exits non-zero if it failed.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_url="${YOKE_MANIFEST:-https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl}"
id=yoke-reference:station.01
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL  $id — $*"; exit 1; }

# The composer of the newest programs release, as anyone obtains it: through the public module proxy.
curl -fsSL "$manifest_url" -o "$work/manifest.jsonl" || fail "the release manifest cannot be obtained"
release="$(jq -r 'select(.line == "publication" and (.published | startswith("yoke-linux-"))) | .version' "$work/manifest.jsonl" \
  | sort -V | tail -n1)"
[[ -n "$release" ]] || fail "the manifest names no programs release"
# YOKE_COMPOSE names a composer built elsewhere, to run the case against what is not yet published.
if [[ -n "${YOKE_COMPOSE:-}" ]]; then mkdir -p "$work/bin" && cp "$YOKE_COMPOSE" "$work/bin/yoke-compose"; else
GOBIN="$work/bin" go install "github.com/yoke-project/yoke/cmd/yoke-compose@$release" > "$work/install.log" 2>&1 \
  || fail "the composer of $release cannot be obtained: $(tail -3 "$work/install.log")"
fi

# A descriptor read as JSON, by the YAML library the project's own Go code uses, from the public proxy.
mkdir -p "$work/tojson-src" && cat > "$work/tojson-src/main.go" <<'GO'
package main

import (
	"encoding/json"
	"os"

	"go.yaml.in/yaml/v3"
)

func main() {
	var v any
	if err := yaml.NewDecoder(os.Stdin).Decode(&v); err != nil {
		os.Exit(1)
	}
	json.NewEncoder(os.Stdout).Encode(v)
}
GO
{ (cd "$work/tojson-src" && go mod init tojson && go get go.yaml.in/yaml/v3@v3.0.5 && go build -o "$work/tojson" .); } > "$work/tojson.log" 2>&1 \
  || fail "the descriptor reader does not build: $(tail -3 "$work/tojson.log")"

# What the project carries: two host executables, and an image reference for each containerised unit.
printf '#!/bin/sh\nexit 0\n' > "$work/acquire" && printf '#!/bin/sh\nexit 0\n' > "$work/panel" && chmod +x "$work/acquire" "$work/panel"
n=0
for unit in provision-store migrate-store pipeline archive; do
  n=$((n + 1))
  printf '%s=ghcr.io/yoke/station-%s@sha256:%064d\n' "$unit" "$unit" "$n"
done > "$work/images"

# std: yoke-reference:station.01
check_both_versions_are_written_refused_nothing_and_built() {
  local v dir out
  for v in 2.1.0 2.2.0; do
    dir="$work/$v"
    bash "$root/applications/station/compose.sh" "$work/bin/yoke-compose" "$dir" "$v" "$(uname -m)" \
      "$work/acquire" "$work/panel" "$work/images" 2> "$work/compose-$v.log" \
      || { echo "$v: a verb was refused: $(tail -2 "$work/compose-$v.log")"; return 1; }
    out="$("$work/bin/yoke-compose" check --dir "$dir")" || { echo "$v: check refused: $out"; return 1; }
    [[ "$(grep -c '^weaker' <<<"$out")" == 1 && "$out" == *"channel.address.loopback"* && "$out" != *refusal* ]] \
      || { echo "$v: check said $out"; return 1; }
    mkdir -p "$work/out-$v" && "$work/bin/yoke-compose" build --dir "$dir" --out "$work/out-$v" > /dev/null || { echo "$v: build refused"; return 1; }
    [[ "$(ls "$work/out-$v" | wc -l)" == 1 ]] || { echo "$v: build wrote $(ls "$work/out-$v")"; return 1; }
    "$work/tojson" < "$dir/yoke.yaml" > "$dir/yoke.json" || { echo "$v: the descriptor does not read"; return 1; }
    local first=provision-store before=""
    [[ "$v" == 2.2.0 ]] && first=migrate-store before='"migrate-store",'
    out="$(jq -r --arg v "$v" --arg first "$first" --argjson want "[\"provision-store\",$before\"acquire\",\"pipeline\",\"archive\",\"panel\"]" '
      [ (if (.units | keys) != ($want | sort) then "the units are \(.units | keys)" else empty end),
        (.units | to_entries[] | select(.key == "acquire" or .key == "pipeline" or .key == "archive")
          | select(.value.depends_on != [$first]) | "\(.key) depends on \(.value.depends_on)"),
        (if .units.panel.depends_on != ["pipeline"] then "panel depends on \(.units.panel.depends_on)" else empty end),
        (if $v == "2.2.0" and .units["migrate-store"].migrates_from != "<2.2" then "migrate-store migrates from \(.units["migrate-store"].migrates_from)" else empty end),
        (if (.parameters | map_values(keys)) != {"shared":["site_label"],"acquire":["instrument"],"archive":["retention_days"],"remote":["listen_port"]}
           then "the parameters are \(.parameters | map_values(keys))" else empty end),
        (if (.channels | keys) != ["panel","remote"] then "the channels are \(.channels | keys)" else empty end),
        (if .arbitration != [{"prevails":"panel","over":["remote"]}] then "the arbitration is \(.arbitration)" else empty end),
        (if .data != ">=2.0" then "the data range is \(.data)" else empty end)
      ] | join("; ")' "$dir/yoke.json")"
    [[ -z "$out" ]] || { echo "$v: $out"; return 1; }
  done
}

if out="$(check_both_versions_are_written_refused_nothing_and_built 2>&1)"; then
  echo "pass  $id"
else
  fail "$out"
fi
