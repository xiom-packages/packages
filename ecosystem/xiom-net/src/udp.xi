module xiom.net.udp

pub type UdpSocket = {
  fd: Int;
  bound: Bool;
} derive[Clone]

extern "C" {
  fn socket(af: Int, typ: Int, protocol: Int) -> Int;
  fn bind(sock: Int, addr: *UInt8, addrlen: Int) -> Int;
  fn sendto(sock: Int, buf: *UInt8, len: Int, flags: Int, addr: *UInt8, addrlen: Int) -> Int;
  fn recvfrom(sock: Int, buf: *UInt8, len: Int, flags: Int, addr: *UInt8, addrlen: *UInt8) -> Int;
  fn closesocket(sock: Int) -> Int;
  fn WSAGetLastError() -> Int;
  fn WSAStartup(version: Int, data: *UInt8) -> Int;
  fn WSACleanup() -> Int;
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

fn make_error() -> Str {
  var err = unsafe { WSAGetLastError() };
  return ws_error_to_str(err);
}

pub fn udp_bind(addr: SocketAddr) -> Result[UdpSocket, Str] {
  var init = ensure_wsa();
  match init {
    Err(msg) => { return Err(msg); },
    Ok(()) => {},
  };

  var fd = unsafe { socket(AF_INET, SOCK_DGRAM, 0) };
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

  return Ok(UdpSocket{ fd: fd, bound: true });
}

pub fn udp_send_to(socket: &UdpSocket, data: &Vec[Int], addr: SocketAddr) -> Result[Int, Str] {
  if !socket.bound {
    return Err("socket is not bound");
  };

  var data_len: Int = data.len();
  if data_len == 0 { return Ok(0); };

  var sockaddr = build_sockaddr_in(&addr);
  var bytes = unsafe { sendto(socket.fd, &data[0], data_len, 0, &sockaddr[0], 16) };
  if bytes == SOCKET_ERROR {
    return Err("sendto() failed: " + make_error());
  };
  return Ok(bytes);
}

pub fn udp_recv_from(socket: &UdpSocket, buf: &mut Vec[Int]) -> Result[(Int, SocketAddr), Str] {
  if !socket.bound {
    return Err("socket is not bound");
  };

  var buf_len: Int = buf.len();
  if buf_len == 0 {
    var empty_addr = socket_addr(ipv4(0, 0, 0, 0), 0);
    return Ok((0, empty_addr));
  };

  var recv_buf = Vec[Int].new();
  var i: Int = 0;
  while i < buf_len {
    recv_buf.push(0);
    i = i + 1;
  };

  var addr_buf = Vec[Int].new();
  var j: Int = 0;
  while j < 16 {
    addr_buf.push(0);
    j = j + 1;
  };
  var addrlen_buf = Vec[Int].new();
  addrlen_buf.push(16 & 0xFF);
  addrlen_buf.push(0);
  addrlen_buf.push(0);
  addrlen_buf.push(0);

  var bytes = unsafe { recvfrom(socket.fd, &recv_buf[0], buf_len, 0, &addr_buf[0], &addrlen_buf[0]) };
  if bytes == SOCKET_ERROR {
    return Err("recvfrom() failed: " + make_error());
  };

  var k: Int = 0;
  while k < bytes {
    buf[k] = recv_buf[k];
    k = k + 1;
  };

  var parsed = parse_sockaddr_in(&addr_buf);
  match parsed {
    Ok(sa) => { return Ok((bytes, sa)); },
    Err(_) => {
      var fallback = socket_addr(ipv4(0, 0, 0, 0), 0);
      return Ok((bytes, fallback));
    },
  }
}

pub fn udp_close(socket: UdpSocket) {
  if socket.fd >= 0 {
    var _closed = unsafe { closesocket(socket.fd) };
  };
}
