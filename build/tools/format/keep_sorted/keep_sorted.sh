#!/usr/bin/env bash
# Wrapper that selects the host-OS keep-sorted prebuilt binary.

set -euo pipefail

runfiles_dir="${RUNFILES_DIR:-}"
runfiles_manifest="${RUNFILES_MANIFEST_FILE:-}"

if [[ -z "${runfiles_dir}" && -d "$0.runfiles" ]]; then
  runfiles_dir="$0.runfiles"
fi

if [[ -z "${runfiles_manifest}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    runfiles_manifest="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    runfiles_manifest="$0.runfiles/MANIFEST"
  fi
fi

case "$(uname -s)" in
  Darwin)
    keep_sorted_repo="keep_sorted_darwin"
    keep_sorted_canonical_repo="+http_file+keep_sorted_darwin"
    ;;
  Linux)
    keep_sorted_repo="keep_sorted_linux"
    keep_sorted_canonical_repo="+http_file+keep_sorted_linux"
    ;;
  *)
    echo "Unsupported OS for keep-sorted: $(uname -s)" >&2
    exit 2
    ;;
esac

keep_sorted_bin=""
keep_sorted_runfiles=(
  "${keep_sorted_repo}/file"
  "${keep_sorted_repo}/file/downloaded"
  "${keep_sorted_canonical_repo}/file"
  "${keep_sorted_canonical_repo}/file/downloaded"
)

if [[ -n "${runfiles_dir}" ]]; then
  for keep_sorted_runfile in "${keep_sorted_runfiles[@]}"; do
    if [[ -f "${runfiles_dir}/${keep_sorted_runfile}" && -x "${runfiles_dir}/${keep_sorted_runfile}" ]]; then
      keep_sorted_bin="${runfiles_dir}/${keep_sorted_runfile}"
      break
    fi
  done
fi

if [[ -z "${keep_sorted_bin}" && -n "${runfiles_manifest}" ]]; then
  for keep_sorted_runfile in "${keep_sorted_runfiles[@]}"; do
    keep_sorted_bin="$(grep -sm1 "^${keep_sorted_runfile} " "${runfiles_manifest}" | cut -d " " -f2- || true)"
    if [[ -n "${keep_sorted_bin}" ]]; then
      break
    fi
  done
fi

if [[ -z "${keep_sorted_bin}" || ! -x "${keep_sorted_bin}" ]]; then
  echo "ERROR: cannot resolve keep-sorted binary from Bazel runfiles." >&2
  exit 1
fi

exec "${keep_sorted_bin}" "$@"
