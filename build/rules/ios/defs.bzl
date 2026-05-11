"""Repository iOS rule wrappers."""

load("@build_bazel_rules_apple//apple:ios.bzl", _ios_application = "ios_application", _ios_unit_test = "ios_unit_test")
load("@build_bazel_rules_swift//swift:swift_library.bzl", _swift_library = "swift_library")
load("@platforms//host:constraints.bzl", "HOST_CONSTRAINTS")
load("//build/rules/kotlin/multiplatform:defs.bzl", "kmp_platform_forward")

_HOST_IS_MACOS = "@platforms//os:macos" in HOST_CONSTRAINTS or "@platforms//os:osx" in HOST_CONSTRAINTS
_HOST_INCOMPATIBLE = ["@platforms//:incompatible"]

IOS_TARGET_COMPATIBLE_WITH = select({
    "@platforms//os:ios": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

IOS_TEST_TARGET_COMPATIBLE_WITH = select({
    "@platforms//os:macos": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

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

def _target_compatible_with_or_default(target_compatible_with, default):
    if not _HOST_IS_MACOS:
        return _HOST_INCOMPATIBLE
    if target_compatible_with == None:
        return default
    return target_compatible_with

def _transitioned_label_list(owner_name, labels, platform, attr_name, testonly = None):
    if labels == None:
        return None
    if type(labels) != "list":
        return labels

    transitioned = []
    for index, label in enumerate(labels):
        dep_name = "{}__{}_{}_forward".format(owner_name, attr_name, index)
        transition_kwargs = {}
        if testonly != None:
            transition_kwargs["testonly"] = testonly
        kmp_platform_forward(
            name = dep_name,
            actual = label,
            platform = platform,
            visibility = ["//visibility:private"],
            **transition_kwargs
        )
        transitioned.append(":{}".format(dep_name))
    return transitioned

def ios_application(name, tags = None, target_compatible_with = None, **kwargs):
    """ios_application with repository compatibility defaults."""
    target_compatible_with = _target_compatible_with_or_default(target_compatible_with, IOS_TARGET_COMPATIBLE_WITH)
    if tags != None:
        kwargs["tags"] = tags
    _ios_application(
        name = name,
        target_compatible_with = target_compatible_with,
        **kwargs
    )

def ios_unit_test(name, target_compatible_with = None, **kwargs):
    """ios_unit_test with repository macOS-host compatibility defaults."""
    target_compatible_with = _target_compatible_with_or_default(target_compatible_with, IOS_TEST_TARGET_COMPATIBLE_WITH)
    _ios_unit_test(
        name = name,
        target_compatible_with = target_compatible_with,
        **kwargs
    )

def swift_library(name, deps = None, target_compatible_with = None, visibility = None, **kwargs):
    """swift_library with repository iOS-platform compatibility defaults."""
    target_compatible_with = _target_compatible_with_or_default(target_compatible_with, IOS_TARGET_COMPATIBLE_WITH)

    public_kwargs = _public_common_kwargs(kwargs)
    public_kwargs["target_compatible_with"] = target_compatible_with
    if deps != None and _HOST_IS_MACOS:
        kwargs["deps"] = _transitioned_label_list(name, deps, "iosSimulatorArm64", "deps", kwargs.get("testonly"))
    elif deps != None:
        kwargs["deps"] = deps

    impl = _impl_target_name(name)
    _swift_library(
        name = impl,
        target_compatible_with = target_compatible_with,
        visibility = ["//visibility:private"],
        **kwargs
    )
    kmp_platform_forward(
        name = name,
        actual = ":{}".format(impl),
        platform = "iosSimulatorArm64",
        visibility = visibility,
        **public_kwargs
    )
