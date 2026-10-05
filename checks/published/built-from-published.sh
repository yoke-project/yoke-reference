#!/usr/bin/env bash
# The check described by built-from-published.std.md.
# A module cache of its own, the public proxy and the public checksum database, and nothing exempted:
# a requirement nobody outside the project can obtain fails the build here.

published_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# std: yoke-reference:built-from-published.01
check_every_module_builds_from_published_modules() {
  local modules module dir cache failed=""
  mapfile -t modules < <(find "$published_root" -name go.mod -not -path '*/.git/*' | sort)
  (( ${#modules[@]} > 0 )) || { echo "no Go module in the tree"; return 1; }
  if find "$published_root" -name go.work -not -path '*/.git/*' | grep -q .; then
    echo "the tree holds a workspace file"; return 1
  fi
  cache="$(mktemp -d)"
  for module in "${modules[@]}"; do
    dir="$(dirname "$module")"
    grep -qE '^[[:space:]]*replace\b|^replace[[:space:]]*\(' "$module" && failed+=" ${dir#"$published_root"/} replaces a requirement;"
    [[ -d "$dir/vendor" ]] && failed+=" ${dir#"$published_root"/} vendors its requirements;"
    if ! (cd "$dir" && env -u GOPRIVATE -u GONOPROXY -u GONOSUMDB -u GONOSUMCHECK -u GOINSECURE \
        GOWORK=off GOFLAGS=-mod=readonly GOMODCACHE="$cache" GOPROXY=https://proxy.golang.org \
        GOSUMDB=sum.golang.org go build ./... > /dev/null 2>&1); then
      failed+=" ${dir#"$published_root"/} does not build from published modules;"
    fi
  done
  chmod -R u+w "$cache" && rm -rf "$cache"
  [[ -z "$failed" ]] || { echo "${failed# }"; return 1; }
}

# std: yoke-reference:built-from-published.02
check_every_node_package_installs_from_the_public_registry() {
  local packages package dir failed=""
  mapfile -t packages < <(find "$published_root" -name package.json -not -path '*/node_modules/*' -not -path '*/.git/*' | sort)
  for package in "${packages[@]}"; do
    dir="$(dirname "$package")"
    if [[ ! -f "$dir/package-lock.json" ]]; then
      failed+=" ${dir#"$published_root"/} has no lockfile;"
      continue
    fi
    # Every locked requirement, resolved from the public registry with a digest; the root entry is the
    # package itself.
    if ! out="$(node -e '
      const lock = require(process.argv[1]);
      const wrong = Object.entries(lock.packages ?? {}).filter(([at]) => at !== "")
        .filter(([, p]) => p.link || !String(p.resolved ?? "").startsWith("https://registry.npmjs.org/") || !p.integrity)
        .map(([at]) => at);
      if (wrong.length) { console.log(wrong.join(", ")); process.exit(1); }' "$dir/package-lock.json" 2>&1)"; then
      failed+=" ${dir#"$published_root"/} locks what the public registry does not serve: $out;"
    fi
  done
  [[ -z "$failed" ]] || { echo "${failed# }"; return 1; }
}
