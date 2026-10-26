#!/usr/bin/env bash
# Writes com.yoke.station.device, the example application as a device runs it alone, with the composer's
# verbs alone: the units that run on the host — acquire on its instrument, and the LVGL panel drawing to the
# framebuffer — and no unit in a container, so a host with no container engine runs it.
#
# Usage: compose-device.sh <yoke-compose> <dir> <arch> <acquire> <panel>
#   <acquire>, <panel>   the host executables the project carries; the panel is the LVGL one
set -euo pipefail

compose="$1" dir="$2" arch="$3" acquire="$4" panel="$5"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Each verb is said before it runs, so a refusal names the verb it answers.
c() { echo "+ $*" >&2; "$compose" "$@" --dir "$dir" > /dev/null; }

c init com.yoke.station.device --version 2.1.0 --arch "$arch" --core ">=0.6.0"

# What the project carries: the two host executables and acquire's Manifest.
mkdir -p "$dir/components/plugins" "$dir/components/interfaces"
cp "$acquire" "$dir/components/plugins/acquire"
cp "$panel" "$dir/components/interfaces/panel"
cp "$root/plugins/go/acquire/manifest.yaml" "$dir/manifests/com.yoke.station.acquire.yaml"

c add parameter shared.site_label --type string --pattern "^[A-Za-z0-9 _-]{1,32}$" --required \
  --label "Instrument label shown on the panel"

# acquire as compose.sh writes it: the binding first, as a path, then the unit's fields, then the parameter
# the binding becomes.
c set units.acquire.bind.instrument /dev/null
c set units.acquire.kind plugin
c set units.acquire.plugin com.yoke.station.acquire
c set units.acquire.digest "sha256:$(sha256sum "$dir/components/plugins/acquire" | cut -d' ' -f1)"
c set units.acquire.exec components/plugins/acquire
c set units.acquire.args '["--device", "${bind.instrument}", "--label", "${site_label}"]'
c add parameter acquire.instrument --type path --required --label "Stable device name of the spectrometer"
c set units.acquire.bind.instrument '${instrument}'

# The panel draws to the framebuffer, which it binds as a device, after the unit it shows.
c add unit panel --kind interface --exec components/interfaces/panel --depends-on acquire
c set units.panel.needs "[device:framebuffer]"
c set units.panel.bind.framebuffer /dev/fb0
c set units.panel.env.PANEL_DISPLAY fbdev:/dev/fb0
c set units.panel.env.STATION_LABEL '${site_label}'

c add channel panel --transport local --clients single --unit panel
