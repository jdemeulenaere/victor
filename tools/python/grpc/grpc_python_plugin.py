#!/usr/bin/env python3
"""Protocol compiler plugin that reuses grpcio-tools code generation.

This executable implements protoc plugin I/O and delegates generation of
*_pb2_grpc.py files to grpc_tools._protoc_compiler.get_services.
"""

from __future__ import annotations

import sys

from google.protobuf.compiler import plugin_pb2
from grpc_tools import _protoc_compiler


def main() -> int:
    request = plugin_pb2.CodeGeneratorRequest()
    request.ParseFromString(sys.stdin.buffer.read())

    response = plugin_pb2.CodeGeneratorResponse()

    # Provide stable, best-effort search roots for grpc_tools' generator.
    search_paths = {"."}
    for proto in request.proto_file:
        if "/" in proto.name:
            search_paths.add(proto.name.rsplit("/", 1)[0])
    search_path_bytes = [path.encode("utf-8") for path in sorted(search_paths)]

    for proto in request.file_to_generate:
        generated_files = _protoc_compiler.get_services(
            proto.encode("utf-8"),
            search_path_bytes,
        )
        for filename_bytes, content_bytes in generated_files:
            out = response.file.add()
            out.name = filename_bytes.decode("utf-8")
            out.content = content_bytes.decode("utf-8")

    sys.stdout.buffer.write(response.SerializeToString())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
