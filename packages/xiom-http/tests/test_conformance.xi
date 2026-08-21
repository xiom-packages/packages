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
  xiom.io.println("=== xiom-http Conformance Tests ===");

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
  results.push(test_url_to_str());
  results.push(test_path_join());
  results.push(test_http_parse_headers());
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
  match m {
    POST => { return Ok(Unit); },
    _ => { return Err("FAIL: method_from_str('POST') did not return POST"); },
  };
}

fn test_http_versions() -> Result[Unit, Str] {
  var v: HttpVersion = version_from_str("HTTP/1.1");
  match v {
    HTTP11 => { return Ok(Unit); },
    _ => { return Err("FAIL: version_from_str('HTTP/1.1') did not return HTTP11"); },
  };
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
  match req.method {
    GET => {},
    _ => { return Err("FAIL: HttpRequest.new method not GET"); },
  };
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
  resp.set_header("Server", "xiom-http");
  try(assert_true(resp.headers.has("Server"), "HttpResponse.set_header"));
  return Ok(Unit);
}

fn test_http_response_to_str() -> Result[Unit, Str] {
  var resp: HttpResponse = HttpResponse.new(200);
  var s: Str = resp.to_str();
  try(assert_true(xiom.string.str_len(s) > 0, "HttpResponse.to_str non-empty"));
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
    },
    Err(e) => { return Err("FAIL: parse_headers error: " + e.message); },
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
    Err(e) => { xiom.io.println(e); },
  };
}
