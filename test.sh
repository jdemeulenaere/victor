#!/usr/bin/env bash
# High-level test script.

set -euo pipefail

echo "Running all Bazel tests..."
bazel test //...
echo "All tests passed."
