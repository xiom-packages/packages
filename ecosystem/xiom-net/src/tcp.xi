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

pub fn tcp_connect(addr: SocketAddr) -> Result[TcpStream, Str] {
  return Err("TCP requires OS socket FFI — implement tcp_connect in Layer 2 via platform socket API (socket/connect)");
}

pub fn tcp_listen(addr: SocketAddr) -> Result[TcpListener, Str] {
  return Err("TCP requires OS socket FFI — implement tcp_listen in Layer 2 via platform socket API (socket/bind/listen)");
}

pub fn tcp_accept(listener: &mut TcpListener) -> Result[TcpStream, Str] {
  return Err("TCP requires OS socket FFI — implement tcp_accept in Layer 2 via platform socket API (accept)");
}

pub fn tcp_read(stream: &mut TcpStream, buf: &mut Vec[Int]) -> Result[Int, Str] {
  return Err("TCP requires OS socket FFI — implement tcp_read in Layer 2 via platform socket API (recv/read)");
}

pub fn tcp_write(stream: &mut TcpStream, data: &Vec[Int]) -> Result[Int, Str] {
  return Err("TCP requires OS socket FFI — implement tcp_write in Layer 2 via platform socket API (send/write)");
}

pub fn tcp_close(stream: TcpStream) {
  return;
}

pub fn tcp_listener_close(listener: TcpListener) {
  return;
}

pub fn tcp_is_connected(stream: &TcpStream) -> Bool {
  return stream.connected;
}

pub fn tcp_remote_addr(stream: &TcpStream) -> SocketAddr {
  return stream.remote;
}
