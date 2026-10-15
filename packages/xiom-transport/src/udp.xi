// XIOM -- xiom.transport.udp: real UDP backend over xiom.net.socket
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The first real datagram transport (NETCODE.md sec. 2): bind a loopback/
// wildcard UDP socket, send/receive datagrams non-blocking inside poll(),
// report the peer address of every received datagram, and count honestly.
// Reliability is NOT a transport property: pair this backend with
// xiom.transport.session for reliable channels over it.
//
// Toolchain note (XIOM v0.64.5, evidence in AUDIT.md): the stdlib
// wrapper socket_recv_from returns a three-element tuple
// (Vec[UInt8], Str, Int) that the pinned compiler lowers incorrectly
// ("unknown type Tuple__Vec[UInt8]__Str__Int", garbage fields, AVs). The
// scratch probe proves the underlying runtime primitive itself is sound,
// so this module declares the same runtime entry point the stdlib socket
// module declares (xiom_socket_recvfrom, pointer out-parameters) and
// wraps it with the same byte-safe code the stdlib uses. No C code is
// added, vendored or linked: this is the runtime's own socket call.
//
// Windows notes (runtime behavior observed during verification):
//   * socket_bind binds the wildcard address on the given port; peers
//     reach it through 127.0.0.1 on this host;
//   * a non-blocking recvfrom reports -1 both for "would block" and for a
//     socket error; socket_poll_read is the readiness oracle, so poll()
//     only drains after readiness and treats -1 as end-of-drain;
//   * socket_local_addr is not exposed, so an ephemeral port cannot be
//     discovered; udp_bind_auto scans a caller range instead of binding
//     port 0 and guessing;
//   * SO_REUSEADDR is set best-effort before bind (a failed option never
//     fails the bind).
//
// SKIP-safe: every failure is a typed UdpError; the suite prints an
// explicit SKIP when binding is unavailable and never fakes a pass.

module xiom.transport.udp

use xiom.net.socket;
use xiom.transport.caps;

// ---------------------------------------------------------------------------
// Runtime entry point (same symbol the stdlib socket module wraps; see the
// toolchain note above)
// ---------------------------------------------------------------------------

extern "C" {
  fn xiom_socket_recvfrom(sock: Int, buf: *UInt8, len: Int, out_ip: *UInt8, out_port: *Int) -> Int32;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// UdpError kinds.
pub const UDP_ERR_BIND: Int = 1;
pub const UDP_ERR_SEND: Int = 2;
pub const UDP_ERR_RECV: Int = 3;
pub const UDP_ERR_ADDR: Int = 4;
pub const UDP_ERR_CLOSED: Int = 5;

/// Receive buffer per datagram (the shared datagram cap).
pub const UDP_RECV_CAP: Int = 65507;

/// Drain guard: at most this many datagrams per poll (a hostile flood
/// cannot spin the loop forever).
pub const UDP_DRAIN_MAX: Int = 4096;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A typed UDP failure.
pub type UdpError = {
  kind: Int;
  message: Str;
}

/// One bound UDP endpoint.
pub type UdpSocket = {
  fd: Int;
  open: Bool;
  local_port: Int;
  peer_host: Str;
  peer_port: Int;
  nonblocking: Bool;
  sent: Int;
  received: Int;
  bytes_sent: Int;
  bytes_received: Int;
  refused: Int;
}

/// One received datagram with its source address.
pub type UdpDatagram = {
  data: Vec[UInt8];
  from_host: Str;
  from_port: Int;
}

/// Copy-out stats view.
pub type UdpStats = {
  open: Bool;
  local_port: Int;
  peer_host: Str;
  peer_port: Int;
  sent: Int;
  received: Int;
  bytes_sent: Int;
  bytes_received: Int;
  refused: Int;
}

// ---------------------------------------------------------------------------
// Leaf helpers
// ---------------------------------------------------------------------------

fn _uerr(kind: Int, message: Str) -> UdpError {
  return UdpError { kind: kind, message: message };
}

fn _ok_sock(v: UdpSocket) -> Result[UdpSocket, UdpError] { return Ok(v); }
fn _err_sock(e: UdpError) -> Result[UdpSocket, UdpError] { return Err(e); }
fn _ok_int(v: Int) -> Result[Int, UdpError] { return Ok(v); }
fn _err_int(e: UdpError) -> Result[Int, UdpError] { return Err(e); }
fn _ok_unit() -> Result[Unit, UdpError] { return Ok(()); }
fn _err_unit(e: UdpError) -> Result[Unit, UdpError] { return Err(e); }
fn _ok_data(v: Vec[UdpDatagram]) -> Result[Vec[UdpDatagram], UdpError] { return Ok(v); }
fn _err_data(e: UdpError) -> Result[Vec[UdpDatagram], UdpError] { return Err(e); }

fn _port_ok(p: Int) -> Bool {
  if p < 1 { return false; }
  if p > 65535 { return false; }
  return true;
}

// Read a NUL-terminated C string from a fixed buffer into a Str.
fn _cstr_of(buf: &[64]UInt8) -> Str {
  var len = 0;
  while len < 64 && buf[len] != 0 as UInt8 {
    len = len + 1;
  }
  var chars: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < len {
    let b: UInt8 = buf[i];
    chars.push(b);
    i = i + 1;
  }
  return Str::from_utf8(chars);
}

// ---------------------------------------------------------------------------
// Bind
// ---------------------------------------------------------------------------

/// Bind a UDP socket on host:port (port 1..65535). The runtime binds the
/// wildcard address; SO_REUSEADDR is attempted best-effort; the socket is
/// switched to non-blocking because poll() owns readiness.
pub fn udp_bind(host: Str, port: Int) -> Result[UdpSocket, UdpError] {
  if host.len() == 0 {
    return _err_sock(_uerr(UDP_ERR_ADDR, "udp_bind: empty host"));
  }
  if !_port_ok(port) {
    return _err_sock(_uerr(UDP_ERR_ADDR, "udp_bind: port out of range (1-65535)"));
  }
  let rfd = socket_udp();
  if !rfd.is_ok {
    return _err_sock(_uerr(UDP_ERR_BIND, "udp_bind: socket create failed: " + rfd.error));
  }
  let fd: Int = rfd.value;
  let rr = socket_reuse_addr(fd, true);
  let _ = rr;
  let rb = socket_bind(fd, host, port);
  if !rb.is_ok {
    socket_close(fd);
    return _err_sock(_uerr(UDP_ERR_BIND, "udp_bind: bind failed on " + host + ":" + port.to_str() + " (" + rb.error + ")"));
  }
  let rn = socket_set_nonblocking(fd, true);
  if !rn.is_ok {
    socket_close(fd);
    return _err_sock(_uerr(UDP_ERR_BIND, "udp_bind: non-blocking mode failed: " + rn.error));
  }
  return _ok_sock(UdpSocket {
    fd: fd;
    open: true;
    local_port: port;
    peer_host: "";
    peer_port: 0;
    nonblocking: true;
    sent: 0;
    received: 0;
    bytes_sent: 0;
    bytes_received: 0;
    refused: 0;
  });
}

/// Bind the first free port in [first_port, last_port] (inclusive;
/// deterministic ascending scan -- the runtime does not expose the
/// ephemeral port, so port 0 cannot be used). Typed Err when the whole
/// candidate range is taken; callers SKIP honestly.
pub fn udp_bind_auto(host: Str, first_port: Int, last_port: Int) -> Result[UdpSocket, UdpError] {
  if !_port_ok(first_port) || !_port_ok(last_port) || last_port < first_port {
    return _err_sock(_uerr(UDP_ERR_ADDR, "udp_bind_auto: invalid candidate range"));
  }
  var p = first_port;
  while p <= last_port {
    let r = udp_bind(host, p);
    if r.is_ok {
      return r;
    }
    p = p + 1;
  }
  return _err_sock(_uerr(UDP_ERR_BIND, "udp_bind_auto: no free UDP port in the candidate range"));
}

/// Set the default destination for udp_send (validated).
pub fn udp_set_peer(s: &mut UdpSocket, host: Str, port: Int) -> Result[Unit, UdpError] {
  if host.len() == 0 {
    return _err_unit(_uerr(UDP_ERR_ADDR, "udp_set_peer: empty host"));
  }
  if !_port_ok(port) {
    return _err_unit(_uerr(UDP_ERR_ADDR, "udp_set_peer: port out of range"));
  }
  s.peer_host = host;
  s.peer_port = port;
  return _ok_unit();
}

// ---------------------------------------------------------------------------
// Send
// ---------------------------------------------------------------------------

fn _send_via(s: &mut UdpSocket, data: &Vec[UInt8], host: Str, port: Int) -> Result[Int, UdpError] {
  if !s.open {
    s.refused = s.refused + 1;
    return _err_int(_uerr(UDP_ERR_CLOSED, "udp_send: socket closed"));
  }
  if data.len() > UDP_RECV_CAP {
    s.refused = s.refused + 1;
    return _err_int(_uerr(UDP_ERR_SEND, "udp_send: datagram above the 65507-byte cap"));
  }
  let r = socket_send_to(s.fd, data, host, port);
  if !r.is_ok {
    s.refused = s.refused + 1;
    return _err_int(_uerr(UDP_ERR_SEND, "udp_send: send_to failed: " + r.error));
  }
  let n = r.value;
  if n >= 0 {
    s.sent = s.sent + 1;
    s.bytes_sent = s.bytes_sent + n;
  }
  return _ok_int(n);
}

/// Send to the configured peer (typed Err when no peer is set).
pub fn udp_send(s: &mut UdpSocket, data: &Vec[UInt8]) -> Result[Int, UdpError] {
  if s.peer_host.len() == 0 || s.peer_port == 0 {
    s.refused = s.refused + 1;
    return _err_int(_uerr(UDP_ERR_ADDR, "udp_send: no peer configured (use udp_set_peer)"));
  }
  return _send_via(s, data, s.peer_host, s.peer_port);
}

/// Send to an explicit destination.
pub fn udp_send_to(s: &mut UdpSocket, data: &Vec[UInt8], host: Str, port: Int) -> Result[Int, UdpError] {
  if host.len() == 0 || !_port_ok(port) {
    s.refused = s.refused + 1;
    return _err_int(_uerr(UDP_ERR_ADDR, "udp_send_to: invalid destination"));
  }
  return _send_via(s, data, host, port);
}

// ---------------------------------------------------------------------------
// Poll / receive
// ---------------------------------------------------------------------------

// Drain the non-blocking socket: every pending datagram is received with
// its source address until would-block (-1 on this runtime).
fn _drain(s: &mut UdpSocket) -> Result[Vec[UdpDatagram], UdpError] {
  var out: Vec[UdpDatagram] = Vec[UdpDatagram].new();
  var rounds = 0;
  var keep = true;
  while keep && rounds < UDP_DRAIN_MAX {
    rounds = rounds + 1;
    var raw_buf: [65536]UInt8;
    var ip_buf: [64]UInt8;
    var port_val: Int = 0;
    let n32: Int32;
    unsafe {
      n32 = xiom_socket_recvfrom(s.fd, &raw_buf as *UInt8, UDP_RECV_CAP, &ip_buf as *UInt8, &port_val);
    }
    let n = n32 as Int;
    if n < 0 {
      keep = false;
    } else {
      var data: Vec[UInt8] = Vec[UInt8].new();
      var i = 0;
      while i < n {
        let b: UInt8 = raw_buf[i];
        data.push(b);
        i = i + 1;
      }
      let from = _cstr_of(&ip_buf);
      var dg = UdpDatagram { data: data; from_host: from; from_port: port_val; };
      s.received = s.received + 1;
      s.bytes_received = s.bytes_received + n;
      out.push(dg);
    }
  }
  return _ok_data(out);
}

/// Wait up to timeout_ms for readability (0 = immediate), then drain
/// every pending datagram. Returns them in receive order with source
/// addresses; an empty batch on timeout is Ok (a poll, not an error).
pub fn udp_poll(s: &mut UdpSocket, timeout_ms: Int) -> Result[Vec[UdpDatagram], UdpError] {
  if !s.open {
    s.refused = s.refused + 1;
    return _err_data(_uerr(UDP_ERR_CLOSED, "udp_poll: socket closed"));
  }
  var fds: Vec[Int] = Vec[Int].new();
  fds.push(s.fd);
  let pr = socket_poll_read(&fds, timeout_ms);
  if !pr.is_ok {
    return _err_data(_uerr(UDP_ERR_RECV, "udp_poll: poll_read failed: " + pr.error));
  }
  let ready: Vec[Int] = pr.value;
  if ready.len() == 0 {
    return _ok_data(Vec[UdpDatagram].new());
  }
  return _drain(s);
}

// ---------------------------------------------------------------------------
// Introspection / close
// ---------------------------------------------------------------------------

pub fn udp_close(s: &mut UdpSocket) {
  if s.open {
    socket_close(s.fd);
    s.open = false;
  }
}

pub fn udp_is_open(s: &UdpSocket) -> Bool {
  return s.open;
}

pub fn udp_local_port(s: &UdpSocket) -> Int {
  return s.local_port;
}

pub fn udp_stats(s: &UdpSocket) -> UdpStats {
  return UdpStats {
    open: s.open;
    local_port: s.local_port;
    peer_host: s.peer_host;
    peer_port: s.peer_port;
    sent: s.sent;
    received: s.received;
    bytes_sent: s.bytes_sent;
    bytes_received: s.bytes_received;
    refused: s.refused;
  };
}

/// The declared UDP capability facts (same record as
/// xiom.transport.caps.caps_udp; convenience for backend-local readers).
pub fn udp_caps() -> CapFacts {
  return caps_udp();
}
