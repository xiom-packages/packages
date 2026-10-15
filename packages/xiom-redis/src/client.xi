// XIOM -- xiom.redis.client: RESP2 session transport over xiom.net.socket
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM Redis transport: connect / disconnect over a real TCP socket
// (stdlib xiom.net.socket), buffered reply reading, raw and checked command
// execution, and pipelines. The wire codec lives in xiom.redis.resp, the
// value model in xiom.redis.value, the verb wrappers in xiom.redis.verbs.
//
// Error taxonomy (RedisError.kind):
//   REDIS_ERR_CONNECT   socket create/connect failures and a first-command
//                       send failure before any byte has been sent (see
//                       redis_connect's runtime note)
//   REDIS_ERR_PROTOCOL  decode errors (RESP_ERR_* codes), local argument
//                       validation, and mid-reply truncation
//   REDIS_ERR_TIMEOUT   a read deadline (read_timeout_ms) expired
//   REDIS_ERR_SERVER    a real server error reply (-ERR ...), message
//                       preserved verbatim (redis_command_checked and the
//                       verb wrappers; redis_command returns the Error value)
//   REDIS_ERR_CLOSED    the peer closed the connection or the socket failed
//
// Language notes (XIOM v0.64.4): free functions only; Ok/Err construction
// confined to leaf helpers; no `?` operator; explicit `&mut` at every &mut
// call site; Vec element reads bind typed locals; no internal wall clock
// (timeouts are socket poll deadlines, never measured by the library).

module xiom.redis.client

use xiom.net.socket;
use xiom.redis.value;
use xiom.redis.resp;

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

/// One Redis connection: the socket fd, where it points, the read deadline
/// in milliseconds (0 = block forever), the reply buffer that carries
/// partial replies between reads, and whether any command has been sent
/// successfully yet (a first-send failure is classified REDIS_ERR_CONNECT,
/// see redis_connect). Not thread-safe; one connection per task.
pub type RedisConn = {
  fd: Int;
  host: Str;
  port: Int;
  read_timeout_ms: Int;
  established: Bool;
  buf: Vec[UInt8];
}

const _RECV_CHUNK: Int = 65536;
const _READ_GUARD: Int = 8192;

// ---------------------------------------------------------------------------
// Constructors (leaf helpers)
// ---------------------------------------------------------------------------

fn _err_raw(kind: Int, code: Int, message: Str) -> RedisError {
  return redis_error(kind, code, message);
}

fn _conn_error(msg: Str) -> RedisError {
  return redis_error(REDIS_ERR_CONNECT, 0, msg);
}

fn _protocol_error(code: Int, msg: Str) -> RedisError {
  return redis_error(REDIS_ERR_PROTOCOL, code, msg);
}

fn _timeout_error(ms: Int) -> RedisError {
  return redis_error(REDIS_ERR_TIMEOUT, 0, "redis: read deadline of " + ms.to_str() + " ms expired");
}

fn _closed_error(msg: Str) -> RedisError {
  return redis_error(REDIS_ERR_CLOSED, 0, msg);
}

fn _conn_new(fd: Int, host: Str, port: Int, timeout_ms: Int) -> RedisConn {
  var empty: Vec[UInt8] = Vec[UInt8].new();
  return RedisConn { fd: fd, host: host, port: port, read_timeout_ms: timeout_ms, established: false, buf: empty };
}

fn _ok_conn(c: RedisConn) -> Result[RedisConn, RedisError] {
  return Ok(c);
}

fn _err_conn(e: RedisError) -> Result[RedisConn, RedisError] {
  return Err(e);
}

fn _ok_unit() -> Result[Unit, RedisError] {
  return Ok(());
}

fn _err_unit(e: RedisError) -> Result[Unit, RedisError] {
  return Err(e);
}

fn _ok_int(v: Int) -> Result[Int, RedisError] {
  return Ok(v);
}

fn _err_int(e: RedisError) -> Result[Int, RedisError] {
  return Err(e);
}

fn _ok_value(v: RedisValue) -> Result[RedisValue, RedisError] {
  return Ok(v);
}

fn _err_value(e: RedisError) -> Result[RedisValue, RedisError] {
  return Err(e);
}

fn _ok_values(v: Vec[RedisValue]) -> Result[Vec[RedisValue], RedisError] {
  return Ok(v);
}

fn _err_values(e: RedisError) -> Result[Vec[RedisValue], RedisError] {
  return Err(e);
}

// ---------------------------------------------------------------------------
// Connect / disconnect
// ---------------------------------------------------------------------------

/// Connect to host:port over TCP, validated: empty host and out-of-range
/// ports are typed REDIS_ERR_CONNECT failures before any socket work. The
/// TCP handshake is bounded by the operating system's connect timeout (the
/// runtime exposes no connect deadline). Runtime note (XIOM v0.64.4 on
/// Windows): a refused handshake can be reported as a successful
/// socket_connect, so a first command whose send fails before any byte has
/// been sent is also classified REDIS_ERR_CONNECT (see _redis_send).
pub fn redis_connect(host: Str, port: Int) -> Result[RedisConn, RedisError] {
  if host.len() == 0 {
    return _err_conn(_conn_error("redis: empty host"));
  }
  if port <= 0 || port > 65535 {
    return _err_conn(_conn_error("redis: port out of range (1-65535)"));
  }
  let t = socket_tcp();
  if !t.is_ok {
    return _err_conn(_conn_error("redis: socket create failed: " + t.error));
  }
  let fd: Int = t.value;
  let c = socket_connect(fd, host, port);
  if !c.is_ok {
    socket_close(fd);
    return _err_conn(_conn_error("redis: connect failed to " + host + ":" + port.to_str()));
  }
  return _ok_conn(_conn_new(fd, host, port, 0));
}

/// Connect, then apply timeout_sec as the session read deadline: a reply
/// that does not arrive within the deadline fails with kind
/// REDIS_ERR_TIMEOUT. 0.0 means block. The TCP handshake itself stays
/// OS-bounded (see redis_connect).
pub fn redis_connect_timeout(host: Str, port: Int, timeout_sec: Float64) -> Result[RedisConn, RedisError] {
  if timeout_sec < 0.0 {
    return _err_conn(_conn_error("redis: negative connect timeout"));
  }
  let ms = (timeout_sec * 1000.0) as Int;
  let base = redis_connect(host, port);
  if !base.is_ok {
    return _err_conn(base.error);
  }
  var conn: RedisConn = base.value;
  if ms > 0 {
    conn.read_timeout_ms = ms;
  }
  return _ok_conn(conn);
}

/// Close the connection and clear its fd. Safe on an already-closed conn.
pub fn redis_disconnect(conn: &mut RedisConn) {
  if conn.fd > 0 {
    socket_close(conn.fd);
  }
  conn.fd = 0;
}

/// Set the read deadline for subsequent replies (milliseconds; <= 0 blocks).
pub fn redis_set_read_timeout(conn: &mut RedisConn, timeout_ms: Int) {
  if timeout_ms <= 0 {
    conn.read_timeout_ms = 0;
  } else {
    conn.read_timeout_ms = timeout_ms;
  }
}

/// Current read deadline in milliseconds (0 = block).
pub fn redis_read_timeout(conn: &RedisConn) -> Int {
  return conn.read_timeout_ms;
}

// ---------------------------------------------------------------------------
// I/O plumbing
// ---------------------------------------------------------------------------

fn _redis_send(conn: &mut RedisConn, args: &Vec[Str]) -> Result[Unit, RedisError] {
  let enc = resp_encode_command_bytes(args);
  if !enc.is_ok {
    return _err_unit(enc.error);
  }
  let bytes: Vec[UInt8] = enc.value;
  let s = socket_send_all(conn.fd, &bytes);
  if !s.is_ok {
    // A send that fails before any byte has ever left is a connect-class
    // failure: on this runtime a refused handshake can be reported as a
    // successful socket_connect (the shim discards the connect() error), so
    // the first send is the earliest reliable establishment check.
    if !conn.established {
      return _err_unit(redis_error(REDIS_ERR_CONNECT, 0, "redis: connection is not established (refused or reset before first command): " + s.error));
    }
    return _err_unit(_closed_error("redis: send failed: " + s.error));
  }
  conn.established = true;
  return _ok_unit();
}

// Read more bytes into the session buffer. Returns Err with the classified
// kind: TIMEOUT (no data within the deadline), CLOSED (socket failure or the
// peer closed with no reply in flight) or PROTOCOL/TRUNCATED (the peer
// closed in the middle of a reply).
fn _redis_recv_more(conn: &mut RedisConn) -> Result[Int, RedisError] {
  if conn.fd <= 0 {
    return _err_int(_closed_error("redis: connection is closed"));
  }
  if conn.read_timeout_ms > 0 {
    var fds: Vec[Int] = Vec[Int].new();
    fds.push(conn.fd);
    let p = socket_poll_read(&fds, conn.read_timeout_ms);
    if !p.is_ok {
      return _err_int(_closed_error("redis: poll failed: " + p.error));
    }
    let ready: Vec[Int] = p.value;
    if ready.len() == 0 {
      return _err_int(_timeout_error(conn.read_timeout_ms));
    }
  }
  let r = socket_recv(conn.fd, _RECV_CHUNK);
  if !r.is_ok {
    return _err_int(_closed_error("redis: recv failed: " + r.error));
  }
  let data: Vec[UInt8] = r.value;
  let got = data.len();
  if got == 0 {
    let pending = conn.buf.len();
    if pending > 0 {
      return _err_int(_protocol_error(RESP_ERR_TRUNCATED, "redis: connection closed with a partial reply (" + pending.to_str() + " bytes buffered)"));
    }
    return _err_int(_closed_error("redis: connection closed by peer"));
  }
  var i = 0;
  while i < got {
    let b: UInt8 = data[i];
    conn.buf.push(b);
    i = i + 1;
  }
  if conn.buf.len() > RESP_MAX_REPLY {
    return _err_int(_protocol_error(RESP_ERR_SIZE, "redis: reply exceeds the 128 MiB assembled cap"));
  }
  return _ok_int(got);
}

// Drop the first `consumed` bytes of the session buffer.
fn _redis_drop_consumed(conn: &mut RedisConn, consumed: Int) {
  if consumed <= 0 {
    return;
  }
  var rest: Vec[UInt8] = Vec[UInt8].new();
  var i = consumed;
  let n = conn.buf.len();
  while i < n {
    let b: UInt8 = conn.buf[i];
    rest.push(b);
    i = i + 1;
  }
  conn.buf = rest;
}

// Read exactly one reply, drawing more bytes from the socket as needed.
fn _redis_read_reply(conn: &mut RedisConn) -> Result[RedisValue, RedisError] {
  var guard = 0;
  while guard < _READ_GUARD {
    guard = guard + 1;
    let o = resp_decode_at(&conn.buf, 0);
    match o {
      Done(d) => {
        let v: RedisValue = d.value;
        let used: Int = d.consumed;
        _redis_drop_consumed(conn, used);
        return _ok_value(v);
      },
      NeedMore => {
        let more = _redis_recv_more(conn);
        if !more.is_ok {
          return _err_value(more.error);
        }
      },
      Bad(e) => {
        let e2: RedisError = e;
        return _err_value(e2);
      },
    };
  }
  return _err_value(_protocol_error(RESP_ERR_SIZE, "redis: reply read exceeded the iteration guard"));
}

/// Read exactly one decoded reply from the wire (the primitive used by
/// pipelines and by pub/sub push consumption): draws more bytes from the
/// socket as needed and applies the session read deadline.
pub fn redis_read_value(conn: &mut RedisConn) -> Result[RedisValue, RedisError] {
  return _redis_read_reply(conn);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// Send one command (a `&Vec[Str]` of arguments; the verb is args[0]) and
/// return its raw decoded reply. A server error reply (`-ERR ...`) is
/// returned as Ok(RedisValue::Error(message)); transport and protocol
/// failures are Err(RedisError). Use redis_command_checked to turn server
/// errors into Err(kind REDIS_ERR_SERVER).
pub fn redis_command(conn: &mut RedisConn, args: &Vec[Str]) -> Result[RedisValue, RedisError] {
  let s = _redis_send(conn, args);
  if !s.is_ok {
    return _err_value(s.error);
  }
  return _redis_read_reply(conn);
}

/// Like redis_command, but a server error reply becomes
/// Err(kind REDIS_ERR_SERVER, message preserved verbatim).
pub fn redis_command_checked(conn: &mut RedisConn, args: &Vec[Str]) -> Result[RedisValue, RedisError] {
  let r = redis_command(conn, args);
  if !r.is_ok {
    return _err_value(r.error);
  }
  let v: RedisValue = r.value;
  if value_kind(&v) == REDIS_VALUE_ERROR {
    let m = value_error_message(&v);
    return _err_value(_err_raw(REDIS_ERR_SERVER, 0, m));
  }
  return _ok_value(v);
}

/// Send all `commands` in one write, then read N replies in order. Server
/// error replies are preserved as Error values (a pipeline is a raw wire
/// facility); transport failures abort the read at the failing command.
pub fn redis_pipeline(conn: &mut RedisConn, commands: &Vec[Vec[Str]]) -> Result[Vec[RedisValue], RedisError] {
  let n = commands.len();
  if n <= 0 {
    return _err_values(_protocol_error(RESP_ERR_EMPTY, "redis: empty pipeline"));
  }
  var i = 0;
  while i < n {
    let cmd: Vec[Str] = commands[i];
    let s = _redis_send(conn, &cmd);
    if !s.is_ok {
      return _err_values(s.error);
    }
    i = i + 1;
  }
  var out: Vec[RedisValue] = Vec[RedisValue].new();
  i = 0;
  while i < n {
    let r = _redis_read_reply(conn);
    if !r.is_ok {
      return _err_values(r.error);
    }
    let v: RedisValue = r.value;
    out.push(v);
    i = i + 1;
  }
  return _ok_values(out);
}
