module xiom.http.parser

pub type HttpParseError = {
  message: Str;
  position: Int;
}

fn char_at(s: Str, pos: Int) -> Int {
  return @axiom_char_at(s, pos);
}

fn is_space(c: Int) -> Bool {
  return c == 32 || c == 9;
}

fn is_cr(c: Int) -> Bool {
  return c == 13;
}

fn is_lf(c: Int) -> Bool {
  return c == 10;
}

fn is_digit(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

fn is_alpha(c: Int) -> Bool {
  return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
}

fn is_token_char(c: Int) -> Bool {
  if c >= 33 && c <= 126 { return true; }
  return false;
}

fn parse_until(input: Str, pos: Int, target: Int) -> Str {
  var result: Str = "";
  var p: Int = pos;
  var len: Int = @axiom_str_len(input);
  while p < len {
    var c: Int = char_at(input, p);
    if c == target { return result; }
    var ch: Str = "";
    if c == 32 { ch = " "; }
    elif c == 33 { ch = "!"; }
    elif c == 34 { ch = "\""; }
    elif c == 35 { ch = "#"; }
    elif c == 36 { ch = "$"; }
    elif c == 37 { ch = "%"; }
    elif c == 38 { ch = "&"; }
    elif c == 39 { ch = "'"; }
    elif c == 40 { ch = "("; }
    elif c == 41 { ch = ")"; }
    elif c == 42 { ch = "*"; }
    elif c == 43 { ch = "+"; }
    elif c == 44 { ch = ","; }
    elif c == 45 { ch = "-"; }
    elif c == 46 { ch = "."; }
    elif c == 47 { ch = "/"; }
    elif c == 48 { ch = "0"; }
    elif c == 49 { ch = "1"; }
    elif c == 50 { ch = "2"; }
    elif c == 51 { ch = "3"; }
    elif c == 52 { ch = "4"; }
    elif c == 53 { ch = "5"; }
    elif c == 54 { ch = "6"; }
    elif c == 55 { ch = "7"; }
    elif c == 56 { ch = "8"; }
    elif c == 57 { ch = "9"; }
    elif c == 58 { ch = ":"; }
    elif c == 59 { ch = ";"; }
    elif c == 60 { ch = "<"; }
    elif c == 61 { ch = "="; }
    elif c == 62 { ch = ">"; }
    elif c == 63 { ch = "?"; }
    elif c == 64 { ch = "@"; }
    elif c >= 65 && c <= 90 {
      if c == 65 { ch = "A"; }
      elif c == 66 { ch = "B"; }
      elif c == 67 { ch = "C"; }
      elif c == 68 { ch = "D"; }
      elif c == 69 { ch = "E"; }
      elif c == 70 { ch = "F"; }
      elif c == 71 { ch = "G"; }
      elif c == 72 { ch = "H"; }
      elif c == 73 { ch = "I"; }
      elif c == 74 { ch = "J"; }
      elif c == 75 { ch = "K"; }
      elif c == 76 { ch = "L"; }
      elif c == 77 { ch = "M"; }
      elif c == 78 { ch = "N"; }
      elif c == 79 { ch = "O"; }
      elif c == 80 { ch = "P"; }
      elif c == 81 { ch = "Q"; }
      elif c == 82 { ch = "R"; }
      elif c == 83 { ch = "S"; }
      elif c == 84 { ch = "T"; }
      elif c == 85 { ch = "U"; }
      elif c == 86 { ch = "V"; }
      elif c == 87 { ch = "W"; }
      elif c == 88 { ch = "X"; }
      elif c == 89 { ch = "Y"; }
      elif c == 90 { ch = "Z"; }
      else { ch = "?"; }
    }
    elif c >= 97 && c <= 122 {
      if c == 97 { ch = "a"; }
      elif c == 98 { ch = "b"; }
      elif c == 99 { ch = "c"; }
      elif c == 100 { ch = "d"; }
      elif c == 101 { ch = "e"; }
      elif c == 102 { ch = "f"; }
      elif c == 103 { ch = "g"; }
      elif c == 104 { ch = "h"; }
      elif c == 105 { ch = "i"; }
      elif c == 106 { ch = "j"; }
      elif c == 107 { ch = "k"; }
      elif c == 108 { ch = "l"; }
      elif c == 109 { ch = "m"; }
      elif c == 110 { ch = "n"; }
      elif c == 111 { ch = "o"; }
      elif c == 112 { ch = "p"; }
      elif c == 113 { ch = "q"; }
      elif c == 114 { ch = "r"; }
      elif c == 115 { ch = "s"; }
      elif c == 116 { ch = "t"; }
      elif c == 117 { ch = "u"; }
      elif c == 118 { ch = "v"; }
      elif c == 119 { ch = "w"; }
      elif c == 120 { ch = "x"; }
      elif c == 121 { ch = "y"; }
      elif c == 122 { ch = "z"; }
      else { ch = "?"; }
    }
    else { ch = "?"; }
    result = result + ch;
    p = p + 1;
  }
  return result;
}

fn parse_until_crlf(input: Str, pos: Int) -> Str {
  var result: Str = "";
  var p: Int = pos;
  var len: Int = @axiom_str_len(input);
  while p + 1 < len {
    var c: Int = char_at(input, p);
    var cn: Int = char_at(input, p + 1);
    if is_cr(c) && is_lf(cn) {
      return result;
    }
    var ch: Str = "";
    if c == 13 { ch = "\r"; }
    elif c == 10 { ch = "\n"; }
    elif c == 32 { ch = " "; }
    elif c == 33 { ch = "!"; }
    elif c == 34 { ch = "\""; }
    elif c == 35 { ch = "#"; }
    elif c == 36 { ch = "$"; }
    elif c == 37 { ch = "%"; }
    elif c == 38 { ch = "&"; }
    elif c == 39 { ch = "'"; }
    elif c == 40 { ch = "("; }
    elif c == 41 { ch = ")"; }
    elif c == 42 { ch = "*"; }
    elif c == 43 { ch = "+"; }
    elif c == 44 { ch = ","; }
    elif c == 45 { ch = "-"; }
    elif c == 46 { ch = "."; }
    elif c == 47 { ch = "/"; }
    elif c == 48 { ch = "0"; }
    elif c == 49 { ch = "1"; }
    elif c == 50 { ch = "2"; }
    elif c == 51 { ch = "3"; }
    elif c == 52 { ch = "4"; }
    elif c == 53 { ch = "5"; }
    elif c == 54 { ch = "6"; }
    elif c == 55 { ch = "7"; }
    elif c == 56 { ch = "8"; }
    elif c == 57 { ch = "9"; }
    elif c == 58 { ch = ":"; }
    elif c == 59 { ch = ";"; }
    elif c == 60 { ch = "<"; }
    elif c == 61 { ch = "="; }
    elif c == 62 { ch = ">"; }
    elif c == 63 { ch = "?"; }
    elif c == 64 { ch = "@"; }
    elif c >= 65 && c <= 90 {
      if c == 65 { ch = "A"; }
      elif c == 66 { ch = "B"; }
      elif c == 67 { ch = "C"; }
      elif c == 68 { ch = "D"; }
      elif c == 69 { ch = "E"; }
      elif c == 70 { ch = "F"; }
      elif c == 71 { ch = "G"; }
      elif c == 72 { ch = "H"; }
      elif c == 73 { ch = "I"; }
      elif c == 74 { ch = "J"; }
      elif c == 75 { ch = "K"; }
      elif c == 76 { ch = "L"; }
      elif c == 77 { ch = "M"; }
      elif c == 78 { ch = "N"; }
      elif c == 79 { ch = "O"; }
      elif c == 80 { ch = "P"; }
      elif c == 81 { ch = "Q"; }
      elif c == 82 { ch = "R"; }
      elif c == 83 { ch = "S"; }
      elif c == 84 { ch = "T"; }
      elif c == 85 { ch = "U"; }
      elif c == 86 { ch = "V"; }
      elif c == 87 { ch = "W"; }
      elif c == 88 { ch = "X"; }
      elif c == 89 { ch = "Y"; }
      elif c == 90 { ch = "Z"; }
      else { ch = "?"; }
    }
    elif c >= 97 && c <= 122 {
      if c == 97 { ch = "a"; }
      elif c == 98 { ch = "b"; }
      elif c == 99 { ch = "c"; }
      elif c == 100 { ch = "d"; }
      elif c == 101 { ch = "e"; }
      elif c == 102 { ch = "f"; }
      elif c == 103 { ch = "g"; }
      elif c == 104 { ch = "h"; }
      elif c == 105 { ch = "i"; }
      elif c == 106 { ch = "j"; }
      elif c == 107 { ch = "k"; }
      elif c == 108 { ch = "l"; }
      elif c == 109 { ch = "m"; }
      elif c == 110 { ch = "n"; }
      elif c == 111 { ch = "o"; }
      elif c == 112 { ch = "p"; }
      elif c == 113 { ch = "q"; }
      elif c == 114 { ch = "r"; }
      elif c == 115 { ch = "s"; }
      elif c == 116 { ch = "t"; }
      elif c == 117 { ch = "u"; }
      elif c == 118 { ch = "v"; }
      elif c == 119 { ch = "w"; }
      elif c == 120 { ch = "x"; }
      elif c == 121 { ch = "y"; }
      elif c == 122 { ch = "z"; }
      else { ch = "?"; }
    }
    else { ch = "?"; }
    result = result + ch;
    p = p + 1;
  }
  return result;
}

fn str_to_int(s: Str) -> Int {
  var result: Int = 0;
  var i: Int = 0;
  var len: Int = @axiom_str_len(s);
  var negative: Bool = false;
  if len > 0 {
    var fc: Int = @axiom_char_at(s, 0);
    if fc == 45 {
      negative = true;
      i = 1;
    }
  }
  while i < len {
    var c: Int = @axiom_char_at(s, i);
    if is_digit(c) {
      result = result * 10 + (c - 48);
    }
    i = i + 1;
  }
  if negative { return -result; }
  return result;
}

fn parse_request_line(input: Str, pos_ref: &mut Int) -> Result[HttpRequest, HttpParseError] {
  var len: Int = @axiom_str_len(input);
  var method_str: Str = parse_until(input, pos_ref, 32);
  var method: HttpMethod = method_from_str(method_str);
  pos_ref = pos_ref + @axiom_str_len(method_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of request line", position: pos_ref });
  }
  var path_str: Str = parse_until(input, pos_ref, 32);
  pos_ref = pos_ref + @axiom_str_len(path_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of request line", position: pos_ref });
  }
  var version_str: Str = parse_until_crlf(input, pos_ref);
  pos_ref = pos_ref + @axiom_str_len(version_str) + 2;
  var version: HttpVersion = version_from_str(version_str);
  return Ok(HttpRequest{
    method: method,
    path: path_str,
    version: version,
    headers: HttpHeaders.new(),
    body: Vec[Int].new(),
  });
}

fn parse_response_line(input: Str, pos_ref: &mut Int) -> Result[HttpResponse, HttpParseError] {
  var len: Int = @axiom_str_len(input);
  var version_str: Str = parse_until(input, pos_ref, 32);
  pos_ref = pos_ref + @axiom_str_len(version_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of response line", position: pos_ref });
  }
  var status_str: Str = parse_until(input, pos_ref, 32);
  pos_ref = pos_ref + @axiom_str_len(status_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of response line", position: pos_ref });
  }
  var reason_str: Str = parse_until_crlf(input, pos_ref);
  pos_ref = pos_ref + @axiom_str_len(reason_str) + 2;
  var status: Int = str_to_int(status_str);
  return Ok(HttpResponse{
    version: version_from_str(version_str),
    status: status,
    reason: reason_str,
    headers: HttpHeaders.new(),
    body: Vec[Int].new(),
  });
}

fn parse_header_line(line: Str) -> Result[HttpHeader, HttpParseError] {
  var len: Int = @axiom_str_len(line);
  var i: Int = 0;
  while i < len {
    var c: Int = @axiom_char_at(line, i);
    if c == 58 {
      var name: Str = "";
      var j: Int = 0;
      while j < i {
        var nc: Int = @axiom_char_at(line, j);
        var ch: Str = "";
        if nc >= 65 && nc <= 90 {
          if nc == 65 { ch = "A"; }
          elif nc == 66 { ch = "B"; }
          elif nc == 67 { ch = "C"; }
          elif nc == 68 { ch = "D"; }
          elif nc == 69 { ch = "E"; }
          elif nc == 70 { ch = "F"; }
          elif nc == 71 { ch = "G"; }
          elif nc == 72 { ch = "H"; }
          elif nc == 73 { ch = "I"; }
          elif nc == 74 { ch = "J"; }
          elif nc == 75 { ch = "K"; }
          elif nc == 76 { ch = "L"; }
          elif nc == 77 { ch = "M"; }
          elif nc == 78 { ch = "N"; }
          elif nc == 79 { ch = "O"; }
          elif nc == 80 { ch = "P"; }
          elif nc == 81 { ch = "Q"; }
          elif nc == 82 { ch = "R"; }
          elif nc == 83 { ch = "S"; }
          elif nc == 84 { ch = "T"; }
          elif nc == 85 { ch = "U"; }
          elif nc == 86 { ch = "V"; }
          elif nc == 87 { ch = "W"; }
          elif nc == 88 { ch = "X"; }
          elif nc == 89 { ch = "Y"; }
          elif nc == 90 { ch = "Z"; }
          else { ch = "?"; }
        }
        elif nc >= 97 && nc <= 122 {
          if nc == 97 { ch = "a"; }
          elif nc == 98 { ch = "b"; }
          elif nc == 99 { ch = "c"; }
          elif nc == 100 { ch = "d"; }
          elif nc == 101 { ch = "e"; }
          elif nc == 102 { ch = "f"; }
          elif nc == 103 { ch = "g"; }
          elif nc == 104 { ch = "h"; }
          elif nc == 105 { ch = "i"; }
          elif nc == 106 { ch = "j"; }
          elif nc == 107 { ch = "k"; }
          elif nc == 108 { ch = "l"; }
          elif nc == 109 { ch = "m"; }
          elif nc == 110 { ch = "n"; }
          elif nc == 111 { ch = "o"; }
          elif nc == 112 { ch = "p"; }
          elif nc == 113 { ch = "q"; }
          elif nc == 114 { ch = "r"; }
          elif nc == 115 { ch = "s"; }
          elif nc == 116 { ch = "t"; }
          elif nc == 117 { ch = "u"; }
          elif nc == 118 { ch = "v"; }
          elif nc == 119 { ch = "w"; }
          elif nc == 120 { ch = "x"; }
          elif nc == 121 { ch = "y"; }
          elif nc == 122 { ch = "z"; }
          else { ch = "?"; }
        }
        elif nc == 45 { ch = "-"; }
        else { ch = "?"; }
        name = name + ch;
        j = j + 1;
      }
      i = i + 1;
      while i < len {
        var sc: Int = @axiom_char_at(line, i);
        if sc == 32 { i = i + 1; }
        else { break; }
      }
      var value: Str = "";
      j = i;
      while j < len {
        var vc: Int = @axiom_char_at(line, j);
        var vch: Str = "";
        if vc == 32 { vch = " "; }
        elif vc == 33 { vch = "!"; }
        elif vc == 34 { vch = "\""; }
        elif vc == 35 { vch = "#"; }
        elif vc == 36 { vch = "$"; }
        elif vc == 37 { vch = "%"; }
        elif vc == 38 { vch = "&"; }
        elif vc == 39 { vch = "'"; }
        elif vc == 40 { vch = "("; }
        elif vc == 41 { vch = ")"; }
        elif vc == 42 { vch = "*"; }
        elif vc == 43 { vch = "+"; }
        elif vc == 44 { vch = ","; }
        elif vc == 45 { vch = "-"; }
        elif vc == 46 { vch = "."; }
        elif vc == 47 { vch = "/"; }
        elif vc == 48 { vch = "0"; }
        elif vc == 49 { vch = "1"; }
        elif vc == 50 { vch = "2"; }
        elif vc == 51 { vch = "3"; }
        elif vc == 52 { vch = "4"; }
        elif vc == 53 { vch = "5"; }
        elif vc == 54 { vch = "6"; }
        elif vc == 55 { vch = "7"; }
        elif vc == 56 { vch = "8"; }
        elif vc == 57 { vch = "9"; }
        elif vc == 58 { vch = ":"; }
        elif vc == 59 { vch = ";"; }
        elif vc == 60 { vch = "<"; }
        elif vc == 61 { vch = "="; }
        elif vc == 62 { vch = ">"; }
        elif vc == 63 { vch = "?"; }
        elif vc == 64 { vch = "@"; }
        elif vc >= 65 && vc <= 90 {
          if vc == 65 { vch = "A"; }
          elif vc == 66 { vch = "B"; }
          elif vc == 67 { vch = "C"; }
          elif vc == 68 { vch = "D"; }
          elif vc == 69 { vch = "E"; }
          elif vc == 70 { vch = "F"; }
          elif vc == 71 { vch = "G"; }
          elif vc == 72 { vch = "H"; }
          elif vc == 73 { vch = "I"; }
          elif vc == 74 { vch = "J"; }
          elif vc == 75 { vch = "K"; }
          elif vc == 76 { vch = "L"; }
          elif vc == 77 { vch = "M"; }
          elif vc == 78 { vch = "N"; }
          elif vc == 79 { vch = "O"; }
          elif vc == 80 { vch = "P"; }
          elif vc == 81 { vch = "Q"; }
          elif vc == 82 { vch = "R"; }
          elif vc == 83 { vch = "S"; }
          elif vc == 84 { vch = "T"; }
          elif vc == 85 { vch = "U"; }
          elif vc == 86 { vch = "V"; }
          elif vc == 87 { vch = "W"; }
          elif vc == 88 { vch = "X"; }
          elif vc == 89 { vch = "Y"; }
          elif vc == 90 { vch = "Z"; }
          else { vch = "?"; }
        }
        elif vc >= 97 && vc <= 122 {
          if vc == 97 { vch = "a"; }
          elif vc == 98 { vch = "b"; }
          elif vc == 99 { vch = "c"; }
          elif vc == 100 { vch = "d"; }
          elif vc == 101 { vch = "e"; }
          elif vc == 102 { vch = "f"; }
          elif vc == 103 { vch = "g"; }
          elif vc == 104 { vch = "h"; }
          elif vc == 105 { vch = "i"; }
          elif vc == 106 { vch = "j"; }
          elif vc == 107 { vch = "k"; }
          elif vc == 108 { vch = "l"; }
          elif vc == 109 { vch = "m"; }
          elif vc == 110 { vch = "n"; }
          elif vc == 111 { vch = "o"; }
          elif vc == 112 { vch = "p"; }
          elif vc == 113 { vch = "q"; }
          elif vc == 114 { vch = "r"; }
          elif vc == 115 { vch = "s"; }
          elif vc == 116 { vch = "t"; }
          elif vc == 117 { vch = "u"; }
          elif vc == 118 { vch = "v"; }
          elif vc == 119 { vch = "w"; }
          elif vc == 120 { vch = "x"; }
          elif vc == 121 { vch = "y"; }
          elif vc == 122 { vch = "z"; }
          else { vch = "?"; }
        }
        else { vch = "?"; }
        value = value + vch;
        j = j + 1;
      }
      return Ok(HttpHeader{ name: name, value: value });
    }
    i = i + 1;
  }
  return Err(HttpParseError{ message: "Invalid header line: no colon found", position: 0 });
}

pub fn http_parse_request(input: Str) -> Result[HttpRequest, HttpParseError]
  requires: input.len() > 0 {
  var pos: Int = 0;
  var len: Int = @axiom_str_len(input);
  if len == 0 {
    return Err(HttpParseError{ message: "Empty input", position: 0 });
  }
  var req_result: Result[HttpRequest, HttpParseError] = parse_request_line(input, &mut pos);
  match req_result {
    Ok(mut req) => {
      var headers: HttpHeaders = HttpHeaders.new();
      while pos + 1 < len {
        var c0: Int = char_at(input, pos);
        var c1: Int = char_at(input, pos + 1);
        if is_cr(c0) && is_lf(c1) {
          pos = pos + 2;
          break;
        }
        var line: Str = parse_until_crlf(input, pos);
        var line_len: Int = @axiom_str_len(line);
        if line_len > 0 {
          var header_result: Result[HttpHeader, HttpParseError] = parse_header_line(line);
          match header_result {
            Ok(hdr) => { headers.add(hdr.name, hdr.value); }
            Err(e) => { return Err(e); }
          }
        }
        pos = pos + line_len + 2;
      }
      req.headers = headers;
      var body_vec: Vec[Int] = Vec[Int].new();
      while pos < len {
        body_vec.push(char_at(input, pos));
        pos = pos + 1;
      }
      req.body = body_vec;
      return Ok(req);
    }
    Err(e) => { return Err(e); }
  }
}

pub fn http_parse_response(input: Str) -> Result[HttpResponse, HttpParseError]
  requires: input.len() > 0 {
  var pos: Int = 0;
  var len: Int = @axiom_str_len(input);
  if len == 0 {
    return Err(HttpParseError{ message: "Empty input", position: 0 });
  }
  var resp_result: Result[HttpResponse, HttpParseError] = parse_response_line(input, &mut pos);
  match resp_result {
    Ok(mut resp) => {
      var headers: HttpHeaders = HttpHeaders.new();
      while pos + 1 < len {
        var c0: Int = char_at(input, pos);
        var c1: Int = char_at(input, pos + 1);
        if is_cr(c0) && is_lf(c1) {
          pos = pos + 2;
          break;
        }
        var line: Str = parse_until_crlf(input, pos);
        var line_len: Int = @axiom_str_len(line);
        if line_len > 0 {
          var header_result: Result[HttpHeader, HttpParseError] = parse_header_line(line);
          match header_result {
            Ok(hdr) => { headers.add(hdr.name, hdr.value); }
            Err(e) => { return Err(e); }
          }
        }
        pos = pos + line_len + 2;
      }
      resp.headers = headers;
      var body_vec: Vec[Int] = Vec[Int].new();
      while pos < len {
        body_vec.push(char_at(input, pos));
        pos = pos + 1;
      }
      resp.body = body_vec;
      return Ok(resp);
    }
    Err(e) => { return Err(e); }
  }
}

pub fn http_parse_headers(input: Str) -> Result[HttpHeaders, HttpParseError] {
  var headers: HttpHeaders = HttpHeaders.new();
  var pos: Int = 0;
  var len: Int = @axiom_str_len(input);
  while pos + 1 < len {
    var c0: Int = char_at(input, pos);
    var c1: Int = char_at(input, pos + 1);
    if is_cr(c0) && is_lf(c1) {
      return Ok(headers);
    }
    var line: Str = parse_until_crlf(input, pos);
    var line_len: Int = @axiom_str_len(line);
    if line_len > 0 {
      var header_result: Result[HttpHeader, HttpParseError] = parse_header_line(line);
      match header_result {
        Ok(hdr) => { headers.add(hdr.name, hdr.value); }
        Err(e) => { return Err(e); }
      }
    }
    pos = pos + line_len + 2;
  }
  return Ok(headers);
}
