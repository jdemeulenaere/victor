"""Kotlin compiler plugin wrappers for repository KMP rules."""

load("@rules_java//java:defs.bzl", "JavaInfo")
load("@rules_java//java/common:java_common.bzl", "java_common")
load("@rules_kotlin//kotlin:core.bzl", _kt_compiler_plugin = "kt_compiler_plugin")
load("@rules_kotlin//kotlin/internal:defs.bzl", "KtCompilerPluginInfo")

KtNativeCompilerPluginInfo = provider(
    fields = {
        "classpath": "Kotlin/Native-compatible compiler plugin classpath.",
    },
)

def _kt_compiler_plugin_adapter_impl(ctx):
    providers = [
        ctx.attr.plugin[DefaultInfo],
        ctx.attr.plugin[KtCompilerPluginInfo],
    ]
    if ctx.attr.native_deps:
        native_info = java_common.merge([dep[JavaInfo] for dep in ctx.attr.native_deps])
        providers.append(KtNativeCompilerPluginInfo(
            classpath = depset(native_info.runtime_output_jars, transitive = [native_info.transitive_runtime_jars]),
        ))
    return providers

_kt_compiler_plugin_adapter = rule(
    implementation = _kt_compiler_plugin_adapter_impl,
    attrs = {
        "native_deps": attr.label_list(
            providers = [JavaInfo],
            cfg = "exec",
        ),
        "plugin": attr.label(
            mandatory = True,
            providers = [KtCompilerPluginInfo],
            cfg = "exec",
        ),
    },
)

def kt_compiler_plugin(name, native_deps = None, visibility = None, **kwargs):
    """kt_compiler_plugin with an optional Kotlin/Native-specific classpath."""
    plugin_name = "{}__plugin".format(name)
    _kt_compiler_plugin(
        name = plugin_name,
        visibility = ["//visibility:private"],
        **kwargs
    )
    _kt_compiler_plugin_adapter(
        name = name,
        native_deps = native_deps or [],
        plugin = ":{}".format(plugin_name),
        visibility = visibility,
    )
