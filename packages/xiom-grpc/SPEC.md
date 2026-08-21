# xiom-grpc -- SPEC
**Phase**: 4 (Enterprise) | **Priority**: Medium
**Status**: Implemented (v0.1.0) | **Depends on**: xiom.ffi, xiom.protobuf
gRPC C Core bindings for XIOM -- types, FFI declarations, safe wrappers with contracts, and full status code support.

## Modules

### `xiom.grpc` (`grpc.xi`)
Core FFI declarations and safe wrappers.

**Types:**
- `GrpcServer = Int` -- Server handle (opaque pointer)
- `GrpcClient = Int` -- Client handle (opaque pointer)
- `GrpcChannel = Int` -- Channel handle (opaque pointer)
- `GrpcCall = Int` -- Call handle (opaque pointer)
- `GrpcStatus = { code: Int; message: Str }` -- Structured gRPC status

**Status Codes (17 canonical codes):**
| Code | Name | Value |
|------|------|-------|
| OK | GRPC_STATUS_OK | 0 |
| CANCELLED | GRPC_STATUS_CANCELLED | 1 |
| UNKNOWN | GRPC_STATUS_UNKNOWN | 2 |
| INVALID_ARGUMENT | GRPC_STATUS_INVALID_ARGUMENT | 3 |
| DEADLINE_EXCEEDED | GRPC_STATUS_DEADLINE_EXCEEDED | 4 |
| NOT_FOUND | GRPC_STATUS_NOT_FOUND | 5 |
| ALREADY_EXISTS | GRPC_STATUS_ALREADY_EXISTS | 6 |
| PERMISSION_DENIED | GRPC_STATUS_PERMISSION_DENIED | 7 |
| RESOURCE_EXHAUSTED | GRPC_STATUS_RESOURCE_EXHAUSTED | 8 |
| FAILED_PRECONDITION | GRPC_STATUS_FAILED_PRECONDITION | 9 |
| ABORTED | GRPC_STATUS_ABORTED | 10 |
| OUT_OF_RANGE | GRPC_STATUS_OUT_OF_RANGE | 11 |
| UNIMPLEMENTED | GRPC_STATUS_UNIMPLEMENTED | 12 |
| INTERNAL | GRPC_STATUS_INTERNAL | 13 |
| UNAVAILABLE | GRPC_STATUS_UNAVAILABLE | 14 |
| DATA_LOSS | GRPC_STATUS_DATA_LOSS | 15 |
| UNAUTHENTICATED | GRPC_STATUS_UNAUTHENTICATED | 16 |

**FFI Declarations (extern "C" -- 14 functions):**
| C Function | Purpose |
|------------|---------|
| grpc_init | Initialize gRPC runtime |
| grpc_shutdown | Shutdown gRPC runtime |
| grpc_server_create | Allocate server handle |
| grpc_server_register_service | Register service handler |
| grpc_server_start | Start accepting requests |
| grpc_server_shutdown | Graceful shutdown |
| grpc_server_destroy | Free server handle |
| grpc_channel_create | Create channel with creds |
| grpc_channel_destroy | Free channel |
| grpc_insecure_channel_create | Create insecure channel |
| grpc_call_create | Allocate call handle |
| grpc_call_start_batch | Start batch of operations |
| grpc_call_cancel | Cancel pending call |
| grpc_call_destroy | Free call handle |

**Safe Wrappers (with requires contracts):**
| Function | Signature | Contracts |
|----------|-----------|-----------|
| `server_new` | `(addr: Str) -> Result[GrpcServer, GrpcStatus]` | addr.len() > 0 |
| `server_register_service` | `(server, service, methods) -> Result[Unit, GrpcStatus]` | server != 0, service.len() > 0 |
| `server_start` | `(server) -> Result[Unit, GrpcStatus]` | server != 0 |
| `server_shutdown` | `(server) -> Result[Unit, GrpcStatus]` | server != 0 |
| `channel_create` | `(addr: Str) -> Result[GrpcChannel, GrpcStatus]` | addr.len() > 0 |
| `channel_destroy` | `(channel)` | channel != 0 |
| `call_create` | `(channel, method) -> Result[GrpcCall, GrpcStatus]` | channel != 0, method.len() > 0 |
| `call_start_batch` | `(call, ops, nops, tag) -> Result[Unit, GrpcStatus]` | call != 0 |
| `call_cancel` | `(call) -> Result[Unit, GrpcStatus]` | call != 0 |
| `call_destroy` | `(call)` | call != 0 |
| `init` / `shutdown` | `() -> Unit` | None |
| `status_to_str` | `(status: Int) -> Str` | Pure function |
| `status_is_ok` | `(status: &GrpcStatus) -> Bool` | Pure function |

### `xiom.grpc.types` (`src/types.xi`)
Domain types for request/response and metadata handling.

**Types:**
- `GrpcRequest { service, method, payload: Vec[Int], metadata: Vec[(Str, Str)] }`
- `GrpcResponse { status: GrpcStatus, payload: Vec[Int], metadata: Vec[(Str, Str)] }`
- `GrpcServerConfig { addr, port }`

**Functions:**
| Function | Contracts |
|----------|-----------|
| `grpc_request_new` | service.len() > 0, method.len() > 0 |
| `grpc_response_ok` | -- |
| `grpc_response_error` | code != 0 |
| `grpc_metadata_get` | key.len() > 0 |
| `grpc_metadata_set` | key.len() > 0 |

### `xiom.grpc.client` (`src/client.xi`)
Client-side channel and call lifecycle wrappers.

### `xiom.grpc.server` (`src/server.xi`)
Server-side lifecycle wrappers with config support.

## Contracts Summary
16 requires contracts across all public functions:
- `grpc.xi`: 11 contracts (server_new, server_register_service, server_start, server_shutdown, channel_create, channel_destroy, call_create, call_start_batch, call_cancel, call_destroy)
- `src/types.xi`: 4 contracts (grpc_request_new, grpc_response_error, grpc_metadata_get, grpc_metadata_set)
- `src/server.xi`: 2 contracts (grpc_server_config)

## Build & Link
```
xiom grpc.xi src/types.xi src/client.xi src/server.xi
```
Runtime requires gRPC C Core: `-l grpc -l gpr -l protobuf`

## Test Suite
36 conformance tests in `tests/test_conformance.xi` covering:
- All 17 status code constants (7 specific + 1 distinctness check)
- GrpcStatus construction (2 tests: ok + error)
- status_to_str for all 17 codes (9 tests)
- status_is_ok (2 tests)
- GrpcRequest construction and mutation
- GrpcResponse construction (ok + error)
- Metadata get/set (4 tests)
- GrpcServerConfig and address formatting (2 tests)
