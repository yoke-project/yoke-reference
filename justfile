# The six verbs every repository defines.
# A verb with nothing to do says so in one line, so a fan-out can tell a gap from a statement.

# Where each reference in Python has its requirements installed: one environment per reference.
venvs := env_var_or_default("XDG_CACHE_HOME", env_var("HOME") + "/.cache") + "/yoke-reference"

# Build this repository's codebase: every reference is a project of its own in its language — a Go
# module, a Cargo package, a Python program with its requirements, a Node.js package — so a reader can
# copy one out whole. What has nothing to compile is built by installing what it locks.
build:
    #!/usr/bin/env bash
    set -euo pipefail
    for module in $(find . -name go.mod -not -path './.git/*' | sort); do go -C "$(dirname "$module")" build -o /dev/null ./...; done
    for crate in $(find . -name Cargo.toml -not -path '*/target/*' -not -path './.git/*' | sort); do cargo build -q --locked --manifest-path "$crate"; done
    for requirements in $(find . -name requirements.txt -not -path './.git/*' | sort); do
        venv="{{venvs}}/$(dirname "${requirements#./}" | tr / -)"
        [[ -x "$venv/bin/python" ]] || python3 -m venv "$venv"
        "$venv/bin/python" -m pip install --quiet --disable-pip-version-check --require-hashes -r "$requirements"
    done
    for package in $(find . -name package-lock.json -not -path '*/node_modules/*' -not -path './.git/*' | sort); do
        (cd "$(dirname "$package")" && npm ci --ignore-scripts --no-audit --no-fund > /dev/null)
    done
    echo "build: every module and crate builds, and every program's and package's requirements install"

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
    : > .results/cargo.txt
    for crate in $(find . -name Cargo.toml -not -path '*/target/*' -not -path './.git/*' | sort); do
      cargo test --locked --no-fail-fast --manifest-path "$crate" 2>&1 | tee -a .results/cargo.txt; (( PIPESTATUS[0] == 0 )) || status=1
    done
    bash ci/cargo-results.sh .results/cargo.txt > .results/cargo.json
    : > .results/python.json
    for requirements in $(find . -name requirements.txt -not -path './.git/*' | sort); do
      venv="{{venvs}}/$(dirname "${requirements#./}" | tr / -)"
      "$venv/bin/python" -I ci/unittest-results.py "$(dirname "$requirements")/tests" .results/python.part || status=1
      cat .results/python.part >> .results/python.json && rm -f .results/python.part
    done
    # L3: the references in Rust and Python under the published Core, on this host.
    bash ci/admitted.sh "{{venvs}}/plugins-python-clock/bin/python" | tee .results/admitted.txt; (( PIPESTATUS[0] == 0 )) || status=1
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
    for program in $(find . -name '*.py' -not -path '*/node_modules/*' -not -path './.git/*' | sort); do python3 -m py_compile "$program"; done
    for script in $(find . \( -name '*.js' -o -name '*.mjs' \) -not -path '*/node_modules/*' -not -path './.git/*' | sort); do node --check "$script"; done
    echo "lint: every shell script and every script in Python and Node.js parses, and go vet is clean in every module"

# Fail, naming each file, when the tree is not formatted.
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    files="$(find . -name '*.go' -not -path './.git/*' -print0 | xargs -0 -r gofmt -l)"
    for crate in $(find . -name Cargo.toml -not -path '*/target/*' -not -path './.git/*' | sort); do
        cargo fmt --check --manifest-path "$crate" > /dev/null 2>&1 || files+=$'\n'"$(dirname "$crate") (cargo fmt)"
    done
    files="${files#$'\n'}"
    if [[ -n "$files" ]]; then printf 'fmt: not formatted:\n%s\n' "$files"; exit 1; fi
    echo "fmt: every Go and Rust file is formatted"

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
