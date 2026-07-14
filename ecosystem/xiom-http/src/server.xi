module xiom.http.server

pub type HttpServer = {
  addr: Str;
  port: Int;
  running: Bool;
}

pub type HttpHandler = {
  path: Str;
  method: HttpMethod;
}

pub fn server_new(addr: Str, port: Int) -> HttpServer
  requires: addr.len() > 0
  requires: port > 0
  requires: port < 65536 {
  return HttpServer{
    addr: addr,
    port: port,
    running: false,
  };
}

pub fn server_listen(server: &mut HttpServer) -> Result[Unit, Str] {
  return Err("HTTP server listen: TCP transport layer not yet available (requires Layer 3.1)");
}

pub fn server_handle(server: &mut HttpServer, method: HttpMethod, path: Str) -> Result[Unit, Str] {
  return Err("HTTP server handler: TCP transport layer not yet available (requires Layer 3.1)");
}

pub fn server_close(server: HttpServer) {
  var s: HttpServer = server;
  s.running = false;
}
