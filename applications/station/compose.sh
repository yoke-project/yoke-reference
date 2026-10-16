#!/usr/bin/env bash
# Writes the example application, com.yoke.station, at one of its two versions, with the composer's verbs
# alone: nothing in the project is typed by hand. The images are named by the digests they were built
# with, so the project is written for the images in hand rather than kept.
#
# Usage: compose.sh <yoke-compose> <dir> <2.1.0|2.2.0> <arch> <acquire> <panel> <images>
#   <acquire>, <panel>   the host executables the project carries
#   <images>             a file of `<unit>=<reference@digest>` lines: provision-store, pipeline,
#                        archive, and migrate-store for 2.2.0
set -euo pipefail

compose="$1" dir="$2" version="$3" arch="$4" acquire="$5" panel="$6" images="$7"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
image() { sed -n "s/^$1=//p" "$images"; }
# Each verb is said before it runs, so a refusal names the verb it answers.
c() { echo "+ $*" >&2; "$compose" "$@" --dir "$dir" > /dev/null; }

c init com.yoke.station --version "$version" --arch "$arch" --core ">=0.6.0"
c set data ">=2.0"

# What the project carries: the two host executables and the Manifests of its three Plugins.
mkdir -p "$dir/components/plugins" "$dir/components/interfaces"
cp "$acquire" "$dir/components/plugins/acquire"
cp "$panel" "$dir/components/interfaces/panel"
cp "$root/plugins/go/acquire/manifest.yaml" "$dir/manifests/com.yoke.station.acquire.yaml"
cp "$root/plugins/python/pipeline/manifest.yaml" "$dir/manifests/com.yoke.station.pipeline.yaml"
cp "$root/plugins/rust/archive/manifest.yaml" "$dir/manifests/com.yoke.station.archive.yaml"

c add parameter shared.site_label --type string --pattern "^[A-Za-z0-9 _-]{1,32}$" --required \
  --label "Instrument label shown on the panel"

# A unit is written before what it refers to can be declared, and its references after: a need, a
# parameter group named after it, then the arguments that use them.
c add unit provision-store --kind oneshot --image "$(image provision-store)"
c set units.provision-store.needs "[storage:datasets]"
c set units.provision-store.args '["${bind.datasets}"]'
first=provision-store
if [[ "$version" == 2.2.0 ]]; then
  c add unit migrate-store --kind oneshot --image "$(image migrate-store)" --depends-on provision-store
  c set units.migrate-store.needs "[storage:datasets]"
  c set units.migrate-store.args '["${bind.datasets}"]'
  c set units.migrate-store.migrates_from "<2.2"
  first=migrate-store
fi

# acquire's Manifest needs a device, which the unit must bind as it is written, and `add unit` binds
# nothing: the binding goes first, as a path, the unit's other fields after it one by one, and the binding
# becomes the parameter once the group the parameter lives in names a unit.
c set units.acquire.bind.instrument /dev/null
c set units.acquire.kind plugin
c set units.acquire.plugin com.yoke.station.acquire
c set units.acquire.digest "sha256:$(sha256sum "$dir/components/plugins/acquire" | cut -d' ' -f1)"
c set units.acquire.exec components/plugins/acquire
c set units.acquire.args '["--device", "${bind.instrument}", "--label", "${site_label}"]'
c set units.acquire.depends_on "[$first]"
c add parameter acquire.instrument --type path --required --label "Stable device name of the spectrometer"
c set units.acquire.bind.instrument '${instrument}'

c add unit pipeline --kind plugin --plugin com.yoke.station.pipeline --image "$(image pipeline)" \
  --arg --site --arg '${site_label}' --depends-on "$first"
c set units.pipeline.policy.startup_window 90s

c add unit archive --kind plugin --plugin com.yoke.station.archive --image "$(image archive)" --depends-on "$first"
c add parameter archive.retention_days --type integer --range "[1, 3650]" --default 90 \
  --label "How long acquired datasets are kept"
c set units.archive.args '["--keep-days", "${retention_days}", "--store", "${bind.datasets}"]'

c add unit panel --kind interface --exec components/interfaces/panel --depends-on pipeline
c set units.panel.needs "[display]"
c set units.panel.env.STATION_LABEL '${site_label}'

c add channel panel --transport local --clients single --unit panel
c add channel remote --transport http+ws --clients single --class loopback --port 8080
c add parameter remote.listen_port --type integer --range "[1024, 65535]" --default 8080 \
  --label "Diagnostics port — reachable by any account on this host"
c set channels.remote.address.port '${listen_port}'
c arbitrate panel over remote
