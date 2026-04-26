"""Macros for Kotlin expect/actual multiplatform libraries in Bazel."""

load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("@rules_kotlin//kotlin:core.bzl", "kt_kotlinc_options")
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")
load("@third_party_maven_kmp_variants//:variants.bzl", "KMP_MAVEN_VARIANTS", "KOTLIN_STDLIB_WASM_LABEL")
load("//build/rules/kotlin/multiplatform:wasm.bzl", "kt_wasm_files", "kt_wasm_library")

_SUPPORTED_PLATFORMS = ["android", "jvm", "wasm"]
_THIRD_PARTY_MAVEN_PREFIX = "@third_party_maven//:"

def _normalize_same_package_srcs(srcs, attr_name):
    normalized = []
    for src in srcs:
        if not type(src) == "string":
            fail("{} values must be strings, got {}".format(attr_name, type(src)))
        if src.startswith("//") or src.startswith("@"):
            fail("{} must reference files in the current package: {}".format(attr_name, src))
        normalized.append(src[1:] if src.startswith(":") else src)
    return normalized

def _fragment_sources_flags(fragment_name, srcs):
    package_name = native.package_name()
    if package_name:
        return ["{}:{}/{}".format(fragment_name, package_name, src) for src in srcs]
    return ["{}:{}".format(fragment_name, src) for src in srcs]

def _platform_target(dep, suffix):
    if not type(dep) == "string":
        fail("deps values must be strings, got {}".format(type(dep)))
    if ":" in dep:
        head, tail = dep.rsplit(":", 1)
        return "{}:{}_{}".format(head, tail, suffix)
    if dep.startswith("//") or dep.startswith("@"):
        fail("deps entries must include an explicit target name: {}".format(dep))
    return "{}_{}".format(dep, suffix)

def _target_name(dep):
    if ":" in dep:
        return dep.rsplit(":", 1)[1]
    if dep.startswith("//") or dep.startswith("@"):
        return ""
    return dep

def _resolve_dep_for_variant(dep, suffix):
    if dep.startswith(_THIRD_PARTY_MAVEN_PREFIX):
        variants = KMP_MAVEN_VARIANTS.get(dep)
        if variants:
            variant = variants.get(suffix)
            if variant:
                return variant
        if suffix == "wasm":
            fail("No Kotlin/WASM Maven variant found for {}".format(dep))
        return dep

    # Other external repositories are generally regular platform-neutral deps and should not be remapped.
    if dep.startswith("@"):
        return dep

    target = _target_name(dep)
    if target.endswith("_jvm") or target.endswith("_android") or target.endswith("_wasm"):
        return dep

    return _platform_target(dep, suffix)

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

def _normalize_tag_list(values):
    if values == None:
        return []
    if not type(values) == "list":
        fail("tags must be a list of strings")
    normalized = []
    for value in values:
        if not type(value) == "string":
            fail("tags values must be strings, got {}".format(type(value)))
        normalized.append(value)
    return normalized

def _platform_opts_name(name, platform_suffix):
    return "{}_{}_kmp_opts".format(name, platform_suffix)

def _normalize_platforms(platforms):
    if not type(platforms) == "list":
        fail("platforms must be a list containing any of: {}".format(", ".join(_SUPPORTED_PLATFORMS)))
    if not platforms:
        fail("kt_multiplatform_library requires at least one platform")

    seen = {}
    normalized = []
    for platform in platforms:
        if not type(platform) == "string":
            fail("platforms values must be strings, got {}".format(type(platform)))
        if platform not in _SUPPORTED_PLATFORMS:
            fail("Unsupported platform '{}'. Expected one of: {}".format(platform, ", ".join(_SUPPORTED_PLATFORMS)))
        if seen.get(platform):
            fail("Duplicate platform '{}'".format(platform))
        seen[platform] = True
        normalized.append(platform)
    return normalized

def _has_platform(platforms, platform):
    return platform in platforms

def _define_platform_opts(name, platform_suffix, platform_fragment, common_srcs, platform_srcs):
    kt_kotlinc_options(
        name = _platform_opts_name(name, platform_suffix),
        x_expect_actual_classes = True,
        x_fragment_refines = ["{}:commonMain".format(platform_fragment)],
        x_fragment_sources = _fragment_sources_flags(platform_fragment, platform_srcs) + _fragment_sources_flags("commonMain", common_srcs),
        x_fragments = [platform_fragment, "commonMain"],
        x_multi_platform = True,
    )

def kt_multiplatform_library(
        name,
        srcs,
        platforms,
        deps = None,
        plugins = None,
        android_manifest = None,
        android_custom_package = None,
        tags = None,
        visibility = None):
    """Creates Kotlin Multiplatform-style JVM/Android/WASM libraries.

    This macro follows the Kotlin Gradle plugin model for platform compilations:
    - each platform target compiles common + platform sources together
    - Kotlin fragment flags model source-set relations (`commonMain` refined by each platform source set)
    - first-party common deps are remapped to platform variants

    Generated targets:
    - :<name>_jvm when `platforms` contains `jvm`
    - :<name>_android when `platforms` contains `android`
    - :<name>_wasm and :<name>_wasm_files when `platforms` contains `wasm`
    - :<name> alias to :<name>_jvm when JVM is selected

    Args:
    - platforms: required list containing any of `android`, `jvm`, `wasm`.
    - srcs: required dictionary with keys `common`, `jvm`, `android`, `wasm`.
    - deps: optional dictionary with keys:
      - `common`: deps added to all selected platform targets. `@third_party_maven` Kotlin Multiplatform
        labels are resolved through Gradle Module Metadata when available; other external labels are used as-is.
        first-party labels are remapped to platform variants (for example `:core` -> `:core_jvm`/`:core_android`/`:core_wasm`).
      - `jvm`: regular deps for the JVM target only.
      - `android`: regular deps for the Android target only.
      - `wasm`: KLIB deps for the WASM target only.
    - plugins: optional list of compiler plugins applied to all selected platform targets.
    - tags: optional list of tags applied to all selected platform targets.
    """
    selected_platforms = _normalize_platforms(platforms)
    if deps == None:
        deps = {}
    if not type(deps) == "dict":
        fail("deps must be a dict with keys common/android/jvm/wasm")
    for key in deps.keys():
        if key not in ["common", "android", "jvm", "wasm"]:
            fail("Unsupported deps key '{}'. Expected one of: common, android, jvm, wasm".format(key))

    normalized_plugins = _normalize_dep_list(plugins, "plugins")

    if not type(srcs) == "dict":
        fail("srcs must be a dict with keys common/android/jvm/wasm")
    for key in srcs.keys():
        if key not in ["common", "android", "jvm", "wasm"]:
            fail("Unsupported srcs key '{}'. Expected one of: common, android, jvm, wasm".format(key))

    common = _normalize_same_package_srcs(srcs.get("common", []), "common_srcs")
    android = _normalize_same_package_srcs(srcs.get("android", []), "android_srcs")
    jvm = _normalize_same_package_srcs(srcs.get("jvm", []), "jvm_srcs")
    wasm = _normalize_same_package_srcs(srcs.get("wasm", []), "wasm_srcs")

    if not common:
        fail("kt_multiplatform_library requires non-empty common_srcs")

    common_deps = _normalize_dep_list(deps.get("common"), "deps[\"common\"]")
    android_deps = _normalize_dep_list(deps.get("android"), "deps[\"android\"]")
    jvm_deps = _normalize_dep_list(deps.get("jvm"), "deps[\"jvm\"]")
    wasm_deps = _normalize_dep_list(deps.get("wasm"), "deps[\"wasm\"]")
    user_tags = _normalize_tag_list(tags)

    if _has_platform(selected_platforms, "jvm"):
        common_jvm_deps = [_resolve_dep_for_variant(dep, "jvm") for dep in common_deps]
        _define_platform_opts(
            name = name,
            platform_suffix = "jvm",
            platform_fragment = "jvmMain",
            common_srcs = common,
            platform_srcs = jvm,
        )
        kt_jvm_library(
            name = "{}_jvm".format(name),
            srcs = common + jvm,
            kotlinc_opts = ":{}".format(_platform_opts_name(name, "jvm")),
            plugins = normalized_plugins,
            tags = user_tags,
            visibility = visibility,
            deps = common_jvm_deps + jvm_deps,
        )
        native.alias(
            name = name,
            actual = ":{}_jvm".format(name),
            visibility = visibility,
        )

    if _has_platform(selected_platforms, "android"):
        common_android_deps = [_resolve_dep_for_variant(dep, "android") for dep in common_deps]
        _define_platform_opts(
            name = name,
            platform_suffix = "android",
            platform_fragment = "androidMain",
            common_srcs = common,
            platform_srcs = android,
        )

        android_kwargs = dict(
            name = "{}_android".format(name),
            srcs = common + android,
            kotlinc_opts = ":{}".format(_platform_opts_name(name, "android")),
            plugins = normalized_plugins,
            tags = user_tags,
            visibility = visibility,
            deps = common_android_deps + android_deps,
        )
        if android_manifest:
            android_kwargs["manifest"] = android_manifest
        if android_custom_package:
            android_kwargs["custom_package"] = android_custom_package
        kt_android_library(**android_kwargs)

    if _has_platform(selected_platforms, "wasm"):
        common_wasm_deps = [_resolve_dep_for_variant(dep, "wasm") for dep in common_deps]
        kt_wasm_library(
            name = "{}_wasm".format(name),
            common_srcs = common,
            deps = common_wasm_deps + wasm_deps + [KOTLIN_STDLIB_WASM_LABEL],
            module_name = name,
            platform_srcs = wasm,
            plugins = normalized_plugins,
            tags = user_tags,
            visibility = visibility,
        )
        kt_wasm_files(
            name = "{}_wasm_files".format(name),
            module = ":{}_wasm".format(name),
            module_name = name,
            visibility = visibility,
        )
