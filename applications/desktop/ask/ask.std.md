# ask, the desktop bench's Plugin that must ask the person something

| | |
| --- | --- |
| **Feature** | `com.yoke.reference.ask`, written against the published Rust plugin library like anyone's: told to join a network, it needs a passphrase only the person at the interface knows, and asks for it the only way a passive Plugin can — an occurrence, `ask.needed`, naming the ask, and a command, `ask.answer`, carrying the answer; `ask.pending` tells the open asks and the sequence they reflect to an interface that comes late, every occurrence carrying the sequence it was reported at; an ask is settled once, by the first well-formed answer, a withdrawal or its time running out, and `ask.settled` says how; the answer is in nothing it says |
| **Planning item** | yoke-project/yoke-reference#75 |

## yoke-reference:ask.01 — the Manifest installed beside it is the one its declaration generates

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/06 §The declaration a plugin library produces |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the committed `com.yoke.reference.ask.yaml` |
| **Action** | generate the Manifest from the declaration |
| **Expected** | the two are byte for byte the same; the declaration is `com.yoke.reference.ask`, and each of `ask.join`, `ask.answer`, `ask.withdraw`, `ask.pending`, `ask.needed` and `ask.settled` is governed by one capability |

## yoke-reference:ask.02 — a join is accepted, and the ask reported with its sequence

| Field | Value |
| --- | --- |
| **Cites** | specs/50.104 · specs/70.51 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | no ask open, acting on a Session that records what it is given |
| **Action** | command `ask.join` for the network `bench`; then the same again |
| **Expected** | the first is acknowledged accepted, and `ask.needed` reported with the Plugin's own severity, its line in the detail too, the detail naming the ask `a1`, the network, that the answer is a secret, when the ask runs out and the sequence 1; the second fails, naming `a1` as already asking |

## yoke-reference:ask.03 — an interface that comes late is told the open asks and their sequence

| Field | Value |
| --- | --- |
| **Cites** | specs/70.51 · arch/70-interface-surface/07 §The present, for a client that subscribes late |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | no ask open; then the ask `a1` of `.02` |
| **Action** | ask `ask.pending`, each time |
| **Expected** | with none open it is answered sequence 0 and no asks; with `a1` open, sequence 1, the sequence of `a1`'s own occurrence, and `a1` with its network |

## yoke-reference:ask.04 — the first answer settles the ask, and one after it is told so

| Field | Value |
| --- | --- |
| **Cites** | specs/50.104 · specs/70.51 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the ask `a1` open |
| **Action** | command `ask.answer` for `a1` with a well-formed passphrase, twice; then ask `ask.pending` |
| **Expected** | the first is acknowledged done and `ask.settled` reported as accepted at sequence 2; the second fails, saying `a1` is not open; the present is sequence 2 with no asks |

## yoke-reference:ask.05 — the answer is in nothing the Plugin says

| Field | Value |
| --- | --- |
| **Cites** | specs/31.23 · specs/50.104 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the ask `a1` open |
| **Action** | answer it with a passphrase too short, with no ask named, with an ask not open, with a payload that is not JSON, and well; then ask `ask.pending` |
| **Expected** | no acknowledgement's line, no occurrence's line or detail and no answer holds any part of the passphrase |

## yoke-reference:ask.06 — an answer that is not one leaves the ask open

| Field | Value |
| --- | --- |
| **Cites** | specs/50.104 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the ask `a1` open |
| **Action** | answer it with a passphrase of five characters; then ask `ask.pending` |
| **Expected** | the answer fails, saying `a1` stays open and why; nothing is reported; `a1` is still in the present |

## yoke-reference:ask.07 — an ask is withdrawn at the interface, or when its time runs out

| Field | Value |
| --- | --- |
| **Cites** | specs/50.104 · specs/70.51 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the ask `a1` open; asks that stay open 60 seconds |
| **Action** | command `ask.withdraw` for `a1`; then join another network, and let the time pass to a millisecond before its ask runs out, and to the moment it does |
| **Expected** | `a1` is settled as withdrawn; the second ask, `a2`, is the next deadline; nothing runs out before its time, and at it `a2` is settled as expired at sequence 4; with no ask open there is no deadline |
