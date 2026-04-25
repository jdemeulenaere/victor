#!/usr/bin/env bash
# Install repository-managed git hooks.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

git config core.hooksPath build/git-hooks
echo "Configured git hooks path: build/git-hooks"
echo "Pre-push hook will run bazel run //:format_check on files in the push range"
