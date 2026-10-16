#!/usr/bin/env bash
# Installs what the Qt panel is built with beyond the language toolchains: CMake, the development
# packages the C++ family's source release configures against (its harness reads JSON with nlohmann-json),
# and Qt's widgets.
set -euo pipefail
sudo apt-get update
sudo apt-get install -y --no-install-recommends cmake pkg-config libprotobuf-dev libgrpc++-dev libssl-dev nlohmann-json3-dev qt6-base-dev
