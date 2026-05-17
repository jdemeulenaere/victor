#!/usr/bin/env bash
set -euo pipefail

variants_file="$1"
android_deps_file="$2"

require_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -F "$expected" "$file" >/dev/null; then
    echo "Expected $file to contain: $expected" >&2
    exit 1
  fi
}

require_not_matches() {
  local file="$1"
  local unexpected="$2"
  if grep -E "$unexpected" "$file" >/dev/null; then
    echo "Expected $file not to match: $unexpected" >&2
    grep -E "$unexpected" "$file" >&2
    exit 1
  fi
}

require_contains "$variants_file" '"@third_party_maven//:org_jetbrains_compose_ui_ui": {'
require_contains "$variants_file" '"android": "@third_party_maven_kmp_variants//:org_jetbrains_compose_ui_ui_android_metadata_variant",'
require_contains "$variants_file" '"jvm": "@third_party_maven//:org_jetbrains_compose_ui_ui_desktop",'
require_contains "$variants_file" '"@third_party_maven//:org_jetbrains_compose_foundation_foundation": {'
require_contains "$variants_file" '"android": "@third_party_maven_kmp_variants//:org_jetbrains_compose_foundation_foundation_android_metadata_variant",'
require_contains "$variants_file" '"jvm": "@third_party_maven//:org_jetbrains_compose_foundation_foundation_desktop",'
require_contains "$variants_file" '"@third_party_maven//:org_jetbrains_compose_material3_material3": {'
require_contains "$variants_file" '"android": "@third_party_maven_kmp_variants//:org_jetbrains_compose_material3_material3_android_metadata_variant",'
require_contains "$variants_file" '"jvm": "@third_party_maven//:org_jetbrains_compose_material3_material3_desktop",'

require_contains "$android_deps_file" "androidx_compose_foundation_foundation_android"
require_contains "$android_deps_file" "androidx_compose_material3_material3_android"
require_contains "$android_deps_file" "androidx_compose_ui_ui_android"
require_contains "$android_deps_file" "org_jetbrains_compose_ui_ui_backhandler_android"
require_not_matches "$android_deps_file" "desktop|jvmstubs"
