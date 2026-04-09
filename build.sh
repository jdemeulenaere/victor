#!/usr/bin/env bash
# High-level clean build script.

set -euo pipefail

echo "Building all Bazel targets..."
bazel build //...
echo "Build complete."
