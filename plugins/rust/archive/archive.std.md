# archive, a reference Plugin in Rust, in a container

| | |
| --- | --- |
| **Feature** | the example's `archive`: a Plugin written against the published Rust plugin library, run in a container from an image of its own, writing to the storage its Manifest needs; it stores a dataset it is commanded to in the layout the store says it has — `v1`, one directory, or `v2`, one directory per day — keeps datasets no longer than it is told, describes the store when asked, and refuses to store into a store nobody prepared |
| **Planning item** | yoke-project/yoke-reference#29 |

## yoke-reference:archive.01 — the Manifest installed beside it is the one its declaration generates

| Field | Value |
| --- | --- |
| **Cites** | specs/40.12 · specs/42.11 · specs/90.42 · arch/90-sdks/06 §The declaration a plugin library produces |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | `archive`'s committed `manifest.yaml` |
| **Action** | generate the Manifest from `archive`'s declaration |
| **Expected** | the two are byte for byte the same; the declaration is `com.yoke.station.archive`, needing `storage:datasets`, with the command `archive.store` and the question `archive.describe`, each governed by one capability |

## yoke-reference:archive.02 — a dataset is stored in the layout the store has

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a store whose `layout` says `v1`, and another whose `layout` says `v2`; the day 2026-10-16; `archive` acting on a Session that records what it is given |
| **Action** | command `archive.store` twice on the first, and once on the second |
| **Expected** | each command is acknowledged as done, naming where it was stored; the first store holds `datasets/1.json` and `datasets/2.json`, the second `datasets/2026-10-16/1.json`, each holding the payload it was given |

## yoke-reference:archive.03 — a store nobody prepared is refused, and said in the health report

| Field | Value |
| --- | --- |
| **Cites** | specs/50.65 · specs/90.42 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an empty store, and one whose `layout` says `v9`; `archive` acting on a Session that records what it is given |
| **Action** | start `archive` on each, and command `archive.store` |
| **Expected** | on each, the health reported is grade 60, naming what the store lacks; the command is acknowledged as failed with the same line, and nothing is written |

## yoke-reference:archive.04 — datasets older than it keeps are removed, and the store is described

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a store in layout `v1` holding a dataset written ten days ago and one written today; `archive` told to keep datasets seven days |
| **Action** | start it, then ask `archive.describe` |
| **Expected** | the old dataset is gone and today's remains; the answer is `{"layout":"v1","datasets":1,"keep_days":7}` |

## yoke-reference:archive.05 — the published Core runs its image in a container on the storage it needs, and it answers

| Field | Value |
| --- | --- |
| **Cites** | specs/45.1 · specs/45.6 · specs/45.15 · specs/97.10 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the `yoke-core` and `yoke` of the release `archive`'s library was cut with, downloaded and authenticated against the release manifest; Podman serving its API on a socket of the case's own; `archive`'s image built from its `Containerfile` and named by its digest; a project's working directory holding `archive`'s Manifest and a descriptor whose one unit of kind `plugin` runs that image with `--store ${bind.datasets}`; the instance's `storage/datasets` prepared in layout `v1` holding one dataset |
| **Action** | execute the Core on that directory in the application form, with the engine's address, and wait for the unit to run; grant `query.describe.answer` and restart the unit; ask it `archive.describe`; stop the Core |
| **Expected** | it runs in a container of its image; the question is answered `{"layout":"v1","datasets":1,"keep_days":90}`, read through the storage mounted into the container; when the Core stops it, `archive` closes its Session itself and the unit is `Stopped` |
