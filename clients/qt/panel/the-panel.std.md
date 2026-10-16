# The Qt panel, a reference interface in C++

| | |
| --- | --- |
| **Feature** | the example's `panel`: a managed interface written in C++ with Qt against the published C++ interface library, attaching to the channel the Core hands it; it composes itself from the opening picture as the web client does — the channel's own state, and for each unit what the channel may address on it — keeps that picture current by reading again each subject the standing subscription names, replaces it whole on an overflow, confirms only what it has applied, and names no unit, Plugin or domain of its own |
| **Planning item** | yoke-project/yoke-reference#32 |

## yoke-reference:the-panel.01 — the picture is the opening, held by subject

| Field | Value |
| --- | --- |
| **Cites** | specs/70.9 · arch/70-interface-surface/03 §The opening picture · arch/90-sdks/07 §What each one is |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an opening at the sequence 4 holding the instance, the channel `panel` and the units `acquire` and `provision-store` |
| **Action** | make the picture from it |
| **Expected** | the picture is at 4, holds the instance, the channel and the two units in the order they came, each by its subject |

## yoke-reference:the-panel.02 — an event reads its subject again, an overflow replaces the picture, and only what is applied is confirmed

| Field | Value |
| --- | --- |
| **Cites** | specs/70.7 · specs/70.32 · specs/70.33 · arch/70-interface-surface/05 §What a subscription promises |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the picture of `.01`, and a reader that answers `unit` `acquire` with its record now `Running`, and cannot read `unit` `gone` |
| **Action** | apply an event at 5 about `acquire`; apply an event at 6 about `gone`; apply an overflow at 9 holding only the channel |
| **Expected** | after the first `acquire` is `Running` and the sequence to confirm is 5; after the second it is still 5, the picture behind; after the overflow the picture holds the channel alone and the sequence to confirm is 9 |

## yoke-reference:the-panel.03 — the window is composed from the picture, and names nothing of its own

| Field | Value |
| --- | --- |
| **Cites** | specs/70.6 · specs/70.27 · arch/90-sdks/07 §What each one is |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a picture holding the channel `panel` on a local socket, suspended in grade `read-only` in favour of `remote`; `acquire` `Running` with the condition `acquiring`, addressed with the stream `station.spectra`; `pipeline` addressed with the question `spectrum.identify` and the command `pipeline.reindex`; `provision-store` addressed with nothing |
| **Action** | compose the window from it, offscreen |
| **Expected** | the channel line says it is suspended, `read-only`, `remote` prevailing, and offers to reclaim; `acquire`'s card shows `Running · acquiring` and a row for `station.spectra` with start, stop and watch; `pipeline`'s card has one ask button for `spectrum.identify` and one command button for `pipeline.reindex`; `provision-store`'s card says nothing is addressed; the panel's sources name no unit, Plugin or stream |

## yoke-reference:the-panel.04 — the published Core launches it on its channel, and it composes itself from what it is given

| Field | Value |
| --- | --- |
| **Cites** | specs/70.19 · specs/70.21 · specs/97.12 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the `yoke-core` and `yoke` of the newest release, downloaded and authenticated against the release manifest; the C++ family's newest source release, downloaded, authenticated and installed under a prefix, and the panel built against it; a project's working directory whose units are the Go clock and `panel`, of kind `interface`, served by a local channel `panel` of a single client, offscreen; the clock granted its question |
| **Action** | execute the Core on that directory in the application form; wait for both units to run; read the panel's output from the log store; stop the Core |
| **Expected** | the panel attached to the channel the Core handed it and composed a card for the clock, with an ask button for `clock.now` and a command button for `clock.mark`, and saw the clock `Running`; when the Core stops it, the panel's process is gone |
