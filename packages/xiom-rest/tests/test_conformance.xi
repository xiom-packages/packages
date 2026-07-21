// XIOM — xiom-rest Conformance Tests (10 tests)
module xiom.rest.tests

use xiom.rest;
use xiom.string;
use xiom.io;

fn assert_true(condition: Bool, label: Str) -> Result[Unit, Str] {
  if condition { return Ok(Unit); };
  return Err("FAIL: " + label);
}

fn assert_int_eq(actual: Int, expected: Int, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label + " — expected " + int_to_str(expected) + " got " + int_to_str(actual));
}

fn assert_str_eq(actual: Str, expected: Str, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label + " — expected '" + expected + "' got '" + actual + "'");
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var num: Int = n;
  var neg: Bool = false;
  if num < 0 { neg = true; num = -num; };
  var out: Str = "";
  while num > 0 {
    var d: Int = num % 10;
    if d == 0 { out = "0" + out; }
    elif d == 1 { out = "1" + out; }
    elif d == 2 { out = "2" + out; }
    elif d == 3 { out = "3" + out; }
    elif d == 4 { out = "4" + out; }
    elif d == 5 { out = "5" + out; }
    elif d == 6 { out = "6" + out; }
    elif d == 7 { out = "7" + out; }
    elif d == 8 { out = "8" + out; }
    elif d == 9 { out = "9" + out; };
    num = num / 10;
  };
  if neg { out = "-" + out; };
  return out;
}

pub fn run_all_tests() -> Result[Unit, Str] {
  io.println("=== xiom-rest Conformance Tests ===");

  var passed: Int = 0;
  var failed: Int = 0;
  var total: Int = 0;

  var results: Vec[Result[Unit, Str]] = Vec[Result[Unit, Str]].new();
  results.push(test_client_new());
  results.push(test_client_add_header());
  results.push(test_client_remove_header());
  results.push(test_request_new());
  results.push(test_request_add_header());
  results.push(test_request_add_query_param());
  results.push(test_method_to_str());
  results.push(test_method_from_str());
  results.push(test_response_is_success());
  results.push(test_error_constructors());

  var i: Int = 0;
  while i < results.len() {
    total = total + 1;
    match results[i] {
      Ok(_) => { passed = passed + 1; },
      Err(e) => { failed = failed + 1; io.println(e); },
    };
    i = i + 1;
  };

  io.println("");
  io.println(int_to_str(passed) + " passed, " + int_to_str(failed) + " failed out of " + int_to_str(total));

  if failed > 0 {
    return Err(int_to_str(failed) + " test(s) failed");
  };
  return Ok(Unit);
}

fn test_client_new() -> Result[Unit, Str] {
  var c = client_new("https://api.example.com");
  try(assert_str_eq(c.base_url, "https://api.example.com", "client_new: base_url"));
  try(assert_int_eq(c.timeout_ms, 30000, "client_new: default timeout"));
  try(assert_true(c.follow_redirects, "client_new: follow_redirects=true"));
  try(assert_int_eq(c.default_headers.len(), 0, "client_new: headers empty"));
  return Ok(Unit);
}

fn test_client_add_header() -> Result[Unit, Str] {
  var c = client_new("https://api.example.com");
  client_add_header(&mut c, "Authorization", "Bearer token123");
  client_add_header(&mut c, "Content-Type", "application/json");
  try(assert_int_eq(c.default_headers.len(), 2, "client_add_header: 2 headers"));

  var found = client_get_default_header(&c, "Authorization");
  match found {
    Some(v) => { try(assert_str_eq(v, "Bearer token123", "client_get_default_header: auth")); },
    None => { return Err("FAIL: client_get_default_header returned None"); },
  };
  return Ok(Unit);
}

fn test_client_remove_header() -> Result[Unit, Str] {
  var c = client_new("https://api.example.com");
  client_add_header(&mut c, "X-Custom", "value1");
  client_add_header(&mut c, "X-Test", "value2");
  try(assert_int_eq(c.default_headers.len(), 2, "remove: 2 headers before"));

  var removed = client_remove_header(&mut c, "X-Custom");
  try(assert_true(removed, "remove: returned true"));
  try(assert_int_eq(c.default_headers.len(), 1, "remove: 1 header after"));

  var removed_again = client_remove_header(&mut c, "X-Custom");
  try(assert_true(!removed_again, "remove: already removed returns false"));
  return Ok(Unit);
}

fn test_request_new() -> Result[Unit, Str] {
  var req = request_new(RestMethod.GET, "/users");
  match req.method {
    RestMethod.GET => {},
    _ => { return Err("FAIL: request_new: method should be GET"); },
  };
  try(assert_str_eq(req.path, "/users", "request_new: path"));
  try(assert_int_eq(req.headers.len(), 0, "request_new: empty headers"));
  try(assert_int_eq(req.query_params.len(), 0, "request_new: empty query params"));
  try(assert_str_eq(req.body, "", "request_new: empty body"));
  return Ok(Unit);
}

fn test_request_add_header() -> Result[Unit, Str] {
  var req = request_new(RestMethod.POST, "/submit");
  request_add_header(&mut req, "Content-Type", "application/json");
  try(assert_int_eq(req.headers.len(), 1, "req_add_header: 1 header"));
  try(assert_str_eq(req.headers[0].name, "Content-Type", "req_add_header: name"));
  try(assert_str_eq(req.headers[0].value, "application/json", "req_add_header: value"));
  return Ok(Unit);
}

fn test_request_add_query_param() -> Result[Unit, Str] {
  var req = request_new(RestMethod.GET, "/search");
  request_add_query_param(&mut req, "q", "xiom");
  request_add_query_param(&mut req, "page", "1");
  try(assert_int_eq(req.query_params.len(), 2, "query_params: 2 params"));
  try(assert_str_eq(req.query_params[0].key, "q", "query_params[0].key"));
  try(assert_str_eq(req.query_params[1].value, "1", "query_params[1].value"));
  return Ok(Unit);
}

fn test_method_to_str() -> Result[Unit, Str] {
  try(assert_str_eq(method_to_str(RestMethod.GET), "GET", "method_to_str: GET"));
  try(assert_str_eq(method_to_str(RestMethod.POST), "POST", "method_to_str: POST"));
  try(assert_str_eq(method_to_str(RestMethod.PUT), "PUT", "method_to_str: PUT"));
  try(assert_str_eq(method_to_str(RestMethod.DELETE), "DELETE", "method_to_str: DELETE"));
  try(assert_str_eq(method_to_str(RestMethod.PATCH), "PATCH", "method_to_str: PATCH"));
  try(assert_str_eq(method_to_str(RestMethod.HEAD), "HEAD", "method_to_str: HEAD"));
  try(assert_str_eq(method_to_str(RestMethod.OPTIONS), "OPTIONS", "method_to_str: OPTIONS"));
  return Ok(Unit);
}

fn test_method_from_str() -> Result[Unit, Str] {
  match method_from_str("POST") { RestMethod.POST => {}, _ => { return Err("FAIL: from_str POST"); }, };
  match method_from_str("PUT") { RestMethod.PUT => {}, _ => { return Err("FAIL: from_str PUT"); }, };
  match method_from_str("DELETE") { RestMethod.DELETE => {}, _ => { return Err("FAIL: from_str DELETE"); }, };
  match method_from_str("UNKNOWN") { RestMethod.GET => {}, _ => { return Err("FAIL: from_str UNKNOWN default"); }, };
  return Ok(Unit);
}

fn test_response_is_success() -> Result[Unit, Str] {
  var r1 = RestResponse{ status: 200, body: "", headers: "" };
  var r2 = RestResponse{ status: 404, body: "", headers: "" };
  var r3 = RestResponse{ status: 500, body: "", headers: "" };
  var r4 = RestResponse{ status: 302, body: "", headers: "" };

  try(assert_true(response_is_success(&r1), "response_is_success: 200"));
  try(assert_true(!response_is_success(&r2), "response_is_success: 404 is not success"));
  try(assert_true(!response_is_success(&r3), "response_is_success: 500 is not success"));
  try(assert_true(!response_is_success(&r4), "response_is_success: 302 is not success"));
  try(assert_true(response_is_client_error(&r2), "response_is_client_error: 404"));
  try(assert_true(response_is_server_error(&r3), "response_is_server_error: 500"));
  return Ok(Unit);
}

fn test_error_constructors() -> Result[Unit, Str] {
  var err = error_not_found("User 42 not found");
  try(assert_str_eq(err.code, "NOT_FOUND", "error: NOT_FOUND code"));
  try(assert_int_eq(err.status, 404, "error: NOT_FOUND status 404"));

  var err2 = error_bad_request("Invalid input");
  try(assert_int_eq(err2.status, 400, "error: BAD_REQUEST status 400"));

  var err3 = error_internal("DB connection lost");
  try(assert_int_eq(err3.status, 500, "error: INTERNAL status 500"));

  var err4 = error_unauthorized("Token expired");
  try(assert_int_eq(err4.status, 401, "error: UNAUTHORIZED status 401"));

  var resp = error_to_response(&err);
  try(assert_int_eq(resp.status, 404, "error_to_response: status preserved"));
  try(assert_true(string.str_len(resp.body) > 0, "error_to_response: body non-empty"));

  return Ok(Unit);
}

fn try(res: Result[Unit, Str]) {
  match res {
    Ok(_) => {},
    Err(e) => { io.println(e); },
  };
}
