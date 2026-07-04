module xiom.net.udp

pub type UdpSocket = {
  fd: Int;
  bound: Bool;
} derive[Clone]

pub fn udp_bind(addr: SocketAddr) -> Result[UdpSocket, Str] {
  return Err("UDP requires OS socket FFI — implement udp_bind in Layer 2 via platform socket API (socket/bind)");
}

pub fn udp_send_to(socket: &UdpSocket, data: &Vec[Int], addr: SocketAddr) -> Result[Int, Str] {
  return Err("UDP requires OS socket FFI — implement udp_send_to in Layer 2 via platform socket API (sendto)");
}

pub fn udp_recv_from(socket: &UdpSocket, buf: &mut Vec[Int]) -> Result[(Int, SocketAddr), Str] {
  return Err("UDP requires OS socket FFI — implement udp_recv_from in Layer 2 via platform socket API (recvfrom)");
}

pub fn udp_close(socket: UdpSocket) {
  return;
}
