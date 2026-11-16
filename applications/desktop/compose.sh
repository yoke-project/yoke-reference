#!/usr/bin/env bash
# Writes the desktop bench, com.yoke.reference.desktop, with the composer's verbs alone: the pool's
# hw-monitor, taken at its tag, and one local channel, `desktop`, that no unit is launched for. A desktop
# shell, or bench.qml, is attached to it from outside, started beside the application as a compositor
# starts its shell.
#
# Usage: compose.sh <yoke-compose> <dir> <arch> [<plugin>]
#   <plugin>   what `add plugin` takes; the pool's hw-monitor at the tag the bench is measured with when
#              it is not given
set -euo pipefail

compose="$1" dir="$2" arch="$3"
plugin="${4:-https://github.com/yoke-project/yoke-plugin-hw-monitor@v0.2.0}"
# Each verb is said before it runs, so a refusal names the verb it answers.
c() { echo "+ $*" >&2; "$compose" "$@" --dir "$dir" > /dev/null; }

c init com.yoke.reference.desktop --version 1.0.0 --arch "$arch" --core ">=0.15.0"
c add plugin "$plugin" --as hw-monitor --yes
c add channel desktop --transport local --clients single
c check
