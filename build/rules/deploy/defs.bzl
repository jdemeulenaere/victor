"""High-level deploy macros for repo-supported dev environments."""

load(
    "//build/rules/backend:providers.bzl",
    "BackendDeployInfo",
    "BackendEndpointConfigInfo",
    "BackendEndpointConfigSetInfo",
)

_DEPLOY_CONFIG = "//build/deploy:dev_environment.json"
_DEPLOY_RUNNER = "//build/deploy:deploy_runner"

DeployTargetInfo = provider(
    fields = {
        "manifest": "Deploy manifest file for this deploy target.",
    },
)

def _maybe_list(value):
    if value == None:
        return []
    return value

def _workspace_runfiles_path(file):
    return "_main/{}".format(file.short_path)

def _repo_label(label):
    if label.package:
        return "//{}:{}".format(label.package, label.name)
    return "//:{}".format(label.name)

def _deploy_manifest_common(ctx, deploy_kind, app_label, extra):
    out = ctx.actions.declare_file("{}.json".format(ctx.label.name))
    payload = {
        "deploy_kind": deploy_kind,
        "target_label": _repo_label(ctx.label),
        "app_label": _repo_label(app_label),
    }
    payload.update(extra)
    ctx.actions.write(out, json.encode(payload) + "\n")
    return DefaultInfo(files = depset([out]))

def _grpc_server_manifest_impl(ctx):
    executable = ctx.executable.app
    extra = {
        "service": ctx.attr.service,
        "app_executable_path": executable.path,
        "app_executable_runfiles_path": _workspace_runfiles_path(executable),
        "app_runfiles_path": executable.path + ".runfiles",
        "app_repo_mapping_path": executable.path + ".repo_mapping",
        "app_runfiles_manifest_path": executable.path + ".runfiles_manifest",
    }
    return _deploy_manifest_common(ctx, "grpc_server", ctx.attr.app.label, extra)

_grpc_server_manifest = rule(
    implementation = _grpc_server_manifest_impl,
    attrs = {
        "app": attr.label(executable = True, cfg = "target"),
        "service": attr.string(mandatory = True),
    },
)

def _web_app_manifest_impl(ctx):
    files = ctx.attr.app[DefaultInfo].files.to_list()
    dist_dir = [file for file in files if file.is_directory]
    if len(dist_dir) != 1:
        fail("expected exactly one web dist directory output, found {}: {}".format(len(dist_dir), [file.path for file in dist_dir]))
    backend_manifest_path = None
    backend_manifest_runfiles_path = None
    if ctx.attr.backend != None:
        backend_manifest = ctx.attr.backend[DeployTargetInfo].manifest
        backend_manifest_path = backend_manifest.path
        backend_manifest_runfiles_path = _workspace_runfiles_path(backend_manifest)
    extra = {
        "site": ctx.attr.site,
        "app_dist_path": dist_dir[0].path,
        "app_dist_runfiles_path": _workspace_runfiles_path(dist_dir[0]),
        "backend_manifest_path": backend_manifest_path,
        "backend_manifest_runfiles_path": backend_manifest_runfiles_path,
    }
    return _deploy_manifest_common(ctx, "web_app", ctx.attr.app.label, extra)

_web_app_manifest = rule(
    implementation = _web_app_manifest_impl,
    attrs = {
        "app": attr.label(mandatory = True),
        "backend": attr.label(providers = [DeployTargetInfo]),
        "site": attr.string(mandatory = True),
    },
)

# Kotlin and Android rules do not forward custom providers from their deps.
# A Bazel aspect is the analysis-phase mechanism for collecting this metadata
# from the app dependency graph without making deploy_android_app list it again.
def _backend_endpoint_config_aspect_impl(target, ctx):
    direct_entries = []
    if BackendEndpointConfigInfo in target:
        endpoint_config = target[BackendEndpointConfigInfo]
        direct_entries.append(json.encode({
            "deploy_service_url_flag": endpoint_config.deploy_service_url_flag,
            "service": endpoint_config.service,
        }))

    transitive_entries = []
    for attr_name in ["deps", "runtime_deps", "exports"]:
        if not hasattr(ctx.rule.attr, attr_name):
            continue
        attr_value = getattr(ctx.rule.attr, attr_name)
        if attr_value == None:
            continue
        if type(attr_value) != "list":
            attr_value = [attr_value]
        for dep in attr_value:
            if BackendEndpointConfigSetInfo in dep:
                transitive_entries.append(dep[BackendEndpointConfigSetInfo].entries)

    return [
        BackendEndpointConfigSetInfo(
            entries = depset(direct_entries, transitive = transitive_entries),
        ),
    ]

_backend_endpoint_config_aspect = aspect(
    implementation = _backend_endpoint_config_aspect_impl,
    attr_aspects = ["deps", "runtime_deps", "exports"],
    provides = [BackendEndpointConfigSetInfo],
)

def _android_app_manifest_impl(ctx):
    endpoint_configs = []
    if BackendEndpointConfigSetInfo in ctx.attr.app:
        for entry in sorted(ctx.attr.app[BackendEndpointConfigSetInfo].entries.to_list()):
            endpoint_configs.append(json.decode(entry))

    extra = {
        "backend_endpoint_configs": endpoint_configs,
        "firebase_app_id": ctx.attr.firebase_app_id,
        "tester_groups": _maybe_list(ctx.attr.tester_groups),
    }
    return _deploy_manifest_common(ctx, "android_app", ctx.attr.app.label, extra)

_android_app_manifest = rule(
    implementation = _android_app_manifest_impl,
    attrs = {
        "app": attr.label(
            aspects = [_backend_endpoint_config_aspect],
            mandatory = True,
        ),
        "firebase_app_id": attr.string(mandatory = True),
        "tester_groups": attr.string_list(),
    },
)

def _deploy_script(runner, manifest, config):
    return "\n".join([
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        'runfiles_dir="${RUNFILES_DIR:-}"',
        'if [[ -z "$runfiles_dir" ]]; then',
        '  runfiles_dir="$0.runfiles"',
        "fi",
        'main_runfiles="$runfiles_dir/_main"',
        "exec \"$main_runfiles/{}\" --manifest \"$main_runfiles/{}\" --config \"$main_runfiles/{}\" \"$@\"".format(
            runner.short_path,
            manifest.short_path,
            config.short_path,
        ),
        "",
    ])

# Keep deploy targets as first-class Bazel targets: runnable via bazel run, and
# provider-bearing so other rules can depend on :deploy without label conventions.
def _deploy_binary_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        executable,
        _deploy_script(ctx.executable.runner, ctx.file.manifest, ctx.file.config),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [
        ctx.executable.runner,
        ctx.file.config,
        ctx.file.manifest,
    ])
    for target in [ctx.attr.runner] + ctx.attr.data:
        default = target[DefaultInfo]
        runfiles = runfiles.merge(ctx.runfiles(transitive_files = default.files))
        runfiles = runfiles.merge(default.default_runfiles)
        runfiles = runfiles.merge(default.data_runfiles)

    providers = [
        DefaultInfo(
            executable = executable,
            runfiles = runfiles,
        ),
        DeployTargetInfo(manifest = ctx.file.manifest),
    ]
    if ctx.attr.backend_service:
        providers.append(BackendDeployInfo(service = ctx.attr.backend_service))
    return providers

_deploy_binary = rule(
    implementation = _deploy_binary_impl,
    attrs = {
        "backend_service": attr.string(),
        "config": attr.label(
            allow_single_file = True,
            default = Label(_DEPLOY_CONFIG),
        ),
        "data": attr.label_list(allow_files = True),
        "manifest": attr.label(allow_single_file = True, mandatory = True),
        "runner": attr.label(
            cfg = "exec",
            default = Label(_DEPLOY_RUNNER),
            executable = True,
        ),
    },
    executable = True,
)

def _deploy_target(name, manifest, data, deploy_kind, visibility, backend_service = ""):
    _deploy_binary(
        name = name,
        backend_service = backend_service,
        data = data,
        manifest = manifest,
        tags = [
            "deploy_on_main",
            "deploy_kind={}".format(deploy_kind),
        ],
        visibility = visibility,
    )

def deploy_grpc_server(name, app, service, visibility = None):
    manifest_name = "{}__manifest".format(name)
    _grpc_server_manifest(
        name = manifest_name,
        app = app,
        service = service,
        visibility = visibility,
    )
    _deploy_target(
        name = name,
        manifest = ":{}".format(manifest_name),
        data = [app],
        deploy_kind = "grpc_server",
        backend_service = service,
        visibility = visibility,
    )

def deploy_web_app(name, app, site, backend = None, visibility = None):
    manifest_name = "{}__manifest".format(name)
    data = [app]
    if backend != None:
        data.append(backend)
    _web_app_manifest(
        name = manifest_name,
        app = app,
        backend = backend,
        site = site,
        visibility = visibility,
    )
    _deploy_target(
        name = name,
        manifest = ":{}".format(manifest_name),
        data = data,
        deploy_kind = "web_app",
        visibility = visibility,
    )

def deploy_android_app(name, app, firebase_app_id, tester_groups = None, visibility = None):
    manifest_name = "{}__manifest".format(name)
    _android_app_manifest(
        name = manifest_name,
        app = app,
        firebase_app_id = firebase_app_id,
        tester_groups = _maybe_list(tester_groups),
        visibility = visibility,
    )
    _deploy_target(
        name = name,
        manifest = ":{}".format(manifest_name),
        data = [],
        deploy_kind = "android_app",
        visibility = visibility,
    )
