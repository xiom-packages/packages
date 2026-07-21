# xiom-grpc ROADMAP

## v0.1.0 (Current)
- [x] Type system (GrpcServer, GrpcClient, GrpcChannel, GrpcCall, GrpcStatus)
- [x] All 17 gRPC canonical status codes (OK=0 through UNAUTHENTICATED=16)
- [x] status_to_str mapping for all 17 codes + unknown fallback
- [x] status_is_ok predicate helper
- [x] extern "C" FFI block — 14 gRPC C-core functions declared
- [x] Safe wrappers with requires contracts (server_new, channel_create, call_create, etc.)
- [x] GrpcRequest / GrpcResponse domain types with metadata accessors
- [x] Client module: channel/call lifecycle with GrpcStatus error handling
- [x] Server module: server lifecycle with GrpcServerConfig and address formatting
- [x] 16 requires contracts across all public functions
- [x] Conformance test suite (36 tests)

## v0.2.0 — gRPC C-Core FFI Bridge
- [ ] Protobuf message serialization via xiom-protobuf
- [ ] Unary RPC: request/response with deadline and metadata propagation
- [ ] Client streaming RPC (request stream, single response)
- [ ] Server streaming RPC (single request, response stream)
- [ ] Bidirectional streaming RPC
- [ ] gRPC completion queue event loop
- [ ] Async call batching via grpc_call_start_batch
- [ ] Real server listen/accept loop with service registration
- [ ] Link-time dependency on libgrpc (-l grpc -l gpr -l protobuf)
- [ ] CI pipeline with gRPC C Core installed for integration tests

## v0.3.0 — Advanced Features
- [ ] TLS/SSL channel credentials
- [ ] JWT/OAuth2 token-based auth interceptors
- [ ] Client-side load balancing (round-robin, pick-first)
- [ ] Service config / name resolution
- [ ] Retry policy with exponential backoff
- [ ] Keepalive and health checking
- [ ] Reflection API (grpc.reflection.v1alpha.ServerReflection)
- [ ] gRPC-Web proxy support
- [ ] Interceptors (unary + streaming middleware)

## v1.0.0 — Production Readiness
- [ ] Codegen from .proto files (protoc plugin for XIOM)
- [ ] Streaming flow control (backpressure via grpc_call_start_batch ops)
- [ ] Cancellation propagation across call chains
- [ ] Deadline/timeout enforcement
- [ ] Structured logging with trace IDs
- [ ] Performance benchmarks (QPS, latency p50/p99)
- [ ] Chaos testing (network partition, server restart)
- [ ] Full gRPC status code round-trip through GrpcStatus type
- [ ] Connection pooling and channel reuse
