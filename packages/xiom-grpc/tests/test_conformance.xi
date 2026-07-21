module grpc_conformance_tests
use xiom.grpc;
use xiom.grpc.types;

fn test_status_code_ok() -> Int {
  if GRPC_STATUS_OK == 0 { return 0; }
  return 1;
}

fn test_status_code_cancelled() -> Int {
  if GRPC_STATUS_CANCELLED == 1 { return 0; }
  return 1;
}

fn test_status_code_unknown() -> Int {
  if GRPC_STATUS_UNKNOWN == 2 { return 0; }
  return 1;
}

fn test_status_code_invalid_argument() -> Int {
  if GRPC_STATUS_INVALID_ARGUMENT == 3 { return 0; }
  return 1;
}

fn test_status_code_not_found() -> Int {
  if GRPC_STATUS_NOT_FOUND == 5 { return 0; }
  return 1;
}

fn test_status_code_permission_denied() -> Int {
  if GRPC_STATUS_PERMISSION_DENIED == 7 { return 0; }
  return 1;
}

fn test_status_code_unauthenticated() -> Int {
  if GRPC_STATUS_UNAUTHENTICATED == 16 { return 0; }
  return 1;
}

fn test_all_status_codes_distinct() -> Int {
  if GRPC_STATUS_OK != GRPC_STATUS_CANCELLED
    && GRPC_STATUS_CANCELLED != GRPC_STATUS_UNKNOWN
    && GRPC_STATUS_UNKNOWN != GRPC_STATUS_INVALID_ARGUMENT
    && GRPC_STATUS_INVALID_ARGUMENT != GRPC_STATUS_DEADLINE_EXCEEDED
    && GRPC_STATUS_NOT_FOUND != GRPC_STATUS_ALREADY_EXISTS
    && GRPC_STATUS_PERMISSION_DENIED != GRPC_STATUS_RESOURCE_EXHAUSTED
    && GRPC_STATUS_INTERNAL != GRPC_STATUS_UNAVAILABLE
    && GRPC_STATUS_DATA_LOSS != GRPC_STATUS_UNAUTHENTICATED
    && GRPC_STATUS_UNAUTHENTICATED != GRPC_STATUS_OK
    { return 0; }
  return 1;
}

fn test_grpc_status_construction() -> Int {
  var s = GrpcStatus { code: GRPC_STATUS_OK; message: "OK"; };
  if s.code == 0 && s.message == "OK" { return 0; }
  return 1;
}

fn test_grpc_status_error_construction() -> Int {
  var s = GrpcStatus { code: GRPC_STATUS_NOT_FOUND; message: "resource not found"; };
  if s.code == 5 && s.message.len() > 0 { return 0; }
  return 1;
}

fn test_status_to_str_ok() -> Int {
  var s = status_to_str(GRPC_STATUS_OK);
  if s == "OK" { return 0; }
  return 1;
}

fn test_status_to_str_not_found() -> Int {
  var s = status_to_str(GRPC_STATUS_NOT_FOUND);
  if s == "NOT_FOUND" { return 0; }
  return 1;
}

fn test_status_to_str_unauthenticated() -> Int {
  var s = status_to_str(GRPC_STATUS_UNAUTHENTICATED);
  if s == "UNAUTHENTICATED" { return 0; }
  return 1;
}

fn test_status_to_str_internal() -> Int {
  var s = status_to_str(GRPC_STATUS_INTERNAL);
  if s == "INTERNAL" { return 0; }
  return 1;
}

fn test_status_to_str_unknown_code() -> Int {
  var s = status_to_str(999);
  if s == "UNKNOWN" { return 0; }
  return 1;
}

fn test_status_to_str_covers_all_17() -> Int {
  var codes: Vec[Int] = Vec[Int].new();
  codes.push(0); codes.push(1); codes.push(2); codes.push(3); codes.push(4);
  codes.push(5); codes.push(6); codes.push(7); codes.push(8); codes.push(9);
  codes.push(10); codes.push(11); codes.push(12); codes.push(13); codes.push(14);
  codes.push(15); codes.push(16);
  var i = 0;
  while i < codes.len() {
    var s = status_to_str(codes[i]);
    if s == "UNKNOWN" { return 1; };
    i = i + 1;
  };
  return 0;
}

fn test_status_is_ok_true() -> Int {
  var s = GrpcStatus { code: GRPC_STATUS_OK; message: "OK"; };
  if status_is_ok(&s) { return 0; }
  return 1;
}

fn test_status_is_ok_false() -> Int {
  var s = GrpcStatus { code: GRPC_STATUS_UNAVAILABLE; message: "unavailable"; };
  if status_is_ok(&s) { return 1; }
  return 0;
}

fn test_grpc_request_construction() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  payload.push(1); payload.push(2); payload.push(3);
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var req = grpc_request_new("helloworld.Greeter", "SayHello", payload, meta);
  if req.service == "helloworld.Greeter" && req.method == "SayHello" && req.payload.len() == 3 { return 0; }
  return 1;
}

fn test_grpc_response_ok_construction() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  payload.push(42);
  var resp = grpc_response_ok(payload);
  var ok = resp.payload.len() == 1 && resp.payload[0] == 42;
  ok = ok && resp.status.code == GRPC_STATUS_OK;
  if ok { return 0; }
  return 1;
}

fn test_grpc_response_error_construction() -> Int {
  var resp = grpc_response_error(GRPC_STATUS_NOT_FOUND, "not found");
  var ok = resp.status.code == GRPC_STATUS_NOT_FOUND;
  ok = ok && resp.status.message == "not found";
  ok = ok && resp.payload.len() == 0;
  if ok { return 0; }
  return 1;
}

fn test_grpc_metadata_get_found() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  meta.push(("content-type", "application/grpc"));
  meta.push(("authorization", "Bearer token123"));
  var req = grpc_request_new("svc", "m", payload, meta);
  var resp = grpc_response_ok(Vec[Int].new());
  resp.metadata = req.metadata;
  match grpc_metadata_get(&resp, "content-type") {
    Some(v) => { if v == "application/grpc" { return 0; } return 2; }
    None => { return 1; }
  }
}

fn test_grpc_metadata_get_missing() -> Int {
  var resp = grpc_response_ok(Vec[Int].new());
  match grpc_metadata_get(&resp, "x-custom") {
    Some(_) => { return 1; }
    None => { return 0; }
  }
}

fn test_grpc_metadata_set_new_key() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var req = grpc_request_new("svc", "m", payload, meta);
  grpc_metadata_set(&mut req, "grpc-timeout", "5s");
  if req.metadata.len() == 1 && req.metadata[0].0 == "grpc-timeout" { return 0; }
  return 1;
}

fn test_grpc_metadata_set_overwrite() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  meta.push(("key", "old-value"));
  var req = grpc_request_new("svc", "m", payload, meta);
  grpc_metadata_set(&mut req, "key", "new-value");
  if req.metadata.len() == 1 && req.metadata[0].1 == "new-value" { return 0; }
  return 1;
}

fn test_server_config_construction() -> Int {
  var cfg = GrpcServerConfig { addr: "0.0.0.0"; port: 50051; };
  if cfg.addr == "0.0.0.0" && cfg.port == 50051 { return 0; }
  return 1;
}

fn test_server_config_address() -> Int {
  var cfg = grpc_server_config("127.0.0.1", 9090);
  var addr = grpc_server_address(&cfg);
  if addr == "127.0.0.1:9090" { return 0; }
  return 1;
}

fn test_grpc_status_all_codes_to_str() -> Int {
  if status_to_str(GRPC_STATUS_DEADLINE_EXCEEDED) == "DEADLINE_EXCEEDED" { return 0; }
  return 1;
}

fn test_grpc_status_all_codes_aborted() -> Int {
  if status_to_str(GRPC_STATUS_ABORTED) == "ABORTED" { return 0; }
  return 1;
}

fn test_grpc_status_all_codes_unimplemented() -> Int {
  if status_to_str(GRPC_STATUS_UNIMPLEMENTED) == "UNIMPLEMENTED" { return 0; }
  return 1;
}

fn test_grpc_status_all_codes_data_loss() -> Int {
  if status_to_str(GRPC_STATUS_DATA_LOSS) == "DATA_LOSS" { return 0; }
  return 1;
}

fn test_grpc_status_all_codes_failed_precondition() -> Int {
  if status_to_str(GRPC_STATUS_FAILED_PRECONDITION) == "FAILED_PRECONDITION" { return 0; }
  return 1;
}

fn test_grpc_status_all_codes_resource_exhausted() -> Int {
  if status_to_str(GRPC_STATUS_RESOURCE_EXHAUSTED) == "RESOURCE_EXHAUSTED" { return 0; }
  return 1;
}

fn test_grpc_status_all_codes_out_of_range() -> Int {
  if status_to_str(GRPC_STATUS_OUT_OF_RANGE) == "OUT_OF_RANGE" { return 0; }
  return 1;
}

fn test_response_status_field_access() -> Int {
  var resp = grpc_response_error(GRPC_STATUS_UNAVAILABLE, "server down");
  if resp.status.code == 14 && resp.status.message == "server down" { return 0; }
  return 1;
}

fn test_mutable_request_payload() -> Int {
  var payload: Vec[Int] = Vec[Int].new();
  payload.push(10);
  var meta: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  var req = grpc_request_new("s", "m", payload, meta);
  req.payload.push(20);
  if req.payload.len() == 2 && req.payload[1] == 20 { return 0; }
  return 1;
}

pub fn main() -> Int {
  var failures: Int = 0;
  failures = failures + test_status_code_ok();
  failures = failures + test_status_code_cancelled();
  failures = failures + test_status_code_unknown();
  failures = failures + test_status_code_invalid_argument();
  failures = failures + test_status_code_not_found();
  failures = failures + test_status_code_permission_denied();
  failures = failures + test_status_code_unauthenticated();
  failures = failures + test_all_status_codes_distinct();
  failures = failures + test_grpc_status_construction();
  failures = failures + test_grpc_status_error_construction();
  failures = failures + test_status_to_str_ok();
  failures = failures + test_status_to_str_not_found();
  failures = failures + test_status_to_str_unauthenticated();
  failures = failures + test_status_to_str_internal();
  failures = failures + test_status_to_str_unknown_code();
  failures = failures + test_status_to_str_covers_all_17();
  failures = failures + test_status_is_ok_true();
  failures = failures + test_status_is_ok_false();
  failures = failures + test_grpc_request_construction();
  failures = failures + test_grpc_response_ok_construction();
  failures = failures + test_grpc_response_error_construction();
  failures = failures + test_grpc_metadata_get_found();
  failures = failures + test_grpc_metadata_get_missing();
  failures = failures + test_grpc_metadata_set_new_key();
  failures = failures + test_grpc_metadata_set_overwrite();
  failures = failures + test_server_config_construction();
  failures = failures + test_server_config_address();
  failures = failures + test_grpc_status_all_codes_to_str();
  failures = failures + test_grpc_status_all_codes_aborted();
  failures = failures + test_grpc_status_all_codes_unimplemented();
  failures = failures + test_grpc_status_all_codes_data_loss();
  failures = failures + test_grpc_status_all_codes_failed_precondition();
  failures = failures + test_grpc_status_all_codes_resource_exhausted();
  failures = failures + test_grpc_status_all_codes_out_of_range();
  failures = failures + test_response_status_field_access();
  failures = failures + test_mutable_request_payload();
  return failures;
}
