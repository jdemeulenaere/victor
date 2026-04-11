#!/usr/bin/env bash
# Deterministic Bazel/Starlark formatter using the pinned buildifier_prebuilt.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

echo "Formatting Bazel/Starlark files..."
pattern='(^|/)(BUILD|WORKSPACE)(\.bazel)?$|(^|/)MODULE\.bazel$|\.MODULE\.bazel$|\.bzl$'
files=()

if command -v rg >/dev/null 2>&1; then
  while IFS= read -r file; do
    [[ -n "${file}" ]] && files+=("${ROOT}/${file}")
  done < <(git ls-files | rg "${pattern}" || true)
else
  while IFS= read -r file; do
    [[ -n "${file}" ]] && files+=("${ROOT}/${file}")
  done < <(git ls-files | grep -E "${pattern}" || true)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No Bazel/Starlark files found."
  exit 0
fi

bazel run @buildifier_prebuilt//:buildifier -- -mode=fix "${files[@]}"
echo "Formatting complete."
