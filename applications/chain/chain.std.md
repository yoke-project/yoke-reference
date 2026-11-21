# The chain

| | |
| --- | --- |
| **Feature** | the chain, `com.yoke.reference.chain`: an application written by `compose.sh` with the composer's verbs alone — three Plugin units, each using the next through a need of class `unit`: `front` and `middle`, two copies of `link`, and `back`, the chain's last link, `end` — and the chain's client, which asks `front` from the channel `bench`; each link answers by asking the unit its need is bound to, naming the question it answers as the cause, and follows that unit's stream from the start |
| **Planning item** | yoke-project/yoke-reference#83 |

## yoke-reference:chain.01 — the chain is written with the composer's verbs alone, and states no order

| Field | Value |
| --- | --- |
| **Cites** | specs/40.25 · specs/28.58 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the newest published composer |
| **Action** | run `compose.sh` into an empty directory |
| **Expected** | every verb is taken and the gate passes the project; it holds `back` of `com.yoke.reference.chain.end`, and `middle` and `front` of `com.yoke.reference.chain.link`, `middle`'s need `next` bound to `back` and `front`'s to `middle`; no unit states an order |

## yoke-reference:chain.02 — the order the units start in is derived from the bindings

| Field | Value |
| --- | --- |
| **Cites** | specs/28.58 · specs/28.61 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the chain of `.01` |
| **Action** | run it under the newest published Core; grant each Plugin what its Manifest declares, and start the units again in turn |
| **Expected** | the units reach `Running` in the order `back`, `middle`, `front`; each runs again holding its grants |

## yoke-reference:chain.03 — a question asked along the chain carries its deadline and its chain

| Field | Value |
| --- | --- |
| **Cites** | specs/50.107 · specs/50.108 · specs/50.109 · specs/50.110 · specs/70.59 · specs/70.60 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the chain of `.02` running, every grant held |
| **Action** | from the channel `bench`, ask `front` `chain.ask` |
| **Expected** | the answer holds `front`, `middle` and `back` in that order; each was asked by `channel:bench`, `unit:front` and `unit:middle`; all three questions carry one chain of 32 hex digits; the first deadline is about 30 s ahead and each is 500 ms short of the one before; `unit.question.chained` is reported on `middle` and on `back` with that chain |

## yoke-reference:chain.04 — a restart in the middle of the chain is survived

| Field | Value |
| --- | --- |
| **Cites** | specs/28.60 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the chain of `.03`, `front` following `middle`'s `chain.ticks` |
| **Action** | restart `middle`; ask `front` again |
| **Expected** | `front` is answered through `middle` and `back` again; it counts more frames of `middle`'s stream than before the restart; `front` itself was not restarted |

## yoke-reference:chain.05 — a stream a unit follows through its need is held

| Field | Value |
| --- | --- |
| **Cites** | specs/70.58 |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the chain of `.04`: `front` following `middle`'s `chain.ticks`, `middle` following `back`'s |
| **Action** | from `bench`, stop `middle`'s `chain.ticks`, then `back`'s; then stop `middle`'s as the operator |
| **Expected** | the first is refused `stream.held` naming `front`, the second `stream.held` naming `middle`; the operator's stop is answered |
