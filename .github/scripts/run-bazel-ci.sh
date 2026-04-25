#!/usr/bin/env bash

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <bazel command> [bazel args...]" >&2
  exit 1
fi

remote_args=()
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
  echo "BuildBuddy API key is available; using remote Bazel cache." >&2
  remote_args+=(
    "--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}"
  )

  if [[ "${GITHUB_EVENT_NAME:-}" != "push" || "${GITHUB_REF:-}" != "refs/heads/main" ]]; then
    echo "Remote cache uploads are disabled outside push builds on main." >&2
    remote_args+=("--remote_upload_local_results=false")
  fi
else
  echo "BuildBuddy API key is not available; using local Bazel configuration." >&2
  remote_args+=(
    "--bes_backend="
    "--remote_cache="
    "--remote_executor="
  )
fi

bazel_args=()
inserted_remote_args=0
for arg in "$@"; do
  if [[ "${arg}" == "--" && "${inserted_remote_args}" -eq 0 ]]; then
    bazel_args+=("${remote_args[@]}")
    inserted_remote_args=1
  fi
  bazel_args+=("${arg}")
done

if [[ "${inserted_remote_args}" -eq 0 ]]; then
  bazel_args+=("${remote_args[@]}")
fi

exec bazel "${bazel_args[@]}"
