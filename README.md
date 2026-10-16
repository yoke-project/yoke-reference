# yoke-reference

## What it is

Reference programs for Yoke: small, complete Plugins and clients, written against the published SDKs
and kept working against the published Core. They are written to be copied from.

It is not an SDK and not a test suite of the libraries: each program uses a library the way an author
would, from the package registry, at a released version.

## What is where

| Path | What it holds |
| --- | --- |
| `plugins/go/clock/` | A clock Plugin in Go, with its Manifest |
| `plugins/rust/clock/` | The same clock in Rust |
| `plugins/rust/archive/` | `archive`, the example application's Plugin in a container that keeps data: it stores datasets in the layout its storage says it has; with its `Containerfile` |
| `plugins/python/clock/` | The same clock in Python |
| `plugins/python/pipeline/` | `pipeline`, the example application's Plugin in a container: it identifies a spectrum it is asked about against an index of reference lines; with its `Containerfile` |
| `plugins/go/acquire/` | `acquire`, the example application's Plugin on the host: it drives a spectrometer over the serial device its unit binds, with `instrument/`, a program playing the spectrometer on a pseudo-terminal |
| `oneshots/go/store/` | `provision-store` and `migrate-store`, the example application's units that run to completion: they prepare the archive's store and carry it from one layout to the next; with a `Containerfile` building either |
| `clients/qt/panel/` | `panel`, the example application's managed interface, in C++ with Qt: it composes itself from the opening picture as the web client does, built against the C++ family's source release |
| `applications/station/` | `com.yoke.station`, the example application, at 2.1.0 and 2.2.0: `compose.sh` writes it with the composer's verbs alone, for the executables and images in hand |
| `clients/web/` | A web client of the interface contract on its browser projection, in Node.js — see its own README |
| `checks/`, `ci/` | This repository's own checks, and the scripts continuous integration runs; `ci/admitted.sh` runs the Rust and Python clocks under the published Core, `ci/station.sh` runs `acquire`, `ci/pipeline.sh` and `ci/archive.sh` run `pipeline`'s and `archive`'s images under Podman |

A test's description sits beside the test, as a `.std.md` file.

## Working on it

Go, Rust through `cargo`, Python 3, Node.js 24 or newer, CMake with the development packages of gRPC's
C++ API, OpenSSL and Qt 6 for the panel (`ci/install-tools.sh` installs them on Ubuntu), and
[`just`](https://just.systems) 1.58.0 or newer. Nobody needs them all to change one program; `just build`
and `just test` walk every program, so they do. `just develop` also puts the published verification tool,
`yoke-verify`, on the `PATH`, which `just test` needs, and `just test` runs `pipeline`'s and `archive`'s
images under Podman, so it needs Podman too. The
`Containerfile` builds a container with the toolchains.

| Command | What it does |
| --- | --- |
| `just build` | Builds every Go module and Rust crate, and installs every Python program's and Node.js package's requirements |
| `just test` | Runs the checks and every program's tests, runs the Rust and Python clocks under the published Core, and checks each description against its tests |
| `just lint` | Parses every shell, Python and Node.js script, and runs `go vet` in every module |
| `just fmt` | Fails, naming each file, when a Go or Rust file is not formatted |
| `just develop` | Verifies the installed `just` against a floor, given as `just develop 1.58.0`, and installs `yoke-verify` |
| `just release` | Says there is nothing to publish |

## Where the depth is

The documentation at [docs.yoke-project.dev](https://docs.yoke-project.dev/): the
[reference](https://docs.yoke-project.dev/reference/) for the contracts these programs speak, and the
[contributors' section](https://docs.yoke-project.dev/contributing/) for how the work is done.

## Licence

Apache 2.0, in [`LICENSE`](LICENSE), with a [`NOTICE`](NOTICE).
