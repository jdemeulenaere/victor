load("@grpc//bazel:python_rules.bzl", grpc_py_grpc_library = "py_grpc_library")
load("@pip//:requirements.bzl", "requirement")

def py_grpc_library(
        name,
        srcs,
        deps,
        strip_prefixes = [],
        grpc_library = None,
        grpc_plugin = Label("//tools/python/grpc:grpc_python_plugin"),
        **kwargs):
    """Generate python gRPC stubs with a pip grpc runtime and overridable plugin."""
    if grpc_library == None:
        grpc_library = requirement("grpcio")

    grpc_py_grpc_library(
        name = name,
        srcs = srcs,
        deps = deps,
        strip_prefixes = strip_prefixes,
        grpc_library = grpc_library,
        grpc_plugin = grpc_plugin,
        **kwargs
    )
