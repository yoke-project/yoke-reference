#!/usr/bin/env bash
# Installs what the Qt panel is built with beyond the language toolchains: CMake, the development
# packages the C++ family's source release builds against, and Qt's widgets.
set -euo pipefail
sudo apt-get update
sudo apt-get install -y --no-install-recommends cmake pkg-config libprotobuf-dev libgrpc++-dev libssl-dev qt6-base-dev
