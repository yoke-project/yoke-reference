#!/usr/bin/env bash
# L3: the reference web client signs in across a routable channel of a real Core and attaches with the
# cookie. Prints one line per case, as checks/run.sh does, and exits non-zero if it failed.
#
# The Core and the program it asks the host through are the published host archive of the release named
# here, authenticated against the manifest before they run, as admitted.sh obtains its Core.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release=0.7.0
manifest_url=https://raw.githubusercontent.com/yoke-project/yoke/main/releases/manifest.jsonl
id=yoke-reference:the-web-client.10

work="$(mktemp -d)"
run="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/yr.XXXX")"
trap 'pkill -f "$work/yoke-core" 2> /dev/null; rm -rf "$work" "$run"' EXIT

fail() { echo "FAIL  $id — $*"; exit 1; }

# certificate <dir> <name>: a self-signed certificate for 127.0.0.1, as <name>.crt and <name>.key.
certificate() {
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj "/CN=$2" \
    -addext subjectAltName=IP:127.0.0.1 -keyout "$1/$2.key" -out "$1/$2.crt" 2> /dev/null
}

free_port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

case "$(uname -m)" in
  x86_64) architecture=amd64 ;;
  aarch64 | arm64) architecture=arm64 ;;
  *) fail "no release for $(uname -m)" ;;
esac
archive="yoke-$release-linux-$architecture.tar.gz"
curl -fsSL "https://github.com/yoke-project/yoke/releases/download/v$release/$archive" -o "$work/$archive" \
  && curl -fsSL "$manifest_url" -o "$work/manifest.jsonl" || fail "the host archive of $release cannot be obtained"
want="$(jq -r --arg p "yoke-linux-$architecture" --arg v "v$release" \
  'select(.line == "publication" and .published == $p and .version == $v) | .digests[0]' "$work/manifest.jsonl")"
got="sha256:$(sha256sum "$work/$archive" | cut -d' ' -f1)"
[[ -n "$want" && "$want" == "$got" ]] || fail "the archive's digest $got is not the manifest's $want"
tar -xzf "$work/$archive" -C "$work" yoke-core yoke-auth || fail "the archive holds no yoke-core and yoke-auth"

# The host's authentication service, as a stack of the test's own: alice, with hunter2x.
mkdir -p "$work/pam.d" "$work/state/tls" "$work/plugins.d" "$work/plugins"
printf '#!/bin/sh\nread -r secret\n[ "$PAM_USER" = alice ] && [ "$secret" = hunter2x ]\n' > "$work/check.sh"
chmod +x "$work/check.sh"
printf 'auth required pam_exec.so expose_authtok quiet %s\naccount required pam_permit.so\n' "$work/check.sh" > "$work/pam.d/yoke"

certificate "$work/state/tls" service || fail "openssl made no certificate"
certificate "$work" front || fail "openssl made no certificate"
chmod 600 "$work/state/tls/"*
port="$(free_port)" listen="$(free_port)"
printf 'state_dir: %s/state\nruntime_dir: %s\nplugins:\n  manifests: %s/plugins.d\n  executables: %s/plugins\n' "$work" "$run" "$work" "$work" > "$work/core.yaml"
cat > "$work/deployment.yaml" <<YAML
units: {}
channels:
  service:
    transport: http+ws
    clients: multiple
    address: { class: routable, host: 127.0.0.1, port: "$port", security: { transport: encrypted, caller: authenticated } }
YAML
YOKE_CONFIG="$work/core.yaml" YOKE_AUTH_STACKS="$work/pam.d" "$work/yoke-core" --composition "$work/deployment.yaml" > "$work/core.log" 2>&1 &
waited=0
until grep -q 'msg=channel.*name=service' "$work/core.log" || (( waited >= 30 )); do sleep 1; ((waited++)); done
grep -q 'msg=channel.*name=service' "$work/core.log" || fail "the Core bound no channel: $(tail -5 "$work/core.log")"

# std: yoke-reference:the-web-client.10
check_the_client_signs_in_across_a_routable_channel() {
  NODE_EXTRA_CA_CERTS="$work/front.crt" node "$root/clients/web/test/l3/signed-in.mjs" \
    "https://127.0.0.1:$port" "$work/state/tls/service.crt" "$work/front.crt" "$work/front.key" "$listen"
}

if out="$(check_the_client_signs_in_across_a_routable_channel 2>&1)"; then
  echo "pass  $id"
else
  fail "$out"
fi
