"""App-facing Bazel API for this repository."""

load("//build/rules/deploy:defs.bzl", _deploy_android_app = "deploy_android_app", _deploy_grpc_server = "deploy_grpc_server", _deploy_web_app = "deploy_web_app")
load("//build/rules/kotlin/multiplatform:defs.bzl", _kt_multiplatform_library = "kt_multiplatform_library")
load("//build/rules/proto:defs.bzl", _grpc_proto = "grpc_proto")
load("//build/rules/python/grpc:defs.bzl", _py_grpc_library = "py_grpc_library")
load("//build/rules/web:defs.bzl", _web_app = "web_app")
load("//build/tools/android:defs.bzl", _android_binary = "android_binary", _android_local_test = "android_local_test", _android_service_url_config = "android_service_url_config")

android_binary = _android_binary
android_local_test = _android_local_test
android_service_url_config = _android_service_url_config
deploy_android_app = _deploy_android_app
deploy_grpc_server = _deploy_grpc_server
deploy_web_app = _deploy_web_app
grpc_proto = _grpc_proto
kt_multiplatform_library = _kt_multiplatform_library
py_grpc_library = _py_grpc_library
web_app = _web_app
