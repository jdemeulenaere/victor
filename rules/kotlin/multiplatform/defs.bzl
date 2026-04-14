"""Macros for Kotlin expect/actual multiplatform libraries in Bazel."""

load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("@rules_kotlin//kotlin:core.bzl", "kt_kotlinc_options")
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")

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
    # External repositories are generally regular platform-neutral deps and should not be remapped.
    if dep.startswith("@"):
        return dep

    target = _target_name(dep)
    if target.endswith("_jvm") or target.endswith("_android"):
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
        deps = None,
        plugins = None,
        android_manifest = None,
        android_custom_package = None,
        tags = None,
        visibility = None):
    """Creates Kotlin Multiplatform-style JVM/Android libraries.

    This macro follows the Kotlin Gradle plugin model for platform compilations:
    - each platform target compiles common + platform sources together
    - Kotlin fragment flags model source-set relations (`commonMain` refined by `jvmMain`/`androidMain`)
    - first-party common deps are remapped to platform variants

    Generated targets:
    - :<name>_jvm (when `srcs["jvm"]` is non-empty)
    - :<name>_android (when `srcs["android"]` is non-empty)
    - :<name> alias to :<name>_jvm when JVM sources exist

    Args:
    - srcs: required dictionary with keys `common`, `jvm`, `android`.
    - deps: optional dictionary with keys:
      - `common`: deps added to both platform targets. External labels are used as-is;
        first-party labels are remapped to platform variants (for example `:core` -> `:core_jvm`/`:core_android`).
      - `jvm`: regular deps for the JVM target only.
      - `android`: regular deps for the Android target only.
    - plugins: optional list of compiler plugins applied to both platform targets.
    - tags: optional list of tags applied to both platform targets.
    """
    if deps == None:
        deps = {}
    if not type(deps) == "dict":
        fail("deps must be a dict with keys common/jvm/android")
    for key in deps.keys():
        if key not in ["common", "jvm", "android"]:
            fail("Unsupported deps key '{}'. Expected one of: common, jvm, android".format(key))

    normalized_plugins = _normalize_dep_list(plugins, "plugins")

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

    common_deps = _normalize_dep_list(deps.get("common"), "deps[\"common\"]")
    jvm_deps = _normalize_dep_list(deps.get("jvm"), "deps[\"jvm\"]")
    android_deps = _normalize_dep_list(deps.get("android"), "deps[\"android\"]")
    user_tags = _normalize_tag_list(tags)

    common_jvm_deps = [_resolve_dep_for_variant(dep, "jvm") for dep in common_deps]
    common_android_deps = [_resolve_dep_for_variant(dep, "android") for dep in common_deps]

    if jvm:
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

    if android:
        _define_platform_opts(
            name = name,
            platform_suffix = "android",
            platform_fragment = "androidMain",
            common_srcs = common,
            platform_srcs = android,
        )

        manifest = android_manifest
        if not manifest:
            manifest_package = android_custom_package
            if not manifest_package:
                package_name = native.package_name().replace("/", ".").replace("-", "_")
                manifest_package = "generated.{}.{}".format(package_name, name.replace("-", "_"))
            generated_manifest = "{}_android_manifest.xml".format(name)
            native.genrule(
                name = "{}_android_manifest".format(name),
                outs = [generated_manifest],
                cmd = "echo '<manifest package=\"{}\" />' > \"$@\"".format(manifest_package),
            )
            manifest = ":{}".format(generated_manifest)

        android_kwargs = dict(
            name = "{}_android".format(name),
            srcs = common + android,
            manifest = manifest,
            kotlinc_opts = ":{}".format(_platform_opts_name(name, "android")),
            plugins = normalized_plugins,
            tags = user_tags,
            visibility = visibility,
            deps = common_android_deps + android_deps,
        )
        if android_custom_package:
            android_kwargs["custom_package"] = android_custom_package
        kt_android_library(**android_kwargs)
