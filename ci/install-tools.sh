#!/usr/bin/env bash
# Installs what the panels are built with beyond the language toolchains: CMake, the development packages
# the C++ family's source release configures against (its harness reads JSON with nlohmann-json), Qt's
# widgets for the Qt panel, and the packages the C family's source release configures against — gRPC's core
# API, protobuf-c and json-c — for the LVGL panel; and Qt's QML and its `qml` runtime, which the C++
# family's QML binding is built with and the desktop bench's document runs in.
set -euo pipefail
sudo apt-get update
sudo apt-get install -y --no-install-recommends cmake pkg-config libprotobuf-dev libgrpc++-dev libssl-dev nlohmann-json3-dev qt6-base-dev libgrpc-dev libprotobuf-c-dev libjson-c-dev \
  qt6-declarative-dev qml-qt6 qml6-module-qtqml qml6-module-qtqml-models qml6-module-qtqml-workerscript \
  qml6-module-qtquick qml6-module-qtquick-window
