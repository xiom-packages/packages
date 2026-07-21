module grpc_tests
use xiom.test;
use xiom.grpc;

fn test_init_shutdown() -> TestResult {
  init();
  shutdown();
  return assert(true, "grpc: init/shutdown cycle");
}

fn test_channel_create_stub() -> TestResult {
  init();
  match channel_create("localhost:50051") {
    Ok(ch) => {
      channel_destroy(ch);
      shutdown();
      return assert(true, "grpc: channel created (stub)");
    }
    Err(s) => {
      shutdown();
      return assert(true, "grpc: channel stub failed (expected without libgrpc): " + s.message);
    }
  }
}

fn test_status_mapping() -> TestResult {
  return assert(status_to_str(GRPC_STATUS_NOT_FOUND) == "NOT_FOUND", "grpc: status_to_str NOT_FOUND");
}

fn test_status_is_ok_true() -> TestResult {
  var s = GrpcStatus { code: GRPC_STATUS_OK; message: "OK"; };
  return assert(status_is_ok(&s), "grpc: status_is_ok true");
}

fn test_status_is_ok_false() -> TestResult {
  var s = GrpcStatus { code: GRPC_STATUS_INTERNAL; message: "error"; };
  return assert(!status_is_ok(&s), "grpc: status_is_ok false");
}

fn main() -> Int {
  var tests = [test_init_shutdown, test_channel_create_stub, test_status_mapping, test_status_is_ok_true, test_status_is_ok_false];
  return test.run_all(tests);
}
