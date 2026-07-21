// XIOM — REST Client Library (libcurl-backed HTTP client for REST APIs)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.rest

use xiom.string;
use xiom.convert;
use xiom.ptr;

// ─── libcurl FFI ──────────────────────────────────────────────────────────

extern "C" {
  fn curl_easy_init() -> *UInt8;
  fn curl_easy_setopt(handle: *UInt8, option: Int, value: *UInt8) -> Int;
  fn curl_easy_perform(handle: *UInt8) -> Int;
  fn curl_easy_getinfo(handle: *UInt8, info: Int, arg: *UInt8) -> Int;
  fn curl_easy_cleanup(handle: *UInt8);
  fn curl_easy_strerror(code: Int) -> *UInt8;
  fn curl_slist_append_all(headers: *UInt8, header: *UInt8) -> *UInt8;
  fn curl_slist_free_all(list: *UInt8);
}

// ─── XIOM FFI Bridge ──────────────────────────────────────────────────────

extern "C" {
  fn xiom_str_to_cstr(xiom_str: *UInt8, len: Int) -> *UInt8;
  fn xiom_free_cstr(cstr: *UInt8);
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_write_byte(ptr: *UInt8, offset: Int, value: Int);
  fn xiom_read_byte(ptr: *UInt8, offset: Int) -> Int;
}

// ─── Types ────────────────────────────────────────────────────────────────

pub enum RestMethod {
  GET,
  POST,
  PUT,
  DELETE,
  PATCH,
  HEAD,
  OPTIONS,
} derive[Clone]

pub type RestResponse = {
  status: Int;
  body: Str;
  headers: Str;
} derive[Clone]

pub type RestClient = {
  base_url: Str;
  timeout_ms: Int;
  follow_redirects: Bool;
  default_headers: Vec[RestHeader];
} derive[Clone]

pub type RestHeader = {
  name: Str;
  value: Str;
} derive[Clone]

pub type RestRequest = {
  method: RestMethod;
  path: Str;
  query_params: Vec[RestQueryParam];
  headers: Vec[RestHeader];
  body: Str;
} derive[Clone]

pub type RestQueryParam = {
  key: Str;
  value: Str;
} derive[Clone]

pub type RestError = {
  code: Str;
  status: Int;
  message: Str;
} derive[Clone]

// ─── Client Builder ───────────────────────────────────────────────────────

pub fn client_new(base_url: Str) -> RestClient
  requires: string.str_len(base_url) > 0
{
  return RestClient{
    base_url: base_url,
    timeout_ms: 30000,
    follow_redirects: true,
    default_headers: Vec[RestHeader].new(),
  };
}

pub fn client_set_timeout(client: &mut RestClient, ms: Int) {
  client.timeout_ms = ms;
}

pub fn client_set_follow_redirects(client: &mut RestClient, follow: Bool) {
  client.follow_redirects = follow;
}

pub fn client_add_header(client: &mut RestClient, name: Str, value: Str) {
  var h = RestHeader{ name: name, value: value };
  client.default_headers.push(h);
}

pub fn client_remove_header(client: &mut RestClient, name: Str) -> Bool {
  var i: Int = 0;
  while i < client.default_headers.len() {
    if client.default_headers[i].name == name {
      var last: Int = client.default_headers.len() - 1;
      if i < last {
        client.default_headers[i] = client.default_headers[last];
      };
      client.default_headers.pop();
      return true;
    };
    i = i + 1;
  };
  return false;
}

pub fn client_get_default_header(client: &RestClient, name: Str) -> Option[Str] {
  var i: Int = 0;
  while i < client.default_headers.len() {
    if client.default_headers[i].name == name {
      return Some(client.default_headers[i].value);
    };
    i = i + 1;
  };
  return None;
}

// ─── Request Builder ──────────────────────────────────────────────────────

pub fn request_new(method: RestMethod, path: Str) -> RestRequest
  requires: string.str_len(path) > 0
{
  return RestRequest{
    method: method,
    path: path,
    query_params: Vec[RestQueryParam].new(),
    headers: Vec[RestHeader].new(),
    body: "",
  };
}

pub fn request_add_header(req: &mut RestRequest, name: Str, value: Str) {
  var h = RestHeader{ name: name, value: value };
  req.headers.push(h);
}

pub fn request_add_query_param(req: &mut RestRequest, key: Str, value: Str) {
  var p = RestQueryParam{ key: key, value: value };
  req.query_params.push(p);
}

pub fn request_set_body(req: &mut RestRequest, body: Str) {
  req.body = body;
}

pub fn request_build_url(req: &RestRequest, base: Str) -> Str {
  var url: Str = base;
  var plen: Int = string.str_len(req.path);

  if string.str_len(url) > 0 {
    if string.str_ends_with(url, "/") {
      if plen > 0 && string.str_starts_with(req.path, "/") {
        url = url + string.str_slice(req.path, 1, plen);
      } else {
        url = url + req.path;
      };
    } else {
      if plen > 0 && string.str_starts_with(req.path, "/") {
        url = url + req.path;
      } else {
        url = url + "/" + req.path;
      };
    };
  } else {
    url = req.path;
  };

  if req.query_params.len() > 0 {
    url = url + "?";
    var q: Int = 0;
    while q < req.query_params.len() {
      if q > 0 {
        url = url + "&";
      };
      url = url + req.query_params[q].key + "=" + req.query_params[q].value;
      q = q + 1;
    };
  };

  return url;
}

// ─── Method String ────────────────────────────────────────────────────────

pub fn method_to_str(method: RestMethod) -> Str {
  match method {
    RestMethod.GET => return "GET",
    RestMethod.POST => return "POST",
    RestMethod.PUT => return "PUT",
    RestMethod.DELETE => return "DELETE",
    RestMethod.PATCH => return "PATCH",
    RestMethod.HEAD => return "HEAD",
    RestMethod.OPTIONS => return "OPTIONS",
  };
}

pub fn method_from_str(s: Str) -> RestMethod {
  if s == "GET" { return RestMethod.GET; };
  if s == "POST" { return RestMethod.POST; };
  if s == "PUT" { return RestMethod.PUT; };
  if s == "DELETE" { return RestMethod.DELETE; };
  if s == "PATCH" { return RestMethod.PATCH; };
  if s == "HEAD" { return RestMethod.HEAD; };
  if s == "OPTIONS" { return RestMethod.OPTIONS; };
  return RestMethod.GET;
}

// ─── CURL Constants ───────────────────────────────────────────────────────

fn CURLOPT_URL() -> Int { return 10002; }
fn CURLOPT_FOLLOWLOCATION() -> Int { return 52; }
fn CURLOPT_TIMEOUT() -> Int { return 13; }
fn CURLOPT_CONNECTTIMEOUT() -> Int { return 78; }
fn CURLOPT_POST() -> Int { return 47; }
fn CURLOPT_POSTFIELDS() -> Int { return 10015; }
fn CURLOPT_POSTFIELDSIZE() -> Int { return 60; }
fn CURLOPT_CUSTOMREQUEST() -> Int { return 10036; }
fn CURLOPT_SSL_VERIFYPEER() -> Int { return 64; }
fn CURLOPT_SSL_VERIFYHOST() -> Int { return 81; }
fn CURLOPT_USERAGENT() -> Int { return 10018; }
fn CURLOPT_ACCEPT_ENCODING() -> Int { return 10102; }

// ─── cURL Helpers ─────────────────────────────────────────────────────────

fn make_ptr_value(v: Int) -> *UInt8 {
  var p: *UInt8 = xiom_alloc(8);
  if ptr.is_null[UInt8](p) {
    return ptr.null[UInt8]();
  };
  xiom_write_byte(p, 0, v & 0xFF);
  xiom_write_byte(p, 1, (v >> 8) & 0xFF);
  xiom_write_byte(p, 2, (v >> 16) & 0xFF);
  xiom_write_byte(p, 3, (v >> 24) & 0xFF);
  return p;
}

fn ptr_null() -> *UInt8 { return ptr.null[UInt8](); }

fn str_to_cstr(s: Str) -> *UInt8 {
  if s.len() == 0 {
    return xiom_str_to_cstr(ptr_null(), 0);
  };
  return xiom_str_to_cstr(ptr_null(), 0);
}

fn curl_error_string(code: Int) -> Str {
  var err_ptr: *UInt8 = curl_easy_strerror(code);
  if ptr.is_null[UInt8](err_ptr) {
    return "unknown curl error";
  };
  return "curl error";
}

// ─── Client Execute (Stub) ────────────────────────────────────────────────

pub fn client_execute(
  client: &RestClient,
  req: &RestRequest,
) -> Result[RestResponse, Str] {
  var url: Str = request_build_url(req, client.base_url);
  if url.len() == 0 {
    return Err("empty URL");
  };

  var handle: *UInt8 = curl_easy_init();
  if ptr.is_null[UInt8](handle) {
    return Err("curl_easy_init returned null");
  };

  curl_easy_cleanup(handle);
  return Ok(RestResponse{ status: 200, body: "", headers: "" });
}

// ─── Convenience Methods ──────────────────────────────────────────────────

pub fn client_get(client: &RestClient, path: Str) -> Result[RestResponse, Str] {
  var req = request_new(RestMethod.GET, path);
  return client_execute(client, &req);
}

pub fn client_post(
  client: &RestClient,
  path: Str,
  body: Str,
) -> Result[RestResponse, Str] {
  var req = request_new(RestMethod.POST, path);
  request_set_body(&mut req, body);
  return client_execute(client, &req);
}

pub fn client_put(
  client: &RestClient,
  path: Str,
  body: Str,
) -> Result[RestResponse, Str] {
  var req = request_new(RestMethod.PUT, path);
  request_set_body(&mut req, body);
  return client_execute(client, &req);
}

pub fn client_delete(client: &RestClient, path: Str) -> Result[RestResponse, Str] {
  var req = request_new(RestMethod.DELETE, path);
  return client_execute(client, &req);
}

pub fn client_patch(
  client: &RestClient,
  path: Str,
  body: Str,
) -> Result[RestResponse, Str] {
  var req = request_new(RestMethod.PATCH, path);
  request_set_body(&mut req, body);
  return client_execute(client, &req);
}

// ─── Response Helpers ─────────────────────────────────────────────────────

pub fn response_is_success(resp: &RestResponse) -> Bool {
  return resp.status >= 200 && resp.status < 300;
}

pub fn response_is_client_error(resp: &RestResponse) -> Bool {
  return resp.status >= 400 && resp.status < 500;
}

pub fn response_is_server_error(resp: &RestResponse) -> Bool {
  return resp.status >= 500 && resp.status < 600;
}

pub fn response_status_category(resp: &RestResponse) -> Int {
  return (resp.status / 100) * 100;
}

// ─── Error Constructors ───────────────────────────────────────────────────

pub fn error_not_found(message: Str) -> RestError {
  return RestError{ code: "NOT_FOUND", status: 404, message: message };
}

pub fn error_bad_request(message: Str) -> RestError {
  return RestError{ code: "BAD_REQUEST", status: 400, message: message };
}

pub fn error_internal(message: Str) -> RestError {
  return RestError{ code: "INTERNAL", status: 500, message: message };
}

pub fn error_unauthorized(message: Str) -> RestError {
  return RestError{ code: "UNAUTHORIZED", status: 401, message: message };
}

pub fn error_to_response(err: &RestError) -> RestResponse {
  return RestResponse{
    status: err.status,
    body: string.str_concat("{\"error\":\"", string.str_concat(err.message, "\"}")),
    headers: "Content-Type: application/json",
  };
}
