module xiom.grpc.types
use xiom.grpc;
use xiom.convert;

pub type GrpcRequest = {
  service: Str;
  method: Str;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
} derive[Clone]

pub type GrpcResponse = {
  status: GrpcStatus;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
} derive[Clone]

pub type GrpcServerConfig = {
  addr: Str;
  port: Int;
} derive[Clone]

pub fn grpc_request_new(service: Str, method: Str, payload: Vec[Int], metadata: Vec[(Str, Str)]) -> GrpcRequest
  requires: service.len() > 0
  requires: method.len() > 0
{
  GrpcRequest {
    service: service.clone();
    method: method.clone();
    payload: payload;
    metadata: metadata;
  }
}

pub fn grpc_response_ok(payload: Vec[Int]) -> GrpcResponse
{
  GrpcResponse {
    status: GrpcStatus { code: GRPC_STATUS_OK; message: "OK"; };
    payload: payload;
    metadata: Vec[(Str, Str)].new();
  }
}

pub fn grpc_response_error(code: Int, message: Str) -> GrpcResponse
  requires: code != 0
{
  var metadata = Vec[(Str, Str)].new();
  metadata.push(("error-message".clone(), message.clone()));
  GrpcResponse {
    status: GrpcStatus { code: code; message: message.clone(); };
    payload: Vec[Int].new();
    metadata: metadata;
  }
}

pub fn grpc_metadata_get(resp: &GrpcResponse, key: Str) -> Option[Str]
  requires: key.len() > 0
{
  // Direct component reads: destructuring `let (k, v) = &vec[i]` yields
  // pointer-like values on v0.64.0/main (see docs/COMPILER-FINDINGS.md).
  var i = 0;
  while i < resp.metadata.len() {
    if resp.metadata[i].0 == key {
      return Some(resp.metadata[i].1.clone());
    };
    i = i + 1;
  };
  None
}

pub fn grpc_metadata_set(req: &mut GrpcRequest, key: Str, value: Str)
  requires: key.len() > 0
{
  // Direct component reads (same reason as grpc_metadata_get).
  var found = false;
  var i = 0;
  while i < req.metadata.len() {
    if req.metadata[i].0 == key {
      req.metadata[i] = (key.clone(), value.clone());
      found = true;
    };
    i = i + 1;
  };
  if !found {
    req.metadata.push((key.clone(), value.clone()));
  };
}

// --- Server Config Helpers --------------------------------------------------

pub fn grpc_server_config(host: Str, port: Int) -> GrpcServerConfig
  requires: host.len() > 0
  requires: port > 0
{
  return GrpcServerConfig{ addr: host, port: port };
}

pub fn grpc_server_address(cfg: &GrpcServerConfig) -> Str {
  return cfg.addr + ":" + int_to_string(cfg.port);
}
