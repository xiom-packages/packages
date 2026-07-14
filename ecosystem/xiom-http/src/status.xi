module xiom.http.status

pub fn http_status_text(code: Int) -> Str {
  if code == 100 { return "Continue"; }
  elif code == 101 { return "Switching Protocols"; }
  elif code == 200 { return "OK"; }
  elif code == 201 { return "Created"; }
  elif code == 202 { return "Accepted"; }
  elif code == 204 { return "No Content"; }
  elif code == 206 { return "Partial Content"; }
  elif code == 301 { return "Moved Permanently"; }
  elif code == 302 { return "Found"; }
  elif code == 303 { return "See Other"; }
  elif code == 304 { return "Not Modified"; }
  elif code == 307 { return "Temporary Redirect"; }
  elif code == 308 { return "Permanent Redirect"; }
  elif code == 400 { return "Bad Request"; }
  elif code == 401 { return "Unauthorized"; }
  elif code == 403 { return "Forbidden"; }
  elif code == 404 { return "Not Found"; }
  elif code == 405 { return "Method Not Allowed"; }
  elif code == 406 { return "Not Acceptable"; }
  elif code == 408 { return "Request Timeout"; }
  elif code == 409 { return "Conflict"; }
  elif code == 410 { return "Gone"; }
  elif code == 413 { return "Payload Too Large"; }
  elif code == 414 { return "URI Too Long"; }
  elif code == 415 { return "Unsupported Media Type"; }
  elif code == 422 { return "Unprocessable Entity"; }
  elif code == 429 { return "Too Many Requests"; }
  elif code == 500 { return "Internal Server Error"; }
  elif code == 501 { return "Not Implemented"; }
  elif code == 502 { return "Bad Gateway"; }
  elif code == 503 { return "Service Unavailable"; }
  elif code == 504 { return "Gateway Timeout"; }
  return "Unknown";
}

pub fn http_is_success(code: Int) -> Bool {
  return code >= 200 && code < 300;
}

pub fn http_is_redirect(code: Int) -> Bool {
  return code >= 300 && code < 400;
}

pub fn http_is_client_error(code: Int) -> Bool {
  return code >= 400 && code < 500;
}

pub fn http_is_server_error(code: Int) -> Bool {
  return code >= 500 && code < 600;
}

pub fn http_status_category(code: Int) -> Int {
  if code >= 100 && code < 200 { return 100; }
  elif code >= 200 && code < 300 { return 200; }
  elif code >= 300 && code < 400 { return 300; }
  elif code >= 400 && code < 500 { return 400; }
  elif code >= 500 && code < 600 { return 500; }
  return 0;
}
