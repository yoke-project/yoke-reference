# The LVGL panel, a reference interface in C

| | |
| --- | --- |
| **Feature** | the Qt panel's twin for a device with a framebuffer: a managed interface written in C with LVGL against the published C interface library, attaching to the channel the Core hands it; it composes its screen from the opening picture — the channel's own state, and for each unit what the channel may address on it, with a button for each command and each question — keeps that picture current by reading again each subject an event of its own subscription names, replaces it on an overflow, and confirms only what it has applied; it draws to a framebuffer on a device and to memory under a test, and is built from the C family's source release and from an LVGL the build provides, as an image build provides one, or else from LVGL's release by the digest it pins |
| **Planning item** | yoke-project/yoke-reference#55 · yoke-project/yoke-reference#61 |

## yoke-reference:the-lvgl-panel.01 — the picture is the opening, held by subject

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

## yoke-reference:the-lvgl-panel.02 — an event reads its subject again, an overflow replaces the picture, and only what is applied is confirmed

| Field | Value |
| --- | --- |
| **Cites** | specs/31.31 · specs/70.7 · specs/70.32 · specs/70.33 · arch/70-interface-surface/05 §What a subscription promises |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the picture of `.01`, and a reader that answers `unit` `acquire` with its record now `Failed`, says `provision-store` is gone, and cannot read `acquire` a second time |
| **Action** | apply an event for `acquire`; one for `provision-store`; one for `acquire` that cannot be read; then replace the picture with another |
| **Expected** | the first puts the record the reader gave in its place and the picture is current as of the event; the second takes the subject out; the third is not applied, the picture is as it was and nothing is to be confirmed; the replacement is the picture |

## yoke-reference:the-lvgl-panel.03 — the screen is composed from the picture

| Field | Value |
| --- | --- |
| **Cites** | specs/70.9 · arch/70-interface-surface/03 §The opening picture |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the picture of `.01`, and a display in memory |
| **Action** | compose the screen from it |
| **Expected** | the channel is one line saying it is `panel`, local and attached; each unit is a line saying its state and what the channel may address on it; `acquire` has a button for its command and one for its question, and a unit that was given none has none |

## yoke-reference:the-lvgl-panel.04 — a button does what the panel is told, and the screen says what came of it

| Field | Value |
| --- | --- |
| **Cites** | specs/70.12 · arch/70-interface-surface/04 §The eleven |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the screen of `.03`, and a panel told what to do for a command and for a question |
| **Action** | press the button of the command, then the button of the question |
| **Expected** | the command is carried out once, for that unit and that type, and the screen says what came of it; the question is asked once and the screen says the answer |

## yoke-reference:the-lvgl-panel.05 — the screen is drawn to the display

| Field | Value |
| --- | --- |
| **Cites** | arch/90-sdks/07 §What is still owed |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the screen of `.03` |
| **Action** | draw it; open a display named by something that is not one |
| **Expected** | the display is flushed at least once; the second display is refused |

## yoke-reference:the-lvgl-panel.06 — the published Core launches the panel on its channel, which composes the clock and keeps it current

| Field | Value |
| --- | --- |
| **Cites** | specs/70.9 · arch/70-interface-surface/03 §The opening picture · arch/70-interface-surface/05 §What a subscription promises |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the host archive the manifest names as latest, authenticated by its digest; the panel, built against the C family's newest source release and LVGL; an instance holding the Go clock and the panel as a managed interface on its channel, `clients: single`, drawing to memory |
| **Action** | start the Core; grant the clock its question and its command; restart the clock; read the panel's log; stop the Core |
| **Expected** | the panel says it attached; composed the clock from the opening, and kept it current — the clock running with its command and its question — after the grants and the restart; it stops with the Core and does not outlive it |

## yoke-reference:the-lvgl-panel.07 — the panel is built against an LVGL the build provides, and downloads nothing

| Field | Value |
| --- | --- |
| **Cites** | prj_structure/40 E2 · prj_structure/97 §What a recipe pins, and what offline means |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the C family of `.06`; LVGL's release, by the digest the panel pins, built with the panel's configuration and installed under a prefix of the case's own, which the build is told of by `pkg-config` |
| **Action** | configure and build the panel with downloads forbidden |
| **Expected** | the panel builds; the program links the LVGL of the prefix; nothing was downloaded |

## yoke-reference:the-lvgl-panel.08 — with no LVGL provided and no download allowed, the build is refused, naming LVGL

| Field | Value |
| --- | --- |
| **Cites** | prj_structure/40 E2 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the C family of `.06`; no LVGL the build can find |
| **Action** | configure the panel with downloads forbidden |
| **Expected** | the configuration is refused, and its error names LVGL |
