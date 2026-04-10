"""High-level macro for minimal Bazel web apps."""

load("@npm//:typescript/package_json.bzl", typescript_bin = "bin")
load("@npm//:vite/package_json.bzl", vite_bin = "bin")

_VITE_CONFIG_CMD = """cat > $@ <<'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/grpc': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\\/grpc/, ''),
      },
    },
  },
});
EOF
"""

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

def web_app(
        name,
        srcs,
        deps = None,
        visibility = None):
    """Creates dev/build/typecheck targets for a minimal Vite web app.

    Generates:
    - :dev (vite dev server)
    - :<name> (vite production build)
    - :typecheck (tsc with no emit)
    """
    if deps == None:
        deps = []
    if not srcs:
        fail("web_app requires srcs to be set explicitly")
    if name in ["dev", "typecheck"]:
        fail("web_app target name '{}' conflicts with generated targets".format(name))

    ts_srcs = [src for src in srcs if src.endswith(".ts") or src.endswith(".tsx")]
    if not ts_srcs:
        fail("web_app requires at least one .ts or .tsx source in srcs")

    vite_config_file = "{}.vite.config.mjs".format(name)
    native.genrule(
        name = "{}_vite_config".format(name),
        outs = [vite_config_file],
        cmd = _VITE_CONFIG_CMD,
    )

    vite_config_label = ":{}".format(vite_config_file)
    common_inputs = ["//:node_modules", vite_config_label] + deps + srcs

    vite_bin.vite_binary(
        name = "dev",
        args = [
            "dev",
            "--host",
            "--config",
            vite_config_file,
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
            vite_config_file,
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
