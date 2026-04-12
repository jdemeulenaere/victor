#!/usr/bin/env bash
# High-level clean build script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_SDK_ROOT="$("${SCRIPT_DIR}/tools/android/ensure_sdk.sh")"
export ANDROID_HOME="${ANDROID_SDK_ROOT}"
export ANDROID_SDK_ROOT

echo "Building all Bazel targets..."
bazel build //...
echo "Build complete."
