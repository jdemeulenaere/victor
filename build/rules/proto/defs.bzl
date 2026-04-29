"""Repository proto macros."""

load("@aspect_rules_js//js:defs.bzl", "js_info_files", "js_library")
load("@aspect_rules_js//js:providers.bzl", "JsInfo")
load("@build_bazel_rules_swift//proto:swift_proto_library.bzl", "swift_proto_library")
load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo", "SwiftProtoInfo")
load("@com_google_protobuf//bazel:java_proto_library.bzl", "java_proto_library")
load("@com_google_protobuf//bazel:py_proto_library.bzl", "py_proto_library")
load("@grpc_kotlin//:kt_jvm_grpc.bzl", "kt_jvm_grpc_library")
load("@rules_cc//cc:defs.bzl", "CcInfo")
load("@rules_java//java:defs.bzl", "JavaInfo")
load("@rules_kotlin//kotlin/internal:defs.bzl", "KtJvmInfo")
load("@rules_proto//proto:defs.bzl", "ProtoInfo", "proto_library")
load("@rules_python//python:defs.bzl", "PyInfo")
load("//build/rules/npm:defs.bzl", "npm_node_modules")
load("//build/rules/python/grpc:defs.bzl", "py_grpc_library")

_ALL_PLATFORMS = ["ios", "jvm", "python", "web"]
_PLATFORM_SET = {
    platform: True
    for platform in _ALL_PLATFORMS
}
_IOS_OR_MACOS_TARGET_COMPATIBLE_WITH = select({
    "@platforms//os:ios": [],
    "@platforms//os:macos": [],
    "//conditions:default": ["@platforms//:incompatible"],
})
_IOS_OR_MACOS_DEPS = {
    "@platforms//os:ios": True,
    "@platforms//os:macos": True,
    "//conditions:default": False,
}
_JVM_DEPS = {
    "@platforms//os:ios": False,
    "//conditions:default": True,
}
_HOST_TOOL_DEPS = {
    "@platforms//os:linux": True,
    "@platforms//os:macos": True,
    "@platforms//os:windows": True,
    "//conditions:default": False,
}

def _target(target):
    return ":{}".format(target)

def _platform_deps(targets, platform_deps):
    if type(targets) == "string":
        targets = [targets]
    return select({
        platform: targets if include else []
        for platform, include in platform_deps.items()
    })

def _capitalize_ascii(value):
    if not value:
        return ""
    return value[0].upper() + value[1:]

def _swift_module_name(name):
    return "{}IosSwiftClientProto".format("".join([_capitalize_ascii(part) for part in name.split("_")]))

def _normalize_platforms(platforms):
    if platforms == None:
        fail("grpc_proto platforms is required; expected one or more of: {}".format(", ".join(_ALL_PLATFORMS)))

    if not type(platforms) == "list":
        fail("grpc_proto platforms must be a list of strings")

    if not platforms:
        fail("grpc_proto platforms must not be empty; expected one or more of: {}".format(", ".join(_ALL_PLATFORMS)))

    normalized = []
    seen = {}
    for platform in platforms:
        if not type(platform) == "string":
            fail("grpc_proto platforms values must be strings, got {}".format(type(platform)))
        if not _PLATFORM_SET.get(platform, False):
            fail("Unsupported grpc_proto platform '{}'. Expected one of: {}".format(platform, ", ".join(_ALL_PLATFORMS)))
        if seen.get(platform, False):
            fail("Duplicate grpc_proto platform '{}'".format(platform))
        seen[platform] = True
        normalized.append(platform)

    return normalized

def _provider_or_none(targets, provider):
    for target in targets:
        if provider in target:
            return target[provider]
    return None

def _append_provider(providers, targets, provider):
    value = _provider_or_none(targets, provider)
    if value != None:
        providers.append(value)

def _merge_default_runfiles(ctx, targets):
    runfiles = ctx.runfiles()
    for target in targets:
        default_info = target[DefaultInfo]
        runfiles = runfiles.merge(default_info.default_runfiles)
        runfiles = runfiles.merge(default_info.data_runfiles)
    return runfiles

def _output_group(targets, name):
    transitive = []
    for target in targets:
        if OutputGroupInfo in target:
            output_group_info = target[OutputGroupInfo]
            if hasattr(output_group_info, name):
                transitive.append(getattr(output_group_info, name))
    return depset(transitive = transitive)

def _grpc_proto_library_impl(ctx):
    implementation_deps = ctx.attr.proto + ctx.attr.deps + ctx.attr.ios + ctx.attr.python + ctx.attr.web_files
    providers = [
        DefaultInfo(
            files = depset(transitive = [dep[DefaultInfo].files for dep in implementation_deps]),
            runfiles = _merge_default_runfiles(ctx, implementation_deps),
        ),
        OutputGroupInfo(
            _hidden_top_level_INTERNAL_ = _output_group(implementation_deps, "_hidden_top_level_INTERNAL_"),
            _validation = _output_group(implementation_deps, "_validation"),
        ),
    ]

    _append_provider(providers, ctx.attr.proto, ProtoInfo)
    _append_provider(providers, ctx.attr.deps, JavaInfo)
    _append_provider(providers, ctx.attr.deps, KtJvmInfo)
    _append_provider(providers, ctx.attr.ios, SwiftInfo)
    _append_provider(providers, ctx.attr.ios, SwiftProtoInfo)
    _append_provider(providers, ctx.attr.ios, CcInfo)
    _append_provider(providers, ctx.attr.python, PyInfo)
    _append_provider(providers, ctx.attr.web, JsInfo)

    return providers

_grpc_proto_library = rule(
    implementation = _grpc_proto_library_impl,
    attrs = {
        "deps": attr.label_list(providers = [JavaInfo, KtJvmInfo]),
        "ios": attr.label_list(providers = [SwiftInfo, CcInfo]),
        "proto": attr.label_list(providers = [ProtoInfo]),
        "python": attr.label_list(providers = [PyInfo]),
        "web": attr.label_list(providers = [JsInfo]),
        "web_files": attr.label_list(),
    },
)

def grpc_proto(
        name,
        srcs,
        platforms,
        visibility = None):
    """Creates repo-standard gRPC/proto targets for selected platforms.

    Args:
      platforms: required list containing any of `ios`, `jvm`, `python`, and `web`.
    """
    selected_platforms = _normalize_platforms(platforms)
    proto_name = "{}_proto".format(name)
    proto_library(
        name = proto_name,
        srcs = srcs,
    )

    direct_deps = {
        "deps": [],
        "ios": [],
        "python": [],
        "web": [],
        "web_files": [],
    }

    if "jvm" in selected_platforms:
        java_proto_name = "{}_java_proto".format(name)
        kt_grpc_name = "{}_kt_grpc".format(name)
        java_proto_library(
            name = java_proto_name,
            deps = [_target(proto_name)],
        )

        kt_jvm_grpc_library(
            name = kt_grpc_name,
            srcs = [_target(proto_name)],
            deps = [_target(java_proto_name)],
        )
        direct_deps["deps"] = _platform_deps(_target(kt_grpc_name), _JVM_DEPS)

    if "ios" in selected_platforms:
        ios_swift_name = "{}_ios_swift_client_proto".format(name)
        swift_proto_library(
            name = ios_swift_name,
            compilers = [
                "@build_bazel_rules_swift//proto/compilers:swift_client_proto",
                "@build_bazel_rules_swift//proto/compilers:swift_proto",
            ],
            module_name = _swift_module_name(name),
            protos = [_target(proto_name)],
            target_compatible_with = _IOS_OR_MACOS_TARGET_COMPATIBLE_WITH,
        )
        direct_deps["ios"] = _platform_deps(_target(ios_swift_name), _IOS_OR_MACOS_DEPS)

    if "python" in selected_platforms:
        py_pb2_name = "{}_py_pb2".format(name)
        py_pb2_grpc_name = "{}_py_pb2_grpc".format(name)
        py_proto_library(
            name = py_pb2_name,
            deps = [_target(proto_name)],
        )

        py_grpc_library(
            name = py_pb2_grpc_name,
            srcs = [_target(proto_name)],
            deps = [_target(py_pb2_name)],
        )
        direct_deps["python"] = _platform_deps(
            [
                _target(py_pb2_grpc_name),
                _target(py_pb2_name),
            ],
            _HOST_TOOL_DEPS,
        )

    if "web" in selected_platforms:
        js_proto_name = "{}_js_proto".format(name)
        js_proto_files_raw_name = "{}_js_proto_files_raw".format(name)
        js_node_modules_name = "{}_js_node_modules".format(name)
        js_proto_files_name = "{}_js_proto_files".format(name)
        js_library(
            name = js_proto_name,
            deps = [_target(proto_name)],
        )

        js_info_files(
            name = js_proto_files_raw_name,
            srcs = [_target(js_proto_name)],
            include_transitive_types = True,
            include_types = True,
        )

        npm_node_modules(
            name = js_node_modules_name,
            out = "node_modules",
        )

        native.filegroup(
            name = js_proto_files_name,
            srcs = [
                _target(js_node_modules_name),
                _target(js_proto_files_raw_name),
            ],
        )
        direct_deps["web"] = _platform_deps(_target(js_proto_name), _HOST_TOOL_DEPS)
        direct_deps["web_files"] = _platform_deps(_target(js_proto_files_name), _HOST_TOOL_DEPS)

    _grpc_proto_library(
        name = name,
        proto = [_target(proto_name)],
        visibility = visibility,
        **direct_deps
    )
