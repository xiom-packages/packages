// XIOM — xiom-micro Conformance Tests (10 tests)
module xiom.micro.tests

use xiom.micro;
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
  io.println("=== xiom-micro Conformance Tests ===");

  var passed: Int = 0;
  var failed: Int = 0;
  var total: Int = 0;

  var results: Vec[Result[Unit, Str]] = Vec[Result[Unit, Str]].new();
  results.push(test_router_new());
  results.push(test_router_register_get());
  results.push(test_router_register_post());
  results.push(test_router_route_count());
  results.push(test_router_find_route());
  results.push(test_response_helpers());
  results.push(test_middleware_registration());
  results.push(test_middleware_evaluate_auth());
  results.push(test_app_builder());
  results.push(test_request_builder());

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

fn test_router_new() -> Result[Unit, Str] {
  var r = router_new();
  try(assert_int_eq(r.routes.len(), 0, "router_new: empty routes"));
  try(assert_int_eq(router_route_count(&r), 0, "router_new: route_count 0"));
  try(assert_int_eq(r.middleware.len(), 0, "router_new: empty middleware"));
  return Ok(Unit);
}

fn test_router_register_get() -> Result[Unit, Str] {
  var r = router_new();
  var route = router_get(&mut r, "/api/hello", "hello_handler");
  try(assert_str_eq(route.path, "/api/hello", "router_get: path"));
  try(assert_int_eq(router_route_count(&r), 1, "router_get: 1 route added"));

  match route.method {
    HttpMethod.GET => {},
    _ => { return Err("FAIL: router_get: method not GET"); },
  };
  return Ok(Unit);
}

fn test_router_register_post() -> Result[Unit, Str] {
  var r = router_new();
  var route = router_post(&mut r, "/api/users", "create_user");
  try(assert_str_eq(route.handler, "create_user", "router_post: handler"));
  try(assert_int_eq(router_route_count(&r), 1, "router_post: 1 route added"));

  match route.method {
    HttpMethod.POST => {},
    _ => { return Err("FAIL: router_post: method not POST"); },
  };
  return Ok(Unit);
}

fn test_router_route_count() -> Result[Unit, Str] {
  var r = router_new();
  var _route1 = router_get(&mut r, "/a", "ha");
  var _route2 = router_post(&mut r, "/a", "hp");
  var _route3 = router_put(&mut r, "/b", "hu");
  var _route4 = router_delete(&mut r, "/c", "hd");
  try(assert_int_eq(router_route_count(&r), 4, "router_route_count: 4 routes"));
  return Ok(Unit);
}

fn test_router_find_route() -> Result[Unit, Str] {
  var r = router_new();
  var _route1 = router_get(&mut r, "/api/items", "list_items");
  var _route2 = router_post(&mut r, "/api/items", "create_item");

  var found = router_find_route(&r, HttpMethod.GET, "/api/items");
  match found {
    Some(rt) => { try(assert_str_eq(rt.handler, "list_items", "find_route: GET /api/items")); },
    None => { return Err("FAIL: find_route returned None"); },
  };

  var not_found = router_find_route(&r, HttpMethod.DELETE, "/api/items");
  match not_found {
    Some(_) => { return Err("FAIL: find_route DELETE should be None"); },
    None => {},
  };

  try(assert_true(router_has_route(&r, HttpMethod.POST, "/api/items"), "has_route: POST exists"));
  try(assert_true(!router_has_route(&r, HttpMethod.PATCH, "/api/items"), "has_route: PATCH absent"));
  return Ok(Unit);
}

fn test_response_helpers() -> Result[Unit, Str] {
  var ok = response_ok("hello");
  try(assert_int_eq(ok.status, 200, "response_ok: status 200"));
  try(assert_str_eq(ok.body, "hello", "response_ok: body"));
  try(assert_true(response_is_success(&ok), "response_is_success: ok"));

  var nf = response_not_found("missing");
  try(assert_int_eq(nf.status, 404, "response_not_found: status 404"));
  try(assert_true(response_is_client_error(&nf), "response_is_client_error: 404"));

  var ie = response_internal_error("boom");
  try(assert_int_eq(ie.status, 500, "response_internal_error: status 500"));
  try(assert_true(response_is_server_error(&ie), "response_is_server_error: 500"));

  var created = response_created("new");
  try(assert_int_eq(created.status, 201, "response_created: status 201"));
  try(assert_true(response_is_success(&created), "response_is_success: 201"));

  return Ok(Unit);
}

fn test_middleware_registration() -> Result[Unit, Str] {
  var r = router_new();
  router_use_middleware(&mut r, "logger", MiddlewarePhase.Before);
  router_use_middleware(&mut r, "auth", MiddlewarePhase.Before);
  router_use_middleware(&mut r, "cors", MiddlewarePhase.After);

  try(assert_int_eq(router_middleware_count(&r), 3, "middleware: 3 registered"));
  try(assert_int_eq(router_middleware_before_count(&r), 2, "middleware: 2 before"));
  try(assert_int_eq(router_middleware_after_count(&r), 1, "middleware: 1 after"));
  return Ok(Unit);
}

fn test_middleware_evaluate_auth() -> Result[Unit, Str] {
  var r = router_new();
  router_use_middleware(&mut r, "auth", MiddlewarePhase.Before);

  var req_no_auth = request_new(HttpMethod.GET, "/api/protected");
  var mw_result = middleware_evaluate(&r.middleware, &req_no_auth);
  try(assert_true(!middleware_evaluate_allowed(&mw_result), "auth middleware: no auth blocked"));

  var req_auth = request_new(HttpMethod.GET, "/api/protected");
  request_add_header(&mut req_auth, "Authorization", "Bearer token123");
  var mw_result2 = middleware_evaluate(&r.middleware, &req_auth);
  try(assert_true(middleware_evaluate_allowed(&mw_result2), "auth middleware: auth allowed"));

  return Ok(Unit);
}

fn test_app_builder() -> Result[Unit, Str] {
  var app = app_new("127.0.0.1", 3000);
  try(assert_str_eq(app.host, "127.0.0.1", "app_new: host"));
  try(assert_int_eq(app.port, 3000, "app_new: port"));
  try(assert_true(!app_is_running(&app), "app: not running initially"));

  app_use_global_middleware(&mut app, "logger");
  var _r1 = app_get(&mut app, "/health", "health_check");
  var _r2 = app_post(&mut app, "/data", "post_data");

  try(assert_int_eq(app_global_middleware_count(&app), 1, "app: 1 global middleware"));
  try(assert_int_eq(router_route_count(app.router), 2, "app: 2 routes"));

  return Ok(Unit);
}

fn test_request_builder() -> Result[Unit, Str] {
  var req = request_new(HttpMethod.POST, "/api/submit");
  try(assert_str_eq(req.path, "/api/submit", "request_new: path"));

  match req.method {
    HttpMethod.POST => {},
    _ => { return Err("FAIL: request_new: method not POST"); },
  };

  try(assert_int_eq(req.headers.len(), 0, "request_new: empty headers"));
  try(assert_str_eq(req.body, "", "request_new: empty body"));

  request_add_header(&mut req, "Content-Type", "application/json");
  request_add_query_param(&mut req, "v", "1");
  request_set_body(&mut req, "{}");

  try(assert_int_eq(req.headers.len(), 1, "request_add_header: 1 header"));
  try(assert_int_eq(req.query_params.len(), 1, "request_add_query_param: 1 param"));
  try(assert_str_eq(req.body, "{}", "request_set_body: json body"));

  var has_ct = request_has_header(&req, "Content-Type");
  try(assert_true(has_ct, "request_has_header: Content-Type"));

  var has_missing = request_has_header(&req, "X-Missing");
  try(assert_true(!has_missing, "request_has_header: missing header"));

  return Ok(Unit);
}

fn try(res: Result[Unit, Str]) {
  match res {
    Ok(_) => {},
    Err(e) => { io.println(e); },
  };
}
