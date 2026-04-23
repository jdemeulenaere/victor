load("@rules_cc//cc:defs.bzl", "CcToolchainConfigInfo")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

def _fake_cc_toolchain_config_impl(ctx):
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "android-arm64-v8a-packaging-only",
        host_system_name = "local",
        target_system_name = "android",
        target_cpu = "arm64-v8a",
        target_libc = "unknown",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
    )

fake_cc_toolchain_config = rule(
    implementation = _fake_cc_toolchain_config_impl,
    provides = [CcToolchainConfigInfo],
)
