// XIOM -- ZeroMQ Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe wrappers around libzmq via extern "C" FFI.
// Int-based context/socket handles with design-by-contract.
// Links against system-installed libzmq at link time.
//
// Compiler gap: raw pointer marshaling uses Int (memory address).
// Vec[UInt8] <-> buffer bridge is stubbed until compiler supports *UInt8.

module xiom.zeromq

// =========================================================================
// Opaque handle types
// =========================================================================

pub type ZmqContext = Int
pub type ZmqSocket = Int

// =========================================================================
// Socket type constants -- libzmq S zmq_socket(3)
// =========================================================================

pub const ZMQ_PAIR:   Int = 0
pub const ZMQ_PUB:    Int = 1
pub const ZMQ_SUB:    Int = 2
pub const ZMQ_REQ:    Int = 3
pub const ZMQ_REP:    Int = 4
pub const ZMQ_DEALER: Int = 5
pub const ZMQ_ROUTER: Int = 6
pub const ZMQ_PULL:   Int = 7
pub const ZMQ_PUSH:   Int = 8
pub const ZMQ_XPUB:   Int = 9
pub const ZMQ_XSUB:   Int = 10
pub const ZMQ_STREAM: Int = 11

// =========================================================================
// Send/Recv flags
// =========================================================================

pub const ZMQ_DONTWAIT: Int = 1
pub const ZMQ_SNDMORE:  Int = 2

// =========================================================================
// Socket options (subset -- commonly used)
// =========================================================================

pub const ZMQ_SUBSCRIBE:   Int = 6
pub const ZMQ_UNSUBSCRIBE: Int = 7
pub const ZMQ_LINGER:      Int = 17
pub const ZMQ_RCVTIMEO:    Int = 27
pub const ZMQ_SNDTIMEO:    Int = 28

// =========================================================================
// extern "C" -- ZeroMQ C API (libzmq)
//
// All pointer parameters use Int (memory address) until the compiler
// supports typed C pointer interop.
// =========================================================================

extern "C" {
  fn zmq_ctx_new() -> Int;
  fn zmq_ctx_destroy(context: Int) -> Int;
  fn zmq_socket(context: Int, type_: Int) -> Int;
  fn zmq_close(socket: Int) -> Int;
  fn zmq_bind(socket: Int, addr: Int) -> Int;
  fn zmq_connect(socket: Int, addr: Int) -> Int;
  fn zmq_send(socket: Int, buf: Int, len: Int, flags: Int) -> Int;
  fn zmq_recv(socket: Int, buf: Int, len: Int, flags: Int) -> Int;
  fn zmq_setsockopt(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int;
  fn zmq_getsockopt(socket: Int, option_name: Int, option_value: Int, option_len: Int) -> Int;
  fn zmq_poll(items: Int, nitems: Int, timeout: Int) -> Int;
  fn zmq_version(major: Int, minor: Int, patch: Int) -> Int;
}

// =========================================================================
// context_new -- create a new ZeroMQ context
//
// Returns Ok(context) on success or Err(message) on failure.
// =========================================================================

pub fn context_new() -> Result[ZmqContext, Str] {
  let ctx: Int = unsafe { zmq_ctx_new() };
  if ctx == 0 {
    return Err("zmq_ctx_new: failed to create context");
  }
  return Ok(ctx);
}

// =========================================================================
// context_destroy -- destroy a ZeroMQ context
//
// Returns Ok(()) or Err(message). Safe wrapper calls zmq_ctx_destroy
// and checks the return code.
// =========================================================================

pub fn context_destroy(ctx: ZmqContext) -> Result[Int, Str] {
  if ctx == 0 {
    return Err("context_destroy: null context");
  }
  let rc: Int = unsafe { zmq_ctx_destroy(ctx) };
  if rc != 0 {
    return Err("zmq_ctx_destroy: failed to destroy context");
  }
  return Ok(0);
}

// =========================================================================
// socket -- create a ZeroMQ socket within a context
//
// Returns Ok(socket) or Err(message). Type must be one of the ZMQ_*
// socket type constants.
// =========================================================================

pub fn socket(ctx: ZmqContext, type_: Int) -> Result[ZmqSocket, Str] {
  if ctx == 0 {
    return Err("socket: null context");
  }
  let s: Int = unsafe { zmq_socket(ctx, type_) };
  if s == 0 {
    return Err("zmq_socket: failed to create socket");
  }
  return Ok(s);
}

// =========================================================================
// close -- close a ZeroMQ socket
// =========================================================================

pub fn close(s: ZmqSocket) -> Result[Int, Str] {
  if s == 0 {
    return Err("close: null socket");
  }
  let rc: Int = unsafe { zmq_close(s) };
  if rc != 0 {
    return Err("zmq_close: failed to close socket");
  }
  return Ok(0);
}

// =========================================================================
// bind -- bind socket to an endpoint address
//
// addr must be a null-terminated C string (pointer). The caller is
// responsible for allocation.
// requires: addr != 0
// =========================================================================

pub fn bind(s: ZmqSocket, addr: Int) -> Result[Int, Str]
  requires: addr != 0
{
  if s == 0 {
    return Err("bind: null socket");
  }
  let rc: Int = unsafe { zmq_bind(s, addr) };
  if rc != 0 {
    return Err("zmq_bind: failed to bind");
  }
  return Ok(0);
}

// =========================================================================
// connect -- connect socket to an endpoint address
//
// addr must be a null-terminated C string (pointer). The caller is
// responsible for allocation.
// =========================================================================

pub fn connect(s: ZmqSocket, addr: Int) -> Result[Int, Str] {
  if s == 0 {
    return Err("connect: null socket");
  }
  let rc: Int = unsafe { zmq_connect(s, addr) };
  if rc != 0 {
    return Err("zmq_connect: failed to connect");
  }
  return Ok(0);
}

// =========================================================================
// send -- send data on a socket
//
// buf and len describe the raw buffer. Caller owns the memory.
// requires: len > 0
// =========================================================================

pub fn send(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]
  requires: len > 0
{
  if s == 0 {
    return Err("send: null socket");
  }
  let rc: Int = unsafe { zmq_send(s, buf, len, flags) };
  if rc < 0 {
    return Err("zmq_send: failed to send");
  }
  return Ok(rc);
}

// =========================================================================
// recv -- receive data from a socket
//
// buf and len describe the receiving buffer. Caller owns the memory.
// Returns Ok(bytes_received) or Err(message).
// requires: len > 0
// =========================================================================

pub fn recv(s: ZmqSocket, buf: Int, len: Int, flags: Int) -> Result[Int, Str]
  requires: len > 0
{
  if s == 0 {
    return Err("recv: null socket");
  }
  let rc: Int = unsafe { zmq_recv(s, buf, len, flags) };
  if rc < 0 {
    return Err("zmq_recv: failed to receive");
  }
  return Ok(rc);
}

// =========================================================================
// poll -- poll sockets for I/O events
//
// items is a pointer to an array of zmq_pollitem_t; nitems is count.
// timeout in milliseconds (-1 = block indefinitely).
// =========================================================================

pub fn poll(items: Int, nitems: Int, timeout: Int) -> Result[Int, Str] {
  let rc: Int = unsafe { zmq_poll(items, nitems, timeout) };
  if rc < 0 {
    return Err("zmq_poll: failed");
  }
  return Ok(rc);
}

// =========================================================================
// setsockopt -- set a socket option
//
// option_value is a pointer to the option value.
// =========================================================================

pub fn setsockopt(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str] {
  if s == 0 {
    return Err("setsockopt: null socket");
  }
  let rc: Int = unsafe { zmq_setsockopt(s, option_name, option_value, option_len) };
  if rc != 0 {
    return Err("zmq_setsockopt: failed to set option");
  }
  return Ok(0);
}

// =========================================================================
// getsockopt -- get a socket option
//
// option_value is a pointer to storage for the option value.
// option_len is a pointer to a size_t with the storage capacity.
// =========================================================================

pub fn getsockopt(s: ZmqSocket, option_name: Int, option_value: Int, option_len: Int) -> Result[Int, Str] {
  if s == 0 {
    return Err("getsockopt: null socket");
  }
  let rc: Int = unsafe { zmq_getsockopt(s, option_name, option_value, option_len) };
  if rc != 0 {
    return Err("zmq_getsockopt: failed to get option");
  }
  return Ok(0);
}

// =========================================================================
// version -- query the ZeroMQ library version
//
// major, minor, patch are pointers to int storage.
// The caller allocates storage; zmq_version fills the values.
// =========================================================================

pub fn version(major: Int, minor: Int, patch: Int) -> Result[Int, Str] {
  if major == 0 || minor == 0 || patch == 0 {
    return Err("version: null pointer argument");
  }
  unsafe { zmq_version(major, minor, patch) };
  return Ok(0);
}
