# The clock, a reference Plugin in Go

| | |
| --- | --- |
| **Feature** | a small Plugin written against the published Go plugin library like anyone's: it declares one question, one command and one occurrence, each governed by a capability; it answers the question with the time and marks the time when told, reporting the mark with a severity it states itself |
| **Planning item** | yoke-project/yoke-reference#1 |

## yoke-reference:the-clock.01 — the Manifest installed beside it is the one its declaration generates

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/07 §What each one is · arch/90-sdks/06 §The declaration a plugin library produces |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the clock's committed `manifest.yaml` |
| **Action** | generate the Manifest from the clock's declaration |
| **Expected** | the two are byte for byte the same; the declaration is `com.yoke.reference.clock`, with the question `clock.now`, the command `clock.mark` and the occurrence `clock.marked`, each governed by one capability |

## yoke-reference:the-clock.02 — a question for the time is answered with it

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/07 §What each one is |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a clock whose time is 2026-09-26 12:00:00 UTC, acting on a Session that records what it is given |
| **Action** | ask it `clock.now` |
| **Expected** | the question is answered, correlated to it, with `2026-09-26T12:00:00Z` |

## yoke-reference:the-clock.03 — a mark is acknowledged, and reported with the clock's own severity

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · specs/90.34 · arch/90-sdks/07 §What each one is |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a clock whose time is 2026-09-26 12:00:00 UTC, acting on a Session that records what it is given |
| **Action** | command it `clock.mark` |
| **Expected** | the command is acknowledged as done, correlated to it, with `marked at 2026-09-26T12:00:00Z`; the occurrence `clock.marked` is reported with severity 10 and the same line |
