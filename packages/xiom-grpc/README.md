# xiom-grpc

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** gRPC client/server over HTTP/2 with protobuf messages.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `grpc-server` | gRPC server hosting service handlers. |
| `grpc-client` | gRPC client calling remote services. |
| `channel` | Channel with connection pooling and load balancing. |
| `stub` | Generated-style call stubs for services. |
| `protobuf` | Protobuf message encode/decode integration. |
| `codec` | gRPC framing, compression, and status handling. |
