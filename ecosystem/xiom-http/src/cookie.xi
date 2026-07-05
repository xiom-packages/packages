module xiom.http.cookie

use xiom.string;
use xiom.convert;

pub type Cookie = {
  name: Str;
  value: Str;
  domain: Str;
  path: Str;
  secure: Bool;
  http_only: Bool;
  max_age: Int;
}

fn str_lower(s: Str) -> Str {
  var result: Str = "";
  var i: Int = 0;
  var len: Int = xiom.string.str_len(s);
  while i < len {
    var c: Int = xiom.string.char_at(s, i);
    if c >= 65 && c <= 90 {
      if c == 65 { result = xiom.string.str_concat(result, "a"); }
      elif c == 66 { result = xiom.string.str_concat(result, "b"); }
      elif c == 67 { result = xiom.string.str_concat(result, "c"); }
      elif c == 68 { result = xiom.string.str_concat(result, "d"); }
      elif c == 69 { result = xiom.string.str_concat(result, "e"); }
      elif c == 70 { result = xiom.string.str_concat(result, "f"); }
      elif c == 71 { result = xiom.string.str_concat(result, "g"); }
      elif c == 72 { result = xiom.string.str_concat(result, "h"); }
      elif c == 73 { result = xiom.string.str_concat(result, "i"); }
      elif c == 74 { result = xiom.string.str_concat(result, "j"); }
      elif c == 75 { result = xiom.string.str_concat(result, "k"); }
      elif c == 76 { result = xiom.string.str_concat(result, "l"); }
      elif c == 77 { result = xiom.string.str_concat(result, "m"); }
      elif c == 78 { result = xiom.string.str_concat(result, "n"); }
      elif c == 79 { result = xiom.string.str_concat(result, "o"); }
      elif c == 80 { result = xiom.string.str_concat(result, "p"); }
      elif c == 81 { result = xiom.string.str_concat(result, "q"); }
      elif c == 82 { result = xiom.string.str_concat(result, "r"); }
      elif c == 83 { result = xiom.string.str_concat(result, "s"); }
      elif c == 84 { result = xiom.string.str_concat(result, "t"); }
      elif c == 85 { result = xiom.string.str_concat(result, "u"); }
      elif c == 86 { result = xiom.string.str_concat(result, "v"); }
      elif c == 87 { result = xiom.string.str_concat(result, "w"); }
      elif c == 88 { result = xiom.string.str_concat(result, "x"); }
      elif c == 89 { result = xiom.string.str_concat(result, "y"); }
      elif c == 90 { result = xiom.string.str_concat(result, "z"); }
      else { result = xiom.string.str_concat(result, "?"); }
    }
    else {
      result = xiom.string.str_concat(result, xiom.string.str_slice(s, i, i + 1));
    }
    i = i + 1;
  }
  return result;
}

fn parse_int_from_str(s: Str) -> Int {
  var result: Int = 0;
  var i: Int = 0;
  var len: Int = xiom.string.str_len(s);
  var neg: Bool = false;
  if len > 0 {
    var fc: Int = xiom.string.char_at(s, 0);
    if fc == 45 {
      neg = true;
      i = 1;
    }
  }
  while i < len {
    var c: Int = xiom.string.char_at(s, i);
    if c >= 48 && c <= 57 {
      result = result * 10 + (c - 48);
    }
    i = i + 1;
  }
  if neg { return -result; }
  return result;
}

pub fn cookie_new(name: Str, value: Str) -> Cookie
  requires: name.len() > 0 {
  return Cookie{
    name: name,
    value: value,
    domain: "",
    path: "/",
    secure: false,
    http_only: false,
    max_age: -1,
  };
}

pub fn cookie_parse(set_cookie_header: Str) -> Result[Cookie, Str]
  requires: set_cookie_header.len() > 0 {
  var segments: Vec[Str] = xiom.string.str_split(set_cookie_header, ";");
  if segments.len() == 0 {
    return Err("Invalid Set-Cookie: empty header");
  }

  var first: Str = xiom.string.str_trim(segments[0]);
  var eq_pos: Int = xiom.string.index_of(first, "=");
  if eq_pos < 0 {
    return Err("Invalid Set-Cookie: missing '=' after name");
  }
  var name: Str = xiom.string.str_slice(first, 0, eq_pos);
  var value: Str = xiom.string.str_slice(first, eq_pos + 1, xiom.string.str_len(first));

  var cookie: Cookie = cookie_new(name, value);

  var i: Int = 1;
  while i < segments.len() {
    var attr: Str = xiom.string.str_trim(segments[i]);
    var attr_eq: Int = xiom.string.index_of(attr, "=");
    if attr_eq >= 0 {
      var attr_name: Str = xiom.string.str_slice(attr, 0, attr_eq);
      var attr_value: Str = xiom.string.str_slice(attr, attr_eq + 1, xiom.string.str_len(attr));
      attr_name = str_lower(attr_name);
      if attr_name == "domain" {
        cookie.domain = attr_value;
      }
      elif attr_name == "path" {
        cookie.path = attr_value;
      }
      elif attr_name == "max-age" {
        cookie.max_age = parse_int_from_str(attr_value);
      }
    }
    else {
      var attr_lower: Str = str_lower(attr);
      if attr_lower == "secure" {
        cookie.secure = true;
      }
      elif attr_lower == "httponly" {
        cookie.http_only = true;
      }
    }
    i = i + 1;
  }
  return Ok(cookie);
}

pub fn cookie_to_str(cookie: &Cookie) -> Str {
  var s: Str = xiom.string.str_concat(cookie.name, "=", cookie.value);
  if xiom.string.str_len(cookie.path) > 0 && cookie.path != "/" {
    s = xiom.string.str_concat(s, "; Path=", cookie.path);
  }
  if xiom.string.str_len(cookie.domain) > 0 {
    s = xiom.string.str_concat(s, "; Domain=", cookie.domain);
  }
  if cookie.max_age >= 0 {
    s = xiom.string.str_concat(s, "; Max-Age=", xiom.convert.int_to_string(cookie.max_age));
  }
  if cookie.secure {
    s = xiom.string.str_concat(s, "; Secure");
  }
  if cookie.http_only {
    s = xiom.string.str_concat(s, "; HttpOnly");
  }
  return s;
}

pub fn cookie_parse_all(cookie_header: Str) -> Vec[Cookie] {
  var cookies: Vec[Cookie] = Vec[Cookie].new();
  var len: Int = xiom.string.str_len(cookie_header);
  if len == 0 { return cookies; }

  var segments: Vec[Str] = xiom.string.str_split(cookie_header, ";");
  var i: Int = 0;
  while i < segments.len() {
    var pair: Str = xiom.string.str_trim(segments[i]);
    var eq_pos: Int = xiom.string.index_of(pair, "=");
    if eq_pos > 0 {
      var name: Str = xiom.string.str_slice(pair, 0, eq_pos);
      var value: Str = xiom.string.str_slice(pair, eq_pos + 1, xiom.string.str_len(pair));
      cookies.push(cookie_new(name, value));
    }
    else {
      var comma_segments: Vec[Str] = xiom.string.str_split(pair, ",");
      var j: Int = 0;
      while j < comma_segments.len() {
        var cpair: Str = xiom.string.str_trim(comma_segments[j]);
        var ceq_pos: Int = xiom.string.index_of(cpair, "=");
        if ceq_pos > 0 {
          var cname: Str = xiom.string.str_slice(cpair, 0, ceq_pos);
          var cvalue: Str = xiom.string.str_slice(cpair, ceq_pos + 1, xiom.string.str_len(cpair));
          cookies.push(cookie_new(cname, cvalue));
        }
        j = j + 1;
      }
    }
    i = i + 1;
  }
  return cookies;
}
