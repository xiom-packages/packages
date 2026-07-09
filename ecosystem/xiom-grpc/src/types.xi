module xiom.grpc.types

pub type GrpcRequest = {
  service: Str;
  method: Str;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
} derive[Clone]

pub type GrpcResponse = {
  status: Int;
  payload: Vec[Int];
  metadata: Vec[(Str, Str)];
} derive[Clone]

pub type GrpcServer = {
  addr: Str;
  port: Int;
} derive[Clone]

pub const GRPC_STATUS_OK: Int = 0;
pub const GRPC_STATUS_CANCELLED: Int = 1;
pub const GRPC_STATUS_UNKNOWN: Int = 2;
pub const GRPC_STATUS_INVALID_ARGUMENT: Int = 3;
pub const GRPC_STATUS_DEADLINE_EXCEEDED: Int = 4;
pub const GRPC_STATUS_NOT_FOUND: Int = 5;
pub const GRPC_STATUS_ALREADY_EXISTS: Int = 6;
pub const GRPC_STATUS_PERMISSION_DENIED: Int = 7;
pub const GRPC_STATUS_INTERNAL: Int = 13;
pub const GRPC_STATUS_UNAVAILABLE: Int = 14;
pub const GRPC_STATUS_UNAUTHENTICATED: Int = 16;

fn grpc_request_new(service: Str, method: Str, payload: Vec[Int], metadata: Vec[(Str, Str)]) -> GrpcRequest
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

fn grpc_response_ok(payload: Vec[Int]) -> GrpcResponse
{
  GrpcResponse {
    status: GRPC_STATUS_OK;
    payload: payload;
    metadata: Vec[(Str, Str)].new();
  }
}

fn grpc_response_error(status: Int, message: Str) -> GrpcResponse
  requires: status != 0
{
  var metadata = Vec[(Str, Str)].new();
  metadata.push(("error-message".to_owned(), message.clone()));
  GrpcResponse {
    status: status;
    payload: Vec[Int].new();
    metadata: metadata;
  }
}

fn grpc_metadata_get(resp: &GrpcResponse, key: Str) -> Option[Str]
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

fn grpc_metadata_set(req: &mut GrpcRequest, key: Str, value: Str)
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

fn grpc_status_to_str(status: Int) -> Str
{
  match status {
    GRPC_STATUS_OK => "OK",
    GRPC_STATUS_CANCELLED => "CANCELLED",
    GRPC_STATUS_INVALID_ARGUMENT => "INVALID_ARGUMENT",
    GRPC_STATUS_DEADLINE_EXCEEDED => "DEADLINE_EXCEEDED",
    GRPC_STATUS_NOT_FOUND => "NOT_FOUND",
    GRPC_STATUS_ALREADY_EXISTS => "ALREADY_EXISTS",
    GRPC_STATUS_PERMISSION_DENIED => "PERMISSION_DENIED",
    GRPC_STATUS_INTERNAL => "INTERNAL",
    GRPC_STATUS_UNAVAILABLE => "UNAVAILABLE",
    GRPC_STATUS_UNAUTHENTICATED => "UNAUTHENTICATED",
    _ => "UNKNOWN",
  }
}
