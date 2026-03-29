# Victor Communication Protocol: Protobuf & gRPC

To enable seamless interaction between the **Kotlin Brain** and the **React Dashboard**, we will implement a type-safe communication layer using Protocol Buffers (Protobuf).

## 🎯 Objectives
- **Single Source of Truth**: Define all events and commands in a language-agnostic format.
- **Auto-Generation**: Use Bazel to generate Kotlin and TypeScript code directly from `.proto` files.
- **Type Safety**: Eliminate runtime errors caused by mismatched JSON payloads.

---

## 🏗 Proposed Architecture

### 1. Schema Definition (`core/proto/`)
All services and message types will reside in the `core/proto` directory.
- `command.proto`: Manual overrides and "wake-up" signals.
- `event.proto`: System events for the dashboard to display.
- `service.proto`: The gRPC service definitions (e.g., `VictorService`).

### 2. Technology Stack
| Layer | Technology | Rationale |
| :--- | :--- | :--- |
| **Schema** | Protobuf 3 | Industry standard for structured data. |
| **Protocol** | **Connect-RPC** | Modern, gRPC-compatible, and works natively in browsers without complex proxies. |
| **Backend** | `grpc-kotlin` | Standard gRPC implementation for Kotlin/JVM. |
| **Frontend** | `@connectrpc/connect-web` | Lightweight TS client for React. |

---

## 🛠 Bazel Workflow

### Phase A: Schema Setup
1. Define a `proto_library` in `core/proto/BUILD.bazel`.
2. Configure `MODULE.bazel` with `grpc_kotlin` and `rules_proto`.

### Phase B: Code Generation
- **Kotlin**: Use `kt_jvm_grpc_library` to generate the server stubs.
- **TypeScript**: Use `js_run_binary` with `ts-proto` or `protoc-gen-connect-es` to generate React-ready hooks and types.

### Phase C: Integration
1. **Backend**: Implement the `VictorService` in Kotlin.
2. **Frontend**: Use the generated Connect-RPC client in `web/src/App.tsx`.

---

## 📝 Example Schema (`wake_up.proto`)
```proto
syntax = "proto3";

package victor.core.v1;

message WakeUpRequest {
  string command = 1;
  int64 timestamp = 2;
}

message WakeUpResponse {
  bool success = 1;
  string message = 2;
}

service VictorService {
  rpc WakeUp(WakeUpRequest) returns (WakeUpResponse);
}
```

> [!TIP]
> Once this is set up, adding a new feature is as simple as adding a message to the `.proto` file and running `bazel build`. Both ends of the stack will be updated automatically.
