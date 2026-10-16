# pipeline, a reference Plugin in Python, in a container

| | |
| --- | --- |
| **Feature** | the example's `pipeline`: a Plugin written against the published Python plugin library, run in a container from an image of its own; it builds its index of reference lines before it says it is well, answers a question identifying a spectrum against that index with the site it was told it stands in, and publishes each identification on a stream of its own only while that stream is activated |
| **Planning item** | yoke-project/yoke-reference#28 |

## yoke-reference:pipeline.01 — the Manifest installed beside it is the one its declaration generates

| Field | Value |
| --- | --- |
| **Cites** | specs/40.12 · specs/90.42 · arch/90-sdks/06 §The declaration a plugin library produces |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `pipeline`'s committed `manifest.yaml` |
| **Action** | generate the Manifest from `pipeline`'s declaration |
| **Expected** | the two are byte for byte the same; the declaration is `com.yoke.station.pipeline`, with the question `spectrum.identify` and the stream `station.identified`, which tolerates neither loss nor reorder, each governed by one capability, and no need |

## yoke-reference:pipeline.02 — a spectrum is identified against the index, with the site

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/07 §What each one is |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `pipeline` at the site `bench a`, its index built, acting on a Session that records what it is given |
| **Action** | ask `spectrum.identify` about a spectrum as `acquire` publishes it, scan 3, peaking in bin 8; then about a payload that is not a spectrum |
| **Expected** | the first is answered, correlated to it, with a JSON object carrying the site `bench a`, the scan 3, the peak bin 8, the centroid, and the reference line `lamp` at bin 8; the second is answered with a JSON object carrying the site and `error`, saying what was unreadable |

## yoke-reference:pipeline.03 — an identification is published only while its stream is activated

| Field | Value |
| --- | --- |
| **Cites** | specs/50.86 · specs/00.10 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `pipeline` at the site `bench a`, acting on a Session that records what it is given |
| **Action** | ask about a spectrum; activate `station.identified` and ask about another; stop it and ask about a third |
| **Expected** | all three are answered; only the second identification is emitted, on `station.identified`, and it is the bytes it was answered with |

## yoke-reference:pipeline.04 — it says it is well only once its index is built

| Field | Value |
| --- | --- |
| **Cites** | specs/50.65 · specs/50.66 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a Session that records what it is given |
| **Action** | start `pipeline` on it |
| **Expected** | its first act is a health report of grade 0 naming how many reference lines its index holds, made after the index is built |

## yoke-reference:pipeline.05 — the published Core runs its image in a container, and it answers

| Field | Value |
| --- | --- |
| **Cites** | specs/45.1 · specs/45.5 · specs/45.15 · specs/97.10 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the `yoke-core` and `yoke` of the release `pipeline`'s library was cut with, downloaded and authenticated against the release manifest; Podman serving its API on a socket of the case's own; `pipeline`'s image built from its `Containerfile` and named by its digest; a project's working directory holding `pipeline`'s Manifest and a descriptor whose one unit of kind `plugin` runs that image with `--site "bench a"`; nothing granted |
| **Action** | execute the Core on that directory in the application form, with the engine's address, and wait for the unit to run; grant `query.identify.answer` and restart the unit; ask it `spectrum.identify` about a spectrum peaking in bin 8; stop the Core |
| **Expected** | the unit is admitted at its first incarnation with what it declares withheld, and at its second with `station.identified` withheld and nothing else; it runs in a container; the question is answered with the site `bench a`, the peak bin 8 and the line `lamp`; when the Core stops it, `pipeline` closes its Session itself and the unit is `Stopped` |
