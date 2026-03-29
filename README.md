# Simple Bazel Monorepo Example

This repository is a minimal monorepo showing:

- Kotlin gRPC backend
- TypeScript + React web client using gRPC-Web
- Python code in the same Bazel workspace
- Shared protobuf API contract

## Layout

```text
.
├── backend/       # Kotlin gRPC server
├── core/proto/    # Shared .proto contract
├── web/           # React client using gRPC-Web
├── scripts/       # Python example target
├── MODULE.bazel
└── BUILD.bazel
```

## API

The shared API is in `core/proto/event.proto`.

- Service: `victor.api.v1.Greeter`
- RPC: `SayHello(HelloRequest) -> HelloResponse`

## Commands

Build everything:

```bash
bazel build //...
```

Run Kotlin backend (port `8080` by default):

```bash
bazel run //backend:backend
```

Run web dev server:

```bash
bazel run //web:dev
```

Run TypeScript typecheck:

```bash
bazel test //web:typecheck
```

Run Python target:

```bash
bazel run //scripts:scripts
```

## How Web Connects To Backend

The web app calls the backend using gRPC-Web (`application/grpc-web+proto`) at:

- `POST /victor.api.v1.Greeter/SayHello`

`web/vite.config.ts` proxies `/grpc` to `http://localhost:8080`, so local development works without extra setup.
