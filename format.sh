#!/usr/bin/env bash
# Deterministic formatter/checker for Bazel, Kotlin, Python, and TypeScript.
#
# Default mode is "fix" (rewrite files) over all tracked files.
# Use --check to verify formatting without rewriting.
# Selectors:
#   --all          all tracked files (default)
#   --staged       only staged files
#   --last-commit  only files changed in HEAD

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

# Pinned latest versions verified on 2026-04-11:
# - ktfmt:       0.62
# - ruff:        0.15.10
# - prettier:    3.8.2
KTFMT_VERSION="0.62"
RUFF_VERSION="0.15.10"
PRETTIER_VERSION="3.8.2"

MODE="fix"
SELECTOR="all"
explicit_files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      MODE="check"
      ;;
    --fix)
      MODE="fix"
      ;;
    --all)
      SELECTOR="all"
      ;;
    --staged)
      SELECTOR="staged"
      ;;
    --last-commit)
      SELECTOR="last_commit"
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        explicit_files+=("$1")
        shift
      done
      break
      ;;
    --*)
      echo "Unknown option: $1"
      echo "Usage: $0 [--fix|--check] [--all|--staged|--last-commit] [files...]"
      exit 2
      ;;
    *)
      explicit_files+=("$1")
      ;;
  esac
  shift
done

if [[ ${#explicit_files[@]} -gt 0 && "${SELECTOR}" != "all" ]]; then
  echo "Cannot combine explicit file paths with ${SELECTOR} selector."
  echo "Usage: $0 [--fix|--check] [--all|--staged|--last-commit] [files...]"
  exit 2
fi

candidate_file="$(mktemp "${TMPDIR:-/tmp}/victor-format-candidates.XXXXXX")"
trap 'rm -f "${candidate_file}"' EXIT

if [[ ${#explicit_files[@]} -gt 0 ]]; then
  printf '%s\n' "${explicit_files[@]}" >"${candidate_file}"
else
  case "${SELECTOR}" in
    all)
      git ls-files >"${candidate_file}"
      ;;
    staged)
      git diff --cached --name-only --diff-filter=ACMR >"${candidate_file}"
      ;;
    last_commit)
      if git rev-parse --verify HEAD >/dev/null 2>&1; then
        git diff-tree --no-commit-id --name-only -r --diff-filter=ACMR HEAD >"${candidate_file}"
      fi
      ;;
  esac
fi

bazel_files=()
kotlin_files=()
python_files=()
typescript_files=()

while IFS= read -r path; do
  [[ -z "${path}" ]] && continue
  rel="${path}"
  case "${rel}" in
    "${ROOT}"/*) rel="${rel#"${ROOT}/"}" ;;
  esac
  rel="${rel#./}"
  [[ -z "${rel}" ]] && continue
  [[ "${rel}" == /* ]] && continue

  abs="${ROOT}/${rel}"
  [[ -f "${abs}" ]] || continue

  case "${rel}" in
    BUILD | BUILD.bazel | WORKSPACE | WORKSPACE.bazel | MODULE.bazel | *.MODULE.bazel | *.bzl | */BUILD | */BUILD.bazel | */WORKSPACE | */WORKSPACE.bazel | */MODULE.bazel)
      bazel_files+=("${abs}")
      ;;
  esac

  case "${rel}" in
    *.kt | *.kts)
      kotlin_files+=("${abs}")
      ;;
  esac

  case "${rel}" in
    *.py)
      python_files+=("${abs}")
      ;;
  esac

  case "${rel}" in
    *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css | *.scss | *.md | *.yaml | *.yml)
      typescript_files+=("${abs}")
      ;;
  esac
done <"${candidate_file}"

echo "Formatting mode: ${MODE} (${SELECTOR})"

if [[ ${#bazel_files[@]} -gt 0 ]]; then
  echo "Bazel/Starlark files: ${#bazel_files[@]}"
  if [[ "${MODE}" == "check" ]]; then
    bazel run @buildifier_prebuilt//:buildifier -- -mode=check "${bazel_files[@]}"
  else
    bazel run @buildifier_prebuilt//:buildifier -- -mode=fix "${bazel_files[@]}"
  fi
fi

if [[ ${#kotlin_files[@]} -gt 0 ]]; then
  echo "Kotlin files: ${#kotlin_files[@]}"
  ktfmt_dir="${ROOT}/.tools/ktfmt"
  ktfmt_jar="${ktfmt_dir}/ktfmt-${KTFMT_VERSION}-with-dependencies.jar"
  mkdir -p "${ktfmt_dir}"
  if [[ ! -f "${ktfmt_jar}" ]]; then
    curl -sSfL \
      "https://github.com/facebook/ktfmt/releases/download/v${KTFMT_VERSION}/ktfmt-${KTFMT_VERSION}-with-dependencies.jar" \
      -o "${ktfmt_jar}"
  fi

  if [[ "${MODE}" == "check" ]]; then
    java -jar "${ktfmt_jar}" --kotlinlang-style --dry-run --set-exit-if-changed "${kotlin_files[@]}"
  else
    java -jar "${ktfmt_jar}" --kotlinlang-style "${kotlin_files[@]}"
  fi
fi

if [[ ${#python_files[@]} -gt 0 ]]; then
  echo "Python files: ${#python_files[@]}"
  ruff_dir="${ROOT}/.tools/ruff-venv"
  ruff_bin="${ruff_dir}/bin/ruff"
  install_ruff="false"
  if [[ ! -x "${ruff_bin}" ]]; then
    install_ruff="true"
  else
    current_ruff="$("${ruff_bin}" --version | awk '{print $2}')"
    if [[ "${current_ruff}" != "${RUFF_VERSION}" ]]; then
      install_ruff="true"
    fi
  fi

  if [[ "${install_ruff}" == "true" ]]; then
    python3 -m venv "${ruff_dir}"
    "${ruff_dir}/bin/python" -m pip install --upgrade pip >/dev/null
    "${ruff_dir}/bin/pip" install "ruff==${RUFF_VERSION}" >/dev/null
  fi

  if [[ "${MODE}" == "check" ]]; then
    "${ruff_bin}" format --check "${python_files[@]}"
  else
    "${ruff_bin}" format "${python_files[@]}"
  fi
fi

if [[ ${#typescript_files[@]} -gt 0 ]]; then
  echo "TypeScript/Web files: ${#typescript_files[@]}"
  export NPM_CONFIG_CACHE="${ROOT}/.tools/npm-cache"
  mkdir -p "${NPM_CONFIG_CACHE}"
  if [[ "${MODE}" == "check" ]]; then
    npm exec --yes "prettier@${PRETTIER_VERSION}" -- --check "${typescript_files[@]}"
  else
    npm exec --yes "prettier@${PRETTIER_VERSION}" -- --write "${typescript_files[@]}"
  fi
fi

echo "Formatting ${MODE} completed."
