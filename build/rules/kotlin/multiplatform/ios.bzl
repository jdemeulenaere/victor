"""Internal Kotlin/Native iOS framework rules for KMP targets."""

load("@rules_kotlin//kotlin/internal:defs.bzl", "KtCompilerPluginInfo", "KtPluginConfiguration")
load("//build/rules/kotlin/multiplatform:compiler_plugin.bzl", "KtNativeCompilerPluginInfo")

_KONANC_MAIN = "org.jetbrains.kotlin.cli.utilities.MainKt"
_NATIVE_TOOLCHAIN_TYPE = "//build/rules/kotlin/multiplatform:native_toolchain_type"

KtNativeKlibInfo = provider(fields = ["klib"])

def _dedupe_files(files):
    seen = {}
    deduped = []
    for file in files:
        if seen.get(file.path):
            continue
        seen[file.path] = True
        deduped.append(file)
    return deduped

def _collect_dep_klibs(deps):
    files = []
    for dep in deps:
        if KtNativeKlibInfo in dep:
            files.append(dep[KtNativeKlibInfo].klib)
            continue
        if DefaultInfo in dep:
            files.extend([
                file
                for file in dep[DefaultInfo].files.to_list()
                if file.basename.endswith(".klib")
            ])
    return _dedupe_files(files)

def _native_plugin_classpath(plugin, info):
    if KtNativeCompilerPluginInfo in plugin:
        return plugin[KtNativeCompilerPluginInfo].classpath
    return info.classpath

def _compile_plugin_data(plugins):
    plugin_infos = {}
    plugin_targets = {}
    plugin_configs = {}
    for plugin in plugins:
        if KtCompilerPluginInfo in plugin:
            info = plugin[KtCompilerPluginInfo]
            if info.id in plugin_infos and plugin_infos[info.id] != info:
                fail("Multiple Kotlin compiler plugins with id '{}'".format(info.id))
            plugin_infos[info.id] = info
            plugin_targets[info.id] = plugin
        if KtPluginConfiguration in plugin:
            config = plugin[KtPluginConfiguration]
            plugin_configs.setdefault(config.id, []).append(config)

    for plugin_id in plugin_configs.keys():
        if plugin_id not in plugin_infos:
            fail("Kotlin compiler plugin configuration for '{}' has no matching plugin".format(plugin_id))

    classpaths = []
    options = []
    for plugin_id in sorted(plugin_infos.keys()):
        info = plugin_infos[plugin_id]
        if not info.compile:
            continue
        classpaths.append(_native_plugin_classpath(plugin_targets[plugin_id], info))
        options.extend(info.options)
        configs = plugin_configs.get(plugin_id)
        if configs:
            config = info.merge_cfgs(info, configs)
            classpaths.append(config.classpath)
            options.extend(config.options)

    return struct(
        classpath = depset(transitive = classpaths),
        options = options,
    )

def _plugin_flags(plugin_data):
    flags = [
        "-Xplugin={}".format(file.path)
        for file in plugin_data.classpath.to_list()
    ]
    for option in plugin_data.options:
        flags.extend([
            "-P",
            "plugin:{}:{}".format(option.id, option.value),
        ])
    return flags

def _dedupe_strings(values):
    seen = {}
    deduped = []
    for value in values:
        if seen.get(value):
            continue
        seen[value] = True
        deduped.append(value)
    return deduped

def _fragment_source_flags(src_targets, source_set_names):
    if len(src_targets) != len(source_set_names):
        fail("expected source_set_names to match srcs length")
    flags = []
    for index in range(len(src_targets)):
        source_set_name = source_set_names[index]
        for src in src_targets[index][DefaultInfo].files.to_list():
            flags.append("-Xfragment-sources={}:{}".format(source_set_name, src.path))
    return flags

def _library_flags(files):
    flags = []
    for file in files:
        flags.extend(["-library", file.path])
    return flags

def _dependency_flags(ctx, libraries):
    return [
        "-target",
        ctx.attr.konan_target,
        "-module-name",
        ctx.attr.module_name,
    ] + _library_flags(libraries)

def _compile_flags(ctx, libraries):
    fragments = _dedupe_strings(ctx.attr.source_set_names)
    return _dependency_flags(ctx, libraries) + [
        "-Xmulti-platform",
        "-Xexpect-actual-classes",
    ] + [
        "-Xfragments={}".format(fragment)
        for fragment in fragments
    ] + [
        "-Xfragment-refines={}".format(refine)
        for refine in ctx.attr.fragment_refines
    ] + _fragment_source_flags(ctx.attr.srcs, ctx.attr.source_set_names)

def _export_library_flags(files):
    flags = []
    for file in files:
        flags.append("-Xexport-library={}".format(file.path))
    return flags

def _framework_flags(ctx, libraries, exported_libraries):
    return _dependency_flags(ctx, libraries) + [
        "-produce",
        "framework",
    ] + _export_library_flags(exported_libraries)

def _framework_outputs(ctx):
    framework_root = "{}/{}.framework".format(ctx.label.name, ctx.attr.module_name)
    return [
        ctx.actions.declare_file("{}/{}".format(framework_root, ctx.attr.module_name)),
        ctx.actions.declare_file("{}/Headers/{}.h".format(framework_root, ctx.attr.module_name)),
        ctx.actions.declare_file("{}/Modules/module.modulemap".format(framework_root)),
        ctx.actions.declare_file("{}/Info.plist".format(framework_root)),
    ]

def _repo_relative_path(file):
    parts = file.short_path.split("/")
    if len(parts) >= 3 and parts[0] == "..":
        return "/".join(parts[2:])
    if len(parts) >= 3 and parts[0] == "external":
        return "/".join(parts[2:])
    return file.basename

def _java_executable(ctx):
    return ctx.toolchains[_NATIVE_TOOLCHAIN_TYPE].kmp_native.java_runtime.java_executable_exec_path

def _java_runtime_files(ctx):
    return ctx.toolchains[_NATIVE_TOOLCHAIN_TYPE].kmp_native.java_runtime.files.to_list()

def _write_link_manifest(ctx, name, files):
    output = ctx.actions.declare_file("{}_{}.txt".format(ctx.label.name, name))
    ctx.actions.write(
        output = output,
        content = "\n".join(["{}|{}".format(file.path, _repo_relative_path(file)) for file in files]) + "\n",
    )
    return output

def _write_args_file(ctx, name, values):
    output = ctx.actions.declare_file("{}_{}.args".format(ctx.label.name, name))
    ctx.actions.write(output = output, content = "\n".join(values) + "\n")
    return output

def _kt_ios_framework_files_impl(ctx):
    framework_files = _framework_outputs(ctx)
    framework_binary = framework_files[0]
    header = framework_files[1]
    modulemap = framework_files[2]
    info_plist = framework_files[3]
    klib = ctx.actions.declare_file("{}/{}.klib".format(ctx.label.name, ctx.attr.module_name))

    source_files = ctx.files.srcs
    libraries = _collect_dep_klibs(ctx.attr.deps + ctx.attr.exports)
    exported_libraries = _collect_dep_klibs(ctx.attr.exports)
    plugin_data = _compile_plugin_data(ctx.attr.plugins)
    plugin_jars = plugin_data.classpath.to_list()
    native_toolchain = ctx.toolchains[_NATIVE_TOOLCHAIN_TYPE].kmp_native
    llvm_files = native_toolchain.llvm_files.to_list()
    libffi_files = native_toolchain.libffi_files.to_list()
    llvm_manifest = _write_link_manifest(ctx, "llvm_files", llvm_files)
    libffi_manifest = _write_link_manifest(ctx, "libffi_files", libffi_files)
    plugin_flags = _plugin_flags(plugin_data)
    compile_flags = _compile_flags(ctx, libraries) + plugin_flags
    framework_flags = _framework_flags(ctx, libraries, exported_libraries)
    compile_args_file = _write_args_file(ctx, "compile", compile_flags + [file.path for file in source_files])
    framework_args_file = _write_args_file(ctx, "framework", framework_flags)
    inputs = (
        source_files +
        libraries +
        plugin_jars +
        llvm_files +
        libffi_files +
        native_toolchain.home_files.to_list() +
        _java_runtime_files(ctx) +
        [
            native_toolchain.compiler,
            compile_args_file,
            framework_args_file,
            llvm_manifest,
            libffi_manifest,
        ]
    )

    ctx.actions.run_shell(
        inputs = depset(inputs),
        outputs = framework_files + [klib],
        command = """
set -euo pipefail

java="$1"
kotlin_native_compiler_jar="$2"
konanc_main="$3"
module_name="$4"
framework_binary="$5"
header="$6"
modulemap="$7"
info_plist="$8"
klib="${9}"
compile_args_file="${10}"
framework_args_file="${11}"
llvm_manifest="${12}"
libffi_manifest="${13}"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/konan-action.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT
mkdir -p "${work_dir}/cache" "${work_dir}/konan-data/dependencies/cache" "${work_dir}/tmp" "$(dirname "${framework_binary}")" "$(dirname "${header}")" "$(dirname "${modulemap}")" "$(dirname "${info_plist}")" "$(dirname "${klib}")"

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "${PWD}/$1" ;;
  esac
}

link_manifest() {
  local manifest="$1"
  local destination="$2"
  mkdir -p "${destination}"
  while IFS='|' read -r source relative; do
    [[ -z "${source}" ]] && continue
    mkdir -p "${destination}/$(dirname "${relative}")"
    ln -s "$(absolute_path "${source}")" "${destination}/${relative}"
  done < "${manifest}"
}

prepare_konan_home() {
  local distribution_home="$1"
  local konan_home="$2"
  mkdir -p "${konan_home}/klib/cache"

  local entry
  for entry in "${distribution_home}"/*; do
    local basename
    basename="$(basename "${entry}")"
    if [[ "${basename}" == "klib" ]]; then
      continue
    fi
    ln -s "${entry}" "${konan_home}/${basename}"
  done

  for entry in "${distribution_home}/klib"/*; do
    local basename
    basename="$(basename "${entry}")"
    if [[ "${basename}" == "cache" ]]; then
      continue
    fi
    ln -s "${entry}" "${konan_home}/klib/${basename}"
  done
}

# Kotlin/Native always creates system caches under konan.home/klib/cache.
# Symlink the read-only Bazel distribution into a small writable home instead
# of copying or mutating the compiler distribution itself.
kotlin_native_distribution="$(cd "$(dirname "${kotlin_native_compiler_jar}")/../.." && pwd)"
konan_home="${work_dir}/kotlin-native"
prepare_konan_home "${kotlin_native_distribution}" "${konan_home}"

run_konanc() {
  while IFS=$'\r' read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" ]] && continue
    unset "${line}"
  done < "${konan_home}/tools/env_blacklist"

  LIBCLANG_DISABLE_CRASH_RECOVERY=1 \
    "${java}" \
    -ea \
    -Xmx3G \
    -XX:TieredStopAtLevel=1 \
    -Dfile.encoding=UTF-8 \
    -Dkonan.home="${konan_home}" \
    -cp "${kotlin_native_compiler_jar}" \
    "${konanc_main}" \
    konanc \
    "$@"
}

link_manifest "${llvm_manifest}" "${work_dir}/konan-data/dependencies/llvm-19-aarch64-macos-essentials-81"
link_manifest "${libffi_manifest}" "${work_dir}/konan-data/dependencies/libffi-3.3-1-macos-arm64"

# Seed Kotlin/Native's dependency directory from Bazel-managed archives so the
# compiler never downloads LLVM/libffi during the action.
printf '%s\n%s\n' \
  "llvm-19-aarch64-macos-essentials-81" \
  "libffi-3.3-1-macos-arm64" \
  > "${work_dir}/konan-data/dependencies/.extracted"

cache_args=(
  "-Xcache-directory=${work_dir}/cache"
  "-Xauto-cache-dir=${work_dir}/cache"
  "-Xkonan-data-dir=${work_dir}/konan-data"
  "-Xtemporary-files-dir=${work_dir}/tmp"
)
export KONAN_DATA_DIR="${work_dir}/konan-data"

run_konanc "${cache_args[@]}" @"${compile_args_file}" -produce library -o "${work_dir}/${module_name}"

run_konanc "${cache_args[@]}" @"${framework_args_file}" -Xinclude="${work_dir}/${module_name}.klib" -o "${work_dir}/${module_name}"

cp "${work_dir}/${module_name}.klib" "${klib}"
cp "${work_dir}/${module_name}.framework/${module_name}" "${framework_binary}"
cp "${work_dir}/${module_name}.framework/Headers/${module_name}.h" "${header}"
cp "${work_dir}/${module_name}.framework/Modules/module.modulemap" "${modulemap}"
if [[ -f "${work_dir}/${module_name}.framework/Info.plist" ]]; then
  cp "${work_dir}/${module_name}.framework/Info.plist" "${info_plist}"
else
  cat > "${info_plist}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict></dict></plist>
EOF
fi
""",
        arguments = [
            _java_executable(ctx),
            native_toolchain.compiler.path,
            _KONANC_MAIN,
            ctx.attr.module_name,
            framework_binary.path,
            header.path,
            modulemap.path,
            info_plist.path,
            klib.path,
            compile_args_file.path,
            framework_args_file.path,
            llvm_manifest.path,
            libffi_manifest.path,
        ],
        mnemonic = "KtIosFramework",
        progress_message = "Compiling Kotlin/Native iOS simulator framework %{label}",
    )

    return [
        DefaultInfo(files = depset(framework_files)),
        KtNativeKlibInfo(klib = klib),
    ]

kt_ios_framework_files = rule(
    implementation = _kt_ios_framework_files_impl,
    attrs = {
        "deps": attr.label_list(),
        "exports": attr.label_list(),
        "fragment_refines": attr.string_list(),
        "konan_target": attr.string(
            mandatory = True,
            doc = "Kotlin/Native target.",
        ),
        "module_name": attr.string(mandatory = True),
        "plugins": attr.label_list(cfg = "exec"),
        "source_set_names": attr.string_list(),
        "srcs": attr.label_list(allow_files = [".kt"]),
    },
    doc = "Compiles a Kotlin/Native dynamic framework.",
    toolchains = [_NATIVE_TOOLCHAIN_TYPE],
)
