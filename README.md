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
| `plugins/python/clock/` | The same clock in Python |
| `clients/web/` | A web client of the interface contract on its browser projection, in Node.js — see its own README |
| `checks/`, `ci/` | This repository's own checks, and the scripts continuous integration runs; `ci/admitted.sh` runs the Rust and Python clocks under the published Core |

A test's description sits beside the test, as a `.std.md` file.

## Working on it

Go, Rust through `cargo`, Python 3, Node.js 24 or newer, and [`just`](https://just.systems) 1.58.0 or
newer. Nobody needs them all to change one program; `just build` and `just test` walk every program,
so they do. `just develop` also puts the published verification tool, `yoke-verify`, on the `PATH`,
which `just test` needs. The `Containerfile` builds a container with the toolchains.

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
