module xiom.net.tcp

pub type TcpStream = {
  fd: Int;
  connected: Bool;
  remote: SocketAddr;
} derive[Clone]

pub type TcpListener = {
  fd: Int;
  bound: Bool;
  addr: SocketAddr;
} derive[Clone]

extern "C" {
  fn socket(af: Int, typ: Int, protocol: Int) -> Int;
  fn connect(sock: Int, addr: *UInt8, addrlen: Int) -> Int;
  fn bind(sock: Int, addr: *UInt8, addrlen: Int) -> Int;
  fn listen(sock: Int, backlog: Int) -> Int;
  fn accept(sock: Int, addr: *UInt8, addrlen: *UInt8) -> Int;
  fn send(sock: Int, buf: *UInt8, len: Int, flags: Int) -> Int;
  fn recv(sock: Int, buf: *UInt8, len: Int, flags: Int) -> Int;
  fn closesocket(sock: Int) -> Int;
  fn WSAGetLastError() -> Int;
  fn WSAStartup(version: Int, data: *UInt8) -> Int;
  fn WSACleanup() -> Int;
  fn shutdown(sock: Int, how: Int) -> Int;
}

var wsa_initialized: Bool = false;

fn ensure_wsa() -> Result[Unit, Str] {
  if wsa_initialized { return Ok(()); };
  var version: Int = (2 << 8) | 2;
  var data = Vec[Int].new();
  var i: Int = 0;
  while i < 400 {
    data.push(0);
    i = i + 1;
  };
  var result = unsafe { WSAStartup(version, &data[0]) };
  if result != 0 {
    var err = unsafe { WSAGetLastError() };
    return Err("WSAStartup failed: " + ws_error_to_str(err));
  };
  wsa_initialized = true;
  return Ok(());
}

pub fn wsa_cleanup() {
  if wsa_initialized {
    var _discard = unsafe { WSACleanup() };
    wsa_initialized = false;
  };
}

fn sockaddr_to_ptr(addr: &Vec[Int]) -> *UInt8 {
  return unsafe { &addr[0] };
}

fn make_error() -> Str {
  var err = unsafe { WSAGetLastError() };
  return ws_error_to_str(err);
}

pub fn tcp_connect(addr: SocketAddr) -> Result[TcpStream, Str]
  requires: addr.port > 0
  requires: addr.port < 65536
{
  var init = ensure_wsa();
  match init {
    Err(msg) => { return Err(msg); },
    Ok(()) => {},
  };

  var fd = unsafe { socket(AF_INET, SOCK_STREAM, 0) };
  if fd == INVALID_SOCKET || fd < 0 {
    return Err("socket() failed: " + make_error());
  };

  var sockaddr = build_sockaddr_in(&addr);
  var conn_result = unsafe { connect(fd, &sockaddr[0], 16) };
  if conn_result == SOCKET_ERROR {
    var err_msg = make_error();
    var _close = unsafe { closesocket(fd) };
    return Err("connect() failed: " + err_msg);
  };

  return Ok(TcpStream{ fd: fd, connected: true, remote: addr });
}

pub fn tcp_listen(addr: SocketAddr) -> Result[TcpListener, Str]
  requires: addr.port > 0
  requires: addr.port < 65536
{
  var init = ensure_wsa();
  match init {
    Err(msg) => { return Err(msg); },
    Ok(()) => {},
  };

  var fd = unsafe { socket(AF_INET, SOCK_STREAM, 0) };
  if fd == INVALID_SOCKET || fd < 0 {
    return Err("socket() failed: " + make_error());
  };

  var sockaddr = build_sockaddr_in(&addr);
  var bind_result = unsafe { bind(fd, &sockaddr[0], 16) };
  if bind_result == SOCKET_ERROR {
    var err_msg = make_error();
    var _close = unsafe { closesocket(fd) };
    return Err("bind() failed: " + err_msg);
  };

  var listen_result = unsafe { listen(fd, SOMAXCONN) };
  if listen_result == SOCKET_ERROR {
    var err_msg = make_error();
    var _close = unsafe { closesocket(fd) };
    return Err("listen() failed: " + err_msg);
  };

  return Ok(TcpListener{ fd: fd, bound: true, addr: addr });
}

pub fn tcp_accept(listener: &mut TcpListener) -> Result[TcpStream, Str]
  requires: listener.bound
{
  if !listener.bound {
    return Err("listener is not bound");
  };

  var addr_buf = Vec[Int].new();
  var i: Int = 0;
  while i < 16 {
    addr_buf.push(0);
    i = i + 1;
  };
  var addrlen_buf = Vec[Int].new();
  addrlen_buf.push(16 & 0xFF);
  addrlen_buf.push(0);
  addrlen_buf.push(0);
  addrlen_buf.push(0);

  var client_fd = unsafe { accept(listener.fd, &addr_buf[0], &addrlen_buf[0]) };
  if client_fd == INVALID_SOCKET || client_fd < 0 {
    return Err("accept() failed: " + make_error());
  };

  var parsed = parse_sockaddr_in(&addr_buf);
  var remote = listener.addr;
  match parsed {
    Ok(sa) => { remote = sa; },
    Err(_) => {},
  };

  return Ok(TcpStream{ fd: client_fd, connected: true, remote: remote });
}

pub fn tcp_read(stream: &mut TcpStream, buf: &mut Vec[Int]) -> Result[Int, Str]
  requires: stream.connected
{
  if !stream.connected {
    return Err("stream is not connected");
  };

  var recv_buf = Vec[Int].new();
  var i: Int = 0;
  var buf_len: Int = buf.len();
  if buf_len == 0 { return Ok(0); };
  while i < buf_len {
    recv_buf.push(0);
    i = i + 1;
  };

  var bytes = unsafe { recv(stream.fd, &recv_buf[0], buf_len, 0) };
  if bytes == SOCKET_ERROR {
    return Err("recv() failed: " + make_error());
  };
  if bytes == 0 {
    stream.connected = false;
    return Ok(0);
  };

  var j: Int = 0;
  while j < bytes {
    buf[j] = recv_buf[j];
    j = j + 1;
  };
  return Ok(bytes);
}

pub fn tcp_write(stream: &mut TcpStream, data: &Vec[Int]) -> Result[Int, Str]
  requires: stream.connected
  requires: data.len() > 0
{
  if !stream.connected {
    return Err("stream is not connected");
  };

  var data_len: Int = data.len();
  if data_len == 0 { return Ok(0); };

  var bytes = unsafe { send(stream.fd, &data[0], data_len, 0) };
  if bytes == SOCKET_ERROR {
    return Err("send() failed: " + make_error());
  };
  return Ok(bytes);
}

pub fn tcp_close(stream: TcpStream)
  requires: stream.connected
{
  if stream.fd >= 0 {
    var _shut = unsafe { shutdown(stream.fd, 2) };
    var _closed = unsafe { closesocket(stream.fd) };
  };
}

pub fn tcp_listener_close(listener: TcpListener)
  requires: listener.bound
{
  if listener.fd >= 0 {
    var _closed = unsafe { closesocket(listener.fd) };
  };
}

pub fn tcp_is_connected(stream: &TcpStream) -> Bool {
  return stream.connected;
}

pub fn tcp_remote_addr(stream: &TcpStream) -> SocketAddr
  requires: stream.connected
{
  return stream.remote;
}
