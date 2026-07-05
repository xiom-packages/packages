module xiom.http.client

pub fn http_get(url: Str) -> Result[HttpResponse, Str] {
  return xiom.http.http_get(url);
}

pub fn http_post(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str] {
  var body_str: Str = str_from_vec_byte(body);
  return xiom.http.http_post(url, body_str, content_type);
}

pub fn http_put(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str] {
  var body_str: Str = str_from_vec_byte(body);
  return xiom.http.http_put(url, body_str);
}

pub fn http_delete(url: Str) -> Result[HttpResponse, Str] {
  return xiom.http.http_delete(url);
}

pub fn http_send(request: &HttpRequest, url: &Url) -> Result[HttpResponse, Str] {
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

fn byte_to_char(b: Int) -> Str {
  if b == 0 { return "\0"; };
  if b == 10 { return "\n"; };
  if b == 13 { return "\r"; };
  if b == 9 { return "\t"; };
  if b == 32 { return " "; };
  if b == 33 { return "!"; };
  if b == 34 { return "\""; };
  if b == 35 { return "#"; };
  if b == 36 { return "$"; };
  if b == 37 { return "%"; };
  if b == 38 { return "&"; };
  if b == 39 { return "'"; };
  if b == 40 { return "("; };
  if b == 41 { return ")"; };
  if b == 42 { return "*"; };
  if b == 43 { return "+"; };
  if b == 44 { return ","; };
  if b == 45 { return "-"; };
  if b == 46 { return "."; };
  if b == 47 { return "/"; };
  if b == 48 { return "0"; };
  if b == 49 { return "1"; };
  if b == 50 { return "2"; };
  if b == 51 { return "3"; };
  if b == 52 { return "4"; };
  if b == 53 { return "5"; };
  if b == 54 { return "6"; };
  if b == 55 { return "7"; };
  if b == 56 { return "8"; };
  if b == 57 { return "9"; };
  if b == 58 { return ":"; };
  if b == 59 { return ";"; };
  if b == 60 { return "<"; };
  if b == 61 { return "="; };
  if b == 62 { return ">"; };
  if b == 63 { return "?"; };
  if b == 64 { return "@"; };
  if b >= 65 && b <= 90 {
    if b == 65 { return "A"; };
    if b == 66 { return "B"; };
    if b == 67 { return "C"; };
    if b == 68 { return "D"; };
    if b == 69 { return "E"; };
    if b == 70 { return "F"; };
    if b == 71 { return "G"; };
    if b == 72 { return "H"; };
    if b == 73 { return "I"; };
    if b == 74 { return "J"; };
    if b == 75 { return "K"; };
    if b == 76 { return "L"; };
    if b == 77 { return "M"; };
    if b == 78 { return "N"; };
    if b == 79 { return "O"; };
    if b == 80 { return "P"; };
    if b == 81 { return "Q"; };
    if b == 82 { return "R"; };
    if b == 83 { return "S"; };
    if b == 84 { return "T"; };
    if b == 85 { return "U"; };
    if b == 86 { return "V"; };
    if b == 87 { return "W"; };
    if b == 88 { return "X"; };
    if b == 89 { return "Y"; };
    if b == 90 { return "Z"; };
  };
  if b >= 97 && b <= 122 {
    if b == 97 { return "a"; };
    if b == 98 { return "b"; };
    if b == 99 { return "c"; };
    if b == 100 { return "d"; };
    if b == 101 { return "e"; };
    if b == 102 { return "f"; };
    if b == 103 { return "g"; };
    if b == 104 { return "h"; };
    if b == 105 { return "i"; };
    if b == 106 { return "j"; };
    if b == 107 { return "k"; };
    if b == 108 { return "l"; };
    if b == 109 { return "m"; };
    if b == 110 { return "n"; };
    if b == 111 { return "o"; };
    if b == 112 { return "p"; };
    if b == 113 { return "q"; };
    if b == 114 { return "r"; };
    if b == 115 { return "s"; };
    if b == 116 { return "t"; };
    if b == 117 { return "u"; };
    if b == 118 { return "v"; };
    if b == 119 { return "w"; };
    if b == 120 { return "x"; };
    if b == 121 { return "y"; };
    if b == 122 { return "z"; };
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
    if d == 0 { digits.push("0"); };
    elif d == 1 { digits.push("1"); };
    elif d == 2 { digits.push("2"); };
    elif d == 3 { digits.push("3"); };
    elif d == 4 { digits.push("4"); };
    elif d == 5 { digits.push("5"); };
    elif d == 6 { digits.push("6"); };
    elif d == 7 { digits.push("7"); };
    elif d == 8 { digits.push("8"); };
    elif d == 9 { digits.push("9"); };
  };
  var result: Str = "";
  if n < 0 { result = result + "-"; };
  var j: Int = digits.len() - 1;
  while j >= 0 {
    result = result + digits[j];
    j = j - 1;
  };
  return result;
}
