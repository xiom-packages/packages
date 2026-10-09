module xiom.http.types

use xiom.string;
use xiom.convert;
use xiom.convert.tostring;

pub enum HttpMethod {
  GET,
  POST,
  PUT,
  DELETE,
  PATCH,
  HEAD,
  OPTIONS,
}

pub enum HttpVersion {
  HTTP09,
  HTTP10,
  HTTP11,
  HTTP20,
}

pub type HttpHeader = {
  name: Str;
  value: Str;
}

pub type HttpHeaders = {
  entries: Vec[HttpHeader];
}

pub type HttpRequest = {
  method: HttpMethod;
  path: Str;
  version: HttpVersion;
  headers: HttpHeaders;
  body: Vec[Int];
}

pub type HttpResponse = {
  version: HttpVersion;
  status: Int;
  reason: Str;
  headers: HttpHeaders;
  body: Vec[Int];
}

pub fn HttpHeaders.new() -> HttpHeaders {
  return HttpHeaders{ entries: Vec[HttpHeader].new() };
}

pub fn HttpHeaders.add(name: Str, value: Str)
  requires: name.len() > 0 {
  entries.push(HttpHeader{ name: name, value: value });
}

pub fn HttpHeaders.get(name: Str) -> Option[Str]
  requires: name.len() > 0 {
  var i: Int = 0;
  while i < entries.len() {
    if entries[i].name == name {
      return Some(entries[i].value);
    }
    i = i + 1;
  }
  return None;
}

pub fn HttpHeaders.has(name: Str) -> Bool
  requires: name.len() > 0 {
  var i: Int = 0;
  while i < entries.len() {
    if entries[i].name == name {
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn HttpHeaders.remove_header(name: Str) -> Bool
  requires: name.len() > 0 {
  var new_entries: Vec[HttpHeader] = Vec[HttpHeader].new();
  var i: Int = 0;
  var found: Bool = false;
  while i < entries.len() {
    if !found && entries[i].name == name {
      found = true;
    } else {
      new_entries.push(entries[i]);
    };
    i = i + 1;
  };
  entries = new_entries;
  return found;
}

pub fn HttpHeaders.count() -> Int {
  return entries.len();
}

fn method_to_str(method: HttpMethod) -> Str {
  match method {
    GET => "GET",
    POST => "POST",
    PUT => "PUT",
    DELETE => "DELETE",
    PATCH => "PATCH",
    HEAD => "HEAD",
    OPTIONS => "OPTIONS",
  }
}

fn version_to_str(version: HttpVersion) -> Str {
  match version {
    HTTP09 => "HTTP/0.9",
    HTTP10 => "HTTP/1.0",
    HTTP11 => "HTTP/1.1",
    HTTP20 => "HTTP/2.0",
  }
}

pub fn method_from_str(s: Str) -> HttpMethod {
  if s == "GET" { return HttpMethod.GET; }
  elif s == "POST" { return HttpMethod.POST; }
  elif s == "PUT" { return HttpMethod.PUT; }
  elif s == "DELETE" { return HttpMethod.DELETE; }
  elif s == "PATCH" { return HttpMethod.PATCH; }
  elif s == "HEAD" { return HttpMethod.HEAD; }
  elif s == "OPTIONS" { return HttpMethod.OPTIONS; }
  return HttpMethod.GET;
}

pub fn version_from_str(s: Str) -> HttpVersion {
  if s == "HTTP/0.9" { return HttpVersion.HTTP09; }
  elif s == "HTTP/1.0" { return HttpVersion.HTTP10; }
  elif s == "HTTP/1.1" { return HttpVersion.HTTP11; }
  elif s == "HTTP/2.0" { return HttpVersion.HTTP20; }
  return HttpVersion.HTTP11;
}

// Renders a byte code as text: control specials keep their current mappings
// (0 -> "\0", 9 -> "\t", 10 -> "\n", 13 -> "\r"), 32 -> " ", printable ASCII
// (33..126) renders as the actual character via the stdlib Char -> Str helper
// (tostring.to_string_char, UTF-8), everything else falls back to "?".
fn byte_to_char(b: Int) -> Str {
  if b == 0 { return "\0"; }
  if b == 10 { return "\n"; }
  if b == 13 { return "\r"; }
  if b == 9 { return "\t"; }
  if b == 32 { return " "; }
  if b >= 33 && b <= 126 {
    return tostring.to_string_char(to_char(b));
  }
  return "?";
}

fn str_from_vec_byte(body: Vec[Int]) -> Str {
  var result: Str = "";
  var i: Int = 0;
  while i < body.len() {
    result = result + byte_to_char(body[i]);
    i = i + 1;
  }
  return result;
}

pub fn HttpRequest.new(method: HttpMethod, path: Str) -> HttpRequest
  requires: path.len() > 0 {
  return HttpRequest{
    method: method,
    path: path,
    version: HttpVersion.HTTP11,
    headers: HttpHeaders.new(),
    body: Vec[Int].new(),
  };
}

pub fn HttpRequest.set_header(name: Str, value: Str)
  requires: name.len() > 0 {
  headers.add(name, value);
}

pub fn HttpRequest.set_body(new_body: Vec[Int]) {
  body = new_body;
}

pub fn HttpRequest.to_str() -> Str {
  var s: Str = method_to_str(method) + " " + path + " " + version_to_str(version) + "\r\n";
  var i: Int = 0;
  while i < headers.entries.len() {
    s = s + headers.entries[i].name + ": " + headers.entries[i].value + "\r\n";
    i = i + 1;
  }
  s = xiom.string.str_concat(s, "\r\n");
  if body.len() > 0 {
    s = xiom.string.str_concat(s, str_from_vec_byte(body));
  }
  return s;
}

pub fn HttpResponse.new(status: Int) -> HttpResponse
  requires: status >= 100
  requires: status < 600 {
  return HttpResponse{
    version: HttpVersion.HTTP11,
    status: status,
    reason: "",
    headers: HttpHeaders.new(),
    body: Vec[Int].new(),
  };
}

pub fn HttpResponse.set_header(name: Str, value: Str)
  requires: name.len() > 0 {
  headers.add(name, value);
}

pub fn HttpResponse.set_body(new_body: Vec[Int]) {
  body = new_body;
}

pub fn HttpResponse.to_str() -> Str {
  var s: Str = version_to_str(version) + " " + xiom.convert.int_to_string(status) + " " + reason + "\r\n";
  var i: Int = 0;
  while i < headers.entries.len() {
    s = s + headers.entries[i].name + ": " + headers.entries[i].value + "\r\n";
    i = i + 1;
  }
  s = xiom.string.str_concat(s, "\r\n");
  if body.len() > 0 {
    s = xiom.string.str_concat(s, str_from_vec_byte(body));
  }
  return s;
}
