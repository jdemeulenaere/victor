#!/usr/bin/env bash
# Install repository-managed git hooks.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

git config core.hooksPath .githooks
echo "Configured git hooks path: .githooks"
echo "Pre-push hook will run ./format.sh --check on files in the push range"
