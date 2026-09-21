// XIOM -- Microservice Framework (Pure-XIOM Router, Middleware, Request/Response)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.micro

use xiom.string;
use xiom.convert;

// --- Types ------------------------------------------------------------------

pub enum HttpMethod {
  GET,
  POST,
  PUT,
  DELETE,
  PATCH,
  HEAD,
  OPTIONS,
} derive[Clone]

pub type MicroRequest = {
  method: HttpMethod;
  path: Str;
  headers: Vec[MicroHeader];
  query_params: Vec[MicroQueryParam];
  body: Str;
  route_params: Vec[MicroRouteParam];
} derive[Clone]

pub type MicroHeader = {
  name: Str;
  value: Str;
} derive[Clone]

pub type MicroQueryParam = {
  key: Str;
  value: Str;
} derive[Clone]

pub type MicroRouteParam = {
  key: Str;
  value: Str;
} derive[Clone]

pub type MicroResponse = {
  status: Int;
  body: Str;
  headers: Vec[MicroHeader];
} derive[Clone]

pub type MicroHandler = {
  name: Str;
  method: HttpMethod;
  path: Str;
} derive[Clone]

pub type MicroMiddleware = {
  name: Str;
  phase: MiddlewarePhase;
} derive[Clone]

pub enum MiddlewarePhase {
  Before,
  After,
} derive[Clone]

pub type MicroRouter = {
  routes: Vec[MicroRoute];
  middleware: Vec[MicroMiddleware];
  prefix: Str;
  not_found_handler: Str;
} derive[Clone]

pub type MicroRoute = {
  method: HttpMethod;
  path: Str;
  handler: Str;
  middleware: Vec[Str];
} derive[Clone]

pub type MicroApp = {
  router: MicroRouter;
  host: Str;
  port: Int;
  running: Bool;
  global_middleware: Vec[Str];
} derive[Clone]

pub type MiddlewareResult = {
  allowed: Bool;
  message: Str;
} derive[Clone]

// --- Method Helpers ---------------------------------------------------------

pub fn method_to_str(method: HttpMethod) -> Str {
  match method {
    HttpMethod.GET => return "GET",
    HttpMethod.POST => return "POST",
    HttpMethod.PUT => return "PUT",
    HttpMethod.DELETE => return "DELETE",
    HttpMethod.PATCH => return "PATCH",
    HttpMethod.HEAD => return "HEAD",
    HttpMethod.OPTIONS => return "OPTIONS",
  };
}

pub fn method_from_str(s: Str) -> HttpMethod {
  if s == "GET" { return HttpMethod.GET; };
  if s == "POST" { return HttpMethod.POST; };
  if s == "PUT" { return HttpMethod.PUT; };
  if s == "DELETE" { return HttpMethod.DELETE; };
  if s == "PATCH" { return HttpMethod.PATCH; };
  if s == "HEAD" { return HttpMethod.HEAD; };
  if s == "OPTIONS" { return HttpMethod.OPTIONS; };
  return HttpMethod.GET;
}

// --- Request Builder --------------------------------------------------------

pub fn request_new(method: HttpMethod, path: Str) -> MicroRequest
  requires: string.str_len(path) > 0
{
  return MicroRequest{
    method: method,
    path: path,
    headers: Vec[MicroHeader].new(),
    query_params: Vec[MicroQueryParam].new(),
    body: "",
    route_params: Vec[MicroRouteParam].new(),
  };
}

pub fn request_add_header(req: &mut MicroRequest, name: Str, value: Str) {
  var h = MicroHeader{ name: name, value: value };
  req.headers.push(h);
}

pub fn request_add_query_param(req: &mut MicroRequest, key: Str, value: Str) {
  var p = MicroQueryParam{ key: key, value: value };
  req.query_params.push(p);
}

pub fn request_set_body(req: &mut MicroRequest, body: Str) {
  req.body = body;
}

pub fn request_get_header(req: &MicroRequest, name: Str) -> Option[Str] {
  var i: Int = 0;
  while i < req.headers.len() {
    if req.headers[i].name == name {
      return Some(req.headers[i].value);
    };
    i = i + 1;
  };
  return None;
}

pub fn request_has_header(req: &MicroRequest, name: Str) -> Bool {
  var found = request_get_header(req, name);
  match found {
    Some(_) => return true,
    None => return false,
  };
}

// --- Response Builder -------------------------------------------------------

pub fn response_new(status: Int) -> MicroResponse
  requires: status >= 100
  requires: status < 600
{
  return MicroResponse{
    status: status,
    body: "",
    headers: Vec[MicroHeader].new(),
  };
}

pub fn response_ok(body: Str) -> MicroResponse {
  return MicroResponse{
    status: 200,
    body: body,
    headers: Vec[MicroHeader].new(),
  };
}

pub fn response_json(body: Str) -> MicroResponse {
  var r = MicroResponse{
    status: 200,
    body: body,
    headers: Vec[MicroHeader].new(),
  };
  var h = MicroHeader{ name: "Content-Type", value: "application/json" };
  r.headers.push(h);
  return r;
}

pub fn response_created(body: Str) -> MicroResponse {
  return MicroResponse{
    status: 201,
    body: body,
    headers: Vec[MicroHeader].new(),
  };
}

pub fn response_not_found(body: Str) -> MicroResponse {
  return MicroResponse{
    status: 404,
    body: body,
    headers: Vec[MicroHeader].new(),
  };
}

pub fn response_internal_error(body: Str) -> MicroResponse {
  return MicroResponse{
    status: 500,
    body: body,
    headers: Vec[MicroHeader].new(),
  };
}

pub fn response_bad_request(body: Str) -> MicroResponse {
  return MicroResponse{
    status: 400,
    body: body,
    headers: Vec[MicroHeader].new(),
  };
}

pub fn response_add_header(res: &mut MicroResponse, name: Str, value: Str) {
  var h = MicroHeader{ name: name, value: value };
  res.headers.push(h);
}

pub fn response_is_success(res: &MicroResponse) -> Bool {
  return res.status >= 200 && res.status < 300;
}

pub fn response_is_client_error(res: &MicroResponse) -> Bool {
  return res.status >= 400 && res.status < 500;
}

pub fn response_is_server_error(res: &MicroResponse) -> Bool {
  return res.status >= 500 && res.status < 600;
}

// --- Router -----------------------------------------------------------------

pub fn router_new() -> MicroRouter
  requires: true
  ensures: result.routes.len() == 0
{
  return MicroRouter{
    routes: Vec[MicroRoute].new(),
    middleware: Vec[MicroMiddleware].new(),
    prefix: "",
    not_found_handler: "",
  };
}

pub fn router_with_prefix(prefix: Str) -> MicroRouter {
  var r = router_new();
  r.prefix = prefix;
  return r;
}

pub fn router_route_count(router: &MicroRouter) -> Int {
  return router.routes.len();
}

pub fn router_has_route(router: &MicroRouter, method: HttpMethod, path: Str) -> Bool {
  var i: Int = 0;
  while i < router.routes.len() {
    if router.routes[i].method == method && router.routes[i].path == path {
      return true;
    };
    i = i + 1;
  };
  return false;
}

pub fn router_find_route(router: &MicroRouter, method: HttpMethod, path: Str) -> Option[MicroRoute] {
  var i: Int = 0;
  while i < router.routes.len() {
    if router.routes[i].method == method && router.routes[i].path == path {
      return Some(router.routes[i]);
    };
    i = i + 1;
  };
  return None;
}

pub fn router_get_routes_by_method(router: &MicroRouter, method: HttpMethod) -> Vec[MicroRoute] {
  var result: Vec[MicroRoute] = Vec[MicroRoute].new();
  var i: Int = 0;
  while i < router.routes.len() {
    if router.routes[i].method == method {
      result.push(router.routes[i]);
    };
    i = i + 1;
  };
  return result;
}

// --- Route Registration -----------------------------------------------------

pub fn router_register(
  router: &mut MicroRouter,
  method: HttpMethod,
  path: Str,
  handler: Str,
) -> MicroRoute
  requires: string.str_len(path) > 0
{
  var resolved_path: Str = path;
  if string.str_len(router.prefix) > 0 {
    resolved_path = router.prefix + path;
  };
  var route = MicroRoute{
    method: method,
    path: resolved_path,
    handler: handler,
    middleware: Vec[Str].new(),
  };
  router.routes.push(route);
  return route;
}

pub fn router_get(router: &mut MicroRouter, path: Str, handler: Str) -> MicroRoute {
  return router_register(router, HttpMethod.GET, path, handler);
}

pub fn router_post(router: &mut MicroRouter, path: Str, handler: Str) -> MicroRoute {
  return router_register(router, HttpMethod.POST, path, handler);
}

pub fn router_put(router: &mut MicroRouter, path: Str, handler: Str) -> MicroRoute {
  return router_register(router, HttpMethod.PUT, path, handler);
}

pub fn router_delete(router: &mut MicroRouter, path: Str, handler: Str) -> MicroRoute {
  return router_register(router, HttpMethod.DELETE, path, handler);
}

pub fn router_patch(router: &mut MicroRouter, path: Str, handler: Str) -> MicroRoute {
  return router_register(router, HttpMethod.PATCH, path, handler);
}

pub fn router_head(router: &mut MicroRouter, path: Str, handler: Str) -> MicroRoute {
  return router_register(router, HttpMethod.HEAD, path, handler);
}

pub fn router_options(router: &mut MicroRouter, path: Str, handler: Str) -> MicroRoute {
  return router_register(router, HttpMethod.OPTIONS, path, handler);
}

// --- Middleware Chain --------------------------------------------------------

pub fn middleware_new(name: Str, phase: MiddlewarePhase) -> MicroMiddleware {
  return MicroMiddleware{
    name: name,
    phase: phase,
  };
}

pub fn middleware_is_before(mw: &MicroMiddleware) -> Bool {
  match mw.phase {
    MiddlewarePhase.Before => return true,
    MiddlewarePhase.After => return false,
  };
}

pub fn middleware_is_after(mw: &MicroMiddleware) -> Bool {
  match mw.phase {
    MiddlewarePhase.After => return true,
    MiddlewarePhase.Before => return false,
  };
}

pub fn router_use_middleware(router: &mut MicroRouter, mw_name: Str, phase: MiddlewarePhase) {
  var mw = middleware_new(mw_name, phase);
  router.middleware.push(mw);
}

pub fn router_middleware_count(router: &MicroRouter) -> Int {
  return router.middleware.len();
}

pub fn router_middleware_before_count(router: &MicroRouter) -> Int {
  var count: Int = 0;
  var i: Int = 0;
  while i < router.middleware.len() {
    if middleware_is_before(&router.middleware[i]) {
      count = count + 1;
    };
    i = i + 1;
  };
  return count;
}

pub fn router_middleware_after_count(router: &MicroRouter) -> Int {
  var count: Int = 0;
  var i: Int = 0;
  while i < router.middleware.len() {
    if middleware_is_after(&router.middleware[i]) {
      count = count + 1;
    };
    i = i + 1;
  };
  return count;
}

pub fn router_route_with_middleware(
  router: &mut MicroRouter,
  method: HttpMethod,
  path: Str,
  handler: Str,
  mw_names: Vec[Str],
) -> MicroRoute {
  var route = router_register(router, method, path, handler);
  var i: Int = 0;
  while i < mw_names.len() {
    route.middleware.push(mw_names[i]);
    i = i + 1;
  };
  // Update the stored route with middleware
  var j: Int = router.routes.len() - 1;
  router.routes[j].middleware = route.middleware;
  return route;
}

// --- Middleware Evaluation ---------------------------------------------------

pub fn middleware_evaluate(
  middleware_list: &Vec[MicroMiddleware],
  req: &MicroRequest,
) -> MiddlewareResult {
  var i: Int = 0;
  while i < middleware_list.len() {
    if middleware_is_before(&middleware_list[i]) {
      if middleware_list[i].name == "auth" {
        var has_auth = request_has_header(req, "Authorization");
        if !has_auth {
          return MiddlewareResult{ allowed: false, message: "unauthorized" };
        };
      };
      if middleware_list[i].name == "rate-limit" {
        // Stub: rate limit check always passes
      };
    };
    i = i + 1;
  };
  return MiddlewareResult{ allowed: true, message: "" };
}

pub fn middleware_evaluate_allowed(result: &MiddlewareResult) -> Bool {
  return result.allowed;
}

// --- Router Dispatch --------------------------------------------------------

pub fn router_dispatch(
  router: &MicroRouter,
  req: &MicroRequest,
) -> MicroResponse {
  // Run before-middleware
  var mw_result = middleware_evaluate(&router.middleware, req);
  if !mw_result.allowed {
    return response_new(401);
  };

  // Match route
  var i: Int = 0;
  while i < router.routes.len() {
    if router.routes[i].method == req.method && router.routes[i].path == req.path {
      // Stub: invoke handler -- returns 200 OK with handler name echo
      return response_ok(router.routes[i].handler);
    };
    i = i + 1;
  };

  // Not found
  return response_not_found("not found");
}

// --- App Builder ------------------------------------------------------------

pub fn app_new(host: Str, port: Int) -> MicroApp
  requires: string.str_len(host) > 0
  requires: port > 0
{
  return MicroApp{
    router: router_new(),
    host: host,
    port: port,
    running: false,
    global_middleware: Vec[Str].new(),
  };
}

pub fn app_router(app: &mut MicroApp) -> &mut MicroRouter {
  return &mut app.router;
}

pub fn app_use_global_middleware(app: &mut MicroApp, name: Str) {
  app.global_middleware.push(name);
  router_use_middleware(&mut app.router, name, MiddlewarePhase.Before);
}

pub fn app_global_middleware_count(app: &MicroApp) -> Int {
  return app.global_middleware.len();
}

pub fn app_start(app: &mut MicroApp) {
  app.running = true;
}

pub fn app_stop(app: &mut MicroApp) {
  app.running = false;
}

pub fn app_is_running(app: &MicroApp) -> Bool {
  return app.running;
}

pub fn app_get(app: &mut MicroApp, path: Str, handler: Str) -> MicroRoute {
  return router_get(app_router(app), path, handler);
}

pub fn app_post(app: &mut MicroApp, path: Str, handler: Str) -> MicroRoute {
  return router_post(app_router(app), path, handler);
}

// --- Route Grouping ---------------------------------------------------------

pub fn route_group(
  router: &mut MicroRouter,
  prefix: Str,
  register_fn: Str,
) {
  // Stub: group creation -- prefix is stored for documentation/debugging
  // Actual registration of sub-routes happens via the caller chaining
  // router_get/router_post with the already-prefixed path.
}

pub fn router_group_with_prefix(router: &mut MicroRouter, prefix: Str) -> &mut MicroRouter {
  router.prefix = prefix;
  return router;
}

pub fn router_clear_prefix(router: &mut MicroRouter) {
  router.prefix = "";
}
