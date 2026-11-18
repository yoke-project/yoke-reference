# The desktop bench

| | |
| --- | --- |
| **Feature** | the desktop bench, `com.yoke.reference.desktop`: an application written by `compose.sh` with the composer's verbs alone — the pool's `hw-monitor` taken at its tag, the bench's own `ask` taken from beside it, and one local channel, `desktop`, that no unit is launched for — and `bench.qml`, a QML document anyone could have written, started beside the application as a compositor starts a desktop shell, attached to `desktop` with the C++ family's QML binding as published: it subscribes to the CPU and memory streams, starts them, then asks the snapshot, and joins the two by the sequence each value carries; it answers what `ask` asks the person, learning of an ask from its occurrence or, when it attaches after it, from `ask.pending`; it is nobody's shell, and what the release's measurements are taken with |
| **Planning item** | yoke-project/yoke-reference#74 · yoke-project/yoke-reference#75 |

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
| **Expected** | every verb is taken and the gate passes the project; it holds the unit `hw-monitor` of the Plugin `com.yoke.hw-monitor`, recorded in `plugins.yaml` at the tag it was taken from, the unit `ask` of `com.yoke.reference.ask`, and the channel `desktop`, local, for a single client, naming no unit |

## yoke-reference:desktop.02 — the document attached beside the application sees the snapshot and follows the streams

| Field | Value |
| --- | --- |
| **Cites** | specs/70.9 · specs/70.19 · specs/70.21 · specs/70.6 · specs/90.22 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the bench of `.01` running under the newest published Core, `hw-monitor` and `ask` granted what their Manifests declare; the C++ family's newest source release built with its QML binding and installed under a prefix |
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

## yoke-reference:desktop.05 — the document answers what a Plugin asks the person

| Field | Value |
| --- | --- |
| **Cites** | specs/50.104 · specs/70.51 · specs/31.23 · arch/70-interface-surface/07 §The present, for a client that subscribes late |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the run of `.04`, its document stopped; a document started with an answer to give, in place of a person, which has followed `ask`'s occurrences and joined `ask.pending`'s present, with no ask open |
| **Action** | tell `ask`, over the operator's surface, to join the network `bench` |
| **Expected** | the document is told of the ask `a1` by its occurrence, at sequence 1; it answers it with `ask.answer`, whose acknowledgement is done; it is told the ask is settled as accepted, at sequence 2; and the answer is in none of the Core's output, its state directory, the log store as `yoke log query` shows it, nor what the document said |

## yoke-reference:desktop.06 — a document that attaches after the ask learns of it and answers it

| Field | Value |
| --- | --- |
| **Cites** | specs/70.51 · specs/70.9 · arch/70-interface-surface/07 §The present, for a client that subscribes late |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the run of `.05`, its document stopped, so that nothing is attached to `desktop` |
| **Action** | tell `ask` to join the network `late`; then start a document with an answer to give |
| **Expected** | the document joins `ask.pending`'s present at sequence 3, which holds the ask `a2`, and is not told again of `a1`, settled before it came; it answers `a2`, the acknowledgement is done, and it is told `a2` is settled as accepted at sequence 4; the answer is still in none of the places of `.05` |
