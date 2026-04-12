#!/usr/bin/env bash
# High-level test script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_SDK_ROOT="$("${SCRIPT_DIR}/tools/android/ensure_sdk.sh")"
export ANDROID_HOME="${ANDROID_SDK_ROOT}"
export ANDROID_SDK_ROOT

echo "Running all Bazel tests..."
bazel test //...
echo "All tests passed."
