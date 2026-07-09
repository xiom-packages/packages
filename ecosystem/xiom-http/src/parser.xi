module xiom.http.parser

use xiom.string;

pub type HttpParseError = {
  message: Str;
  position: Int;
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

fn parse_until(input: Str, pos: Int, target: Int) -> Str {
  var len: Int = xiom.string.str_len(input);
  var p: Int = pos;
  while p < len {
    var c: Int = xiom.string.char_at(input, p);
    if c == target {
      return xiom.string.str_slice(input, pos, p);
    }
    p = p + 1;
  }
  return xiom.string.str_slice(input, pos, len);
}

fn parse_until_crlf(input: Str, pos: Int) -> Str {
  var len: Int = xiom.string.str_len(input);
  var p: Int = pos;
  while p + 1 < len {
    var c: Int = xiom.string.char_at(input, p);
    var cn: Int = xiom.string.char_at(input, p + 1);
    if is_cr(c) && is_lf(cn) {
      return xiom.string.str_slice(input, pos, p);
    }
    p = p + 1;
  }
  return xiom.string.str_slice(input, pos, len);
}

fn str_to_int(s: Str) -> Int {
  var result: Int = 0;
  var i: Int = 0;
  var len: Int = xiom.string.str_len(s);
  var negative: Bool = false;
  if len > 0 {
    var fc: Int = xiom.string.char_at(s, 0);
    if fc == 45 {
      negative = true;
      i = 1;
    }
  }
  while i < len {
    var c: Int = xiom.string.char_at(s, i);
    if is_digit(c) {
      result = result * 10 + (c - 48);
    }
    i = i + 1;
  }
  if negative { return -result; }
  return result;
}

fn parse_request_line(input: Str, pos_ref: &mut Int) -> Result[HttpRequest, HttpParseError] {
  var len: Int = xiom.string.str_len(input);
  var method_str: Str = parse_until(input, pos_ref, 32);
  var method: HttpMethod = method_from_str(method_str);
  pos_ref = pos_ref + xiom.string.str_len(method_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of request line", position: pos_ref });
  }
  var path_str: Str = parse_until(input, pos_ref, 32);
  pos_ref = pos_ref + xiom.string.str_len(path_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of request line", position: pos_ref });
  }
  var version_str: Str = parse_until_crlf(input, pos_ref);
  pos_ref = pos_ref + xiom.string.str_len(version_str) + 2;
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
  var len: Int = xiom.string.str_len(input);
  var version_str: Str = parse_until(input, pos_ref, 32);
  pos_ref = pos_ref + xiom.string.str_len(version_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of response line", position: pos_ref });
  }
  var status_str: Str = parse_until(input, pos_ref, 32);
  pos_ref = pos_ref + xiom.string.str_len(status_str) + 1;
  if pos_ref >= len {
    return Err(HttpParseError{ message: "Unexpected end of response line", position: pos_ref });
  }
  var reason_str: Str = parse_until_crlf(input, pos_ref);
  pos_ref = pos_ref + xiom.string.str_len(reason_str) + 2;
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
  var len: Int = xiom.string.str_len(line);
  var colon_pos: Int = -1;
  var i: Int = 0;
  while i < len {
    var c: Int = xiom.string.char_at(line, i);
    if c == 58 {
      colon_pos = i;
      break;
    }
    i = i + 1;
  }
  if colon_pos < 0 {
    return Err(HttpParseError{ message: "Invalid header line: no colon found", position: 0 });
  }
  var name: Str = xiom.string.str_slice(line, 0, colon_pos);
  var value: Str = xiom.string.str_slice(line, colon_pos + 1, len);
  value = xiom.string.str_trim(value);
  return Ok(HttpHeader{ name: name, value: value });
}

pub fn http_parse_request(input: Str) -> Result[HttpRequest, HttpParseError]
  requires: input.len() > 0 {
  var pos: Int = 0;
  var len: Int = xiom.string.str_len(input);
  if len == 0 {
    return Err(HttpParseError{ message: "Empty input", position: 0 });
  }
  var req_result: Result[HttpRequest, HttpParseError] = parse_request_line(input, &mut pos);
  match req_result {
    Ok(req) => {
      var headers: HttpHeaders = HttpHeaders.new();
      while pos + 1 < len {
        var c0: Int = xiom.string.char_at(input, pos);
        var c1: Int = xiom.string.char_at(input, pos + 1);
        if is_cr(c0) && is_lf(c1) {
          pos = pos + 2;
          break;
        }
        var line: Str = parse_until_crlf(input, pos);
        var line_len: Int = xiom.string.str_len(line);
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
        body_vec.push(xiom.string.char_at(input, pos));
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
  var len: Int = xiom.string.str_len(input);
  if len == 0 {
    return Err(HttpParseError{ message: "Empty input", position: 0 });
  }
  var resp_result: Result[HttpResponse, HttpParseError] = parse_response_line(input, &mut pos);
  match resp_result {
    Ok(resp) => {
      var headers: HttpHeaders = HttpHeaders.new();
      while pos + 1 < len {
        var c0: Int = xiom.string.char_at(input, pos);
        var c1: Int = xiom.string.char_at(input, pos + 1);
        if is_cr(c0) && is_lf(c1) {
          pos = pos + 2;
          break;
        }
        var line: Str = parse_until_crlf(input, pos);
        var line_len: Int = xiom.string.str_len(line);
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
        body_vec.push(xiom.string.char_at(input, pos));
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
  var len: Int = xiom.string.str_len(input);
  while pos + 1 < len {
    var c0: Int = xiom.string.char_at(input, pos);
    var c1: Int = xiom.string.char_at(input, pos + 1);
    if is_cr(c0) && is_lf(c1) {
      return Ok(headers);
    }
    var line: Str = parse_until_crlf(input, pos);
    var line_len: Int = xiom.string.str_len(line);
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
