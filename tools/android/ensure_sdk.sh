#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

readonly REPOSITORY_XML_URL="https://dl.google.com/android/repository/repository2-1.xml"
readonly REPOSITORY_BASE_URL="https://dl.google.com/android/repository"

readonly ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-36}"
readonly ANDROID_BUILD_TOOLS_VERSION="${ANDROID_BUILD_TOOLS_VERSION:-36.0.0}"
readonly ANDROID_SDK_ROOT_PATH="${REPO_ROOT}/.cache/android-sdk"

log() {
  printf '%s\n' "$*" >&2
}

detect_host_os() {
  case "$(uname -s)" in
    Linux)
      printf 'linux\n'
      ;;
    Darwin)
      printf 'macosx\n'
      ;;
    *)
      log "Unsupported host OS: $(uname -s)."
      exit 1
      ;;
  esac
}

sha1_file() {
  local file_path="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "${file_path}" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 1 "${file_path}" | awk '{print $1}'
    return
  fi
  log "No SHA-1 utility found. Install 'sha1sum' or 'shasum'."
  exit 1
}

resolve_cmdline_tools_archive() {
  local host_os="$1"
  local xml_path="$2"

  awk -v host="${host_os}" '
    /<remotePackage path="cmdline-tools;latest">/ {
      in_pkg = 1
    }
    in_pkg && /<\/remotePackage>/ {
      in_pkg = 0
    }
    in_pkg && /<archive>/ {
      in_archive = 1
      archive_host = ""
      archive_url = ""
      archive_checksum = ""
    }
    in_pkg && in_archive {
      if ($0 ~ /<host-os>/) {
        line = $0
        sub(/.*<host-os>/, "", line)
        sub(/<\/host-os>.*/, "", line)
        archive_host = line
      }
      if ($0 ~ /<url>/) {
        line = $0
        sub(/.*<url>/, "", line)
        sub(/<\/url>.*/, "", line)
        archive_url = line
      }
      if ($0 ~ /<checksum>/) {
        line = $0
        sub(/.*<checksum>/, "", line)
        sub(/<\/checksum>.*/, "", line)
        archive_checksum = line
      }
    }
    in_pkg && in_archive && /<\/archive>/ {
      if (archive_host == host && archive_url != "" && archive_checksum != "") {
        print archive_url
        print archive_checksum
        exit
      }
      in_archive = 0
    }
  ' "${xml_path}"
}

bootstrap_cmdline_tools() {
  local sdk_root="$1"
  local host_os="$2"
  local sdkmanager_path="${sdk_root}/cmdline-tools/latest/bin/sdkmanager"

  if [[ -x "${sdkmanager_path}" ]]; then
    return
  fi

  mkdir -p "${sdk_root}"

  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  local repository_xml="${temp_dir}/repository2-1.xml"
  curl -L --fail --retry 3 --retry-delay 1 -o "${repository_xml}" "${REPOSITORY_XML_URL}"

  local archive_relative_url=""
  local expected_sha1=""
  while IFS= read -r line; do
    if [[ -z "${archive_relative_url}" ]]; then
      archive_relative_url="${line}"
    elif [[ -z "${expected_sha1}" ]]; then
      expected_sha1="${line}"
    fi
  done < <(resolve_cmdline_tools_archive "${host_os}" "${repository_xml}")

  if [[ -z "${archive_relative_url}" || -z "${expected_sha1}" ]]; then
    log "Failed to resolve command-line tools for host '${host_os}'."
    exit 1
  fi

  local archive_path="${temp_dir}/commandlinetools.zip"

  curl -L --fail --retry 3 --retry-delay 1 -o "${archive_path}" "${REPOSITORY_BASE_URL}/${archive_relative_url}"

  local actual_sha1
  actual_sha1="$(sha1_file "${archive_path}")"
  if [[ "${actual_sha1}" != "${expected_sha1}" ]]; then
    log "Command-line tools checksum mismatch."
    log "Expected: ${expected_sha1}"
    log "Actual:   ${actual_sha1}"
    exit 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    log "'unzip' is required to extract Android command-line tools."
    exit 1
  fi

  local extract_dir="${temp_dir}/extract"
  mkdir -p "${extract_dir}"
  unzip -q "${archive_path}" -d "${extract_dir}"

  local extracted_tools_dir="${extract_dir}/cmdline-tools"
  if [[ ! -d "${extracted_tools_dir}" ]]; then
    log "Unexpected Android command-line tools archive layout."
    exit 1
  fi

  rm -rf "${sdk_root}/cmdline-tools/latest"
  mkdir -p "${sdk_root}/cmdline-tools"
  mv "${extracted_tools_dir}" "${sdk_root}/cmdline-tools/latest"

  trap - RETURN
  rm -rf "${temp_dir}"
}

ensure_sdk_packages() {
  local sdk_root="$1"
  local sdkmanager_path="${sdk_root}/cmdline-tools/latest/bin/sdkmanager"

  local required_files=(
    "${sdk_root}/platform-tools/adb"
    "${sdk_root}/platforms/android-${ANDROID_API_LEVEL}/android.jar"
    "${sdk_root}/build-tools/${ANDROID_BUILD_TOOLS_VERSION}/aapt2"
  )

  local missing_file=0
  local required_file
  for required_file in "${required_files[@]}"; do
    if [[ ! -e "${required_file}" ]]; then
      missing_file=1
      break
    fi
  done

  if [[ "${missing_file}" -eq 0 ]]; then
    return
  fi

  log "Installing Android SDK packages into ${sdk_root}..."

  yes | "${sdkmanager_path}" --sdk_root="${sdk_root}" --licenses >/dev/null || true
  "${sdkmanager_path}" --sdk_root="${sdk_root}" --install \
    "platform-tools" \
    "platforms;android-${ANDROID_API_LEVEL}" \
    "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" >/dev/null
}

main() {
  local host_os
  host_os="$(detect_host_os)"

  bootstrap_cmdline_tools "${ANDROID_SDK_ROOT_PATH}" "${host_os}"
  ensure_sdk_packages "${ANDROID_SDK_ROOT_PATH}"

  printf '%s\n' "${ANDROID_SDK_ROOT_PATH}"
}

main "$@"
