#!/bin/bash
# High-level build script for the Victor Bazel Monorepo

set -e

echo "🔨 Building all targets in the Victor monorepo..."
bazel build //...

echo "✅ Build complete!"
