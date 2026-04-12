#!/usr/bin/env bash
# CI entrypoint for Codex cloud runners.
# - Installs CA certificates when possible.
# - Configures Coursier to use a Java truststore.
# - Prints diagnostics useful for SSL / dependency debugging.
# - Runs build and tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_BUILD_AND_TEST=1
INSTALL_CERTS=1

usage() {
  cat <<'EOF'
Usage: ./ci.sh [--diagnostics-only] [--skip-cert-install]

Options:
  --diagnostics-only   Print environment + TLS diagnostics, do not run build/test.
  --skip-cert-install  Skip package-manager based CA certificate installation.
  -h, --help           Show this help text.
EOF
}

log() {
  printf '[ci] %s\n' "$*"
}

warn() {
  printf '[ci] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[ci] ERROR: %s\n' "$*" >&2
  exit 1
}

run_with_privilege() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi
  return 1
}

install_ca_certs() {
  if [[ "${INSTALL_CERTS}" -ne 1 ]]; then
    log "Skipping CA certificate installation (--skip-cert-install)."
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "Installing CA packages with apt-get."
    run_with_privilege apt-get update -y || warn "Unable to run apt-get update."
    run_with_privilege apt-get install -y --no-install-recommends \
      ca-certificates ca-certificates-java openssl || warn "Unable to install CA packages with apt-get."
    if command -v update-ca-certificates >/dev/null 2>&1; then
      run_with_privilege update-ca-certificates || warn "update-ca-certificates failed."
    fi
    return
  fi

  if command -v apk >/dev/null 2>&1; then
    log "Installing CA packages with apk."
    run_with_privilege apk add --no-cache ca-certificates openssl || warn "Unable to install CA packages with apk."
    if command -v update-ca-certificates >/dev/null 2>&1; then
      run_with_privilege update-ca-certificates || warn "update-ca-certificates failed."
    fi
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    log "Installing CA packages with dnf."
    run_with_privilege dnf install -y ca-certificates openssl || warn "Unable to install CA packages with dnf."
    if command -v update-ca-trust >/dev/null 2>&1; then
      run_with_privilege update-ca-trust extract || warn "update-ca-trust failed."
    fi
    return
  fi

  warn "No supported package manager found (apt-get/apk/dnf). Continuing."
}

print_basic_diagnostics() {
  log "Timestamp (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  log "User: $(id -un) (uid=$(id -u), gid=$(id -g))"
  log "Working directory: ${SCRIPT_DIR}"
  log "Kernel: $(uname -srmo)"
}

print_tool_versions() {
  if command -v java >/dev/null 2>&1; then
    log "Java version:"
    java -version 2>&1 | sed 's/^/[ci]   /'
  else
    die "java is not available on PATH."
  fi

  if command -v bazel >/dev/null 2>&1; then
    log "Bazel version:"
    bazel --version | sed 's/^/[ci]   /'
  else
    die "bazel is not available on PATH."
  fi
}

discover_java_home() {
  if [[ -n "${JAVA_HOME:-}" ]]; then
    printf '%s\n' "${JAVA_HOME}"
    return 0
  fi

  local java_home
  java_home="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^[[:space:]]*java.home = //p' | head -n1 || true)"
  if [[ -n "${java_home}" ]]; then
    printf '%s\n' "${java_home}"
    return 0
  fi

  return 1
}

discover_truststore() {
  local java_home
  java_home="$(discover_java_home || true)"

  local candidates=(
    "/etc/ssl/certs/java/cacerts"
    "${java_home}/lib/security/cacerts"
    "${java_home}/jre/lib/security/cacerts"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

print_truststore_details() {
  local truststore_path="$1"
  log "Using truststore: ${truststore_path}"

  if command -v keytool >/dev/null 2>&1; then
    local cert_count
    cert_count="$(keytool -list -keystore "${truststore_path}" -storepass changeit 2>/dev/null | grep -c 'trustedCertEntry' || true)"
    log "Truststore trustedCertEntry count: ${cert_count}"
  else
    warn "keytool not available; skipping truststore entry count."
  fi
}

print_maven_connectivity() {
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not available; skipping Maven connectivity check."
    return
  fi

  local urls=(
    "https://repo.maven.apache.org/maven2/com/google/guava/failureaccess/1.0.1/failureaccess-1.0.1.pom"
    "https://maven.google.com/androidx/annotation/annotation/1.9.1/annotation-1.9.1.pom"
  )

  local url status
  for url in "${urls[@]}"; do
    status="$(curl -sS -o /dev/null -w '%{http_code}' -I -L "${url}" || true)"
    log "HTTP HEAD ${url} -> ${status:-<curl-failed>}"
  done
}

configure_coursier_truststore() {
  local truststore_path="$1"
  local opts="-Djavax.net.ssl.trustStore=${truststore_path} -Djavax.net.ssl.trustStorePassword=changeit"

  if [[ -n "${COURSIER_OPTS:-}" ]]; then
    export COURSIER_OPTS="${COURSIER_OPTS} ${opts}"
  else
    export COURSIER_OPTS="${opts}"
  fi

  log "COURSIER_OPTS=${COURSIER_OPTS}"
}

run_ci_pipeline() {
  log "Running build."
  "${SCRIPT_DIR}/build.sh"
  log "Running tests."
  "${SCRIPT_DIR}/test.sh"
  log "CI pipeline completed successfully."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diagnostics-only)
      RUN_BUILD_AND_TEST=0
      ;;
    --skip-cert-install)
      INSTALL_CERTS=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

print_basic_diagnostics
install_ca_certs
print_tool_versions

TRUSTSTORE_PATH="$(discover_truststore || true)"
if [[ -z "${TRUSTSTORE_PATH}" ]]; then
  die "Unable to find a Java truststore (expected /etc/ssl/certs/java/cacerts or JAVA_HOME security cacerts)."
fi

print_truststore_details "${TRUSTSTORE_PATH}"
configure_coursier_truststore "${TRUSTSTORE_PATH}"
print_maven_connectivity

if [[ "${RUN_BUILD_AND_TEST}" -eq 1 ]]; then
  run_ci_pipeline
else
  log "Diagnostics complete (--diagnostics-only)."
fi
