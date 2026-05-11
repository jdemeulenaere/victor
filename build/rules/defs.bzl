"""App-facing Bazel API for this repository."""

load("//build/rules/backend:defs.bzl", _backend_endpoint_config = "backend_endpoint_config")
load("//build/rules/deploy:defs.bzl", _deploy_android_app = "deploy_android_app", _deploy_grpc_server = "deploy_grpc_server", _deploy_web_app = "deploy_web_app")
load("//build/rules/ios:defs.bzl", _ios_application = "ios_application", _ios_unit_test = "ios_unit_test", _swift_library = "swift_library")
load(
    "//build/rules/kotlin/multiplatform:defs.bzl",
    _kmp_android = "kmp_android",
    _kmp_apple_framework = "kmp_apple_framework",
    _kmp_js_browser = "kmp_js_browser",
    _kmp_js_node = "kmp_js_node",
    _kmp_jvm = "kmp_jvm",
    _kmp_source_set = "kmp_source_set",
    _kmp_source_sets = "kmp_source_sets",
    _kmp_targets = "kmp_targets",
    _kmp_wasm_js = "kmp_wasm_js",
    _kt_android_library = "kt_android_library",
    _kt_jvm_binary = "kt_jvm_binary",
    _kt_jvm_library = "kt_jvm_library",
    _kt_jvm_test = "kt_jvm_test",
    _kt_multiplatform_library = "kt_multiplatform_library",
)
load("//build/rules/proto:defs.bzl", _grpc_proto = "grpc_proto")
load("//build/rules/python/grpc:defs.bzl", _py_grpc_library = "py_grpc_library")
load("//build/rules/web:defs.bzl", _web_app = "web_app")
load("//build/tools/android:defs.bzl", _android_binary = "android_binary", _android_local_test = "android_local_test")

android_binary = _android_binary
android_local_test = _android_local_test
backend_endpoint_config = _backend_endpoint_config
deploy_android_app = _deploy_android_app
deploy_grpc_server = _deploy_grpc_server
deploy_web_app = _deploy_web_app
grpc_proto = _grpc_proto
ios_application = _ios_application
ios_unit_test = _ios_unit_test
kmp_android = _kmp_android
kmp_apple_framework = _kmp_apple_framework
kmp_js_browser = _kmp_js_browser
kmp_js_node = _kmp_js_node
kmp_jvm = _kmp_jvm
kmp_source_set = _kmp_source_set
kmp_source_sets = _kmp_source_sets
kmp_targets = _kmp_targets
kmp_wasm_js = _kmp_wasm_js
kt_android_library = _kt_android_library
kt_jvm_binary = _kt_jvm_binary
kt_jvm_library = _kt_jvm_library
kt_jvm_test = _kt_jvm_test
kt_multiplatform_library = _kt_multiplatform_library
py_grpc_library = _py_grpc_library
swift_library = _swift_library
web_app = _web_app
