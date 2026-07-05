# xiom-grpc — gRPC Client & Server

gRPC C Core bindings for XIOM. Unary and streaming RPC with protocol buffer payloads, metadata, and status codes.

## Install

```powershell
xiom pkg install xiom-grpc
```

## Requirements

- **gRPC C Core** and **libprotobuf**
  - Linux: `apt install libgrpc-dev libgrpc++-dev`
  - macOS: `brew install grpc`
  - Windows: vcpkg (`vcpkg install grpc`)

## Link Flags

```
-l grpc -l gpr -l protobuf
```

## Quick Start

### Client

```xiom
use xiom.grpc;

fn main() -> Result[Unit, Str] {
  grpc_init();

  let channel = grpc_channel_create("localhost:50051", false)?;
  let request = grpc_request_new(
    "helloworld.Greeter",
    "SayHello",
    "Hello, gRPC!".as_bytes(),
    vec![]
  );
  let response = grpc_unary_call(channel, "/helloworld.Greeter/SayHello", &request.payload)?;

  grpc_channel_destroy(channel);
  grpc_shutdown();
  return Ok(());
}
```

### Server

```xiom
use xiom.grpc;

fn main() -> Result[Unit, Str] {
  grpc_init();

  let server = grpc_server_create("0.0.0.0", 50051)?;
  grpc_server_register(server, "helloworld.Greeter", say_hello_handler)?;
  grpc_server_start(server)?;
  grpc_server_wait(server)?;

  grpc_shutdown();
  return Ok(());
}

fn say_hello_handler(req: &GrpcRequest) -> Result[GrpcResponse, Str] {
  Ok(grpc_response_ok("Hello back!".as_bytes().to_vec()))
}
```

## API Overview

| Module | File | Purpose |
|--------|------|---------|
| `xiom.grpc` | `grpc.xi` | FFI declarations |
| `xiom.grpc.types` | `src/types.xi` | Type definitions |
| `xiom.grpc.client` | `src/client.xi` | Client stubs |
| `xiom.grpc.server` | `src/server.xi` | Server stubs |

### Types

```xiom
pub type GrpcRequest = {
  service: Str;
  method: Str;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
}

pub type GrpcResponse = {
  status: Int;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
}

pub type GrpcServer = {
  addr: Str;
  port: Int;
}
```

### Streaming

```xiom
let call = grpc_stream_call(channel, "/routeguide.RouteGuide/RecordRoute")?;
grpc_stream_send(&call, &point1_data)?;
grpc_stream_send(&call, &point2_data)?;
grpc_stream_send_close(&call)?;

let response = grpc_stream_recv(&call)?;  // Some(data) or None (stream closed)
```

## gRPC Status Codes

| Code | Name |
|------|------|
| 0 | OK |
| 3 | INVALID_ARGUMENT |
| 5 | NOT_FOUND |
| 7 | PERMISSION_DENIED |
| 13 | INTERNAL |
| 14 | UNAVAILABLE |
| 16 | UNAUTHENTICATED |

## Method Format

Fully qualified: `"/package.Service/Method"` — e.g., `"/helloworld.Greeter/SayHello"`.

## Contracts

- `grpc_init()` must be called before any channel/server operations
- Channels and servers must be destroyed before `grpc_shutdown()`
- Method names must use fully qualified format

## License

MIT or Apache-2.0, at your option.
