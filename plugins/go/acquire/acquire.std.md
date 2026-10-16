# acquire, a reference Plugin in Go, and the instrument it drives

| | |
| --- | --- |
| **Feature** | the example's `acquire`: a Plugin on the host, written against the published Go plugin library, that drives a spectrometer over the serial device its unit binds, publishes what it measures on `station.spectra` and what it reads of itself on `station.diagnostics` only while each is activated, and reports its reference lamp's drift as `calibration.drift` with a severity it states itself; and the test program that plays the spectrometer on the master end of a pseudo-terminal pair |
| **Planning item** | yoke-project/yoke-reference#27 |

## yoke-reference:acquire.01 — the Manifest installed beside it is the example's, and its declaration generates it

| Field | Value |
| --- | --- |
| **Cites** | specs/40.12 · specs/42.11 · specs/90.42 · arch/90-sdks/06 §The declaration a plugin library produces |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `acquire`'s committed `manifest.yaml` |
| **Action** | generate the Manifest from `acquire`'s declaration |
| **Expected** | the two are byte for byte the same; the declaration is `com.yoke.station.acquire`, needing `device:instrument`, with the streams `station.spectra` and `station.diagnostics`, neither tolerating loss or reorder, the occurrence `calibration.drift`, and one capability governing each of the three |

## yoke-reference:acquire.02 — the instrument answers a scan, its lamp, and nothing else, across a pseudo-terminal

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the instrument on the master end of a pseudo-terminal pair, its lamp drifting 3 parts in a thousand from its third reading, and a link naming the slave end |
| **Action** | open the link raw, and write `SCAN`, `LAMP` three times, and `HELLO`, one line each |
| **Expected** | `SCAN` is answered `SPECTRUM 1` and sixteen counts; the three `LAMP`s are answered `LAMP 0`, `LAMP 0` and `LAMP 3`; `HELLO` is answered `ERR HELLO`; nothing written is echoed back |

## yoke-reference:acquire.03 — a spectrum is emitted only while its stream is activated

| Field | Value |
| --- | --- |
| **Cites** | specs/50.86 · specs/00.10 · specs/25.29 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `acquire` labelled `bench a`, granted `stream.spectra.publish`, on an instrument answering every scan, acting on a Session that records what it is given |
| **Action** | scan once; activate `station.spectra` and scan twice; stop it and scan once more |
| **Expected** | every scan is asked of the instrument; only the two scans while the stream is activated are emitted, on `station.spectra`, each one JSON object carrying the label `bench a`, the instrument's scan number and its sixteen counts |

## yoke-reference:acquire.04 — a withheld stream is never written to, and acquiring goes on

| Field | Value |
| --- | --- |
| **Cites** | specs/50.28 · specs/50.30 · specs/97.10 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `acquire` granted `stream.spectra.publish` and with `station.diagnostics` withheld, `station.spectra` activated, acting on a Session that records what it is given |
| **Action** | scan three times |
| **Expected** | three spectra are emitted on `station.spectra`, nothing is emitted on `station.diagnostics`, and the only health reported is grade 0, *acquiring* |

## yoke-reference:acquire.05 — a drift of the lamp is reported once, with acquire's own severity and what the drift was

| Field | Value |
| --- | --- |
| **Cites** | specs/31.15 · specs/31.49 · specs/32.34 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `acquire` granted `occurrence.calibration.drift.report`, on an instrument whose lamp reads 0, 3, 4, 0 and 3 parts in a thousand on successive readings, acting on a Session that records what it is given |
| **Action** | scan five times |
| **Expected** | `calibration.drift` is reported twice — at the second reading and at the fifth, never while the drift lasts — each with severity 50, the line `the reference lamp has drifted 3 parts in a thousand` and the detail `{"lamp_ppt":3}` |

## yoke-reference:acquire.06 — a drift is not reported when reporting it is withheld

| Field | Value |
| --- | --- |
| **Cites** | specs/50.30 · specs/50.28 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `acquire` with `calibration.drift` withheld, on an instrument whose lamp reads 3 parts in a thousand, acting on a Session that records what it is given |
| **Action** | scan twice |
| **Expected** | nothing is reported, so nothing exceeds the scope the Core granted; acquiring goes on |

## yoke-reference:acquire.07 — an instrument that falls silent is said in the health report, and so is its return

| Field | Value |
| --- | --- |
| **Cites** | specs/50.65 · specs/50.66 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `acquire` on an instrument that answers, then stops answering for two scans, then answers again, acting on a Session that records what it is given |
| **Action** | scan four times |
| **Expected** | the health reported is grade 0 *acquiring*, then grade 60 `the instrument does not answer` once, then grade 0 *acquiring* again: a report each time how it is changes, and none otherwise |

## yoke-reference:acquire.08 — acquire opens the device by the name its unit binds, raw, and reads a spectrum across it

| Field | Value |
| --- | --- |
| **Cites** | specs/12.38 · specs/12.35 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the instrument on the master end of a pseudo-terminal pair, and a link naming the slave end; `acquire` granted `stream.spectra.publish` with `station.spectra` activated, acting on a Session that records what it is given |
| **Action** | open the device by the link, as `acquire --device <link>` does, and scan once; then open a path that does not exist |
| **Expected** | one spectrum is emitted, carrying the instrument's scan 1 and its sixteen counts; opening the missing path fails naming it |

## yoke-reference:acquire.09 — the published Core admits acquire on the device its unit binds, and its grant reaches it on a restart

| Field | Value |
| --- | --- |
| **Cites** | specs/97.10 · specs/97.14 · specs/12.35 · specs/50.26 · specs/50.86 · specs/31.49 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the `yoke-core` and `yoke` of the release `acquire`'s library was cut with, downloaded and authenticated against the release manifest; the instrument on a pseudo-terminal pair, its lamp drifting after a few readings, and a link naming the slave end; an instance in the service form with `acquire` built, its Manifest installed, and one unit of kind `plugin` naming it and binding `instrument` to the link; nothing granted |
| **Action** | start the Core and wait for the unit to run; grant `stream.spectra.publish` and `occurrence.calibration.drift.report`, and restart the unit; start `station.spectra`, wait, and stop it; start `station.diagnostics`; wait past the Core's liveness window; stop the Core |
| **Expected** | the first incarnation is admitted with what it declares withheld; the second is admitted with restrictions and is `Running`, and its scope is the grant: the spectra stream stops having read at least one spectrum, with no gap in its sequence, and starting `station.diagnostics` is refused as withheld; `calibration.drift` is reported about the second incarnation with severity 50; the Session is never revoked; when the Core stops it, `acquire` closes its Session itself, the unit is `Stopped`, and no `acquire` process remains |
