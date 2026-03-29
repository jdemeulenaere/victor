# Protocol Notes

Source of truth: `core/proto/event.proto`

```proto
service Greeter {
  rpc SayHello(HelloRequest) returns (HelloResponse);
}
```

Message shapes:

- `HelloRequest { string name = 1; }`
- `HelloResponse { string message = 1; }`

Bazel targets:

- `//core/proto:victor_api_proto`
- `//core/proto:victor_api_java_proto`
- `//core/proto:victor_api_java_grpc`

Backend uses generated gRPC service classes.
Web calls the same service via gRPC-Web.
