"""Repository iOS rule wrappers."""

load("@build_bazel_rules_apple//apple:ios.bzl", _ios_application = "ios_application", _ios_unit_test = "ios_unit_test")
load("@build_bazel_rules_swift//swift:swift_library.bzl", _swift_library = "swift_library")
load("//build/rules/kotlin/multiplatform:defs.bzl", "kmp_variant_forward")

IOS_TARGET_COMPATIBLE_WITH = select({
    "@platforms//os:ios": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

IOS_TEST_TARGET_COMPATIBLE_WITH = select({
    "@platforms//os:macos": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

def _with_manual_tag(tags):
    if tags == None:
        return ["manual"]
    if "manual" in tags:
        return tags
    return tags + ["manual"]

def _impl_target_name(name):
    return "{}__impl".format(name)

def _public_common_kwargs(kwargs):
    public_kwargs = {}
    for attr_name in [
        "compatible_with",
        "deprecation",
        "exec_compatible_with",
        "features",
        "restricted_to",
        "tags",
        "testonly",
    ]:
        value = kwargs.get(attr_name)
        if value != None:
            public_kwargs[attr_name] = value
    return public_kwargs

def ios_application(name, tags = None, target_compatible_with = None, **kwargs):
    """ios_application with repository compatibility defaults."""
    if target_compatible_with == None:
        target_compatible_with = IOS_TARGET_COMPATIBLE_WITH
    _ios_application(
        name = name,
        tags = _with_manual_tag(tags),
        target_compatible_with = target_compatible_with,
        **kwargs
    )

def ios_unit_test(name, target_compatible_with = None, **kwargs):
    """ios_unit_test with repository macOS-host compatibility defaults."""
    if target_compatible_with == None:
        target_compatible_with = IOS_TEST_TARGET_COMPATIBLE_WITH
    _ios_unit_test(
        name = name,
        target_compatible_with = target_compatible_with,
        **kwargs
    )

def swift_library(name, deps = None, target_compatible_with = None, visibility = None, **kwargs):
    """swift_library with repository iOS-platform compatibility defaults."""
    if target_compatible_with == None:
        target_compatible_with = IOS_TARGET_COMPATIBLE_WITH

    public_kwargs = _public_common_kwargs(kwargs)
    public_kwargs["target_compatible_with"] = target_compatible_with
    if deps != None:
        kwargs["deps"] = deps
    kwargs["tags"] = _with_manual_tag(kwargs.get("tags"))

    impl = _impl_target_name(name)
    _swift_library(
        name = impl,
        target_compatible_with = target_compatible_with,
        visibility = ["//visibility:private"],
        **kwargs
    )
    kmp_variant_forward(
        name = name,
        actual = ":{}".format(impl),
        variant = "ios",
        visibility = visibility,
        **public_kwargs
    )
