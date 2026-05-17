"""Bazel helpers for kotlinx-rpc code generation."""

load("@rules_java//java/common:java_common.bzl", "java_common")

_PLATFORM_VALUES = {
    "COMMON": True,
    "JS": True,
    "JVM": True,
    "NATIVE": True,
    "WASM_JS": True,
    "WASM_WASI": True,
}

def _shell_quote(value):
    return "'" + value.replace("'", "'\\''") + "'"

def _join_options(options):
    return ",".join(["{}={}".format(key, value) for key, value in options])

def _copy_lines(outputs, source_root):
    lines = []
    for rel, output in outputs:
        source = "{}/{}".format(source_root, rel)
        lines.extend([
            "mkdir -p {}".format(_shell_quote(output.dirname)),
            "cp \"{}\" {}".format(source, _shell_quote(output.path)),
        ])
    return lines

def _kotlinx_rpc_proto_impl(ctx):
    if ctx.attr.platform not in _PLATFORM_VALUES:
        fail("Unsupported kotlinx-rpc proto platform '{}'. Expected one of: {}".format(
            ctx.attr.platform,
            ", ".join(sorted(_PLATFORM_VALUES.keys())),
        ))

    proto_root = ctx.attr.proto_root or ctx.file.src.dirname
    if ctx.attr.proto_root and ctx.label.package:
        proto_root = "{}/{}".format(ctx.label.package, ctx.attr.proto_root)
    protobuf_outputs = [
        (out, ctx.actions.declare_file("{}/protobuf/{}".format(ctx.label.name, out)))
        for out in ctx.attr.protobuf_outs
    ]
    grpc_outputs = [
        (out, ctx.actions.declare_file("{}/grpc/{}".format(ctx.label.name, out)))
        for out in ctx.attr.grpc_outs
    ]
    outputs = [output for _, output in protobuf_outputs + grpc_outputs]

    java_runtime = ctx.attr._java_runtime[java_common.JavaRuntimeInfo]
    java_runtime_files = java_runtime.files.to_list()

    protobuf_options = _join_options([
        ("platform", ctx.attr.platform),
        ("debugOutput", "$work_dir/protobuf.log"),
    ])
    grpc_options = _join_options([
        ("platform", ctx.attr.platform),
        ("debugOutput", "$work_dir/grpc.log"),
    ])
    protobuf_script_line = 'exec "{}" -jar "{}" "$@"'.format(
        java_runtime.java_executable_exec_path,
        ctx.file._protobuf_plugin.path,
    )
    grpc_script_line = 'exec "{}" -jar "{}" "$@"'.format(
        java_runtime.java_executable_exec_path,
        ctx.file._grpc_plugin.path,
    )

    command = "\n".join([
        "set -euo pipefail",
        "work_dir=\"${{TMPDIR:-/tmp}}/{}_work\"".format(ctx.label.name),
        "protobuf_plugin=\"$work_dir/protoc-gen-kotlinx-rpc-protobuf\"",
        "grpc_plugin=\"$work_dir/protoc-gen-kotlinx-rpc-grpc\"",
        "protobuf_tmp=\"$work_dir/protobuf\"",
        "grpc_tmp=\"$work_dir/grpc\"",
        "rm -rf \"$work_dir\"",
        "mkdir -p \"$protobuf_tmp\" \"$grpc_tmp\"",
        "printf '%s\\n' '#!/usr/bin/env bash' {} > \"$protobuf_plugin\"".format(
            _shell_quote(protobuf_script_line),
        ),
        "printf '%s\\n' '#!/usr/bin/env bash' {} > \"$grpc_plugin\"".format(
            _shell_quote(grpc_script_line),
        ),
        "chmod +x \"$protobuf_plugin\" \"$grpc_plugin\"",
        "{} --proto_path={} --plugin=protoc-gen-kotlinx-rpc-protobuf=\"$protobuf_plugin\" --kotlinx-rpc-protobuf_out=\"$protobuf_tmp\" --kotlinx-rpc-protobuf_opt=\"{}\" {}".format(
            _shell_quote(ctx.executable._protoc.path),
            _shell_quote(proto_root),
            protobuf_options,
            _shell_quote(ctx.file.src.path),
        ),
        "{} --proto_path={} --plugin=protoc-gen-kotlinx-rpc-grpc=\"$grpc_plugin\" --kotlinx-rpc-grpc_out=\"$grpc_tmp\" --kotlinx-rpc-grpc_opt=\"{}\" {}".format(
            _shell_quote(ctx.executable._protoc.path),
            _shell_quote(proto_root),
            grpc_options,
            _shell_quote(ctx.file.src.path),
        ),
    ] + _copy_lines(protobuf_outputs, "$protobuf_tmp") + _copy_lines(grpc_outputs, "$grpc_tmp"))

    ctx.actions.run_shell(
        command = command,
        inputs = depset(
            [ctx.file.src, ctx.file._protobuf_plugin, ctx.file._grpc_plugin],
            transitive = [java_runtime.files],
        ),
        outputs = outputs,
        tools = [ctx.executable._protoc] + java_runtime_files,
        mnemonic = "KotlinxRpcProto",
        progress_message = "Generating kotlinx-rpc Kotlin sources for %{label}",
    )

    return [DefaultInfo(files = depset(outputs))]

kotlinx_rpc_proto = rule(
    implementation = _kotlinx_rpc_proto_impl,
    attrs = {
        "grpc_outs": attr.string_list(mandatory = True),
        "platform": attr.string(default = "COMMON"),
        "proto_root": attr.string(),
        "protobuf_outs": attr.string_list(mandatory = True),
        "src": attr.label(
            allow_single_file = [".proto"],
            mandatory = True,
        ),
        "_grpc_plugin": attr.label(
            allow_single_file = True,
            default = Label("@kotlinx_rpc_protoc_gen_grpc_kotlin_multiplatform_all//file"),
            cfg = "exec",
        ),
        "_java_runtime": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_host_java_runtime"),
            providers = [java_common.JavaRuntimeInfo],
            cfg = "exec",
        ),
        "_protobuf_plugin": attr.label(
            allow_single_file = True,
            default = Label("@kotlinx_rpc_protoc_gen_kotlin_multiplatform_all//file"),
            cfg = "exec",
        ),
        "_protoc": attr.label(
            default = Label("@com_google_protobuf//:protoc"),
            executable = True,
            cfg = "exec",
        ),
    },
)
