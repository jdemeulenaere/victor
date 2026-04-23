"""High-level deploy macros for repo-supported dev environments."""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

_DEPLOY_CONFIG = "//tools/deploy:dev_environment.json"
_DEPLOY_RUNNER = "//tools/deploy:deploy_runner"
_DEPLOY_WRAPPER = "//tools/deploy:run_deploy.sh"
_ANDROID_DEPLOY_SERVICE_URL = "//tools/android:android_deploy_service_url"
_ANDROID_SERVICE_URL_PROFILE = "//tools/android:android_service_url_profile"

def _android_deploy_transition_impl(settings, attr):
    _ = settings
    return {
        _ANDROID_DEPLOY_SERVICE_URL: attr.service_url,
        _ANDROID_SERVICE_URL_PROFILE: "deploy",
    }

_android_deploy_transition = transition(
    implementation = _android_deploy_transition_impl,
    inputs = [],
    outputs = [
        _ANDROID_DEPLOY_SERVICE_URL,
        _ANDROID_SERVICE_URL_PROFILE,
    ],
)

def _append_target_suffix(label, suffix):
    if label.startswith("@"):
        fail("external deploy labels are not supported: {}".format(label))
    if label.startswith("//"):
        if ":" in label:
            package, name = label.split(":", 1)
            return "{}:{}{}".format(package, name, suffix)
        package = label[2:]
        name = package.rsplit("/", 1)[-1]
        return "//{}:{}{}".format(package, name, suffix)
    if label.startswith(":"):
        return "{}{}".format(label, suffix)
    return ":{}{}".format(label, suffix)

def _maybe_list(value):
    if value == None:
        return []
    return value

def _matching_paths(files, predicate):
    return [file.path for file in files if predicate(file)]

def _find_single_path(files, predicate, description):
    matches = _matching_paths(files, predicate)
    if len(matches) != 1:
        fail("expected exactly one {} output, found {}: {}".format(description, len(matches), matches))
    return matches[0]

def _workspace_runfiles_path(file):
    return "_main/{}".format(file.short_path)

def _deploy_manifest_common(ctx, deploy_kind, app_label, extra):
    out = ctx.actions.declare_file("{}.json".format(ctx.label.name))
    payload = {
        "deploy_kind": deploy_kind,
        "target_label": str(ctx.label),
        "app_label": str(app_label),
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
    if ctx.file.backend_manifest != None:
        backend_manifest_path = ctx.file.backend_manifest.path
        backend_manifest_runfiles_path = _workspace_runfiles_path(ctx.file.backend_manifest)
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
        "backend_manifest": attr.label(allow_single_file = True),
        "site": attr.string(mandatory = True),
    },
)

def _android_app_manifest_impl(ctx):
    app = ctx.attr.app[0]
    files = app[DefaultInfo].files.to_list()
    apk = [file for file in files if file.path.endswith(".apk") and not file.path.endswith("_unsigned.apk")]
    if len(apk) != 1:
        fail("expected exactly one signed APK output, found {}: {}".format(len(apk), [file.path for file in apk]))
    extra = {
        "apk_path": apk[0].path,
        "apk_runfiles_path": _workspace_runfiles_path(apk[0]),
        "firebase_app_id": ctx.attr.firebase_app_id,
        "tester_groups": _maybe_list(ctx.attr.tester_groups),
    }
    manifest_info = _deploy_manifest_common(ctx, "android_app", app.label, extra)
    return DefaultInfo(
        files = manifest_info.files,
        runfiles = ctx.runfiles(files = apk),
    )

_android_app_manifest = rule(
    implementation = _android_app_manifest_impl,
    attrs = {
        "app": attr.label(
            mandatory = True,
            cfg = _android_deploy_transition,
        ),
        "firebase_app_id": attr.string(mandatory = True),
        "service_url": attr.string(),
        "tester_groups": attr.string_list(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _deploy_target(name, manifest, data, deploy_kind, visibility):
    sh_binary(
        name = name,
        srcs = [_DEPLOY_WRAPPER],
        args = [
            "$(location {})".format(_DEPLOY_RUNNER),
            "--manifest",
            "$(location {})".format(manifest),
            "--config",
            "$(location {})".format(_DEPLOY_CONFIG),
        ],
        data = [
            _DEPLOY_CONFIG,
            _DEPLOY_RUNNER,
            manifest,
        ] + data,
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
        visibility = visibility,
    )

def deploy_web_app(name, app, site, backend = None, visibility = None):
    manifest_name = "{}__manifest".format(name)
    backend_manifest = None
    data = [app]
    if backend != None:
        backend_manifest = _append_target_suffix(backend, "__manifest")
        data.append(backend_manifest)
    _web_app_manifest(
        name = manifest_name,
        app = app,
        backend_manifest = backend_manifest,
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

def deploy_android_app(name, app, firebase_app_id, service_url = "", tester_groups = None, visibility = None):
    manifest_name = "{}__manifest".format(name)
    _android_app_manifest(
        name = manifest_name,
        app = app,
        firebase_app_id = firebase_app_id,
        service_url = service_url,
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
