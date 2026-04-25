"""Npm helper rules."""

def _node_modules_root(files):
    for file in files:
        marker = "/node_modules/"
        index = file.path.find(marker)
        if index >= 0:
            return file.path[:index + len("/node_modules")]
    fail("could not resolve node_modules root from inputs")

def _npm_node_modules_impl(ctx):
    files = ctx.attr.node_modules[DefaultInfo].files.to_list()
    out = ctx.actions.declare_directory(ctx.attr.out or ctx.attr.name)
    ctx.actions.run_shell(
        inputs = depset(files),
        outputs = [out],
        command = "mkdir -p \"$1\" && cp -RP \"$2\"/. \"$1\"/",
        arguments = [
            out.path,
            _node_modules_root(files),
        ],
        mnemonic = "NpmNodeModules",
        progress_message = "Preparing npm node_modules %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

npm_node_modules = rule(
    implementation = _npm_node_modules_impl,
    attrs = {
        "node_modules": attr.label(default = "//third_party/npm:node_modules"),
        "out": attr.string(),
    },
)
