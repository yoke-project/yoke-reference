#!/usr/bin/env bash
# Installs what the panels are built with beyond the language toolchains: CMake, the development packages
# the C++ family's source release configures against (its harness reads JSON with nlohmann-json), Qt's
# widgets for the Qt panel, and the packages the C family's source release configures against — gRPC's core
# API, protobuf-c and json-c — for the LVGL panel.
set -euo pipefail
sudo apt-get update
sudo apt-get install -y --no-install-recommends cmake pkg-config libprotobuf-dev libgrpc++-dev libssl-dev nlohmann-json3-dev qt6-base-dev libgrpc-dev libprotobuf-c-dev libjson-c-dev
