module xiom.http.url

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

fn is_unreserved(c: Int) -> Bool {
  if is_alphanum(c) { return true; }
  if c == 45 { return true; }
  if c == 46 { return true; }
  if c == 95 { return true; }
  if c == 126 { return true; }
  return false;
}

fn is_hex_digit(c: Int) -> Bool {
  if is_digit_char(c) { return true; }
  if c >= 65 && c <= 70 { return true; }
  if c >= 97 && c <= 102 { return true; }
  return false;
}

fn hex_val(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 65 && c <= 70 { return c - 65 + 10; }
  if c >= 97 && c <= 102 { return c - 97 + 10; }
  return 0;
}

fn hex_char(v: Int) -> Str {
  if v == 0 { return "0"; }
  elif v == 1 { return "1"; }
  elif v == 2 { return "2"; }
  elif v == 3 { return "3"; }
  elif v == 4 { return "4"; }
  elif v == 5 { return "5"; }
  elif v == 6 { return "6"; }
  elif v == 7 { return "7"; }
  elif v == 8 { return "8"; }
  elif v == 9 { return "9"; }
  elif v == 10 { return "A"; }
  elif v == 11 { return "B"; }
  elif v == 12 { return "C"; }
  elif v == 13 { return "D"; }
  elif v == 14 { return "E"; }
  elif v == 15 { return "F"; }
  return "0";
}

fn char_to_str(c: Int) -> Str {
  if c == 32 { return " "; }
  elif c == 33 { return "!"; }
  elif c == 34 { return "\""; }
  elif c == 35 { return "#"; }
  elif c == 36 { return "$"; }
  elif c == 37 { return "%"; }
  elif c == 38 { return "&"; }
  elif c == 39 { return "'"; }
  elif c == 40 { return "("; }
  elif c == 41 { return ")"; }
  elif c == 42 { return "*"; }
  elif c == 43 { return "+"; }
  elif c == 44 { return ","; }
  elif c == 45 { return "-"; }
  elif c == 46 { return "."; }
  elif c == 47 { return "/"; }
  elif c == 48 { return "0"; }
  elif c == 49 { return "1"; }
  elif c == 50 { return "2"; }
  elif c == 51 { return "3"; }
  elif c == 52 { return "4"; }
  elif c == 53 { return "5"; }
  elif c == 54 { return "6"; }
  elif c == 55 { return "7"; }
  elif c == 56 { return "8"; }
  elif c == 57 { return "9"; }
  elif c == 58 { return ":"; }
  elif c == 59 { return ";"; }
  elif c == 60 { return "<"; }
  elif c == 61 { return "="; }
  elif c == 62 { return ">"; }
  elif c == 63 { return "?"; }
  elif c == 64 { return "@"; }
  elif c >= 65 && c <= 90 {
    if c == 65 { return "A"; }
    elif c == 66 { return "B"; }
    elif c == 67 { return "C"; }
    elif c == 68 { return "D"; }
    elif c == 69 { return "E"; }
    elif c == 70 { return "F"; }
    elif c == 71 { return "G"; }
    elif c == 72 { return "H"; }
    elif c == 73 { return "I"; }
    elif c == 74 { return "J"; }
    elif c == 75 { return "K"; }
    elif c == 76 { return "L"; }
    elif c == 77 { return "M"; }
    elif c == 78 { return "N"; }
    elif c == 79 { return "O"; }
    elif c == 80 { return "P"; }
    elif c == 81 { return "Q"; }
    elif c == 82 { return "R"; }
    elif c == 83 { return "S"; }
    elif c == 84 { return "T"; }
    elif c == 85 { return "U"; }
    elif c == 86 { return "V"; }
    elif c == 87 { return "W"; }
    elif c == 88 { return "X"; }
    elif c == 89 { return "Y"; }
    elif c == 90 { return "Z"; }
  }
  elif c >= 97 && c <= 122 {
    if c == 97 { return "a"; }
    elif c == 98 { return "b"; }
    elif c == 99 { return "c"; }
    elif c == 100 { return "d"; }
    elif c == 101 { return "e"; }
    elif c == 102 { return "f"; }
    elif c == 103 { return "g"; }
    elif c == 104 { return "h"; }
    elif c == 105 { return "i"; }
    elif c == 106 { return "j"; }
    elif c == 107 { return "k"; }
    elif c == 108 { return "l"; }
    elif c == 109 { return "m"; }
    elif c == 110 { return "n"; }
    elif c == 111 { return "o"; }
    elif c == 112 { return "p"; }
    elif c == 113 { return "q"; }
    elif c == 114 { return "r"; }
    elif c == 115 { return "s"; }
    elif c == 116 { return "t"; }
    elif c == 117 { return "u"; }
    elif c == 118 { return "v"; }
    elif c == 119 { return "w"; }
    elif c == 120 { return "x"; }
    elif c == 121 { return "y"; }
    elif c == 122 { return "z"; }
  }
  return "?";
}

pub fn url_parse(input: Str) -> Result[Url, Str] {
  var scheme: Str = "";
  var host: Str = "";
  var port: Int = 0;
  var path: Str = "/";
  var query: Str = "";
  var fragment: Str = "";
  var len: Int = @axiom_str_len(input);
  var pos: Int = 0;
  var scheme_end: Int = 0;
  var has_scheme: Bool = false;
  var i: Int = 0;
  while i < len {
    var c: Int = @axiom_char_at(input, i);
    if c == 58 {
      if i + 2 < len {
        var n1: Int = @axiom_char_at(input, i + 1);
        var n2: Int = @axiom_char_at(input, i + 2);
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
      scheme = scheme + char_to_str(@axiom_char_at(input, j));
      j = j + 1;
    }
    pos = scheme_end + 3;
  }
  else {
    pos = 0;
  }
  var host_start: Int = pos;
  while pos < len {
    var c: Int = @axiom_char_at(input, pos);
    if c == 58 {
      pos = pos + 1;
      break;
    }
    if c == 47 || c == 63 || c == 35 {
      break;
    }
    pos = pos + 1;
  }
  var host_end: Int = pos;
  var j: Int = host_start;
  host = "";
  while j < host_end {
    var c: Int = @axiom_char_at(input, j);
    if c == 58 {
      j = j + 1;
      var port_str: Str = "";
      while j < host_end {
        port_str = port_str + char_to_str(@axiom_char_at(input, j));
        j = j + 1;
      }
      var pi: Int = 0;
      var pv: Int = 0;
      var plen: Int = @axiom_str_len(port_str);
      while pi < plen {
        var pc: Int = @axiom_char_at(port_str, pi);
        pv = pv * 10 + (pc - 48);
        pi = pi + 1;
      }
      port = pv;
      break;
    }
    host = host + char_to_str(c);
    j = j + 1;
  }
  if !has_scheme {
    if pos < len {
      var c: Int = @axiom_char_at(input, pos);
      if c == 58 {
        pos = pos + 1;
        var port_str: Str = "";
        while pos < len {
          var pc: Int = @axiom_char_at(input, pos);
          if pc == 47 || pc == 63 || pc == 35 { break; }
          port_str = port_str + char_to_str(pc);
          pos = pos + 1;
        }
        var pi: Int = 0;
        var pv: Int = 0;
        var plen: Int = @axiom_str_len(port_str);
        while pi < plen {
          var pc: Int = @axiom_char_at(port_str, pi);
          pv = pv * 10 + (pc - 48);
          pi = pi + 1;
        }
        port = pv;
      }
    }
  }
  if pos < len {
    var c: Int = @axiom_char_at(input, pos);
    if c == 47 {
      var path_str: Str = "";
      while pos < len {
        var pc: Int = @axiom_char_at(input, pos);
        if pc == 63 || pc == 35 { break; }
        path_str = path_str + char_to_str(pc);
        pos = pos + 1;
      }
      path = path_str;
    }
  }
  if pos < len {
    var c: Int = @axiom_char_at(input, pos);
    if c == 63 {
      pos = pos + 1;
      var query_str: Str = "";
      while pos < len {
        var pc: Int = @axiom_char_at(input, pos);
        if pc == 35 { break; }
        query_str = query_str + char_to_str(pc);
        pos = pos + 1;
      }
      query = query_str;
    }
  }
  if pos < len {
    var c: Int = @axiom_char_at(input, pos);
    if c == 35 {
      pos = pos + 1;
      var frag_str: Str = "";
      while pos < len {
        frag_str = frag_str + char_to_str(@axiom_char_at(input, pos));
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
  if @axiom_str_len(url.scheme) > 0 {
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
  if @axiom_str_len(url.query) > 0 {
    s = s + "?" + url.query;
  }
  if @axiom_str_len(url.fragment) > 0 {
    s = s + "#" + url.fragment;
  }
  return s;
}

pub fn url_encode(s: Str) -> Str {
  var result: Str = "";
  var i: Int = 0;
  var len: Int = @axiom_str_len(s);
  while i < len {
    var c: Int = @axiom_char_at(s, i);
    if is_unreserved(c) {
      result = result + char_to_str(c);
    }
    else {
      var hi: Int = c / 16;
      var lo: Int = c % 16;
      result = result + "%" + hex_char(hi) + hex_char(lo);
    }
    i = i + 1;
  }
  return result;
}

pub fn url_decode(s: Str) -> Result[Str, Str] {
  var result: Str = "";
  var i: Int = 0;
  var len: Int = @axiom_str_len(s);
  while i < len {
    var c: Int = @axiom_char_at(s, i);
    if c == 37 {
      if i + 2 < len {
        var hi: Int = @axiom_char_at(s, i + 1);
        var lo: Int = @axiom_char_at(s, i + 2);
        if is_hex_digit(hi) && is_hex_digit(lo) {
          var val: Int = hex_val(hi) * 16 + hex_val(lo);
          result = result + char_to_str(val);
          i = i + 3;
          continue;
        }
        return Err("Invalid percent encoding");
      }
      return Err("Truncated percent encoding");
    }
    elif c == 43 {
      result = result + " ";
    }
    else {
      result = result + char_to_str(c);
    }
    i = i + 1;
  }
  return Ok(result);
}

pub fn path_join(base: Str, relative: Str) -> Str {
  var base_len: Int = @axiom_str_len(base);
  var rel_len: Int = @axiom_str_len(relative);
  if rel_len == 0 { return base; }
  if base_len == 0 { return relative; }
  if base_len > 0 {
    var first: Int = @axiom_char_at(relative, 0);
    if first == 47 { return relative; }
  }
  var result: Str = base;
  var last: Int = @axiom_char_at(base, base_len - 1);
  if last != 47 {
    result = result + "/";
  }
  result = result + relative;
  return result;
}
