#!/usr/bin/env bash
# Writes the chain, com.yoke.reference.chain, with the composer's verbs alone: three units, each using the
# next — front uses middle, middle uses back — and a local channel, `bench`, that a client asks the first
# from. back is the chain's last link, end; front and middle are two copies of one Plugin, link, each with its
# need `next` bound to the unit after it. Nothing says in which order they start: the Core derives it from the
# bindings.
#
# Usage: compose.sh <yoke-compose> <dir> <arch>
set -euo pipefail

compose="$1" dir="$2" arch="$3"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Each verb is said before it runs, so a refusal names the verb it answers.
c() { echo "+ $*" >&2; "$compose" "$@" --dir "$dir" > /dev/null; }

c init com.yoke.reference.chain --version 1.0.0 --arch "$arch" --core ">=0.17.0"
c add plugin "$here/end" --as back --yes
c set units.back.args '["--name", "back"]'
c add plugin "$here/link" --as middle --bind next=back --yes
c set units.middle.args '["--name", "middle", "--next", "${bind.next}"]'
c add unit front --kind plugin --plugin com.yoke.reference.chain.link --exec components/plugins/middle \
  --arg --name --arg front --arg --next --arg '${bind.next}' --bind next=middle
c add channel bench --transport local --clients single
c check
