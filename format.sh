#!/usr/bin/env bash
# Deterministic formatter/checker for Bazel, Kotlin, Python, Swift, TypeScript, and keep-sorted blocks.
#
# Default mode is "fix" (rewrite files) over all tracked files.
# Use --check to verify formatting without rewriting.
# Selectors:
#   --all          all tracked files (default)
#   --staged       only staged files
#   --last-commit  only files changed in HEAD

set -euo pipefail

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
cd "${ROOT}"

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
        # Include file changes for regular and merge commits. `-m` asks Git to
        # diff merge commits against each parent so files introduced via merge
        # are included as well.
        git show -m --name-only --pretty='' --diff-filter=ACMR HEAD >"${candidate_file}"
      fi
      ;;
  esac
fi

sort -u "${candidate_file}" -o "${candidate_file}"

bazel_files=()
kotlin_files=()
python_files=()
keep_sorted_files=()
swift_files=()
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
    *.md)
      ;;
    *)
      keep_sorted_files+=("${abs}")
      ;;
  esac

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
    *.swift)
      swift_files+=("${abs}")
      ;;
  esac

  case "${rel}" in
    *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css | *.scss | *.yaml | *.yml)
      typescript_files+=("${abs}")
      ;;
  esac
done <"${candidate_file}"

echo "Formatting mode: ${MODE} (${SELECTOR})"

if [[ ${#keep_sorted_files[@]} -gt 0 ]]; then
  echo "keep-sorted files: ${#keep_sorted_files[@]}"
  if [[ "${MODE}" == "check" ]]; then
    bazel run //build/tools/format/keep_sorted:keep_sorted -- --mode=lint "${keep_sorted_files[@]}"
  else
    bazel run //build/tools/format/keep_sorted:keep_sorted -- --mode=fix "${keep_sorted_files[@]}"
  fi
fi

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
  if [[ "${MODE}" == "check" ]]; then
    bazel run //build/tools/format/ktfmt:ktfmt -- --kotlinlang-style --dry-run --set-exit-if-changed "${kotlin_files[@]}"
  else
    bazel run //build/tools/format/ktfmt:ktfmt -- --kotlinlang-style "${kotlin_files[@]}"
  fi
fi

if [[ ${#python_files[@]} -gt 0 ]]; then
  echo "Python files: ${#python_files[@]}"
  if [[ "${MODE}" == "check" ]]; then
    bazel run //build/tools/format/ruff:ruff -- format --check "${python_files[@]}"
  else
    bazel run //build/tools/format/ruff:ruff -- format "${python_files[@]}"
  fi
fi

if [[ ${#swift_files[@]} -gt 0 ]]; then
  echo "Swift files: ${#swift_files[@]}"
  if [[ "${MODE}" == "check" ]]; then
    bazel run //build/tools/format/swiftformat:swiftformat -- --cache ignore --swiftversion 6.0 --lint "${swift_files[@]}"
  else
    bazel run //build/tools/format/swiftformat:swiftformat -- --cache ignore --swiftversion 6.0 "${swift_files[@]}"
  fi
fi

if [[ ${#typescript_files[@]} -gt 0 ]]; then
  echo "TypeScript/Web files: ${#typescript_files[@]}"
  if [[ "${MODE}" == "check" ]]; then
    bazel run //build/tools/format/prettier:prettier -- --check "${typescript_files[@]}"
  else
    bazel run //build/tools/format/prettier:prettier -- --write "${typescript_files[@]}"
  fi
fi

echo "Formatting ${MODE} completed."
