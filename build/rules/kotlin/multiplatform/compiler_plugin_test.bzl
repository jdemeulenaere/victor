"""Analysis tests for repository Kotlin compiler plugin wrappers."""

load("//build/rules/kotlin/multiplatform:compiler_plugin.bzl", "KtNativeCompilerPluginInfo")

def _kt_native_compiler_plugin_test_impl(ctx):
    classpath = ctx.attr.plugin[KtNativeCompilerPluginInfo].classpath.to_list()
    if not classpath:
        fail("{} has an empty Kotlin/Native compiler plugin classpath".format(ctx.attr.plugin.label))

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = executable,
        content = "#!/usr/bin/env bash\nset -euo pipefail\n",
        is_executable = True,
    )
    return [DefaultInfo(executable = executable)]

kt_native_compiler_plugin_test = rule(
    implementation = _kt_native_compiler_plugin_test_impl,
    attrs = {
        "plugin": attr.label(
            mandatory = True,
            providers = [KtNativeCompilerPluginInfo],
        ),
    },
    test = True,
)
