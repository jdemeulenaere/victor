"""Repository proto macros."""

load("@aspect_rules_js//js:defs.bzl", "js_info_files", "js_library")
load("@com_google_protobuf//bazel:java_proto_library.bzl", "java_proto_library")
load("@com_google_protobuf//bazel:py_proto_library.bzl", "py_proto_library")
load("@grpc_kotlin//:kt_jvm_grpc.bzl", "kt_jvm_grpc_library")
load("@rules_proto//proto:defs.bzl", "proto_library")
load("//build/rules/npm:defs.bzl", "npm_node_modules")
load("//build/rules/python/grpc:defs.bzl", "py_grpc_library")

def grpc_proto(
        name,
        srcs,
        js_import_prefix = None,
        legacy_py_import_prefix = None,
        visibility = None):
    """Creates repo-standard gRPC/proto targets for JVM, Python, and web clients."""
    proto_name = "{}_proto".format(name)
    proto_library(
        name = proto_name,
        srcs = srcs,
        visibility = visibility,
    )

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

    py_proto = proto_name
    if legacy_py_import_prefix:
        py_proto = "{}_py_import_proto".format(name)
        proto_library(
            name = py_proto,
            srcs = srcs,
            import_prefix = legacy_py_import_prefix,
            strip_import_prefix = "/{}".format(native.package_name()),
        )

    py_proto_library(
        name = "{}_py_pb2".format(name),
        visibility = visibility,
        deps = [":{}".format(py_proto)],
    )

    py_grpc_library(
        name = "{}_py_pb2_grpc".format(name),
        srcs = [":{}".format(py_proto)],
        visibility = visibility,
        deps = [":{}_py_pb2".format(name)],
    )

    js_proto = proto_name
    if js_import_prefix:
        js_proto = "{}_js_import_proto".format(name)
        proto_library(
            name = js_proto,
            srcs = srcs,
            import_prefix = js_import_prefix,
            strip_import_prefix = "/{}".format(native.package_name()),
        )

    js_library(
        name = "{}_js_proto".format(name),
        visibility = visibility,
        deps = [":{}".format(js_proto)],
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
