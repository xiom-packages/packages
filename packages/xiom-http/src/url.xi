module xiom.http.url

use xiom.encoding;
use xiom.string;
use xiom.convert.tostring;

fn char_code_at(s: Str, pos: Int) -> Int {
  match xiom.string.char_at(s, pos) {
    Some(c) => { return to_int_from_char(c); },
    None => { return -1; },
  }
}

pub type Url = {
  scheme: Str;
  host: Str;
  port: Int;
  path: Str;
  query: Str;
  fragment: Str;
}

fn is_alpha_char(c: Int) -> Bool {
  return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
}

fn is_digit_char(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

fn is_alphanum(c: Int) -> Bool {
  return is_alpha_char(c) || is_digit_char(c);
}

// Renders a byte code as text: space stays " ", printable ASCII (33..126)
// renders as the actual character via the stdlib Char -> Str helper
// (tostring.to_string_char, UTF-8), everything else falls back to "?".
fn char_to_str(c: Int) -> Str {
  if c == 32 { return " "; }
  if c >= 33 && c <= 126 {
    return tostring.to_string_char(to_char(c));
  }
  return "?";
}

pub fn url_parse(input: Str) -> Result[Url, Str]
  requires: xiom.string.str_len(input) > 0 {
  var scheme: Str = "";
  var host: Str = "";
  var port: Int = 0;
  var path: Str = "/";
  var query: Str = "";
  var fragment: Str = "";
  var len: Int = xiom.string.str_len(input);
  var pos: Int = 0;
  var scheme_end: Int = 0;
  var has_scheme: Bool = false;
  var i: Int = 0;
  while i < len {
    var c: Int = char_code_at(input, i);
    if c == 58 {
      if i + 2 < len {
        var n1: Int = char_code_at(input, i + 1);
        var n2: Int = char_code_at(input, i + 2);
        if n1 == 47 && n2 == 47 {
          scheme_end = i;
          has_scheme = true;
        }
      }
      break;
    }
    if !is_alphanum(c) && c != 43 && c != 45 && c != 46 {
      break;
    }
    i = i + 1;
  }
  if has_scheme {
    var j: Int = 0;
    scheme = "";
    while j < scheme_end {
      scheme = scheme + char_to_str(char_code_at(input, j));
      j = j + 1;
    }
    pos = scheme_end + 3;
  }
  else {
    pos = 0;
  }
  var host_start: Int = pos;
  while pos < len {
    var c: Int = char_code_at(input, pos);
    if c == 58 || c == 47 || c == 63 || c == 35 {
      break;
    }
    pos = pos + 1;
  }
  var host_end: Int = pos;
  var j: Int = host_start;
  host = "";
  while j < host_end {
    host = host + char_to_str(char_code_at(input, j));
    j = j + 1;
  }
  if pos < len && char_code_at(input, pos) == 58 {
    pos = pos + 1;
    var port_str: Str = "";
    while pos < len {
      var pc: Int = char_code_at(input, pos);
      if pc == 47 || pc == 63 || pc == 35 { break; }
      port_str = port_str + char_to_str(pc);
      pos = pos + 1;
    }
    var pi: Int = 0;
    var pv: Int = 0;
    var plen: Int = xiom.string.str_len(port_str);
    while pi < plen {
      var pc: Int = char_code_at(port_str, pi);
      if is_digit_char(pc) { pv = pv * 10 + (pc - 48); }
      pi = pi + 1;
    }
    port = pv;
  }
  if pos < len {
    var c: Int = char_code_at(input, pos);
    if c == 47 {
      var path_str: Str = "";
      while pos < len {
        var pc: Int = char_code_at(input, pos);
        if pc == 63 || pc == 35 { break; }
        path_str = path_str + char_to_str(pc);
        pos = pos + 1;
      }
      path = path_str;
    }
  }
  if pos < len {
    var c: Int = char_code_at(input, pos);
    if c == 63 {
      pos = pos + 1;
      var query_str: Str = "";
      while pos < len {
        var pc: Int = char_code_at(input, pos);
        if pc == 35 { break; }
        query_str = query_str + char_to_str(pc);
        pos = pos + 1;
      }
      query = query_str;
    }
  }
  if pos < len {
    var c: Int = char_code_at(input, pos);
    if c == 35 {
      pos = pos + 1;
      var frag_str: Str = "";
      while pos < len {
        frag_str = frag_str + char_to_str(char_code_at(input, pos));
        pos = pos + 1;
      }
      fragment = frag_str;
    }
  }
  if port == 0 {
    if scheme == "https" { port = 443; }
    elif scheme == "http" { port = 80; }
  }
  return Ok(Url{
    scheme: scheme,
    host: host,
    port: port,
    path: path,
    query: query,
    fragment: fragment,
  });
}

pub fn url_to_str(url: &Url) -> Str {
  var s: Str = "";
  if xiom.string.str_len(url.scheme) > 0 {
    s = s + url.scheme + "://";
  }
  s = s + url.host;
  if url.port != 0 && url.port != 80 && url.port != 443 {
    var port_str: Str = "";
    var p: Int = url.port;
    if p == 0 { port_str = "0"; }
    else {
      var digits: Vec[Str] = Vec[Str].new();
      while p > 0 {
        var d: Int = p % 10;
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
        p = p / 10;
      }
      var k: Int = digits.len() - 1;
      while k >= 0 {
        port_str = port_str + digits[k];
        k = k - 1;
      }
    }
    s = s + ":" + port_str;
  }
  s = s + url.path;
  if xiom.string.str_len(url.query) > 0 {
    s = s + "?" + url.query;
  }
  if xiom.string.str_len(url.fragment) > 0 {
    s = s + "#" + url.fragment;
  }
  return s;
}

pub fn url_encode(s: Str) -> Str
  requires: xiom.string.str_len(s) > 0 {
  return xiom.encoding.url_encode(s);
}

pub fn url_decode(s: Str) -> Result[Str, Str]
  requires: xiom.string.str_len(s) > 0 {
  return xiom.encoding.url_decode(s);
}

pub fn path_join(base: Str, relative: Str) -> Str {
  var base_len: Int = xiom.string.str_len(base);
  var rel_len: Int = xiom.string.str_len(relative);
  if rel_len == 0 { return base; }
  if base_len == 0 { return relative; }
  if base_len > 0 {
    var first: Int = char_code_at(relative, 0);
    if first == 47 { return relative; }
  }
  var result: Str = base;
  var last: Int = char_code_at(base, base_len - 1);
  if last != 47 {
    result = result + "/";
  }
  result = result + relative;
  return result;
}
