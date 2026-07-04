module xiom.http.client

pub fn http_get(url: Str) -> Result[HttpResponse, Str] {
  return Err("HTTP GET: TCP transport layer not yet available (requires Layer 3.1)");
}

pub fn http_post(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str] {
  return Err("HTTP POST: TCP transport layer not yet available (requires Layer 3.1)");
}

pub fn http_put(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str] {
  return Err("HTTP PUT: TCP transport layer not yet available (requires Layer 3.1)");
}

pub fn http_delete(url: Str) -> Result[HttpResponse, Str] {
  return Err("HTTP DELETE: TCP transport layer not yet available (requires Layer 3.1)");
}

pub fn http_send(request: &HttpRequest, url: &Url) -> Result[HttpResponse, Str] {
  return Err("HTTP send: TCP transport layer not yet available (requires Layer 3.1)");
}
