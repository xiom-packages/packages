module xiom.grpc.types
use xiom.grpc;

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
  var i = 0;
  while i < resp.metadata.len() {
    let (k, v) = &resp.metadata[i];
    if k == &key {
      return Some(v.clone());
    };
    i = i + 1;
  };
  None
}

pub fn grpc_metadata_set(req: &mut GrpcRequest, key: Str, value: Str)
  requires: key.len() > 0
{
  var found = false;
  var i = 0;
  while i < req.metadata.len() {
    let (k, v) = &req.metadata[i];
    if k == &key {
      req.metadata[i] = (key.clone(), value.clone());
      found = true;
    };
    i = i + 1;
  };
  if !found {
    req.metadata.push((key.clone(), value.clone()));
  };
}
