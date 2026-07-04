module xiom.http.cookie

pub type Cookie = {
  name: Str;
  value: Str;
  domain: Str;
  path: Str;
  secure: Bool;
  http_only: Bool;
  max_age: Int;
}

fn char_from_int(c: Int) -> Str {
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

pub fn cookie_new(name: Str, value: Str) -> Cookie {
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

fn skip_ws(s: Str, pos: Int) -> Int {
  var p: Int = pos;
  var len: Int = @axiom_str_len(s);
  while p < len {
    var c: Int = @axiom_char_at(s, p);
    if c != 32 && c != 9 { return p; }
    p = p + 1;
  }
  return p;
}

fn str_lower(s: Str) -> Str {
  var result: Str = "";
  var i: Int = 0;
  var len: Int = @axiom_str_len(s);
  while i < len {
    var c: Int = @axiom_char_at(s, i);
    if c >= 65 && c <= 90 {
      if c == 65 { result = result + "a"; }
      elif c == 66 { result = result + "b"; }
      elif c == 67 { result = result + "c"; }
      elif c == 68 { result = result + "d"; }
      elif c == 69 { result = result + "e"; }
      elif c == 70 { result = result + "f"; }
      elif c == 71 { result = result + "g"; }
      elif c == 72 { result = result + "h"; }
      elif c == 73 { result = result + "i"; }
      elif c == 74 { result = result + "j"; }
      elif c == 75 { result = result + "k"; }
      elif c == 76 { result = result + "l"; }
      elif c == 77 { result = result + "m"; }
      elif c == 78 { result = result + "n"; }
      elif c == 79 { result = result + "o"; }
      elif c == 80 { result = result + "p"; }
      elif c == 81 { result = result + "q"; }
      elif c == 82 { result = result + "r"; }
      elif c == 83 { result = result + "s"; }
      elif c == 84 { result = result + "t"; }
      elif c == 85 { result = result + "u"; }
      elif c == 86 { result = result + "v"; }
      elif c == 87 { result = result + "w"; }
      elif c == 88 { result = result + "x"; }
      elif c == 89 { result = result + "y"; }
      elif c == 90 { result = result + "z"; }
      else { result = result + "?"; }
    }
    else {
      if c == 32 { result = result + " "; }
      elif c == 33 { result = result + "!"; }
      elif c == 34 { result = result + "\""; }
      elif c == 35 { result = result + "#"; }
      elif c == 36 { result = result + "$"; }
      elif c == 37 { result = result + "%"; }
      elif c == 38 { result = result + "&"; }
      elif c == 39 { result = result + "'"; }
      elif c == 40 { result = result + "("; }
      elif c == 41 { result = result + ")"; }
      elif c == 42 { result = result + "*"; }
      elif c == 43 { result = result + "+"; }
      elif c == 44 { result = result + ","; }
      elif c == 45 { result = result + "-"; }
      elif c == 46 { result = result + "."; }
      elif c == 47 { result = result + "/"; }
      elif c == 48 { result = result + "0"; }
      elif c == 49 { result = result + "1"; }
      elif c == 50 { result = result + "2"; }
      elif c == 51 { result = result + "3"; }
      elif c == 52 { result = result + "4"; }
      elif c == 53 { result = result + "5"; }
      elif c == 54 { result = result + "6"; }
      elif c == 55 { result = result + "7"; }
      elif c == 56 { result = result + "8"; }
      elif c == 57 { result = result + "9"; }
      elif c == 58 { result = result + ":"; }
      elif c == 59 { result = result + ";"; }
      elif c == 60 { result = result + "<"; }
      elif c == 61 { result = result + "="; }
      elif c == 62 { result = result + ">"; }
      elif c == 63 { result = result + "?"; }
      elif c == 64 { result = result + "@"; }
      elif c >= 97 && c <= 122 {
        if c == 97 { result = result + "a"; }
        elif c == 98 { result = result + "b"; }
        elif c == 99 { result = result + "c"; }
        elif c == 100 { result = result + "d"; }
        elif c == 101 { result = result + "e"; }
        elif c == 102 { result = result + "f"; }
        elif c == 103 { result = result + "g"; }
        elif c == 104 { result = result + "h"; }
        elif c == 105 { result = result + "i"; }
        elif c == 106 { result = result + "j"; }
        elif c == 107 { result = result + "k"; }
        elif c == 108 { result = result + "l"; }
        elif c == 109 { result = result + "m"; }
        elif c == 110 { result = result + "n"; }
        elif c == 111 { result = result + "o"; }
        elif c == 112 { result = result + "p"; }
        elif c == 113 { result = result + "q"; }
        elif c == 114 { result = result + "r"; }
        elif c == 115 { result = result + "s"; }
        elif c == 116 { result = result + "t"; }
        elif c == 117 { result = result + "u"; }
        elif c == 118 { result = result + "v"; }
        elif c == 119 { result = result + "w"; }
        elif c == 120 { result = result + "x"; }
        elif c == 121 { result = result + "y"; }
        elif c == 122 { result = result + "z"; }
        else { result = result + "?"; }
      }
      else { result = result + "?"; }
    }
    i = i + 1;
  }
  return result;
}

fn parse_int_from_str(s: Str) -> Int {
  var result: Int = 0;
  var i: Int = 0;
  var len: Int = @axiom_str_len(s);
  var neg: Bool = false;
  if len > 0 {
    var fc: Int = @axiom_char_at(s, 0);
    if fc == 45 {
      neg = true;
      i = 1;
    }
  }
  while i < len {
    var c: Int = @axiom_char_at(s, i);
    if c >= 48 && c <= 57 {
      result = result * 10 + (c - 48);
    }
    i = i + 1;
  }
  if neg { return -result; }
  return result;
}

pub fn cookie_parse(set_cookie_header: Str) -> Result[Cookie, Str] {
  var cookie: Cookie = Cookie{
    name: "",
    value: "",
    domain: "",
    path: "/",
    secure: false,
    http_only: false,
    max_age: -1,
  };
  var len: Int = @axiom_str_len(set_cookie_header);
  var pos: Int = 0;
  pos = skip_ws(set_cookie_header, pos);
  var name_str: Str = "";
  while pos < len {
    var c: Int = @axiom_char_at(set_cookie_header, pos);
    if c == 61 { break; }
    if c == 59 { break; }
    if c == 32 { break; }
    if c == 44 { break; }
    name_str = name_str + char_from_int(c);
    pos = pos + 1;
  }
  if pos >= len || @axiom_char_at(set_cookie_header, pos) != 61 {
    return Err("Invalid Set-Cookie: missing '=' after name");
  }
  pos = pos + 1;
  cookie.name = name_str;
  var value_str: Str = "";
  while pos < len {
    var c: Int = @axiom_char_at(set_cookie_header, pos);
    if c == 59 { break; }
    value_str = value_str + char_from_int(c);
    pos = pos + 1;
  }
  cookie.value = value_str;
  while pos < len {
    var c: Int = @axiom_char_at(set_cookie_header, pos);
    if c == 59 {
      pos = pos + 1;
      pos = skip_ws(set_cookie_header, pos);
      var attr_name: Str = "";
      while pos < len {
        var ac: Int = @axiom_char_at(set_cookie_header, pos);
        if ac == 61 || ac == 59 || ac == 44 { break; }
        attr_name = attr_name + char_from_int(ac);
        pos = pos + 1;
      }
      var attr_lower: Str = str_lower(attr_name);
      var attr_value: Str = "";
      if pos < len {
        var ac2: Int = @axiom_char_at(set_cookie_header, pos);
        if ac2 == 61 {
          pos = pos + 1;
          while pos < len {
            var avc: Int = @axiom_char_at(set_cookie_header, pos);
            if avc == 59 || avc == 44 { break; }
            attr_value = attr_value + char_from_int(avc);
            pos = pos + 1;
          }
        }
      }
      if attr_lower == "domain" {
        if @axiom_str_len(attr_value) > 0 {
          cookie.domain = attr_value;
        }
      }
      elif attr_lower == "path" {
        if @axiom_str_len(attr_value) > 0 {
          cookie.path = attr_value;
        }
      }
      elif attr_lower == "secure" {
        cookie.secure = true;
      }
      elif attr_lower == "httponly" {
        cookie.http_only = true;
      }
      elif attr_lower == "max-age" {
        cookie.max_age = parse_int_from_str(attr_value);
      }
    }
    else {
      pos = pos + 1;
    }
  }
  return Ok(cookie);
}

pub fn cookie_to_str(cookie: &Cookie) -> Str {
  var s: Str = "";
  s = s + cookie.name + "=" + cookie.value;
  if @axiom_str_len(cookie.path) > 0 && cookie.path != "/" {
    s = s + "; Path=" + cookie.path;
  }
  if @axiom_str_len(cookie.domain) > 0 {
    s = s + "; Domain=" + cookie.domain;
  }
  if cookie.max_age >= 0 {
    var age_str: Str = "";
    var a: Int = cookie.max_age;
    if a == 0 {
      age_str = "0";
    }
    else {
      var digits: Vec[Str] = Vec[Str].new();
      while a > 0 {
        var d: Int = a % 10;
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
        a = a / 10;
      }
      var k: Int = digits.len() - 1;
      while k >= 0 {
        age_str = age_str + digits[k];
        k = k - 1;
      }
    }
    s = s + "; Max-Age=" + age_str;
  }
  if cookie.secure {
    s = s + "; Secure";
  }
  if cookie.http_only {
    s = s + "; HttpOnly";
  }
  return s;
}

pub fn cookie_parse_all(cookie_header: Str) -> Vec[Cookie] {
  var cookies: Vec[Cookie] = Vec[Cookie].new();
  var len: Int = @axiom_str_len(cookie_header);
  if len == 0 { return cookies; }
  var pos: Int = 0;
  while pos < len {
    pos = skip_ws(cookie_header, pos);
    var name_str: Str = "";
    while pos < len {
      var c: Int = @axiom_char_at(cookie_header, pos);
      if c == 61 || c == 59 || c == 44 { break; }
      name_str = name_str + char_from_int(c);
      pos = pos + 1;
    }
    if pos < len {
      var c: Int = @axiom_char_at(cookie_header, pos);
      if c == 61 {
        pos = pos + 1;
        var val_str: Str = "";
        while pos < len {
          var vc: Int = @axiom_char_at(cookie_header, pos);
          if vc == 59 || vc == 44 { break; }
          val_str = val_str + char_from_int(vc);
          pos = pos + 1;
        }
        if @axiom_str_len(name_str) > 0 {
          cookies.push(cookie_new(name_str, val_str));
        }
      }
    }
    while pos < len {
      var c: Int = @axiom_char_at(cookie_header, pos);
      if c == 59 || c == 44 { break; }
      pos = pos + 1;
    }
    if pos < len {
      pos = pos + 1;
    }
  }
  return cookies;
}
