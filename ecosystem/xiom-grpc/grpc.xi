// XIOM — gRPC Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.grpc

pub type GrpcServer = Int;
pub type GrpcClient = Int;
pub type GrpcChannel = Int;
pub type GrpcCall = Int;
pub type GrpcStatus = {
  code: Int;
  message: Str;
}

pub const GRPC_STATUS_OK: Int = 0;
pub const GRPC_STATUS_CANCELLED: Int = 1;
pub const GRPC_STATUS_UNKNOWN: Int = 2;
pub const GRPC_STATUS_INVALID_ARGUMENT: Int = 3;
pub const GRPC_STATUS_DEADLINE_EXCEEDED: Int = 4;
pub const GRPC_STATUS_NOT_FOUND: Int = 5;
pub const GRPC_STATUS_ALREADY_EXISTS: Int = 6;
pub const GRPC_STATUS_PERMISSION_DENIED: Int = 7;
pub const GRPC_STATUS_RESOURCE_EXHAUSTED: Int = 8;
pub const GRPC_STATUS_FAILED_PRECONDITION: Int = 9;
pub const GRPC_STATUS_ABORTED: Int = 10;
pub const GRPC_STATUS_OUT_OF_RANGE: Int = 11;
pub const GRPC_STATUS_UNIMPLEMENTED: Int = 12;
pub const GRPC_STATUS_INTERNAL: Int = 13;
pub const GRPC_STATUS_UNAVAILABLE: Int = 14;
pub const GRPC_STATUS_DATA_LOSS: Int = 15;
pub const GRPC_STATUS_UNAUTHENTICATED: Int = 16;

extern "C" {
  fn grpc_init() -> Unit;
  fn grpc_shutdown() -> Unit;
  fn grpc_server_create(addr: Str, creds: Int, reserved: Int) -> Int;
  fn grpc_server_register_service(server: Int, service: Str, methods: Int) -> Int;
  fn grpc_server_start(server: Int) -> Int;
  fn grpc_server_shutdown(server: Int, deadline: Int) -> Int;
  fn grpc_server_destroy(server: Int) -> Unit;
  fn grpc_channel_create(target: Str, creds: Int, reserved: Int) -> Int;
  fn grpc_channel_destroy(channel: Int) -> Unit;
  fn grpc_insecure_channel_create(target: Str, reserved: Int) -> Int;
  fn grpc_call_create(channel: Int, method: Str, host: Str, deadline: Int, reserved: Int) -> Int;
  fn grpc_call_start_batch(call: Int, ops: Int, nops: Int, tag: Int, reserved: Int) -> Int;
  fn grpc_call_cancel(call: Int, reserved: Int) -> Int;
  fn grpc_call_destroy(call: Int) -> Unit;
}

pub fn server_new(addr: Str) -> Result[GrpcServer, GrpcStatus]
  requires: addr.len() > 0
{
  var server = grpc_server_create(addr, 0, 0);
  if server == 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_UNKNOWN; message: "grpc_server_create returned null"; });
  };
  Ok(server)
}

pub fn server_register_service(server: GrpcServer, service: Str, methods: Int) -> Result[Unit, GrpcStatus]
  requires: server != 0
  requires: service.len() > 0
{
  var rc = grpc_server_register_service(server, service, methods);
  if rc != 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_INTERNAL; message: "grpc_server_register_service failed"; });
  };
  Ok(())
}

pub fn server_start(server: GrpcServer) -> Result[Unit, GrpcStatus]
  requires: server != 0
{
  var rc = grpc_server_start(server);
  if rc != 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_INTERNAL; message: "grpc_server_start failed"; });
  };
  Ok(())
}

pub fn server_shutdown(server: GrpcServer) -> Result[Unit, GrpcStatus]
  requires: server != 0
{
  var rc = grpc_server_shutdown(server, 0);
  if rc != 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_INTERNAL; message: "grpc_server_shutdown failed"; });
  };
  grpc_server_destroy(server);
  Ok(())
}

pub fn channel_create(addr: Str) -> Result[GrpcChannel, GrpcStatus]
  requires: addr.len() > 0
{
  var channel = grpc_insecure_channel_create(addr, 0);
  if channel == 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_UNAVAILABLE; message: "grpc_insecure_channel_create returned null"; });
  };
  Ok(channel)
}

pub fn channel_destroy(channel: GrpcChannel)
  requires: channel != 0
{
  grpc_channel_destroy(channel);
}

pub fn call_create(channel: GrpcChannel, method: Str) -> Result[GrpcCall, GrpcStatus]
  requires: channel != 0
  requires: method.len() > 0
{
  var call = grpc_call_create(channel, method, "", 0, 0);
  if call == 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_INTERNAL; message: "grpc_call_create returned null"; });
  };
  Ok(call)
}

pub fn call_start_batch(call: GrpcCall, ops: Int, nops: Int, tag: Int) -> Result[Unit, GrpcStatus]
  requires: call != 0
{
  var rc = grpc_call_start_batch(call, ops, nops, tag, 0);
  if rc != 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_INTERNAL; message: "grpc_call_start_batch failed"; });
  };
  Ok(())
}

pub fn call_cancel(call: GrpcCall) -> Result[Unit, GrpcStatus]
  requires: call != 0
{
  var rc = grpc_call_cancel(call, 0);
  if rc != 0 {
    return Err(GrpcStatus { code: GRPC_STATUS_INTERNAL; message: "grpc_call_cancel failed"; });
  };
  Ok(())
}

pub fn call_destroy(call: GrpcCall)
  requires: call != 0
{
  grpc_call_destroy(call);
}

pub fn init()
{
  grpc_init();
}

pub fn shutdown()
{
  grpc_shutdown();
}

pub fn status_to_str(status: Int) -> Str
{
  match status {
    GRPC_STATUS_OK => "OK",
    GRPC_STATUS_CANCELLED => "CANCELLED",
    GRPC_STATUS_UNKNOWN => "UNKNOWN",
    GRPC_STATUS_INVALID_ARGUMENT => "INVALID_ARGUMENT",
    GRPC_STATUS_DEADLINE_EXCEEDED => "DEADLINE_EXCEEDED",
    GRPC_STATUS_NOT_FOUND => "NOT_FOUND",
    GRPC_STATUS_ALREADY_EXISTS => "ALREADY_EXISTS",
    GRPC_STATUS_PERMISSION_DENIED => "PERMISSION_DENIED",
    GRPC_STATUS_RESOURCE_EXHAUSTED => "RESOURCE_EXHAUSTED",
    GRPC_STATUS_FAILED_PRECONDITION => "FAILED_PRECONDITION",
    GRPC_STATUS_ABORTED => "ABORTED",
    GRPC_STATUS_OUT_OF_RANGE => "OUT_OF_RANGE",
    GRPC_STATUS_UNIMPLEMENTED => "UNIMPLEMENTED",
    GRPC_STATUS_INTERNAL => "INTERNAL",
    GRPC_STATUS_UNAVAILABLE => "UNAVAILABLE",
    GRPC_STATUS_DATA_LOSS => "DATA_LOSS",
    GRPC_STATUS_UNAUTHENTICATED => "UNAUTHENTICATED",
    _ => "UNKNOWN",
  }
}

pub fn status_is_ok(status: &GrpcStatus) -> Bool
{
  status.code == GRPC_STATUS_OK
}
