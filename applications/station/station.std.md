# com.yoke.station, written with the composer alone

| | |
| --- | --- |
| **Feature** | the example application at its two versions, 2.1.0 and 2.2.0, written by `compose.sh` with the newest published composer's verbs and nothing typed by hand: the units, the kinds, the order, the parameters in their groups, the two channels and the one arbitration the worked example declares, and in 2.2.0 the migration unit and the data range; the gate refusing nothing in either, and each built into a package; and `com.yoke.station.device`, the example as a device runs it alone, written by `compose-device.sh` the same way: the units that run on the host, with no unit in a container |
| **Planning item** | yoke-project/yoke-reference#31 · yoke-project/yoke-reference#66 |

## yoke-reference:station.01 — both versions are written by the composer's verbs, refused nothing, and built

| Field | Value |
| --- | --- |
| **Cites** | specs/95.30 · specs/97.1 · specs/97.2 · specs/97.17 · arch/20-composer/01 §The verbs |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the composer of the newest programs release, obtained through the public module proxy; the Manifests of `acquire`, `pipeline` and `archive` from this tree; two host executables, and an image reference for each containerised unit |
| **Action** | run `compose.sh` for 2.1.0 and for 2.2.0; `yoke-compose check` and `yoke-compose build` each |
| **Expected** | every verb exits 0; `check` refuses nothing and notes only that `remote` is on the loopback address; each build writes one package; 2.1.0 holds `provision-store`, `acquire`, `pipeline`, `archive` and `panel`, with `acquire`, `pipeline` and `archive` depending on `provision-store` and `panel` on `pipeline`, the parameters `shared.site_label`, `acquire.instrument`, `archive.retention_days` and `remote.listen_port`, the channels `panel` and `remote`, and `panel` prevailing over `remote`; 2.2.0 holds the same and `migrate-store`, with `migrates_from: "<2.2"`, on which `acquire`, `pipeline` and `archive` depend, and both declare `data: ">=2.0"` |

## yoke-reference:station.02 — the device's form is written by the composer's verbs, refused nothing, and built

| Field | Value |
| --- | --- |
| **Cites** | specs/95.30 · arch/20-composer/01 §The verbs |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the composer of `.01`; the Manifest of `acquire` from this tree; two host executables |
| **Action** | run `compose-device.sh`; `yoke-compose check` and `yoke-compose build` |
| **Expected** | every verb exits 0; `check` refuses nothing; the build writes one package; the project holds `acquire` and `panel` and no other unit, `panel` depending on `acquire`, binding the framebuffer `/dev/fb0` as a device and drawing to it; the parameters `shared.site_label` and `acquire.instrument`; the one channel `panel` |
