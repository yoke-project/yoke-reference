# provision-store and migrate-store, the example's units that run to completion

| | |
| --- | --- |
| **Feature** | the example's two oneshots, in Go: `provision-store` prepares the archive's store before anything writes to it — the layout `v1` and its datasets directory — and leaves a prepared store as it is; `migrate-store`, which belongs to 2.2.0 and runs where the stamp is older than 2.2, carries a `v1` store to `v2`, one directory per day, moving every dataset and writing the new layout last, so that a migration interrupted is finished by running it again; each exits 0 when the store is as it should be, and 1 naming what it found otherwise |
| **Planning item** | yoke-project/yoke-reference#30 |

## yoke-reference:the-store-oneshots.01 — provision-store prepares a store once, and refuses one it does not know

| Field | Value |
| --- | --- |
| **Cites** | specs/28.19 · specs/97.9 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an empty directory; a store already prepared, holding a dataset; a store whose layout is `v9` |
| **Action** | run `provision-store` on each |
| **Expected** | the first exits 0 holding the layout `v1` and an empty `datasets/`; the second exits 0 and is unchanged, its dataset kept; the third exits 1 naming `v9`, and is unchanged |

## yoke-reference:the-store-oneshots.02 — migrate-store carries a v1 store to v2, one directory per day

| Field | Value |
| --- | --- |
| **Cites** | specs/17.53 · specs/97.17 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a `v1` store holding `datasets/1.json`, written on 2026-10-15, and `datasets/2.json`, written on 2026-10-16 |
| **Action** | run `migrate-store` on it |
| **Expected** | it exits 0; the store's layout is `v2`, and it holds `datasets/2026-10-15/1.json` and `datasets/2026-10-16/2.json` with their contents and their times, and no dataset at the top of `datasets/` |

## yoke-reference:the-store-oneshots.03 — an interrupted migration is finished by running it again, and a migrated store is left alone

| Field | Value |
| --- | --- |
| **Cites** | specs/17.53 · specs/97.17 |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a `v1` store with one dataset already moved under its day and one still at the top; a `v2` store; a store never prepared |
| **Action** | run `migrate-store` on each |
| **Expected** | the first exits 0 in `v2` with both datasets under their days; the second exits 0 and is unchanged; the third exits 1 saying the store was never prepared |
