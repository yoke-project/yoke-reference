# The six verbs every repository defines.
# A verb with nothing to do says so in one line, so a fan-out can tell a gap from a statement.

# Build this repository's codebase: every reference in Go is a module of its own, and every one in
# Node.js a package of its own, so a reader can copy one out whole. A package has nothing to compile, so
# building it is installing what it locks.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    for module in $(find . -name go.mod -not -path './.git/*' | sort); do go -C "$(dirname "$module")" build -o /dev/null ./...; done
    for package in $(find . -name package-lock.json -not -path '*/node_modules/*' -not -path './.git/*' | sort); do
        (cd "$(dirname "$package")" && npm ci --ignore-scripts --no-audit --no-fund > /dev/null)
    done
    echo "build: every module builds and every package installs"

# Run this repository's own checks, with no sibling present.
test:
    #!/usr/bin/env bash
    # A run leaves its results where the record writer reads them, whatever it decided.
    set -uo pipefail
    mkdir -p .results
    date -u +%Y-%m-%dT%H:%M:%SZ > .results/started
    status=0
    bash checks/run.sh | tee .results/checks.txt || status=1
    : > .results/go.json
    for module in $(find . -name go.mod -not -path './.git/*' | sort); do
      go test -C "$(dirname "$module")" -json ./... >> .results/go.json || status=1
      go test -C "$(dirname "$module")" ./... || status=1
    done
    : > .results/node.json
    here="$PWD"
    for package in $(find . -name package.json -not -path '*/node_modules/*' -not -path './.git/*' | sort); do
      (cd "$(dirname "$package")" && node --test --test-reporter=spec --test-reporter-destination=stdout \
        --test-reporter="$here/ci/node-results.mjs" --test-reporter-destination=node.json.part 'test/*.test.mjs') || status=1
      cat "$(dirname "$package")/node.json.part" >> .results/node.json && rm -f "$(dirname "$package")/node.json.part"
    done
    if command -v yoke-verify > /dev/null; then
        yoke-verify descriptions --repository yoke-reference . > /dev/null || status=1
        yoke-verify markers --repository yoke-reference . > /dev/null || status=1
    else
        echo "test: yoke-verify is not on PATH; \`just develop\` puts it there"
        status=1
    fi
    date -u +%Y-%m-%dT%H:%M:%SZ > .results/finished
    exit "$status"

# This repository's static checks.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    bash -n checks/run.sh checks/*/*.sh ci/*.sh
    for module in $(find . -name go.mod -not -path './.git/*' | sort); do go -C "$(dirname "$module")" vet ./...; done
    for script in $(find . \( -name '*.js' -o -name '*.mjs' \) -not -path '*/node_modules/*' -not -path './.git/*' | sort); do node --check "$script"; done
    echo "lint: every shell script and every script in Node.js parses, and go vet is clean in every module"

# Fail, naming each file, when the tree is not formatted.
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    files="$(find . -name '*.go' -not -path './.git/*' -print0 | xargs -0 -r gofmt -l)"
    if [[ -n "$files" ]]; then printf 'fmt: not formatted:\n%s\n' "$files"; exit 1; fi
    echo "fmt: every Go file is formatted"

# Verify the toolchain against the floor the workspace's fan-out passes, and put the verification
# tool on PATH at the version the workspace names — run alone, the newest published.
develop floor="" verify="":
    #!/usr/bin/env bash
    set -euo pipefail
    found="$(just --version | awk '{print $2}')"
    if [[ -z "{{floor}}" ]]; then
        echo "develop: no floor given, so none verified — the workspace passes it; found just $found"
    elif ! [[ "{{floor}}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        echo "develop: '{{floor}}' is not a version; pass it as \`just develop 1.58.0\`"
        exit 1
    else
        lowest="$(printf '%s\n%s\n' "{{floor}}" "$found" | sort -V | head -n 1)"
        if [[ "$lowest" != "{{floor}}" ]]; then
            echo "develop: just {{floor}} or newer is needed; found just $found"
            exit 1
        fi
        echo "develop: just $found meets the floor {{floor}}"
    fi
    bash ci/yoke-verify.sh "{{verify}}"

# Publish into this repository's ecosystem, one manifest line per publication.
release:
    @echo "release: nothing to publish from yoke-reference yet"
