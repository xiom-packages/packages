# xiom-grpc Specification

## Overview
gRPC client and server bindings for XIOM via gRPC C Core. Provides unary and streaming RPC with protocol buffer payloads and metadata propagation.

## Architecture

### Layers
```
┌──────────────────────────────────────┐
│  src/types.xi    (XIOM type defs)    │
│  GrpcRequest, GrpcResponse, etc.     │
├──────────────────────────────────────┤
│  src/client.xi   (Client stubs)      │
│  Channel, unary, streaming           │
├──────────────────────────────────────┤
│  src/server.xi   (Server stubs)      │
│  GrpcServer, service registration    │
├──────────────────────────────────────┤
│  grpc.xi         (Raw FFI decls)     │
│  init, create_channel, unary_call    │
├──────────────────────────────────────┤
│  grpc.xiom-bind  (C ABI mapping)     │
│  grpc_init, grpc_channel_create      │
└──────────────────────────────────────┘
```

### Design Decisions
- `GrpcRequest`/`GrpcResponse` use `Vec[Int]` (byte arrays) for payload — serialization is handled upstream (protobuf or JSON).
- Metadata is `Vec[(Str, Str)]` — key-value pairs for headers/trailers.
- Channel lifecycle: `grpc_init()` must be called once before any channels. `grpc_shutdown()` after all channels are destroyed.
- Both insecure and TLS channels are supported via the `secure` flag.

## Type System

### GrpcRequest
```
pub type GrpcRequest = {
  service: Str;
  method: Str;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
}
```

### GrpcResponse
```
pub type GrpcResponse = {
  status: Int;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
}
```

### GrpcServer
```
pub type GrpcServer = {
  addr: Str;
  port: Int;
}
```

### Status Codes
| Code | Name | HTTP Mapping |
|------|------|-------------|
| 0 | OK | 200 |
| 1 | CANCELLED | 499 |
| 2 | UNKNOWN | 500 |
| 3 | INVALID_ARGUMENT | 400 |
| 4 | DEADLINE_EXCEEDED | 504 |
| 5 | NOT_FOUND | 404 |
| 6 | ALREADY_EXISTS | 409 |
| 7 | PERMISSION_DENIED | 403 |
| 13 | INTERNAL | 500 |
| 14 | UNAVAILABLE | 503 |
| 16 | UNAUTHENTICATED | 401 |

## API Surface

### Client (`src/client.xi`)
| Function | Description |
|----------|-------------|
| `grpc_init()` | Initialize gRPC runtime (call once) |
| `grpc_shutdown()` | Shutdown gRPC runtime |
| `grpc_channel_create(target, secure)` | Create channel to `host:port` |
| `grpc_channel_destroy(channel)` | Destroy channel |
| `grpc_unary_call(channel, method, request)` | Blocking unary RPC |
| `grpc_stream_call(channel, method)` | Start bidirectional stream |
| `grpc_stream_send(call, data)` | Send on stream |
| `grpc_stream_recv(call)` | Receive on stream |
| `grpc_stream_close(call)` | Close send side of stream |

### Server (`src/server.xi`)
| Function | Description |
|----------|-------------|
| `grpc_server_create(addr, port)` | Create server bound to address |
| `grpc_server_register(server, service, handler)` | Register service handler |
| `grpc_server_start(server)` | Start accepting connections |
| `grpc_server_stop(server)` | Graceful shutdown |
| `grpc_server_wait(server)` | Block until shutdown complete |

### Types (`src/types.xi`)
| Function | Description |
|----------|-------------|
| `grpc_request_new(service, method, payload, metadata)` | Construct request |
| `grpc_response_ok(payload)` | Construct OK response |
| `grpc_response_error(status, message)` | Construct error response |
| `grpc_metadata_get(resp, key)` | Lookup response metadata by key |

## Safety Contracts
1. `grpc_init()` must be called before any channel/server creation.
2. Channels/servers must be destroyed before `grpc_shutdown()`.
3. Methods are fully qualified: `"/package.Service/Method"`.
4. `payload.len() > 0` is NOT required — empty-body RPCs are valid.
5. Streaming calls require explicit `grpc_stream_close_client_send()` before final receive.

## External Dependencies
- **Runtime:** gRPC C Core — `libgrpc.dll` / `libgrpc.so`
- **Install:** `apt install libgrpc-dev` (Linux), `brew install grpc` (macOS), vcpkg (Windows)
- **Link flags:** `-l grpc -l gpr -l protobuf`
- **Compatibility:** gRPC >= 1.30 (C Core version)

## Error Handling
1. Channel creation failure returns `Err(description)` — typically DNS or network issues.
2. Unary call failures return gRPC status code + error message.
3. Stream errors distinguish between connection errors and peer-initiated close.
4. Server registration conflicts (duplicate methods) return `Err`.
5. Deadlines/exceeded timeouts are propagated as gRPC status `DEADLINE_EXCEEDED`.
