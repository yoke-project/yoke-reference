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

## yoke-reference:built-from-published.02 — every Node.js package installs from the public registry alone

| Field | Value |
| --- | --- |
| **Cites** | prj_structure/40 C1 · prj_structure/40 C2 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L1 |
| **Method** | check |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | this repository's tree |
| **Action** | find every Node.js package in it, and read each package's manifest and lockfile |
| **Expected** | every package has a lockfile; every requirement it locks is resolved from `https://registry.npmjs.org/` with an integrity digest, and none is a path, a link, a repository or a tarball elsewhere |

## yoke-reference:built-from-published.03 — every Cargo package locks crates from crates.io alone

| Field | Value |
| --- | --- |
| **Cites** | prj_structure/40 C1 · prj_structure/40 C2 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L1 |
| **Method** | check |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | this repository's tree |
| **Action** | find every Cargo package in it, and read each package's manifest and lockfile |
| **Expected** | every package has a lockfile; every crate it locks, other than the package itself, comes from crates.io's index with a checksum; no requirement is a path, a repository or a patch |

## yoke-reference:built-from-published.04 — every Python program installs from the public index alone

| Field | Value |
| --- | --- |
| **Cites** | prj_structure/40 C1 · prj_structure/40 C2 · arch/90-sdks/07 §They hold no privileged route, and that is what they are for |
| **Level** | L1 |
| **Method** | check |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | this repository's tree |
| **Action** | find every Python program's `requirements.txt` in it, and install each into an empty environment from `https://pypi.org/simple` alone, requiring every digest |
| **Expected** | every requirement is pinned to one version with at least one digest; none is a path, a repository or an index other than the public one; each installs |
