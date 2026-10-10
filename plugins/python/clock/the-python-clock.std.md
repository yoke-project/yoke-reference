# The clock, a reference Plugin in Python

| | |
| --- | --- |
| **Feature** | the Go clock's twin, written against the published Python plugin library like anyone's and built from the registry alone: it declares one question, one command and one occurrence, each governed by a capability; it answers the question with the time and marks the time when told, reporting the mark with a severity it states itself; and the published Core admits it |
| **Planning item** | yoke-project/yoke-reference#19 |

## yoke-reference:the-python-clock.01 — the Manifest installed beside it is the one its declaration generates

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

## yoke-reference:the-python-clock.02 — a question for the time is answered with it

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

## yoke-reference:the-python-clock.03 — a mark is acknowledged, and reported with the clock's own severity

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

## yoke-reference:the-python-clock.04 — the published Core admits it, and it leaves in order when stopped

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the `yoke-core` of the release the clock's library was cut with, downloaded and authenticated against the release manifest; an instance in the service form with the clock built, its Manifest installed, and one unit of kind `plugin` naming it; nothing granted |
| **Action** | start the Core, wait for the unit to run, then stop the Core |
| **Expected** | the unit is admitted with what it declares withheld, since nothing is granted, and never refused; its Session opens and the unit is `Running`; when the Core stops it, the clock closes its Session itself, the unit is `Stopped`, and no clock process remains |
