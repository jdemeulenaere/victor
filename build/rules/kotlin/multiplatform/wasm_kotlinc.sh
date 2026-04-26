#!/usr/bin/env bash
set -euo pipefail

mode="$1"
java_bin="$2"
compiler_main="$3"
compiler_classpath="$4"
output_dir="$5"
module_name="$6"
main_klib="$7"
libraries_file="$8"
plugins_file="$9"
flags_file="${10}"
sources_file="${11}"

resolved_libraries=()
while IFS= read -r path || [[ -n "$path" ]]; do
  [[ -z "$path" ]] && continue
  resolved_libraries+=("$(realpath "$path")")
done < "$libraries_file"
library_arg=$(IFS=:; echo "${resolved_libraries[*]}")

plugin_args=()
while IFS= read -r path || [[ -n "$path" ]]; do
  [[ -z "$path" ]] && continue
  plugin_args+=("-Xplugin=$(realpath "$path")")
done < "$plugins_file"

flags=()
sources=()
while IFS= read -r flag || [[ -n "$flag" ]]; do
  [[ -z "$flag" ]] && continue
  flags+=("$flag")
done < "$flags_file"
while IFS= read -r source || [[ -n "$source" ]]; do
  [[ -z "$source" ]] && continue
  sources+=("$source")
done < "$sources_file"

if [[ "$mode" == "compile" ]]; then
  mkdir -p "$output_dir"
  "$java_bin" -cp "$compiler_classpath" "$compiler_main" \
    -libraries "$library_arg" \
    -ir-output-dir "$output_dir" \
    -ir-output-name "$module_name" \
    -main noCall \
    "${plugin_args[@]}" \
    "${flags[@]}" \
    "${sources[@]}"
elif [[ "$mode" == "link" ]]; then
  mkdir -p "$output_dir"
  resolved_main_klib="$(realpath "$main_klib")"
  "$java_bin" -cp "$compiler_classpath" "$compiler_main" \
    -Xwasm \
    -Xwasm-target=wasm-js \
    -Xir-produce-js \
    -Xgenerate-dts \
    -libraries "$library_arg" \
    -Xinclude="$resolved_main_klib" \
    -ir-output-dir "$output_dir" \
    -ir-output-name "$module_name" \
    -main noCall
  if [[ -f "$output_dir/$module_name.d.mts" ]]; then
    cp "$output_dir/$module_name.d.mts" "$output_dir/$module_name.d.ts"
  fi
else
  echo "Unknown Kotlin/WASM mode: $mode" >&2
  exit 1
fi
