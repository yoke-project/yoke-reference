# The desktop bench

| | |
| --- | --- |
| **Feature** | the desktop bench, `com.yoke.reference.desktop`: an application written by `compose.sh` with the composer's verbs alone — the pool's `hw-monitor` taken at its tag, and one local channel, `desktop`, that no unit is launched for — and `bench.qml`, a QML document anyone could have written, started beside the application as a compositor starts a desktop shell, attached to `desktop` with the C++ family's QML binding as published: it subscribes to the CPU and memory streams, starts them, then asks the snapshot, and joins the two by the sequence each value carries; it is nobody's shell, and what the release's measurements are taken with |
| **Planning item** | yoke-project/yoke-reference#74 |

## yoke-reference:desktop.01 — the bench is written with the composer's verbs alone

| Field | Value |
| --- | --- |
| **Cites** | specs/70.19 · specs/70.20 · specs/70.42 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the newest published composer; the pool's `hw-monitor` at its tag |
| **Action** | run `compose.sh` into an empty directory |
| **Expected** | every verb is taken and the gate passes the project; it holds the unit `hw-monitor` of the Plugin `com.yoke.hw-monitor`, recorded in `plugins.yaml` at the tag it was taken from, and the channel `desktop`, local, for a single client, naming no unit |

## yoke-reference:desktop.02 — the document attached beside the application sees the snapshot and follows the streams

| Field | Value |
| --- | --- |
| **Cites** | specs/70.9 · specs/70.19 · specs/70.21 · specs/70.6 · specs/90.22 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the bench of `.01` running under the newest published Core, `hw-monitor` granted what its Manifest declares; the C++ family's newest source release built with its QML binding and installed under a prefix |
| **Action** | start `bench.qml` with Qt's `qml` runtime, the binding's import path and the instance's name, beside the application and with no window system |
| **Expected** | the document says it attached to `desktop` under the contract's version; it is answered the snapshot, a JSON object stating `schema` and `at_ms`; both streams are started, and each delivers at least three frames, their sequences rising |

## yoke-reference:desktop.03 — the document is started beside the application, not by it

| Field | Value |
| --- | --- |
| **Cites** | specs/70.19 · specs/70.20 · specs/70.44 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the run of `.02`, the document still attached |
| **Action** | start a second document on the same channel; then stop the first, and start another |
| **Expected** | the second is refused the channel, which takes a single client, and the first keeps following; once the first is stopped the application goes on running, no unit of it having ended, and the next document attaches and follows the streams again |

## yoke-reference:desktop.04 — the document joins the present to what follows it without a gap

| Field | Value |
| --- | --- |
| **Cites** | specs/70.51 · arch/70-interface-surface/07 §The present, for a client that subscribes late |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the run of desktop.03: the Core, hw-monitor at 0.3.0 granted and running, and the third document attached, having subscribed to both streams, started them, and asked the snapshot |
| **Action** | read what the document said for a few seconds |
| **Expected** | for each stream it joined at the sequence the snapshot stated, and the values it applied after go on from the next one, one by one, with no gap said |
