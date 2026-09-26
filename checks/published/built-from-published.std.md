# Built from published artifacts only

| | |
| --- | --- |
| **Feature** | every reference Plugin in this repository is built from what somebody outside the project could obtain: no module of this tree reaches anything but published modules, so a privileged path is a build failure rather than a claim |
| **Planning item** | yoke-project/yoke-reference#1 |

## yoke-reference:built-from-published.01 — every module builds from published modules alone

| Field | Value |
| --- | --- |
| **Cites** | prj_structure/40 C1 · prj_structure/40 C2 · prj_structure/40 C3 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L1 |
| **Method** | check |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | this repository's tree |
| **Action** | find every Go module in it, and build each with an empty module cache, through the public module proxy and verified against the public checksum database, with no module exempted from either and no workspace |
| **Expected** | there is at least one module; no module replaces a requirement or vendors one, the tree holds no workspace file, and every module builds |
