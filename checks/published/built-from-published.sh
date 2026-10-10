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

# std: yoke-reference:built-from-published.03
check_every_cargo_package_locks_crates_from_crates_io() {
  local manifests manifest dir failed="" wrong
  mapfile -t manifests < <(find "$published_root" -name Cargo.toml -not -path '*/target/*' -not -path '*/.git/*' | sort)
  for manifest in "${manifests[@]}"; do
    dir="$(dirname "$manifest")"
    if [[ ! -f "$dir/Cargo.lock" ]]; then
      failed+=" ${dir#"$published_root"/} has no lockfile;"
      continue
    fi
    grep -qE '(^|[[:space:],{])(path|git)[[:space:]]*=' "$manifest" && failed+=" ${dir#"$published_root"/} requires a path or a repository;"
    grep -qE '^\[patch' "$manifest" && failed+=" ${dir#"$published_root"/} patches a requirement;"
    # Every locked package but the root carries crates.io's index as its source, and a checksum.
    wrong="$(awk '
      /^\[\[package\]\]/ { if (name != "" && name != root && !(src ~ /^"registry\+https:\/\/github\.com\/rust-lang\/crates\.io-index"$/ && sum)) print name; name = ""; src = ""; sum = 0; next }
      /^name = / { name = $3 } /^source = / { src = $3 } /^checksum = / { sum = 1 }
      END { if (name != "" && name != root && !(src ~ /^"registry\+https:\/\/github\.com\/rust-lang\/crates\.io-index"$/ && sum)) print name }
    ' root="\"$(awk -F'"' '/^name = /{print $2; exit}' "$manifest")\"" "$dir/Cargo.lock" | tr '\n' ' ')"
    [[ -z "$wrong" ]] || failed+=" ${dir#"$published_root"/} locks what crates.io does not serve: ${wrong% };"
  done
  [[ -z "$failed" ]] || { echo "${failed# }"; return 1; }
}

# std: yoke-reference:built-from-published.04
check_every_python_program_installs_from_the_public_index() {
  local files file dir venv failed="" unpinned
  mapfile -t files < <(find "$published_root" -name requirements.txt -not -path '*/.git/*' | sort)
  for file in "${files[@]}"; do
    dir="$(dirname "$file")"
    # One requirement per logical line, each NAME==VERSION followed by its digests, and no option that
    # names another source.
    unpinned="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$file" | grep -vE '^[[:space:]]*(#|$)' \
      | grep -vE '^[A-Za-z0-9._-]+==[^ ]+( +--hash=sha256:[0-9a-f]{64})+[[:space:]]*$' | tr '\n' ' ')"
    [[ -z "$unpinned" ]] || failed+=" ${dir#"$published_root"/} requires what is not pinned with a digest: ${unpinned% };"
    venv="$(mktemp -d)"
    if ! { python3 -m venv "$venv/v" && env -u PIP_INDEX_URL -u PIP_EXTRA_INDEX_URL -u PIP_FIND_LINKS \
        "$venv/v/bin/python" -m pip install --quiet --disable-pip-version-check --no-cache-dir \
        --index-url https://pypi.org/simple --require-hashes -r "$file"; } > /dev/null 2>&1; then
      failed+=" ${dir#"$published_root"/} does not install from the public index;"
    fi
    rm -rf "$venv"
  done
  [[ -z "$failed" ]] || { echo "${failed# }"; return 1; }
}
