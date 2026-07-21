// XIOM — TCP Networking (Production via Winsock2 + FFI Bridge)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.net.tcp

use xiom.ptr;
use xiom.string;

// ─── XIOM FFI Bridge ────────────────────────────────────────────────────────

extern "C" {
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_write_byte(ptr: *UInt8, offset: Int, value: Int);

  fn xiom_read_byte(ptr: *UInt8, offset: Int) -> Int;

  fn xiom_copy_from_vec(c_buf: *UInt8, vec_data: *UInt8, vec_len: Int, vec_cap: Int, offset: Int, count: Int);
}

// ─── Winsock2 FFI ───────────────────────────────────────────────────────────

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

// ─── Types ──────────────────────────────────────────────────────────────────
// NOTE: SocketAddr and IpAddr are defined in xiom.net.types (same package).
// They are package-level visible and auto-resolved at compile time.

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

// ─── Constants ──────────────────────────────────────────────────────────────

fn AF_INET() -> Int { return 2; }
fn SOCK_STREAM() -> Int { return 1; }
fn INVALID_SOCKET() -> Int { return -1; }
fn SOCKET_ERROR() -> Int { return -1; }
fn SOMAXCONN() -> Int { return 128; }

// ─── Winsock Lifecycle ──────────────────────────────────────────────────────

var wsa_initialized: Bool = false;

fn ensure_wsa() -> Result[Unit, Str] {
  if wsa_initialized { return Ok( () ); };

  var version: Int = (2 << 8) | 2;

  var wsa_data: *UInt8 = xiom_alloc(400);
  if wsa_data == ptr.null[UInt8]() {
    return Err("xiom_alloc failed for WSAStartup data");
  };

  var i: Int = 0;
  while i < 400 {
    xiom_write_byte(wsa_data, i, 0);
    i = i + 1;
  };

  var result: Int = unsafe { WSAStartup(version, wsa_data) };
  xiom_free_ptr(wsa_data);

  if result != 0 {
    var err: Int = unsafe { WSAGetLastError() };
    return Err("WSAStartup failed: " + ws_error_to_str(err));
  };

  wsa_initialized = true;
  return Ok( () );
}

pub fn wsa_cleanup() {
  if wsa_initialized {
    let _ = unsafe { WSACleanup() };
    wsa_initialized = false;
  };
}

fn make_error() -> Str {
  var err: Int = unsafe { WSAGetLastError() };
  return ws_error_to_str(err);
}

// ─── sockaddr_in Builder (Bridge-backed) ────────────────────────────────────
// Allocates 16 bytes via xiom_alloc and writes sockaddr_in fields byte-by-byte
// via xiom_write_byte.  Caller must free the buffer with xiom_free_ptr.
//
// sockaddr_in layout (network byte order):
//   offset 0-1 : sin_family  (AF_INET = 2)
//   offset 2-3 : sin_port    (network byte order)
//   offset 4-7 : sin_addr    (IPv4 bytes)
//   offset 8-15: sin_zero    (padding)

fn build_sockaddr_in_bytes(addr: &SocketAddr) -> *UInt8
  requires: addr.ip.version == 4
  requires: addr.ip.octets.len() == 4
{
  var buf: *UInt8 = xiom_alloc(16);
  if buf == ptr.null[UInt8]() {
    return ptr.null[UInt8]();
  };

  var family: Int = AF_INET();
  xiom_write_byte(buf, 0, family & 0xFF);
  xiom_write_byte(buf, 1, (family >> 8) & 0xFF);

  var port: Int = addr.port;
  var port_net: Int = ((port >> 8) & 0xFF) | ((port & 0xFF) << 8);
  xiom_write_byte(buf, 2, port_net & 0xFF);
  xiom_write_byte(buf, 3, (port_net >> 8) & 0xFF);

  xiom_write_byte(buf, 4, addr.ip.octets[0]);
  xiom_write_byte(buf, 5, addr.ip.octets[1]);
  xiom_write_byte(buf, 6, addr.ip.octets[2]);
  xiom_write_byte(buf, 7, addr.ip.octets[3]);

  var z: Int = 8;
  while z < 16 {
    xiom_write_byte(buf, z, 0);
    z = z + 1;
  };

  return buf;
}

// ─── sockaddr_in Parser (Bridge-backed) ─────────────────────────────────────

fn parse_sockaddr_in_bytes(buf: *UInt8) -> Result[SocketAddr, Str] {
  if buf == ptr.null[UInt8]() {
    return Err("null sockaddr buffer");
  };

  var family_lo: Int = xiom_read_byte(buf, 0);
  var family_hi: Int = xiom_read_byte(buf, 1);
  if family_lo != 2 || family_hi != 0 {
    return Err("sockaddr_in family is not AF_INET");
  };

  var port_hi: Int = xiom_read_byte(buf, 2);
  var port_lo: Int = xiom_read_byte(buf, 3);
  var port_net: Int = (port_hi << 8) | port_lo;
  var port: Int = ((port_net >> 8) & 0xFF) | ((port_net & 0xFF) << 8);

  var a: Int = xiom_read_byte(buf, 4);
  var b: Int = xiom_read_byte(buf, 5);
  var c: Int = xiom_read_byte(buf, 6);
  var d: Int = xiom_read_byte(buf, 7);

  var ip: IpAddr = ipv4(a, b, c, d);
  return Ok(socket_addr(ip, port));
}

// ─── TCP Connect ────────────────────────────────────────────────────────────

pub fn tcp_connect(addr: SocketAddr) -> Result[TcpStream, Str]
  requires: addr.ip.version == 4
  requires: addr.port > 0
  requires: addr.port < 65536
{
  var init = ensure_wsa();
  match init {
    Err(msg) => { return Err(msg); };
    Ok(_) => {};
  };

  var fd: Int = unsafe { socket(AF_INET(), SOCK_STREAM(), 0) };
  if fd == INVALID_SOCKET() || fd < 0 {
    return Err("socket() failed: " + make_error());
  };

  var sockaddr: *UInt8 = build_sockaddr_in_bytes(&addr);
  if sockaddr == ptr.null[UInt8]() {
    let _ = unsafe { closesocket(fd) };
    return Err("xiom_alloc failed for sockaddr");
  };

  var conn: Int = unsafe { connect(fd, sockaddr, 16) };
  if conn == SOCKET_ERROR() {
    var err_msg: Str = make_error();
    xiom_free_ptr(sockaddr);
    let _ = unsafe { closesocket(fd) };
    return Err("connect() failed: " + err_msg);
  };

  xiom_free_ptr(sockaddr);
  return Ok(TcpStream{ fd: fd, connected: true, remote: addr });
}

// ─── TCP Listen ─────────────────────────────────────────────────────────────

pub fn tcp_listen(addr: SocketAddr) -> Result[TcpListener, Str]
  requires: addr.ip.version == 4
  requires: addr.port > 0
  requires: addr.port < 65536
{
  var init = ensure_wsa();
  match init {
    Err(msg) => { return Err(msg); };
    Ok(_) => {};
  };

  var fd: Int = unsafe { socket(AF_INET(), SOCK_STREAM(), 0) };
  if fd == INVALID_SOCKET() || fd < 0 {
    return Err("socket() failed: " + make_error());
  };

  var sockaddr: *UInt8 = build_sockaddr_in_bytes(&addr);
  if sockaddr == ptr.null[UInt8]() {
    let _ = unsafe { closesocket(fd) };
    return Err("xiom_alloc failed for sockaddr");
  };

  var bind_result: Int = unsafe { bind(fd, sockaddr, 16) };
  if bind_result == SOCKET_ERROR() {
    var err_msg: Str = make_error();
    xiom_free_ptr(sockaddr);
    let _ = unsafe { closesocket(fd) };
    return Err("bind() failed: " + err_msg);
  };

  var listen_result: Int = unsafe { listen(fd, SOMAXCONN()) };
  if listen_result == SOCKET_ERROR() {
    var err_msg: Str = make_error();
    xiom_free_ptr(sockaddr);
    let _ = unsafe { closesocket(fd) };
    return Err("listen() failed: " + err_msg);
  };

  xiom_free_ptr(sockaddr);
  return Ok(TcpListener{ fd: fd, bound: true, addr: addr });
}

// ─── TCP Accept ─────────────────────────────────────────────────────────────

pub fn tcp_accept(listener: &mut TcpListener) -> Result[TcpStream, Str]
  requires: listener.bound
{
  if !listener.bound {
    return Err("listener is not bound");
  };

  var addr_buf: *UInt8 = xiom_alloc(16);
  if addr_buf == ptr.null[UInt8]() {
    return Err("xiom_alloc failed for accept addr_buf");
  };
  var i: Int = 0;
  while i < 16 {
    xiom_write_byte(addr_buf, i, 0);
    i = i + 1;
  };

  var addrlen_buf: *UInt8 = xiom_alloc(4);
  if addrlen_buf == ptr.null[UInt8]() {
    xiom_free_ptr(addr_buf);
    return Err("xiom_alloc failed for accept addrlen_buf");
  };
  xiom_write_byte(addrlen_buf, 0, 16);
  xiom_write_byte(addrlen_buf, 1, 0);
  xiom_write_byte(addrlen_buf, 2, 0);
  xiom_write_byte(addrlen_buf, 3, 0);

  var client_fd: Int = unsafe { accept(listener.fd, addr_buf, addrlen_buf) };
  if client_fd == INVALID_SOCKET() || client_fd < 0 {
    var err_msg: Str = make_error();
    xiom_free_ptr(addr_buf);
    xiom_free_ptr(addrlen_buf);
    return Err("accept() failed: " + err_msg);
  };

  var parsed = parse_sockaddr_in_bytes(addr_buf);
  var remote: SocketAddr = listener.addr;
  match parsed {
    Ok(sa) => { remote = sa; };
    Err(_) => {};
  };

  xiom_free_ptr(addr_buf);
  xiom_free_ptr(addrlen_buf);

  return Ok(TcpStream{ fd: client_fd, connected: true, remote: remote });
}

// ─── TCP Write ──────────────────────────────────────────────────────────────
// Uses xiom_copy_from_vec to copy XIOM Vec data into a bridge-allocated C
// buffer, then calls send().

pub fn tcp_write(stream: &mut TcpStream, data: &Vec[Int]) -> Result[Int, Str]
  requires: stream.connected
  requires: data.len() > 0
{
  if !stream.connected {
    return Err("stream is not connected");
  };

  var data_len: Int = data.len();
  if data_len == 0 { return Ok(0); };

  var send_buf: *UInt8 = xiom_alloc(data_len);
  if send_buf == ptr.null[UInt8]() {
    return Err("xiom_alloc failed for send buffer");
  };

  xiom_copy_from_vec(send_buf, &data[0], data_len, data_len, 0, data_len);

  var bytes: Int = unsafe { send(stream.fd, send_buf, data_len, 0) };
  xiom_free_ptr(send_buf);

  if bytes == SOCKET_ERROR() {
    return Err("send() failed: " + make_error());
  };
  return Ok(bytes);
}

// ─── TCP Read ───────────────────────────────────────────────────────────────
// Allocates a bridge buffer, calls recv(), then copies bytes back into the
// XIOM Vec.

pub fn tcp_read(stream: &mut TcpStream, buf: &mut Vec[Int]) -> Result[Int, Str]
  requires: stream.connected
{
  if !stream.connected {
    return Err("stream is not connected");
  };

  var buf_len: Int = buf.len();
  if buf_len == 0 { return Ok(0); };

  var recv_buf: *UInt8 = xiom_alloc(buf_len);
  if recv_buf == ptr.null[UInt8]() {
    return Err("xiom_alloc failed for recv buffer");
  };

  var bytes: Int = unsafe { recv(stream.fd, recv_buf, buf_len, 0) };
  if bytes == SOCKET_ERROR() {
    var err_msg: Str = make_error();
    xiom_free_ptr(recv_buf);
    return Err("recv() failed: " + err_msg);
  };

  if bytes == 0 {
    stream.connected = false;
    xiom_free_ptr(recv_buf);
    return Ok(0);
  };

  var j: Int = 0;
  while j < bytes {
    buf[j] = xiom_read_byte(recv_buf, j);
    j = j + 1;
  };

  xiom_free_ptr(recv_buf);
  return Ok(bytes);
}

// ─── TCP Close ──────────────────────────────────────────────────────────────
// Performs graceful shutdown (SD_BOTH) then closes the socket.

pub fn tcp_close(stream: TcpStream)
  requires: stream.connected
{
  if stream.fd >= 0 {
    let _ = unsafe { shutdown(stream.fd, 2) };
    let _ = unsafe { closesocket(stream.fd) };
  };
}

pub fn tcp_listener_close(listener: TcpListener)
  requires: listener.bound
{
  if listener.fd >= 0 {
    let _ = unsafe { closesocket(listener.fd) };
  };
}

// ─── Query Helpers ──────────────────────────────────────────────────────────

pub fn tcp_is_connected(stream: &TcpStream) -> Bool {
  return stream.connected;
}

pub fn tcp_remote_addr(stream: &TcpStream) -> SocketAddr
  requires: stream.connected
{
  return stream.remote;
}

// ─── Winsock Error Codes ────────────────────────────────────────────────────

fn ws_error_to_str(code: Int) -> Str {
  if code == 10013 { return "permission denied"; }
  elif code == 10022 { return "invalid argument"; }
  elif code == 10035 { return "would block"; }
  elif code == 10036 { return "in progress"; }
  elif code == 10037 { return "already in progress"; }
  elif code == 10038 { return "not a socket"; }
  elif code == 10039 { return "destination address required"; }
  elif code == 10040 { return "message too long"; }
  elif code == 10047 { return "address family not supported"; }
  elif code == 10048 { return "address in use"; }
  elif code == 10049 { return "address not available"; }
  elif code == 10050 { return "network down"; }
  elif code == 10051 { return "network unreachable"; }
  elif code == 10052 { return "network reset"; }
  elif code == 10053 { return "connection aborted"; }
  elif code == 10054 { return "connection reset"; }
  elif code == 10055 { return "no buffer space"; }
  elif code == 10056 { return "already connected"; }
  elif code == 10057 { return "not connected"; }
  elif code == 10060 { return "connection timed out"; }
  elif code == 10061 { return "connection refused"; }
  elif code == 10064 { return "host down"; }
  elif code == 10065 { return "host unreachable"; }
  elif code == 10091 { return "network subsystem unavailable"; }
  elif code == 10092 { return "Winsock version not supported"; }
  elif code == 10093 { return "WSAStartup not called"; };
  return "unknown socket error (" + int_to_str(code) + ")";
}

// ─── Utility ────────────────────────────────────────────────────────────────

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var digits: Vec[Str] = Vec[Str].new();
  var num: Int = n;
  var is_neg: Bool = false;
  if num < 0 {
    is_neg = true;
    num = -num;
  };
  while num > 0 {
    var d: Int = num % 10;
    num = num / 10;
    if d == 0 { digits.push("0"); }
    elif d == 1 { digits.push("1"); }
    elif d == 2 { digits.push("2"); }
    elif d == 3 { digits.push("3"); }
    elif d == 4 { digits.push("4"); }
    elif d == 5 { digits.push("5"); }
    elif d == 6 { digits.push("6"); }
    elif d == 7 { digits.push("7"); }
    elif d == 8 { digits.push("8"); }
    elif d == 9 { digits.push("9"); };
  };
  var result: Str = "";
  if is_neg { result = "-"; };
  var j: Int = digits.len() - 1;
  while j >= 0 {
    result = result + digits[j];
    j = j - 1;
  };
  return result;
}
