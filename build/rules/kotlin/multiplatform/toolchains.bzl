"""Toolchain providers for repository Kotlin Multiplatform rules."""

load("@rules_java//java/common/rules:java_runtime.bzl", "JavaRuntimeInfo")

KmpNativeToolchainInfo = provider(
    fields = {
        "compiler": "Kotlin/Native compiler embeddable jar.",
        "home_files": "Files in the Kotlin/Native distribution.",
        "java_runtime": "Java runtime used to execute the compiler.",
        "libffi_files": "Bazel-managed Kotlin/Native libffi dependency files.",
        "llvm_files": "Bazel-managed Kotlin/Native LLVM dependency files.",
    },
)

KmpWasmToolchainInfo = provider(
    fields = {
        "compiler_main": "Kotlin JS/Wasm compiler main class.",
        "kotlinc_script": "Repository wrapper script for Kotlin JS/Wasm actions.",
    },
)

def _kmp_native_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        kmp_native = KmpNativeToolchainInfo(
            compiler = ctx.file.compiler,
            home_files = ctx.attr.home[DefaultInfo].files,
            java_runtime = ctx.attr.java_runtime[JavaRuntimeInfo],
            libffi_files = ctx.attr.libffi[DefaultInfo].files,
            llvm_files = ctx.attr.llvm[DefaultInfo].files,
        ),
    )]

kmp_native_toolchain = rule(
    implementation = _kmp_native_toolchain_impl,
    attrs = {
        "compiler": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "home": attr.label(mandatory = True),
        "java_runtime": attr.label(
            cfg = "exec",
            mandatory = True,
            providers = [JavaRuntimeInfo],
        ),
        "libffi": attr.label(mandatory = True),
        "llvm": attr.label(mandatory = True),
    },
)

def _kmp_wasm_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        kmp_wasm = KmpWasmToolchainInfo(
            compiler_main = ctx.attr.compiler_main,
            kotlinc_script = ctx.file.kotlinc_script,
        ),
    )]

kmp_wasm_toolchain = rule(
    implementation = _kmp_wasm_toolchain_impl,
    attrs = {
        "compiler_main": attr.string(
            default = "org.jetbrains.kotlin.cli.js.K2JSCompiler",
        ),
        "kotlinc_script": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
