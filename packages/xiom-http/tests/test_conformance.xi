module xiom.http.tests

use xiom.http.types;
use xiom.http.status;
use xiom.http.mime;
use xiom.http.url;
use xiom.http.parser;
use xiom.http.cookie;
use xiom.http.server;
use xiom.io;
use xiom.string;
use xiom.convert;

// Assertions that fail inside a test are collected here so `run_case`
// can report them per test (the old `try()` printed and swallowed them).
var http_failures: Vec[Str] = Vec[Str].new();

fn assert_true(condition: Bool, label: Str) -> Result[Unit, Str] {
  if condition {
    return Ok(Unit);
  };
  return Err("FAIL: " + label);
}

fn assert_str_eq(actual: Str, expected: Str, label: Str) -> Result[Unit, Str] {
  if actual == expected {
    return Ok(Unit);
  };
  return Err("FAIL: " + label + " -- expected '" + expected + "', got '" + actual + "'");
}

fn assert_int_eq(actual: Int, expected: Int, label: Str) -> Result[Unit, Str] {
  if actual == expected {
    return Ok(Unit);
  };
  return Err("FAIL: " + label + " -- expected " + xiom.convert.int_to_string(expected) + ", got " + xiom.convert.int_to_string(actual));
}

fn assert_unit_err(res: Result[Unit, Str], label: Str) -> Result[Unit, Str] {
  match res {
    Ok(_) => { return Err("FAIL: " + label + " -- expected Err, got Ok"); },
    Err(_) => { return Ok(Unit); },
  };
}

pub fn run_all_tests() -> Result[Unit, Str] {
  xiom.io.println("=== xiom.http Conformance Tests ===");

  var passed: Int = 0;
  var failed: Int = 0;
  var total: Int = 0;

  var results: Vec[Result[Unit, Str]] = Vec[Result[Unit, Str]].new();
  results.push(test_http_methods());
  results.push(test_http_versions());
  results.push(test_http_headers_new_and_count());
  results.push(test_http_headers_add_and_get());
  results.push(test_http_headers_has());
  results.push(test_http_headers_remove());
  results.push(test_http_request_new());
  results.push(test_http_request_set_header());
  results.push(test_http_request_to_str());
  results.push(test_http_response_new());
  results.push(test_http_response_set_header());
  results.push(test_http_response_to_str());
  results.push(test_http_response_to_str_body_chars());
  results.push(test_http_status_text());
  results.push(test_http_is_success());
  results.push(test_http_is_redirect());
  results.push(test_http_is_client_error());
  results.push(test_http_is_server_error());
  results.push(test_http_status_category());
  results.push(test_mime_from_ext());
  results.push(test_mime_to_str());
  results.push(test_url_parse_full());
  results.push(test_url_parse_no_scheme());
  results.push(test_url_parse_with_port());
  results.push(test_url_parse_with_query());
  results.push(test_url_parse_with_fragment());
  results.push(test_url_parse_printable_ascii());
  results.push(test_url_to_str());
  results.push(test_path_join());
  results.push(test_http_parse_headers());
  results.push(test_http_parse_headers_malformed());
  results.push(test_http_parse_request_get());
  results.push(test_http_parse_request_post_body());
  results.push(test_http_parse_response_line());
  results.push(test_cookie_new());
  results.push(test_cookie_parse());
  results.push(test_cookie_to_str());
  results.push(test_cookie_parse_all());
  results.push(test_server_new());
  results.push(test_server_listen_error());
  results.push(test_server_handle_error());
  results.push(test_server_close());

  var i: Int = 0;
  while i < results.len() {
    total = total + 1;
    match results[i] {
      Ok(_) => { passed = passed + 1; },
      Err(e) => {
        failed = failed + 1;
        xiom.io.println(e);
      },
    };
    i = i + 1;
  };

  xiom.io.println("");
  xiom.io.println(xiom.convert.int_to_string(passed) + " passed, " + xiom.convert.int_to_string(failed) + " failed out of " + xiom.convert.int_to_string(total));

  if failed > 0 {
    return Err(xiom.convert.int_to_string(failed) + " test(s) failed");
  };
  return Ok(Unit);
}

// --- HttpMethod & HttpVersion ----------------------------------------------

fn test_http_methods() -> Result[Unit, Str] {
  var m: HttpMethod = method_from_str("POST");
  if m == POST { return Ok(Unit); }
  return Err("FAIL: method_from_str('POST') did not return POST");
}

fn test_http_versions() -> Result[Unit, Str] {
  var v: HttpVersion = version_from_str("HTTP/1.1");
  if v == HTTP11 { return Ok(Unit); }
  return Err("FAIL: version_from_str('HTTP/1.1') did not return HTTP11");
}

// --- HttpHeaders -----------------------------------------------------------

fn test_http_headers_new_and_count() -> Result[Unit, Str] {
  var h: HttpHeaders = HttpHeaders.new();
  try(assert_int_eq(h.count(), 0, "HttpHeaders.new().count() == 0"));
  return Ok(Unit);
}

fn test_http_headers_add_and_get() -> Result[Unit, Str] {
  var h: HttpHeaders = HttpHeaders.new();
  h.add("Content-Type", "text/html");
  try(assert_int_eq(h.count(), 1, "HttpHeaders.add + count == 1"));
  match h.get("Content-Type") {
    Some(v) => { try(assert_str_eq(v, "text/html", "HttpHeaders.get Content-Type")); },
    None => { return Err("FAIL: HttpHeaders.get returned None for existing header"); },
  };
  match h.get("X-Missing") {
    Some(_) => { return Err("FAIL: HttpHeaders.get returned Some for missing header"); },
    None => {},
  };
  return Ok(Unit);
}

fn test_http_headers_has() -> Result[Unit, Str] {
  var h: HttpHeaders = HttpHeaders.new();
  h.add("Host", "example.com");
  try(assert_true(h.has("Host"), "HttpHeaders.has Host"));
  try(assert_true(!h.has("X-Nonexistent"), "HttpHeaders.has X-Nonexistent"));
  return Ok(Unit);
}

fn test_http_headers_remove() -> Result[Unit, Str] {
  var h: HttpHeaders = HttpHeaders.new();
  h.add("A", "1");
  h.add("B", "2");
  h.add("A", "3");
  try(assert_int_eq(h.count(), 3, "HttpHeaders: count == 3 before remove"));
  var removed: Bool = h.remove_header("A");
  try(assert_true(removed, "HttpHeaders.remove_header returned true"));
  try(assert_int_eq(h.count(), 2, "HttpHeaders: count == 2 after remove"));
  try(assert_true(!h.has("A"), "HttpHeaders: A removed"));
  try(assert_true(h.has("B"), "HttpHeaders: B remains"));
  return Ok(Unit);
}

// --- HttpRequest -----------------------------------------------------------

fn test_http_request_new() -> Result[Unit, Str] {
  var req: HttpRequest = HttpRequest.new(GET, "/api/test");
  try(assert_str_eq(req.path, "/api/test", "HttpRequest.new path"));
  if req.method != GET {
    return Err("FAIL: HttpRequest.new method not GET");
  }
  return Ok(Unit);
}

fn test_http_request_set_header() -> Result[Unit, Str] {
  var req: HttpRequest = HttpRequest.new(POST, "/submit");
  req.set_header("Content-Type", "application/json");
  try(assert_true(req.headers.has("Content-Type"), "HttpRequest.set_header"));
  return Ok(Unit);
}

fn test_http_request_to_str() -> Result[Unit, Str] {
  var req: HttpRequest = HttpRequest.new(GET, "/");
  var s: Str = req.to_str();
  try(assert_true(xiom.string.str_len(s) > 0, "HttpRequest.to_str non-empty"));
  try(assert_true(xiom.string.str_len(s) >= 14, "HttpRequest.to_str minimum length"));
  return Ok(Unit);
}

// --- HttpResponse ----------------------------------------------------------

fn test_http_response_new() -> Result[Unit, Str] {
  var resp: HttpResponse = HttpResponse.new(200);
  try(assert_int_eq(resp.status, 200, "HttpResponse.new status"));
  return Ok(Unit);
}

fn test_http_response_set_header() -> Result[Unit, Str] {
  var resp: HttpResponse = HttpResponse.new(200);
  resp.set_header("Server", "xiom.http");
  try(assert_true(resp.headers.has("Server"), "HttpResponse.set_header"));
  return Ok(Unit);
}

fn test_http_response_to_str() -> Result[Unit, Str] {
  var resp: HttpResponse = HttpResponse.new(200);
  var s: Str = resp.to_str();
  try(assert_true(xiom.string.str_len(s) > 0, "HttpResponse.to_str non-empty"));
  return Ok(Unit);
}

fn test_http_response_to_str_body_chars() -> Result[Unit, Str] {
  var resp: HttpResponse = HttpResponse.new(200);
  var body: Vec[Int] = Vec[Int].new();
  body.push(126);
  body.push(124);
  resp.set_body(body);
  var s: Str = resp.to_str();
  try(assert_str_eq(s, "HTTP/1.1 200 \r\n\r\n~|", "HttpResponse.to_str body renders '~|' as characters"));
  return Ok(Unit);
}

// --- Status Codes ----------------------------------------------------------

fn test_http_status_text() -> Result[Unit, Str] {
  try(assert_str_eq(http_status_text(200), "OK", "status_text(200)"));
  try(assert_str_eq(http_status_text(404), "Not Found", "status_text(404)"));
  try(assert_str_eq(http_status_text(500), "Internal Server Error", "status_text(500)"));
  try(assert_str_eq(http_status_text(999), "Unknown", "status_text(999) unknown"));
  try(assert_str_eq(http_status_text(100), "Continue", "status_text(100)"));
  try(assert_str_eq(http_status_text(301), "Moved Permanently", "status_text(301)"));
  try(assert_str_eq(http_status_text(0), "Unknown", "status_text(0) boundary"));
  return Ok(Unit);
}

fn test_http_is_success() -> Result[Unit, Str] {
  try(assert_true(http_is_success(200), "is_success 200"));
  try(assert_true(http_is_success(299), "is_success 299"));
  try(assert_true(!http_is_success(199), "is_success 199"));
  try(assert_true(!http_is_success(300), "is_success 300"));
  try(assert_true(!http_is_success(0), "is_success 0"));
  return Ok(Unit);
}

fn test_http_is_redirect() -> Result[Unit, Str] {
  try(assert_true(http_is_redirect(301), "is_redirect 301"));
  try(assert_true(http_is_redirect(399), "is_redirect 399"));
  try(assert_true(!http_is_redirect(299), "is_redirect 299"));
  try(assert_true(!http_is_redirect(400), "is_redirect 400"));
  return Ok(Unit);
}

fn test_http_is_client_error() -> Result[Unit, Str] {
  try(assert_true(http_is_client_error(400), "is_client_error 400"));
  try(assert_true(http_is_client_error(404), "is_client_error 404"));
  try(assert_true(http_is_client_error(499), "is_client_error 499"));
  try(assert_true(!http_is_client_error(399), "is_client_error 399"));
  try(assert_true(!http_is_client_error(500), "is_client_error 500"));
  return Ok(Unit);
}

fn test_http_is_server_error() -> Result[Unit, Str] {
  try(assert_true(http_is_server_error(500), "is_server_error 500"));
  try(assert_true(http_is_server_error(503), "is_server_error 503"));
  try(assert_true(http_is_server_error(599), "is_server_error 599"));
  try(assert_true(!http_is_server_error(499), "is_server_error 499"));
  try(assert_true(!http_is_server_error(600), "is_server_error 600"));
  return Ok(Unit);
}

fn test_http_status_category() -> Result[Unit, Str] {
  try(assert_int_eq(http_status_category(200), 200, "category 200"));
  try(assert_int_eq(http_status_category(404), 400, "category 404"));
  try(assert_int_eq(http_status_category(500), 500, "category 500"));
  try(assert_int_eq(http_status_category(301), 300, "category 301"));
  try(assert_int_eq(http_status_category(101), 100, "category 101"));
  try(assert_int_eq(http_status_category(999), 0, "category 999"));
  try(assert_int_eq(http_status_category(0), 0, "category 0"));
  return Ok(Unit);
}

// --- MIME Types ------------------------------------------------------------

fn test_mime_from_ext() -> Result[Unit, Str] {
  var m1: MimeType = mime_from_ext(".html");
  try(assert_str_eq(m1.main_type, "text", "mime .html main"));
  try(assert_str_eq(m1.sub_type, "html", "mime .html sub"));

  var m2: MimeType = mime_from_ext(".json");
  try(assert_str_eq(m2.main_type, "application", "mime .json main"));
  try(assert_str_eq(m2.sub_type, "json", "mime .json sub"));

  var m3: MimeType = mime_from_ext(".unknown_ext");
  try(assert_str_eq(m3.main_type, "application", "mime unknown main"));
  try(assert_str_eq(m3.sub_type, "octet-stream", "mime unknown sub"));

  var m4: MimeType = mime_from_ext(".png");
  try(assert_str_eq(m4.main_type, "image", "mime .png main"));
  try(assert_str_eq(m4.sub_type, "png", "mime .png sub"));

  var m5: MimeType = mime_from_ext("");
  try(assert_str_eq(m5.main_type, "application", "mime empty main"));
  try(assert_str_eq(m5.sub_type, "octet-stream", "mime empty sub"));
  return Ok(Unit);
}

fn test_mime_to_str() -> Result[Unit, Str] {
  var m: MimeType = MimeType{ main_type: "text", sub_type: "html" };
  try(assert_str_eq(mime_to_str(&m), "text/html", "mime_to_str"));
  return Ok(Unit);
}

// --- URL Parsing -----------------------------------------------------------

fn test_url_parse_full() -> Result[Unit, Str] {
  var res: Result[Url, Str] = url_parse("https://example.com/path/to/resource?q=1#frag");
  match res {
    Ok(u) => {
      try(assert_str_eq(u.scheme, "https", "url scheme"));
      try(assert_str_eq(u.host, "example.com", "url host"));
      try(assert_int_eq(u.port, 443, "url port (https default)"));
      try(assert_str_eq(u.path, "/path/to/resource", "url path"));
      try(assert_str_eq(u.query, "q=1", "url query"));
      try(assert_str_eq(u.fragment, "frag", "url fragment"));
    },
    Err(e) => {
      return Err("FAIL: url_parse full: " + e);
    },
  };
  return Ok(Unit);
}

fn test_url_parse_no_scheme() -> Result[Unit, Str] {
  var res: Result[Url, Str] = url_parse("example.com/about");
  match res {
    Ok(u) => {
      try(assert_str_eq(u.scheme, "", "url no-scheme scheme"));
      try(assert_str_eq(u.host, "example.com", "url no-scheme host"));
      try(assert_str_eq(u.path, "/about", "url no-scheme path"));
      try(assert_int_eq(u.port, 0, "url no-scheme port"));
    },
    Err(e) => { return Err("FAIL: url_parse no-scheme: " + e); },
  };
  return Ok(Unit);
}

fn test_url_parse_with_port() -> Result[Unit, Str] {
  var res: Result[Url, Str] = url_parse("http://localhost:8080/api");
  match res {
    Ok(u) => {
      try(assert_str_eq(u.scheme, "http", "url port scheme"));
      try(assert_str_eq(u.host, "localhost", "url port host"));
      try(assert_int_eq(u.port, 8080, "url port explicit"));
      try(assert_str_eq(u.path, "/api", "url port path"));
    },
    Err(e) => { return Err("FAIL: url_parse port: " + e); },
  };
  return Ok(Unit);
}

fn test_url_parse_with_query() -> Result[Unit, Str] {
  var res: Result[Url, Str] = url_parse("https://api.example.com/search?q=xiom&page=2");
  match res {
    Ok(u) => {
      try(assert_str_eq(u.query, "q=xiom&page=2", "url query multi"));
    },
    Err(e) => { return Err("FAIL: url_parse query: " + e); },
  };
  return Ok(Unit);
}

fn test_url_parse_with_fragment() -> Result[Unit, Str] {
  var res: Result[Url, Str] = url_parse("https://docs.example.com/spec#section-3");
  match res {
    Ok(u) => {
      try(assert_str_eq(u.fragment, "section-3", "url fragment"));
    },
    Err(e) => { return Err("FAIL: url_parse fragment: " + e); },
  };
  return Ok(Unit);
}

fn test_url_parse_printable_ascii() -> Result[Unit, Str] {
  var res: Result[Url, Str] = url_parse("https://example.com/a~b|c{d} e");
  match res {
    Ok(u) => {
      try(assert_str_eq(u.path, "/a~b|c{d} e", "url path renders printable ASCII '~|{}' as characters"));
      try(assert_str_eq(u.host, "example.com", "url printable-ascii host"));
    },
    Err(e) => { return Err("FAIL: url_parse printable ascii: " + e); },
  };
  return Ok(Unit);
}

fn test_url_to_str() -> Result[Unit, Str] {
  var u: Url = Url{
    scheme: "https",
    host: "example.com",
    port: 443,
    path: "/test",
    query: "",
    fragment: "",
  };
  var s: Str = url_to_str(&u);
  try(assert_str_eq(s, "https://example.com/test", "url_to_str basic"));
  return Ok(Unit);
}

fn test_path_join() -> Result[Unit, Str] {
  try(assert_str_eq(path_join("/api/v1", "users"), "/api/v1/users", "path_join basic"));
  try(assert_str_eq(path_join("/api/v1/", "users"), "/api/v1/users", "path_join trailing slash"));
  try(assert_str_eq(path_join("/api/v1", ""), "/api/v1", "path_join empty relative"));
  try(assert_str_eq(path_join("", "users"), "users", "path_join empty base"));
  try(assert_str_eq(path_join("/base", "/absolute"), "/absolute", "path_join absolute relative"));
  return Ok(Unit);
}

// --- Header Parsing --------------------------------------------------------

fn test_http_parse_headers() -> Result[Unit, Str] {
  var input: Str = "Content-Type: text/html\r\nServer: xiom\r\n\r\n";
  var res: Result[HttpHeaders, HttpParseError] = http_parse_headers(input);
  match res {
    Ok(h) => {
      try(assert_int_eq(h.count(), 2, "parse_headers count"));
      try(assert_true(h.has("Content-Type"), "parse_headers Content-Type"));
      try(assert_true(h.has("Server"), "parse_headers Server"));
      match h.get("Content-Type") {
        Some(v) => { try(assert_str_eq(v, "text/html", "parse_headers Content-Type value")); },
        None => { return Err("FAIL: parse_headers Content-Type missing"); },
      };
      match h.get("Server") {
        Some(v) => { try(assert_str_eq(v, "xiom", "parse_headers Server value")); },
        None => { return Err("FAIL: parse_headers Server missing"); },
      };
    },
    Err(e) => { return Err("FAIL: parse_headers error: " + e.message); },
  };
  return Ok(Unit);
}

fn test_http_parse_headers_malformed() -> Result[Unit, Str] {
  var input: Str = "BadHeader\r\n\r\n";
  var res: Result[HttpHeaders, HttpParseError] = http_parse_headers(input);
  match res {
    Ok(_) => { return Err("FAIL: parse_headers malformed -- expected Err, got Ok"); },
    Err(e) => { try(assert_str_eq(e.message, "Invalid header line: no colon found", "parse_headers malformed message")); },
  };
  return Ok(Unit);
}

fn test_http_parse_request_get() -> Result[Unit, Str] {
  var input: Str = "GET /hello HTTP/1.1\r\nHost: x\r\n\r\n";
  var res: Result[HttpRequest, HttpParseError] = http_parse_request(input);
  match res {
    Ok(req) => {
      if req.method != GET { return Err("FAIL: parse_request GET method"); };
      try(assert_str_eq(req.path, "/hello", "parse_request GET path"));
      if req.version != HTTP11 { return Err("FAIL: parse_request GET version"); };
      try(assert_int_eq(req.headers.count(), 1, "parse_request GET header count"));
      match req.headers.get("Host") {
        Some(v) => { try(assert_str_eq(v, "x", "parse_request GET Host value")); },
        None => { return Err("FAIL: parse_request GET Host missing"); },
      };
      try(assert_int_eq(req.body.len(), 0, "parse_request GET body length"));
    },
    Err(e) => { return Err("FAIL: parse_request GET: " + e.message); },
  };
  return Ok(Unit);
}

fn test_http_parse_request_post_body() -> Result[Unit, Str] {
  var input: Str = "POST /submit HTTP/1.1\r\nHost: x\r\n\r\nhello";
  var res: Result[HttpRequest, HttpParseError] = http_parse_request(input);
  match res {
    Ok(req) => {
      if req.method != POST { return Err("FAIL: parse_request POST method"); };
      try(assert_int_eq(req.body.len(), 5, "parse_request POST body length"));
      try(assert_int_eq(req.body[0], 104, "parse_request POST body[0] 'h'"));
      try(assert_int_eq(req.body[1], 101, "parse_request POST body[1] 'e'"));
      try(assert_int_eq(req.body[2], 108, "parse_request POST body[2] 'l'"));
      try(assert_int_eq(req.body[3], 108, "parse_request POST body[3] 'l'"));
      try(assert_int_eq(req.body[4], 111, "parse_request POST body[4] 'o'"));
    },
    Err(e) => { return Err("FAIL: parse_request POST: " + e.message); },
  };
  return Ok(Unit);
}

fn test_http_parse_response_line() -> Result[Unit, Str] {
  var input: Str = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi";
  var res: Result[HttpResponse, HttpParseError] = http_parse_response(input);
  match res {
    Ok(resp) => {
      try(assert_int_eq(resp.status, 200, "parse_response status"));
      try(assert_str_eq(resp.reason, "OK", "parse_response reason"));
      match resp.headers.get("Content-Length") {
        Some(v) => { try(assert_str_eq(v, "2", "parse_response Content-Length value")); },
        None => { return Err("FAIL: parse_response Content-Length missing"); },
      };
      try(assert_int_eq(resp.body.len(), 2, "parse_response body length"));
      try(assert_int_eq(resp.body[0], 104, "parse_response body[0] 'h'"));
      try(assert_int_eq(resp.body[1], 105, "parse_response body[1] 'i'"));
    },
    Err(e) => { return Err("FAIL: parse_response: " + e.message); },
  };
  return Ok(Unit);
}

// --- Cookie Handling -------------------------------------------------------

fn test_cookie_new() -> Result[Unit, Str] {
  var c: Cookie = cookie_new("session", "abc123");
  try(assert_str_eq(c.name, "session", "cookie_new name"));
  try(assert_str_eq(c.value, "abc123", "cookie_new value"));
  try(assert_str_eq(c.path, "/", "cookie_new default path"));
  try(assert_true(!c.secure, "cookie_new default secure"));
  try(assert_true(!c.http_only, "cookie_new default http_only"));
  try(assert_int_eq(c.max_age, -1, "cookie_new default max_age"));
  return Ok(Unit);
}

fn test_cookie_parse() -> Result[Unit, Str] {
  var res: Result[Cookie, Str] = cookie_parse("sid=xyz789; Secure; HttpOnly; Path=/admin; Max-Age=3600");
  match res {
    Ok(c) => {
      try(assert_str_eq(c.name, "sid", "cookie_parse name"));
      try(assert_str_eq(c.value, "xyz789", "cookie_parse value"));
      try(assert_true(c.secure, "cookie_parse secure"));
      try(assert_true(c.http_only, "cookie_parse http_only"));
      try(assert_str_eq(c.path, "/admin", "cookie_parse path"));
      try(assert_int_eq(c.max_age, 3600, "cookie_parse max_age"));
    },
    Err(e) => { return Err("FAIL: cookie_parse: " + e); },
  };
  return Ok(Unit);
}

fn test_cookie_to_str() -> Result[Unit, Str] {
  var c: Cookie = cookie_new("token", "deadbeef");
  c.secure = true;
  c.http_only = true;
  c.max_age = 7200;
  var s: Str = cookie_to_str(&c);
  try(assert_true(xiom.string.str_len(s) > 0, "cookie_to_str non-empty"));
  try(assert_true(xiom.string.str_len(s) >= 18, "cookie_to_str minimum length"));
  return Ok(Unit);
}

fn test_cookie_parse_all() -> Result[Unit, Str] {
  var cookies: Vec[Cookie] = cookie_parse_all("a=1; b=2; c=3");
  try(assert_int_eq(cookies.len(), 3, "cookie_parse_all count"));
  try(assert_str_eq(cookies[0].name, "a", "cookie_parse_all[0].name"));
  try(assert_str_eq(cookies[1].value, "2", "cookie_parse_all[1].value"));
  try(assert_str_eq(cookies[2].name, "c", "cookie_parse_all[2].name"));
  return Ok(Unit);
}

// --- Server Error Paths ----------------------------------------------------

fn test_server_new() -> Result[Unit, Str] {
  var s: HttpServer = server_new("127.0.0.1", 8080);
  try(assert_str_eq(s.addr, "127.0.0.1", "server_new addr"));
  try(assert_int_eq(s.port, 8080, "server_new port"));
  try(assert_true(!s.running, "server_new running == false"));
  return Ok(Unit);
}

fn test_server_listen_error() -> Result[Unit, Str] {
  var s: HttpServer = server_new("127.0.0.1", 9090);
  var res: Result[Unit, Str] = server_listen(&mut s);
  try(assert_unit_err(res, "server_listen returns Err"));
  return Ok(Unit);
}

fn test_server_handle_error() -> Result[Unit, Str] {
  var s: HttpServer = server_new("127.0.0.1", 9090);
  var res: Result[Unit, Str] = server_handle(&mut s, GET, "/api");
  try(assert_unit_err(res, "server_handle returns Err"));
  return Ok(Unit);
}

fn test_server_close() -> Result[Unit, Str] {
  var s: HttpServer = server_new("0.0.0.0", 3000);
  server_close(s);
  return Ok(Unit);
}

fn try(res: Result[Unit, Str]) {
  match res {
    Ok(_) => {},
    Err(e) => { http_failures.push(e); },
  };
}

fn run_case(label: Str, res: Result[Unit, Str]) -> Int {
  let before: Int = http_failures.len();
  match res {
    Ok(_) => {},
    Err(e) => { http_failures.push(e); },
  };
  let added: Int = http_failures.len() - before;
  if added == 0 {
    xiom.io.println("[PASS] " + label);
    return 0;
  }
  var k: Int = before;
  while k < http_failures.len() {
    xiom.io.println("[FAIL] " + label + " -- " + http_failures[k]);
    k = k + 1;
  }
  return 1;
}

fn main() -> Int {
  var failures: Int = 0;
  failures = failures + run_case("http methods", test_http_methods());
  failures = failures + run_case("http versions", test_http_versions());
  failures = failures + run_case("headers new and count", test_http_headers_new_and_count());
  failures = failures + run_case("headers add and get", test_http_headers_add_and_get());
  failures = failures + run_case("headers has", test_http_headers_has());
  failures = failures + run_case("headers remove", test_http_headers_remove());
  failures = failures + run_case("request new", test_http_request_new());
  failures = failures + run_case("request set_header", test_http_request_set_header());
  failures = failures + run_case("request to_str", test_http_request_to_str());
  failures = failures + run_case("response new", test_http_response_new());
  failures = failures + run_case("response set_header", test_http_response_set_header());
  failures = failures + run_case("response to_str", test_http_response_to_str());
  failures = failures + run_case("response to_str body chars", test_http_response_to_str_body_chars());
  failures = failures + run_case("status text", test_http_status_text());
  failures = failures + run_case("status is_success", test_http_is_success());
  failures = failures + run_case("status is_redirect", test_http_is_redirect());
  failures = failures + run_case("status is_client_error", test_http_is_client_error());
  failures = failures + run_case("status is_server_error", test_http_is_server_error());
  failures = failures + run_case("status category", test_http_status_category());
  failures = failures + run_case("mime from_ext", test_mime_from_ext());
  failures = failures + run_case("mime to_str", test_mime_to_str());
  failures = failures + run_case("url parse full", test_url_parse_full());
  failures = failures + run_case("url parse no scheme", test_url_parse_no_scheme());
  failures = failures + run_case("url parse with port", test_url_parse_with_port());
  failures = failures + run_case("url parse with query", test_url_parse_with_query());
  failures = failures + run_case("url parse with fragment", test_url_parse_with_fragment());
  failures = failures + run_case("url parse printable ascii", test_url_parse_printable_ascii());
  failures = failures + run_case("url to_str", test_url_to_str());
  failures = failures + run_case("path join", test_path_join());
  failures = failures + run_case("parse headers", test_http_parse_headers());
  failures = failures + run_case("parse headers malformed", test_http_parse_headers_malformed());
  failures = failures + run_case("parse request GET", test_http_parse_request_get());
  failures = failures + run_case("parse request POST body", test_http_parse_request_post_body());
  failures = failures + run_case("parse response line", test_http_parse_response_line());
  failures = failures + run_case("cookie new", test_cookie_new());
  failures = failures + run_case("cookie parse", test_cookie_parse());
  failures = failures + run_case("cookie to_str", test_cookie_to_str());
  failures = failures + run_case("cookie parse_all", test_cookie_parse_all());
  failures = failures + run_case("server new", test_server_new());
  failures = failures + run_case("server listen error", test_server_listen_error());
  failures = failures + run_case("server handle error", test_server_handle_error());
  failures = failures + run_case("server close", test_server_close());
  xiom.io.println("xiom.http: " + xiom.convert.int_to_string(42 - failures) + "/42 passed");
  return failures;
}
