#!/usr/bin/env bash
# High-level build script for the Victor Bazel monorepo.

set -euo pipefail

echo "Building all Bazel targets in the Victor monorepo..."
bazel build //...
echo "Build complete."
