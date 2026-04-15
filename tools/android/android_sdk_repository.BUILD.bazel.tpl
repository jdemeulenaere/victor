load("@rules_android//rules/android_sdk_repository:helper.bzl", "create_android_sdk_rules")

package(default_visibility = ["//visibility:public"])

toolchain_type(name = "sdk_toolchain_type")

config_setting(
    name = "sdk_present",
)

# Compatibility target consumed by Android rules to detect that the SDK repo is
# populated. It only needs to resolve truthily, not carry any configuration.
alias(
    name = "has_androidsdk",
    actual = ":sdk_present",
)

create_android_sdk_rules(
    name = "__repository_name__",
    build_tools_version = "__build_tools_version__",
    build_tools_directory = "__build_tools_directory__",
    api_levels = [__api_levels__],
    default_api_level = __default_api_level__,
)

alias(
    name = "adb",
    actual = "platform-tools/adb",
)

alias(
    name = "dexdump",
    actual = "build-tools/%s/dexdump" % "__build_tools_directory__",
)

filegroup(
    name = "sdk_path",
    srcs = ["."],
)

exports_files(
    glob(["system-images/**"], allow_empty = True),
)
