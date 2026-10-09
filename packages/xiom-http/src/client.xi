module xiom.http.client

use xiom.convert.tostring;

pub fn http_get(url: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0 {
  return xiom.http.http_get(url);
}

pub fn http_post(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0 {
  var body_str: Str = str_from_vec_byte(body);
  return xiom.http.http_post(url, body_str, content_type);
}

pub fn http_put(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0 {
  var body_str: Str = str_from_vec_byte(body);
  return xiom.http.http_put(url, body_str);
}

pub fn http_delete(url: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0 {
  return xiom.http.http_delete(url);
}

pub fn http_send(request: &HttpRequest, url: &Url) -> Result[HttpResponse, Str]
  requires: url.scheme.len() > 0
  requires: url.host.len() > 0 {
  var url_str: Str = url_to_str(url);

  match request.method {
    HttpMethod.GET => {
      return xiom.http.http_get(url_str);
    };
    HttpMethod.POST => {
      var body_str: Str = str_from_vec_byte(request.body);
      var ct: Str = get_content_type(request.headers);
      return xiom.http.http_post(url_str, body_str, ct);
    };
    HttpMethod.PUT => {
      var body_str: Str = str_from_vec_byte(request.body);
      return xiom.http.http_put(url_str, body_str);
    };
    HttpMethod.DELETE => {
      return xiom.http.http_delete(url_str);
    };
    HttpMethod.PATCH => {
      var body_str: Str = str_from_vec_byte(request.body);
      return xiom.http.http_post(url_str, body_str, "application/json");
    };
    HttpMethod.HEAD => {
      return xiom.http.http_get(url_str);
    };
    HttpMethod.OPTIONS => {
      return xiom.http.http_get(url_str);
    };
  };
}

fn url_to_str(url: &Url) -> Str {
  var s: Str = "";
  if url.scheme.len() > 0 {
    s = s + url.scheme + "://";
  };
  s = s + url.host;
  if url.port > 0 {
    s = s + ":" + int_to_str(url.port);
  };
  s = s + url.path;
  if url.query.len() > 0 {
    s = s + "?" + url.query;
  };
  if url.fragment.len() > 0 {
    s = s + "#" + url.fragment;
  };
  return s;
}

fn get_content_type(headers: HttpHeaders) -> Str {
  match headers.get("Content-Type") {
    Some(ct) => { return ct; };
    None => { return "application/octet-stream"; };
  };
}

// Renders a byte code as text: control specials keep their current mappings
// (0 -> "\0", 9 -> "\t", 10 -> "\n", 13 -> "\r"), 32 -> " ", printable ASCII
// (33..126) renders as the actual character via the stdlib Char -> Str helper
// (tostring.to_string_char, UTF-8), everything else falls back to "?".
fn byte_to_char(b: Int) -> Str {
  if b == 0 { return "\0"; };
  if b == 10 { return "\n"; };
  if b == 13 { return "\r"; };
  if b == 9 { return "\t"; };
  if b == 32 { return " "; };
  if b >= 33 && b <= 126 {
    return tostring.to_string_char(to_char(b));
  };
  return "?";
}

fn str_from_vec_byte(body: Vec[Int]) -> Str {
  var result: Str = "";
  var i: Int = 0;
  while i < body.len() {
    result = result + byte_to_char(body[i]);
    i = i + 1;
  };
  return result;
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var digits: Vec[Str] = Vec[Str].new();
  var num: Int = n;
  if num < 0 { num = -num; };
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
  if n < 0 { result = result + "-"; }
  var j: Int = digits.len() - 1;
  while j >= 0 {
    result = result + digits[j];
    j = j - 1;
  };
  return result;
}
