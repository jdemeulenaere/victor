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

def _common_sources_flags(common_srcs):
    package_name = native.package_name()
    if not package_name:
        return common_srcs
    return ["{}/{}".format(package_name, src) for src in common_srcs]

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

def _resolve_common_dep(dep, suffix):
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

def kt_multiplatform_library(
        name,
        srcs,
        deps = None,
        android_manifest = None,
        android_custom_package = None,
        visibility = None):
    """Creates platform libraries from shared Kotlin expect/actual sources.

    This macro compiles each platform target with:
    - all commonMain sources + platform sources
    - -Xmulti-platform enabled
    - -Xcommon-sources set to commonMain source paths
    - expect/actual class beta flag enabled

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
    """
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
    if not type(srcs) == "dict":
        fail("srcs must be a dict with keys common/jvm/android")
    for key in srcs.keys():
        if key not in ["common", "jvm", "android"]:
            fail("Unsupported srcs key '{}'. Expected one of: common, jvm, android".format(key))

    common_srcs = srcs.get("common", [])
    jvm_srcs = srcs.get("jvm", [])
    android_srcs = srcs.get("android", [])

    common = _normalize_same_package_srcs(common_srcs, "common_srcs")
    jvm = _normalize_same_package_srcs(jvm_srcs, "jvm_srcs")
    android = _normalize_same_package_srcs(android_srcs, "android_srcs")

    if not common:
        fail("kt_multiplatform_library requires non-empty common_srcs")
    if not jvm and not android:
        fail("kt_multiplatform_library requires at least one platform source set")

    opts_name = "{}_kmp_opts".format(name)
    kt_kotlinc_options(
        name = opts_name,
        x_common_sources = _common_sources_flags(common),
        x_expect_actual_classes = True,
        x_multi_platform = True,
    )

    jvm_all_deps = [_resolve_common_dep(dep, "jvm") for dep in common_deps] + jvm_deps
    android_all_deps = [_resolve_common_dep(dep, "android") for dep in common_deps] + android_deps

    if jvm:
        kt_jvm_library(
            name = "{}_jvm".format(name),
            srcs = common + jvm,
            kotlinc_opts = ":{}".format(opts_name),
            visibility = visibility,
            deps = jvm_all_deps,
        )
        native.alias(
            name = name,
            actual = ":{}_jvm".format(name),
            visibility = visibility,
        )

    if android:
        manifest = android_manifest
        if not manifest:
            if not android_custom_package:
                fail("android_custom_package is required when android_manifest is omitted")
            generated_manifest = "{}_android_manifest.xml".format(name)
            native.genrule(
                name = "{}_android_manifest".format(name),
                outs = [generated_manifest],
                cmd = "echo '<manifest package=\"{}\" />' > \"$@\"".format(android_custom_package),
            )
            manifest = ":{}".format(generated_manifest)

        android_kwargs = dict(
            name = "{}_android".format(name),
            srcs = common + android,
            manifest = manifest,
            kotlinc_opts = ":{}".format(opts_name),
            visibility = visibility,
            deps = android_all_deps,
        )
        if android_custom_package:
            android_kwargs["custom_package"] = android_custom_package
        kt_android_library(**android_kwargs)
