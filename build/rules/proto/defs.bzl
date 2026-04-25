"""Repository proto macros."""

load("@aspect_rules_js//js:defs.bzl", "js_info_files", "js_library")
load("@com_google_protobuf//bazel:java_proto_library.bzl", "java_proto_library")
load("@com_google_protobuf//bazel:py_proto_library.bzl", "py_proto_library")
load("@grpc_kotlin//:kt_jvm_grpc.bzl", "kt_jvm_grpc_library")
load("@rules_proto//proto:defs.bzl", "proto_library")
load("//build/rules/npm:defs.bzl", "npm_node_modules")
load("//build/rules/python/grpc:defs.bzl", "py_grpc_library")

_ALL_PLATFORMS = ["jvm", "python", "web"]
_PLATFORM_SET = {
    platform: True
    for platform in _ALL_PLATFORMS
}

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

def grpc_proto(
        name,
        srcs,
        platforms,
        visibility = None):
    """Creates repo-standard gRPC/proto targets for selected platforms.

    Args:
      platforms: required list containing any of `jvm`, `python`, and `web`.
    """
    selected_platforms = _normalize_platforms(platforms)
    proto_name = "{}_proto".format(name)
    proto_library(
        name = proto_name,
        srcs = srcs,
        visibility = visibility,
    )

    if "jvm" in selected_platforms:
        java_proto_library(
            name = "{}_java_proto".format(name),
            visibility = visibility,
            deps = [":{}".format(proto_name)],
        )

        kt_jvm_grpc_library(
            name = "{}_kt_grpc".format(name),
            srcs = [":{}".format(proto_name)],
            visibility = visibility,
            deps = [":{}_java_proto".format(name)],
        )

    if "python" in selected_platforms:
        py_proto_library(
            name = "{}_py_pb2".format(name),
            visibility = visibility,
            deps = [":{}".format(proto_name)],
        )

        py_grpc_library(
            name = "{}_py_pb2_grpc".format(name),
            srcs = [":{}".format(proto_name)],
            visibility = visibility,
            deps = [":{}_py_pb2".format(name)],
        )

    if "web" in selected_platforms:
        js_library(
            name = "{}_js_proto".format(name),
            visibility = visibility,
            deps = [":{}".format(proto_name)],
        )

        js_info_files(
            name = "{}_js_proto_files_raw".format(name),
            srcs = [":{}_js_proto".format(name)],
            include_transitive_types = True,
            include_types = True,
        )

        npm_node_modules(
            name = "{}_js_node_modules".format(name),
            out = "node_modules",
        )

        native.filegroup(
            name = "{}_js_proto_files".format(name),
            srcs = [
                ":{}_js_node_modules".format(name),
                ":{}_js_proto_files_raw".format(name),
            ],
            visibility = visibility,
        )
