"""Repository iOS rule wrappers."""

load("@build_bazel_rules_apple//apple:ios.bzl", _ios_application = "ios_application", _ios_unit_test = "ios_unit_test")
load("@build_bazel_rules_swift//swift:swift_library.bzl", _swift_library = "swift_library")

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

def swift_library(name, target_compatible_with = None, **kwargs):
    """swift_library with repository iOS-platform compatibility defaults."""
    if target_compatible_with == None:
        target_compatible_with = IOS_TARGET_COMPATIBLE_WITH
    _swift_library(
        name = name,
        target_compatible_with = target_compatible_with,
        **kwargs
    )
