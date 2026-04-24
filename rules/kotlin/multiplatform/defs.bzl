"""Kotlin KMP compilation rules with Gradle K2-style source set semantics."""

load("@rules_java//java:defs.bzl", "JavaInfo", "java_common", "java_import")
load("@rules_kotlin//kotlin/internal:defs.bzl", "KtCompilerPluginInfo", "KtPluginConfiguration")
load("@third_party_maven_kmp_variants//:variants.bzl", "KMP_KNOWN_TARGETS", "KMP_METADATA_VARIANTS", "KMP_PLATFORM_VARIANTS")

KmpMetadataInfo = provider(
    doc = "Metadata artifact produced by KMP metadata compilation.",
    fields = {
        "klib": "KLIB output directory for this source set.",
    },
)

def _normalize_same_package_srcs(srcs, attr_name):
    normalized = []
    for src in srcs:
        if not type(src) == "string":
            fail("{} values must be strings, got {}".format(attr_name, type(src)))
        if src.startswith("//") or src.startswith("@"):
            fail("{} must reference files in the current package: {}".format(attr_name, src))
        normalized.append(src[1:] if src.startswith(":") else src)
    return normalized

def _normalize_dep_list(values, attr_name):
    if values == None:
        return []
    if not type(values) == "list":
        fail("{} must be a list of label strings".format(attr_name))
    normalized = []
    for value in values:
        if not type(value) == "string":
            fail("{} values must be strings, got {}".format(attr_name, type(value)))
        normalized.append(value)
    return normalized

def _map_plugin_for_embeddable_compiler(plugin_label):
    if plugin_label == "//toolchains/kotlin/compose:compose_compiler_plugin":
        return "//toolchains/kotlin/compose:compose_compiler_plugin_embeddable"
    return plugin_label

def _target_name(dep):
    if ":" in dep:
        return dep.rsplit(":", 1)[1]
    if dep.startswith("//") or dep.startswith("@"):
        return ""
    return dep

def _platform_target(dep, suffix):
    if not type(dep) == "string":
        fail("deps values must be strings, got {}".format(type(dep)))
    if ":" in dep:
        head, tail = dep.rsplit(":", 1)
        return "{}:{}_{}".format(head, tail, suffix)
    if dep.startswith("//") or dep.startswith("@"):
        fail("deps entries must include an explicit target name: {}".format(dep))
    return "{}_{}".format(dep, suffix)

def _third_party_maven_target(dep):
    if dep.startswith("@third_party_maven//:"):
        return dep.rsplit(":", 1)[1]
    return None

def _common_candidate_from_platform_dep(dep):
    target = _third_party_maven_target(dep)
    if not target:
        return None
    if target.endswith("_desktop"):
        return "@third_party_maven//:{}".format(target[:-len("_desktop")])
    if target.endswith("_android"):
        return "@third_party_maven//:{}".format(target[:-len("_android")])
    return None

def _infer_common_deps_from_platform_deps(jvm_deps, android_deps):
    jvm_candidates = {}
    for dep in jvm_deps:
        candidate = _common_candidate_from_platform_dep(dep)
        if candidate:
            jvm_candidates[candidate] = True

    inferred = []
    for dep in android_deps:
        candidate = _common_candidate_from_platform_dep(dep)
        if candidate and candidate in jvm_candidates:
            inferred.append(candidate)

    return _dedupe_strings(inferred)

def _resolve_common_dep_for_platform(dep, suffix):
    third_party_target = _third_party_maven_target(dep)
    if third_party_target:
        variant = KMP_PLATFORM_VARIANTS.get(third_party_target, {}).get(suffix)
        if variant:
            return "@third_party_maven//:{}".format(variant)

    if dep.startswith("@"):
        return dep

    target = _target_name(dep)
    if target.endswith("_jvm") or target.endswith("_android"):
        return dep
    if target.endswith("_metadata"):
        fail("Common dependency {} resolves to metadata target for platform {}".format(dep, suffix))

    return _platform_target(dep, suffix)

def _split_common_dep_for_metadata(dep):
    if dep.startswith("@"):
        return struct(metadata_dep = None, java_dep = dep)

    target = _target_name(dep)
    if target.endswith("_metadata"):
        return struct(metadata_dep = dep, java_dep = None)
    if target.endswith("_jvm") or target.endswith("_android"):
        return struct(metadata_dep = None, java_dep = dep)

    return struct(metadata_dep = _platform_target(dep, "metadata"), java_dep = None)

def _metadata_extra_jars_for_common_dep(dep):
    third_party_target = _third_party_maven_target(dep)
    if third_party_target and third_party_target in KMP_KNOWN_TARGETS and third_party_target in KMP_METADATA_VARIANTS:
        return ["@third_party_maven_kmp_variants//:{}".format(third_party_target)]
    return []

def _sorted_files(files):
    return sorted(files, key = lambda f: f.path)

def _unique_files_by_path(files):
    by_path = {}
    for file in files:
        by_path[file.path] = file
    return [by_path[path] for path in sorted(by_path.keys())]

def _dedupe_strings(values):
    seen = {}
    deduped = []
    for value in values:
        if value in seen:
            continue
        seen[value] = True
        deduped.append(value)
    return deduped

def _join_paths(files):
    if not files:
        return ""
    return ":".join([f.path for f in files])

def _materialize_common_metadata_views(ctx, jars, name_prefix):
    views = []

    for index, jar in enumerate(jars):
        view = ctx.actions.declare_directory("{}_{}_{}".format(ctx.label.name, name_prefix, index))
        ctx.actions.run_shell(
            inputs = [jar],
            outputs = [view],
            command = """
set -euo pipefail
in="$1"
out="$2"

mkdir -p "$out"

if unzip -Z1 "$in" "commonMain/default/manifest" >/dev/null 2>&1; then
  unzip -qq "$in" "commonMain/default/*" -d "$out"
  mkdir -p "$out/default"
  cp -R "$out/commonMain/default/." "$out/default/"
  rm -rf "$out/commonMain"
elif unzip -Z1 "$in" "default/manifest" >/dev/null 2>&1; then
  unzip -qq "$in" "default/*" -d "$out"
fi
""",
            arguments = [jar.path, view.path],
            mnemonic = "KmpMetadataDepExtract",
            progress_message = "Extracting KMP metadata view for {}".format(jar.path),
        )
        views.append(view)

    return views

def _compiler_runtime_files(ctx):
    return _sorted_files(ctx.attr._compiler[JavaInfo].transitive_runtime_jars.to_list())

def _transitive_runtime_jars(targets):
    if not targets:
        return depset()
    return depset(transitive = [target[JavaInfo].transitive_runtime_jars for target in targets])

def _collect_plugin_data(plugin_targets):
    plugin_infos = {}
    plugin_cfgs = {}
    fallback_jars = []

    for target in plugin_targets:
        has_plugin_provider = False

        if KtCompilerPluginInfo in target:
            has_plugin_provider = True
            info = target[KtCompilerPluginInfo]
            if info.compile:
                existing = plugin_infos.get(info.id)
                if existing != None and existing != info:
                    fail("Multiple compiler plugins found with id '{}'".format(info.id))
                plugin_infos[info.id] = info

        if KtPluginConfiguration in target:
            has_plugin_provider = True
            cfg = target[KtPluginConfiguration]
            plugin_cfgs.setdefault(cfg.id, []).append(cfg)

        if not has_plugin_provider:
            fallback_jars.extend([file for file in target.files.to_list() if file.path.endswith(".jar")])

    orphan_cfg_ids = [plugin_id for plugin_id in plugin_cfgs.keys() if plugin_id not in plugin_infos]
    if orphan_cfg_ids:
        fail("Plugin configurations without corresponding plugins: {}".format(", ".join(sorted(orphan_cfg_ids))))

    classpath_parts = []
    options = []

    for plugin_id in sorted(plugin_infos.keys()):
        info = plugin_infos[plugin_id]
        classpath_parts.append(info.classpath)
        options.extend(info.options)

        cfgs = plugin_cfgs.get(plugin_id, [])
        if cfgs:
            merged_cfg = info.merge_cfgs(info, cfgs)
            classpath_parts.append(merged_cfg.classpath)
            options.extend(merged_cfg.options)

    plugin_classpath_files = []
    if classpath_parts:
        plugin_classpath_files.extend(depset(transitive = classpath_parts).to_list())
    plugin_classpath_files.extend(fallback_jars)
    plugin_classpath_files = _unique_files_by_path(plugin_classpath_files)

    return struct(
        classpath_files = plugin_classpath_files,
        options = options,
    )

def _kmp_platform_compile_impl(ctx):
    common_srcs = _sorted_files(ctx.files.common_srcs)
    platform_srcs = _sorted_files(ctx.files.platform_srcs)
    all_srcs = common_srcs + platform_srcs

    common_dep_jars = _transitive_runtime_jars(ctx.attr.common_deps)
    platform_dep_jars = _transitive_runtime_jars(ctx.attr.platform_deps)

    compile_jars = depset(
        transitive = [
            ctx.attr._stdlib[JavaInfo].transitive_runtime_jars,
            common_dep_jars,
            platform_dep_jars,
        ],
    )
    classpath_files = _sorted_files(compile_jars.to_list())

    plugin_data = _collect_plugin_data(ctx.attr.plugins)
    plugin_paths = [file.path for file in plugin_data.classpath_files]

    compiler_files = _compiler_runtime_files(ctx)
    java_runtime = ctx.attr._java_runtime[java_common.JavaRuntimeInfo]

    args = ctx.actions.args()
    args.add("-cp")
    args.add(_join_paths(compiler_files))
    args.add("org.jetbrains.kotlin.cli.jvm.K2JVMCompiler")

    args.add("-d")
    args.add(ctx.outputs.jar.path)
    args.add("-module-name")
    args.add(ctx.attr.module_name)
    args.add("-jvm-target")
    args.add(ctx.attr.jvm_target)
    args.add("-no-stdlib")
    args.add("-no-reflect")
    args.add("-Xmulti-platform")
    args.add("-Xfragments=commonMain")
    args.add("-Xfragments={}".format(ctx.attr.fragment_name))
    args.add("-Xfragment-refines={}:commonMain".format(ctx.attr.fragment_name))

    for src in common_srcs:
        args.add("-Xfragment-sources=commonMain:{}".format(src.path))
    for src in platform_srcs:
        args.add("-Xfragment-sources={}:{}".format(ctx.attr.fragment_name, src.path))

    if ctx.attr.separate_kmp_compilation:
        args.add("-Xseparate-kmp-compilation")

        for dep in _sorted_files(common_dep_jars.to_list()):
            args.add("-Xfragment-dependency=commonMain:{}".format(dep.path))
        for dep in _sorted_files(platform_dep_jars.to_list()):
            args.add("-Xfragment-dependency={}:{}".format(ctx.attr.fragment_name, dep.path))

    if classpath_files:
        args.add("-classpath")
        args.add(_join_paths(classpath_files))

    if plugin_paths:
        args.add("-Xplugin={}".format(",".join(plugin_paths)))
    for option in plugin_data.options:
        args.add("-P")
        args.add("plugin:{}:{}".format(option.id, option.value))

    for src in all_srcs:
        args.add(src.path)

    ctx.actions.run(
        executable = str(java_runtime.java_executable_exec_path),
        arguments = [args],
        inputs = depset(
            direct = _unique_files_by_path(all_srcs + classpath_files + plugin_data.classpath_files),
            transitive = [
                depset(direct = compiler_files),
                java_runtime.files,
            ],
        ),
        outputs = [ctx.outputs.jar],
        mnemonic = "KmpPlatformCompile",
        progress_message = "Compiling Kotlin {} platform target {}".format(ctx.attr.fragment_name, ctx.label),
    )

    return [DefaultInfo(files = depset([ctx.outputs.jar]))]

def _kmp_metadata_compile_impl(ctx):
    srcs = _sorted_files(ctx.files.srcs)
    out_klib = ctx.actions.declare_directory(ctx.label.name + ".klib")

    metadata_classpath_klibs = _sorted_files([dep[KmpMetadataInfo].klib for dep in ctx.attr.metadata_deps])
    refines_path_klibs = _sorted_files([dep[KmpMetadataInfo].klib for dep in ctx.attr.refines_paths])

    java_dep_jars = _transitive_runtime_jars(ctx.attr.java_deps)
    java_dep_files = _sorted_files(java_dep_jars.to_list())
    metadata_dep_jars = _unique_files_by_path(java_dep_files)
    metadata_dep_views = _materialize_common_metadata_views(ctx, metadata_dep_jars, "metadata_dep")
    extra_metadata_jars = _sorted_files(ctx.files.extra_metadata_jars)
    extra_metadata_views = _materialize_common_metadata_views(ctx, extra_metadata_jars, "extra_metadata")

    classpath_files = _unique_files_by_path(
        metadata_classpath_klibs +
        metadata_dep_views +
        extra_metadata_views +
        metadata_dep_jars +
        [ctx.file._metadata_stdlib_klib],
    )

    plugin_data = _collect_plugin_data(ctx.attr.plugins)
    plugin_paths = [file.path for file in plugin_data.classpath_files]

    compiler_files = _compiler_runtime_files(ctx)
    java_runtime = ctx.attr._java_runtime[java_common.JavaRuntimeInfo]

    args = ctx.actions.args()
    args.add("-cp")
    args.add(_join_paths(compiler_files))
    args.add("org.jetbrains.kotlin.cli.metadata.KotlinMetadataCompiler")

    args.add("-d")
    args.add(out_klib.path)
    args.add("-module-name")
    args.add(ctx.attr.module_name)
    args.add("-Xmetadata-klib")
    args.add("-Xmulti-platform")

    for target_platform in _dedupe_strings(ctx.attr.target_platforms):
        args.add("-Xtarget-platform={}".format(target_platform))

    for src in srcs:
        args.add("-Xcommon-sources={}".format(src.path))

    for dep in refines_path_klibs:
        args.add("-Xrefines-paths={}".format(dep.path))

    if classpath_files:
        args.add("-classpath")
        args.add(_join_paths(classpath_files))

    if plugin_paths:
        args.add("-Xplugin={}".format(",".join(plugin_paths)))
    for option in plugin_data.options:
        args.add("-P")
        args.add("plugin:{}:{}".format(option.id, option.value))

    for src in srcs:
        args.add(src.path)

    ctx.actions.run(
        executable = str(java_runtime.java_executable_exec_path),
        arguments = [args],
        inputs = depset(
            direct = _unique_files_by_path(
                srcs +
                classpath_files +
                refines_path_klibs +
                extra_metadata_jars +
                plugin_data.classpath_files,
            ),
            transitive = [
                depset(direct = compiler_files),
                java_runtime.files,
            ],
        ),
        outputs = [out_klib],
        mnemonic = "KmpMetadataCompile",
        progress_message = "Compiling Kotlin metadata target {}".format(ctx.label),
    )

    return [
        DefaultInfo(files = depset([out_klib])),
        KmpMetadataInfo(klib = out_klib),
    ]

kmp_platform_compile = rule(
    implementation = _kmp_platform_compile_impl,
    attrs = {
        "common_srcs": attr.label_list(allow_files = [".kt"]),
        "platform_srcs": attr.label_list(allow_files = [".kt"]),
        "common_deps": attr.label_list(providers = [JavaInfo]),
        "platform_deps": attr.label_list(providers = [JavaInfo]),
        "plugins": attr.label_list(),
        "fragment_name": attr.string(mandatory = True),
        "separate_kmp_compilation": attr.bool(default = False),
        "jvm_target": attr.string(default = "21"),
        "module_name": attr.string(mandatory = True),
        "_compiler": attr.label(
            default = Label("@third_party_maven//:org_jetbrains_kotlin_kotlin_compiler_embeddable"),
            providers = [JavaInfo],
            cfg = "exec",
        ),
        "_java_runtime": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
            cfg = "exec",
        ),
        "_stdlib": attr.label(
            default = Label("@third_party_maven//:org_jetbrains_kotlin_kotlin_stdlib"),
            providers = [JavaInfo],
        ),
    },
    outputs = {"jar": "%{name}.jar"},
)

kmp_metadata_compile = rule(
    implementation = _kmp_metadata_compile_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".kt"]),
        "metadata_deps": attr.label_list(providers = [KmpMetadataInfo]),
        "java_deps": attr.label_list(providers = [JavaInfo]),
        "extra_metadata_jars": attr.label_list(allow_files = True),
        "refines_paths": attr.label_list(providers = [KmpMetadataInfo]),
        "plugins": attr.label_list(),
        "target_platforms": attr.string_list(default = ["JVM"]),
        "module_name": attr.string(mandatory = True),
        "_compiler": attr.label(
            default = Label("@third_party_maven//:org_jetbrains_kotlin_kotlin_compiler_embeddable"),
            providers = [JavaInfo],
            cfg = "exec",
        ),
        "_java_runtime": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
            cfg = "exec",
        ),
        "_metadata_stdlib_klib": attr.label(
            default = Label("@kotlin_stdlib_js_klib//file"),
            allow_single_file = True,
        ),
    },
)

def kt_multiplatform_library(
        name,
        srcs,
        deps = None,
        plugins = None,
        android_manifest = None,
        android_custom_package = None,
        visibility = None):
    """Creates KMP metadata + platform outputs with Gradle-style K2 source-set compilation semantics.

    Exposed targets:
    - :<name>_metadata
    - :<name>_jvm (if `srcs["jvm"]` non-empty)
    - :<name>_android (if `srcs["android"]` non-empty)

    Notes:
    - The `android_manifest` and `android_custom_package` args are kept for API compatibility.
      They are ignored because this macro now compiles Kotlin-only artifacts.
    """
    _ = android_manifest
    _ = android_custom_package

    if deps == None:
        deps = {}
    if not type(deps) == "dict":
        fail("deps must be a dict with keys common/jvm/android")
    for key in deps.keys():
        if key not in ["common", "jvm", "android"]:
            fail("Unsupported deps key '{}'. Expected one of: common, jvm, android".format(key))

    common_deps = _normalize_dep_list(deps.get("common"), "deps[\"common\"]")
    jvm_deps = _normalize_dep_list(deps.get("jvm"), "deps[\"jvm\"]")
    android_deps = _normalize_dep_list(deps.get("android"), "deps[\"android\"]")
    inferred_common_deps = _infer_common_deps_from_platform_deps(jvm_deps, android_deps)
    effective_common_deps = _dedupe_strings(common_deps + inferred_common_deps)
    normalized_plugins = _normalize_dep_list(plugins, "plugins")
    kmp_plugins = [_map_plugin_for_embeddable_compiler(plugin) for plugin in normalized_plugins]

    if not type(srcs) == "dict":
        fail("srcs must be a dict with keys common/jvm/android")
    for key in srcs.keys():
        if key not in ["common", "jvm", "android"]:
            fail("Unsupported srcs key '{}'. Expected one of: common, jvm, android".format(key))

    common = _normalize_same_package_srcs(srcs.get("common", []), "common_srcs")
    jvm = _normalize_same_package_srcs(srcs.get("jvm", []), "jvm_srcs")
    android = _normalize_same_package_srcs(srcs.get("android", []), "android_srcs")

    if not common:
        fail("kt_multiplatform_library requires non-empty common_srcs")
    if not jvm and not android:
        fail("kt_multiplatform_library requires at least one platform source set")

    common_jvm_deps = [_resolve_common_dep_for_platform(dep, "jvm") for dep in effective_common_deps]
    common_android_deps = [_resolve_common_dep_for_platform(dep, "android") for dep in effective_common_deps]

    metadata_deps = []
    metadata_java_deps = []
    extra_metadata_jars = []
    for dep in effective_common_deps:
        split = _split_common_dep_for_metadata(dep)
        if split.metadata_dep:
            metadata_deps.append(split.metadata_dep)
        if split.java_dep:
            metadata_java_deps.append(split.java_dep)
        extra_metadata_jars.extend(_metadata_extra_jars_for_common_dep(dep))

    metadata_target_platforms = ["JVM"]

    kmp_metadata_compile(
        name = "{}_metadata".format(name),
        module_name = "{}_commonMain".format(name),
        srcs = common,
        metadata_deps = metadata_deps,
        java_deps = metadata_java_deps,
        extra_metadata_jars = extra_metadata_jars,
        refines_paths = [],
        plugins = kmp_plugins,
        target_platforms = metadata_target_platforms,
        visibility = visibility,
    )

    if jvm:
        jvm_raw = "{}_jvm_compile".format(name)
        jvm_all_deps = _dedupe_strings(common_jvm_deps + jvm_deps)

        kmp_platform_compile(
            name = jvm_raw,
            module_name = "{}_jvm".format(name),
            common_srcs = common,
            platform_srcs = jvm,
            common_deps = common_jvm_deps,
            platform_deps = jvm_deps,
            fragment_name = "jvmMain",
            plugins = kmp_plugins,
            visibility = ["//visibility:private"],
        )

        java_import(
            name = "{}_jvm".format(name),
            jars = [":{}.jar".format(jvm_raw)],
            deps = jvm_all_deps,
            visibility = visibility,
        )

    if android:
        android_raw = "{}_android_compile".format(name)
        android_all_deps = _dedupe_strings(common_android_deps + android_deps)

        kmp_platform_compile(
            name = android_raw,
            module_name = "{}_android".format(name),
            common_srcs = common,
            platform_srcs = android,
            common_deps = common_android_deps,
            platform_deps = android_deps,
            fragment_name = "androidMain",
            plugins = kmp_plugins,
            visibility = ["//visibility:private"],
        )

        java_import(
            name = "{}_android".format(name),
            jars = [":{}.jar".format(android_raw)],
            deps = android_all_deps,
            visibility = visibility,
        )
