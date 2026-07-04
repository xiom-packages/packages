module xiom.http.types

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

pub fn HttpHeaders.add(name: Str, value: Str) {
  entries.push(HttpHeader{ name: name, value: value });
}

pub fn HttpHeaders.get(name: Str) -> Option[Str] {
  var i: Int = 0;
  while i < entries.len() {
    if entries[i].name == name {
      return Some(entries[i].value);
    }
    i = i + 1;
  }
  return None;
}

pub fn HttpHeaders.has(name: Str) -> Bool {
  var i: Int = 0;
  while i < entries.len() {
    if entries[i].name == name {
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn HttpHeaders.remove(name: Str) -> Bool {
  var i: Int = 0;
  while i < entries.len() {
    if entries[i].name == name {
      entries.remove(i);
      return true;
    }
    i = i + 1;
  }
  return false;
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

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var digits: Vec[Str] = Vec[Str].new();
  var num: Int = n;
  if num < 0 {
    num = -num;
  }
  while num > 0 {
    var d: Int = num % 10;
    num = num / 10;
    if d == 0 { digits.push("0"); }
    elif d == 1 { digits.push("1"); }
    elif d == 2 { digits.push("2"); }
    elif d == 3 { digits.push("3"); }
    elif d == 4 { digits.push("4"); }
    elif d == 5 { digits.push("5"); }
    elif d == 6 { digits.push("6"); }
    elif d == 7 { digits.push("7"); }
    elif d == 8 { digits.push("8"); }
    elif d == 9 { digits.push("9"); }
  }
  var result: Str = "";
  if n < 0 {
    result = result + "-";
  }
  var j: Int = digits.len() - 1;
  while j >= 0 {
    result = result + digits[j];
    j = j - 1;
  }
  return result;
}

fn byte_to_char(b: Int) -> Str {
  if b == 0 { return "\0"; }
  if b == 10 { return "\n"; }
  if b == 13 { return "\r"; }
  if b == 9 { return "\t"; }
  if b == 32 { return " "; }
  if b == 33 { return "!"; }
  if b == 34 { return "\""; }
  if b == 35 { return "#"; }
  if b == 36 { return "$"; }
  if b == 37 { return "%"; }
  if b == 38 { return "&"; }
  if b == 39 { return "'"; }
  if b == 40 { return "("; }
  if b == 41 { return ")"; }
  if b == 42 { return "*"; }
  if b == 43 { return "+"; }
  if b == 44 { return ","; }
  if b == 45 { return "-"; }
  if b == 46 { return "."; }
  if b == 47 { return "/"; }
  if b == 48 { return "0"; }
  if b == 49 { return "1"; }
  if b == 50 { return "2"; }
  if b == 51 { return "3"; }
  if b == 52 { return "4"; }
  if b == 53 { return "5"; }
  if b == 54 { return "6"; }
  if b == 55 { return "7"; }
  if b == 56 { return "8"; }
  if b == 57 { return "9"; }
  if b == 58 { return ":"; }
  if b == 59 { return ";"; }
  if b == 60 { return "<"; }
  if b == 61 { return "="; }
  if b == 62 { return ">"; }
  if b == 63 { return "?"; }
  if b == 64 { return "@"; }
  if b >= 65 && b <= 90 {
    if b == 65 { return "A"; }
    if b == 66 { return "B"; }
    if b == 67 { return "C"; }
    if b == 68 { return "D"; }
    if b == 69 { return "E"; }
    if b == 70 { return "F"; }
    if b == 71 { return "G"; }
    if b == 72 { return "H"; }
    if b == 73 { return "I"; }
    if b == 74 { return "J"; }
    if b == 75 { return "K"; }
    if b == 76 { return "L"; }
    if b == 77 { return "M"; }
    if b == 78 { return "N"; }
    if b == 79 { return "O"; }
    if b == 80 { return "P"; }
    if b == 81 { return "Q"; }
    if b == 82 { return "R"; }
    if b == 83 { return "S"; }
    if b == 84 { return "T"; }
    if b == 85 { return "U"; }
    if b == 86 { return "V"; }
    if b == 87 { return "W"; }
    if b == 88 { return "X"; }
    if b == 89 { return "Y"; }
    if b == 90 { return "Z"; }
  }
  if b >= 97 && b <= 122 {
    if b == 97 { return "a"; }
    if b == 98 { return "b"; }
    if b == 99 { return "c"; }
    if b == 100 { return "d"; }
    if b == 101 { return "e"; }
    if b == 102 { return "f"; }
    if b == 103 { return "g"; }
    if b == 104 { return "h"; }
    if b == 105 { return "i"; }
    if b == 106 { return "j"; }
    if b == 107 { return "k"; }
    if b == 108 { return "l"; }
    if b == 109 { return "m"; }
    if b == 110 { return "n"; }
    if b == 111 { return "o"; }
    if b == 112 { return "p"; }
    if b == 113 { return "q"; }
    if b == 114 { return "r"; }
    if b == 115 { return "s"; }
    if b == 116 { return "t"; }
    if b == 117 { return "u"; }
    if b == 118 { return "v"; }
    if b == 119 { return "w"; }
    if b == 120 { return "x"; }
    if b == 121 { return "y"; }
    if b == 122 { return "z"; }
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

pub fn HttpRequest.new(method: HttpMethod, path: Str) -> HttpRequest {
  return HttpRequest{
    method: method,
    path: path,
    version: HttpVersion.HTTP11,
    headers: HttpHeaders.new(),
    body: Vec[Int].new(),
  };
}

pub fn HttpRequest.set_header(name: Str, value: Str) {
  headers.add(name, value);
}

pub fn HttpRequest.set_body(new_body: Vec[Int]) {
  body = new_body;
}

pub fn HttpRequest.to_str() -> Str {
  var s: Str = "";
  s = s + method_to_str(method) + " " + path + " " + version_to_str(version) + "\r\n";
  var i: Int = 0;
  while i < headers.entries.len() {
    s = s + headers.entries[i].name + ": " + headers.entries[i].value + "\r\n";
    i = i + 1;
  }
  s = s + "\r\n";
  if body.len() > 0 {
    s = s + str_from_vec_byte(body);
  }
  return s;
}

pub fn HttpResponse.new(status: Int) -> HttpResponse {
  return HttpResponse{
    version: HttpVersion.HTTP11,
    status: status,
    reason: "",
    headers: HttpHeaders.new(),
    body: Vec[Int].new(),
  };
}

pub fn HttpResponse.set_header(name: Str, value: Str) {
  headers.add(name, value);
}

pub fn HttpResponse.set_body(new_body: Vec[Int]) {
  body = new_body;
}

pub fn HttpResponse.to_str() -> Str {
  var s: Str = "";
  s = s + version_to_str(version) + " " + int_to_str(status) + " " + reason + "\r\n";
  var i: Int = 0;
  while i < headers.entries.len() {
    s = s + headers.entries[i].name + ": " + headers.entries[i].value + "\r\n";
    i = i + 1;
  }
  s = s + "\r\n";
  if body.len() > 0 {
    s = s + str_from_vec_byte(body);
  }
  return s;
}
