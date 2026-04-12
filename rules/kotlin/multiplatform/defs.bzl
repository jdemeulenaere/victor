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

def kt_multiplatform_library(
        name,
        common_srcs,
        jvm_srcs = None,
        android_srcs = None,
        deps = None,
        jvm_deps = None,
        android_deps = None,
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
    - :<name>_jvm (when jvm_srcs is set)
    - :<name>_android (when android_srcs is set)
    - :<name> alias to :<name>_jvm when JVM sources exist
    """
    if deps == None:
        deps = []
    if jvm_deps == None:
        jvm_deps = []
    if android_deps == None:
        android_deps = []
    if jvm_srcs == None:
        jvm_srcs = []
    if android_srcs == None:
        android_srcs = []

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

    if jvm:
        kt_jvm_library(
            name = "{}_jvm".format(name),
            srcs = common + jvm,
            kotlinc_opts = ":{}".format(opts_name),
            visibility = visibility,
            deps = deps + jvm_deps,
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
            deps = deps + android_deps,
        )
        if android_custom_package:
            android_kwargs["custom_package"] = android_custom_package
        kt_android_library(**android_kwargs)
