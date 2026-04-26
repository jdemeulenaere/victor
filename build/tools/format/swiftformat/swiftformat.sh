#!/usr/bin/env bash
# Wrapper that selects the host-OS SwiftFormat prebuilt binary.

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
    swiftformat_repo="swiftformat_darwin"
    swiftformat_canonical_repo="+http_archive+swiftformat_darwin"
    swiftformat_file="swiftformat"
    ;;
  Linux)
    case "$(uname -m)" in
      aarch64 | arm64)
        swiftformat_repo="swiftformat_linux_aarch64"
        swiftformat_canonical_repo="+http_archive+swiftformat_linux_aarch64"
        swiftformat_file="swiftformat_linux_aarch64"
        ;;
      x86_64 | amd64)
        swiftformat_repo="swiftformat_linux"
        swiftformat_canonical_repo="+http_archive+swiftformat_linux"
        swiftformat_file="swiftformat_linux"
        ;;
      *)
        echo "Unsupported Linux architecture for SwiftFormat: $(uname -m)" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "Unsupported OS for SwiftFormat: $(uname -s)" >&2
    exit 2
    ;;
esac

swiftformat_bin=""
swiftformat_runfiles=(
  "${swiftformat_repo}/${swiftformat_file}"
  "${swiftformat_canonical_repo}/${swiftformat_file}"
)

if [[ -n "${runfiles_dir}" ]]; then
  for swiftformat_runfile in "${swiftformat_runfiles[@]}"; do
    if [[ -f "${runfiles_dir}/${swiftformat_runfile}" && -x "${runfiles_dir}/${swiftformat_runfile}" ]]; then
      swiftformat_bin="${runfiles_dir}/${swiftformat_runfile}"
      break
    fi
  done
fi

if [[ -z "${swiftformat_bin}" && -n "${runfiles_manifest}" ]]; then
  for swiftformat_runfile in "${swiftformat_runfiles[@]}"; do
    swiftformat_bin="$(grep -sm1 "^${swiftformat_runfile} " "${runfiles_manifest}" | cut -d " " -f2- || true)"
    if [[ -n "${swiftformat_bin}" ]]; then
      break
    fi
  done
fi

if [[ -z "${swiftformat_bin}" || ! -x "${swiftformat_bin}" ]]; then
  echo "ERROR: cannot resolve SwiftFormat binary from Bazel runfiles." >&2
  exit 1
fi

exec "${swiftformat_bin}" "$@"
