"""High-level macro for minimal Bazel web apps."""

load("@npm//:typescript/package_json.bzl", typescript_bin = "bin")
load("@npm//:vite/package_json.bzl", vite_bin = "bin")
load("//build/rules/npm:defs.bzl", "npm_node_modules")

_TSC_COMMON_ARGS = [
    "--noEmit",
    "--target",
    "ES2020",
    "--module",
    "ESNext",
    "--moduleResolution",
    "bundler",
    "--lib",
    "ES2020,DOM,DOM.Iterable",
    "--strict",
    "--skipLibCheck",
    "--noUnusedLocals",
    "--noUnusedParameters",
    "--noFallthroughCasesInSwitch",
    "--jsx",
    "react-jsx",
]

def _vite_config_path(vite_config):
    if vite_config.startswith("//"):
        fail("web_app vite_config must be a file in the same package")
    if vite_config.startswith(":"):
        return vite_config[1:]
    return vite_config

def web_app(
        name,
        srcs,
        vite_config = "vite.config.mjs",
        deps = None,
        visibility = None):
    """Creates dev/build/typecheck targets for a minimal Vite web app.

    Generates:
    - :dev (vite dev server)
    - :<name> (vite production build)
    - :typecheck (tsc with no emit)

    Args:
    - vite_config: Vite config file in this package (e.g. "vite.config.mjs" or ":vite.config.mjs")
    """
    if deps == None:
        deps = []
    if not srcs:
        fail("web_app requires srcs to be set explicitly")
    if name in ["dev", "typecheck"]:
        fail("web_app target name '{}' conflicts with generated targets".format(name))
    if not vite_config:
        fail("web_app requires vite_config to be a non-empty file path")

    ts_srcs = [src for src in srcs if src.endswith(".ts") or src.endswith(".tsx")]
    if not ts_srcs:
        fail("web_app requires at least one .ts or .tsx source in srcs")

    npm_node_modules(name = "node_modules")

    vite_config_path = _vite_config_path(vite_config)
    common_inputs = [":node_modules", vite_config] + deps + srcs

    vite_bin.vite_binary(
        name = "dev",
        args = [
            "dev",
            "--host",
            "--config",
            vite_config_path,
        ],
        data = common_inputs,
        chdir = native.package_name(),
        visibility = visibility,
    )

    vite_bin.vite(
        name = name,
        args = [
            "build",
            "--config",
            vite_config_path,
        ],
        srcs = common_inputs,
        out_dirs = ["dist"],
        chdir = native.package_name(),
        visibility = visibility,
    )

    typescript_bin.tsc_test(
        name = "typecheck",
        args = _TSC_COMMON_ARGS + ts_srcs,
        data = common_inputs,
        chdir = native.package_name(),
        visibility = visibility,
    )
