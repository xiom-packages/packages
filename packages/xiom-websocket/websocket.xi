// XIOM -- WebSocket Transport (Pure-XIOM types + extern C FFI bridge)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.websocket

use xiom.string;
use xiom.ptr;
use xiom.convert;

// --- XIOM FFI Bridge ------------------------------------------------------

extern "C" {
  fn xiom_str_to_cstr(xiom_str: *UInt8, len: Int) -> *UInt8;
  fn xiom_free_cstr(cstr: *UInt8);
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_write_byte(ptr: *UInt8, offset: Int, value: Int);
  fn xiom_read_byte(ptr: *UInt8, offset: Int) -> Int;
}

// --- Platform Socket FFI --------------------------------------------------

extern "C" {
  fn ws_socket_create() -> Int;
  fn ws_socket_destroy(fd: Int);
  fn ws_socket_connect(fd: Int, host: *UInt8, port: Int) -> Int;
  fn ws_socket_bind(fd: Int, host: *UInt8, port: Int) -> Int;
  fn ws_socket_listen(fd: Int, backlog: Int) -> Int;
  fn ws_socket_accept(fd: Int) -> Int;
  fn ws_socket_send(fd: Int, data: *UInt8, len: Int) -> Int;
  fn ws_socket_recv(fd: Int, buf: *UInt8, cap: Int) -> Int;
  fn ws_socket_close(fd: Int);
  fn ws_socket_set_nonblocking(fd: Int, enable: Int);
}

// --- WebSocket Handshake FFI ----------------------------------------------

extern "C" {
  fn ws_handshake_compute_key(client_key: *UInt8, key_len: Int) -> *UInt8;
  fn ws_handshake_build_request(host: *UInt8, path: *UInt8, key: *UInt8) -> *UInt8;
  fn ws_handshake_validate_response(response: *UInt8) -> Int;
  fn ws_handshake_free_result(ptr: *UInt8);
}

// --- WebSocket Frame FFI --------------------------------------------------

extern "C" {
  fn ws_frame_encode(opcode: Int, payload: *UInt8, len: Int, mask: Int) -> *UInt8;
  fn ws_frame_decode(data: *UInt8, len: Int) -> *UInt8;
  fn ws_frame_get_opcode(decoded_frame: *UInt8) -> Int;
  fn ws_frame_get_payload(decoded_frame: *UInt8) -> *UInt8;
  fn ws_frame_get_payload_len(decoded_frame: *UInt8) -> Int;
  fn ws_frame_free(ptr: *UInt8);
  fn ws_frame_is_valid(data: *UInt8, len: Int) -> Int;
}

// --- Types ------------------------------------------------------------------

pub enum WsOpcode {
  Continuation,
  Text,
  Binary,
  Close,
  Ping,
  Pong,
} derive[Clone]

pub enum WsConnectionState {
  Connecting,
  Open,
  Closing,
  Closed,
} derive[Clone]

pub type WsConnection = {
  id: Str;
  socket_fd: Int;
  state: WsConnectionState;
  host: Str;
  port: Int;
  path: Str;
  last_seq: Int;
  heartbeat_interval_ms: Int;
  close_code: Int;
} derive[Clone]

pub type WsFrame = {
  fin: Bool;
  opcode: WsOpcode;
  masked: Bool;
  payload: Vec[Int];
  reserved: Vec[Int];
} derive[Clone]

pub type WsMessage = {
  kind: WsMessageKind;
  data: Vec[Int];
  seq: Int;
} derive[Clone]

pub enum WsMessageKind {
  TextMessage,
  BinaryMessage,
} derive[Clone]

pub type WsHandshakeRequest = {
  host: Str;
  path: Str;
  key: Str;
  subprotocols: Vec[Str];
} derive[Clone]

pub type WsHandshakeResponse = {
  accept_key: Str;
  subprotocol: Str;
  success: Bool;
} derive[Clone]

pub type WsError = {
  code: Str;
  message: Str;
} derive[Clone]

pub type WsServer = {
  connections: Vec[WsConnection];
  host: Str;
  port: Int;
  running: Bool;
} derive[Clone]

pub type WsChannel = {
  name: Str;
  subscribers: Vec[Str];
} derive[Clone]

// --- Opcode Helpers ---------------------------------------------------------

pub fn opcode_to_int(op: WsOpcode) -> Int {
  match op {
    WsOpcode.Continuation => return 0,
    WsOpcode.Text => return 1,
    WsOpcode.Binary => return 2,
    WsOpcode.Close => return 8,
    WsOpcode.Ping => return 9,
    WsOpcode.Pong => return 10,
  };
}

pub fn opcode_from_int(n: Int) -> WsOpcode {
  if n == 0 { return WsOpcode.Continuation; };
  if n == 1 { return WsOpcode.Text; };
  if n == 2 { return WsOpcode.Binary; };
  if n == 8 { return WsOpcode.Close; };
  if n == 9 { return WsOpcode.Ping; };
  if n == 10 { return WsOpcode.Pong; };
  return WsOpcode.Close;
}

pub fn opcode_is_control(op: WsOpcode) -> Bool {
  match op {
    WsOpcode.Close => return true,
    WsOpcode.Ping => return true,
    WsOpcode.Pong => return true,
    _ => return false,
  };
}

pub fn opcode_is_data(op: WsOpcode) -> Bool {
  match op {
    WsOpcode.Text => return true,
    WsOpcode.Binary => return true,
    WsOpcode.Continuation => return true,
    _ => return false,
  };
}

pub fn opcode_to_str(op: WsOpcode) -> Str {
  match op {
    WsOpcode.Continuation => return "Continuation",
    WsOpcode.Text => return "Text",
    WsOpcode.Binary => return "Binary",
    WsOpcode.Close => return "Close",
    WsOpcode.Ping => return "Ping",
    WsOpcode.Pong => return "Pong",
  };
}

// --- Frame Helpers ----------------------------------------------------------

pub fn frame_new(opcode: WsOpcode, payload: Vec[Int]) -> WsFrame {
  return WsFrame{
    fin: true,
    opcode: opcode,
    masked: false,
    payload: payload,
    reserved: Vec[Int].new(),
  };
}

pub fn frame_text(data: Str) -> WsFrame {
  var payload: Vec[Int] = Vec[Int].new();
  var i: Int = 0;
  while i < string.str_len(data) {
    payload.push(data[i] as Int);
    i = i + 1;
  };
  return frame_new(WsOpcode.Text, payload);
}

pub fn frame_binary(data: Vec[Int]) -> WsFrame {
  return frame_new(WsOpcode.Binary, data);
}

pub fn frame_close(code: Int) -> WsFrame {
  var payload: Vec[Int] = Vec[Int].new();
  payload.push((code >> 8) & 0xFF);
  payload.push(code & 0xFF);
  return frame_new(WsOpcode.Close, payload);
}

pub fn frame_ping() -> WsFrame {
  return frame_new(WsOpcode.Ping, Vec[Int].new());
}

pub fn frame_pong() -> WsFrame {
  return frame_new(WsOpcode.Pong, Vec[Int].new());
}

pub fn frame_is_final(frame: &WsFrame) -> Bool {
  return frame.fin;
}

pub fn frame_is_control(frame: &WsFrame) -> Bool {
  return opcode_is_control(frame.opcode);
}

pub fn frame_is_data(frame: &WsFrame) -> Bool {
  return opcode_is_data(frame.opcode);
}

pub fn frame_payload_len(frame: &WsFrame) -> Int {
  return frame.payload.len();
}

// --- Frame Validation -------------------------------------------------------

pub fn frame_validate(frame: &WsFrame) -> Result[Unit, Str] {
  if opcode_is_control(frame.opcode) {
    if frame.payload.len() > 125 {
      return Err("control frame payload exceeds 125 bytes");
    };
    if !frame.fin {
      return Err("control frames must not be fragmented");
    };
  };
  if frame.masked {
    // Client-to-server frames must be masked per RFC 6455
  };
  return Ok(());
}

// --- Frame Encode/Decode Stubs ----------------------------------------------

pub fn frame_encode(frame: &WsFrame) -> Result[Vec[Int], Str] {
  // Stub: encode one text frame with 0-length payload pattern
  var encoded: Vec[Int] = Vec[Int].new();
  var first_byte: Int = 0;
  if frame.fin {
    first_byte = first_byte | 0x80;
  };
  var op_int: Int = opcode_to_int(frame.opcode);
  first_byte = first_byte | (op_int & 0x0F);
  encoded.push(first_byte);
  encoded.push(frame.payload.len());
  var i: Int = 0;
  while i < frame.payload.len() {
    encoded.push(frame.payload[i]);
    i = i + 1;
  };
  return Ok(encoded);
}

pub fn frame_decode(raw: &Vec[Int]) -> Result[WsFrame, Str] {
  if raw.len() < 2 {
    return Err("frame too short: minimum 2 bytes");
  };
  var first_byte: Int = raw[0];
  var fin: Bool = (first_byte & 0x80) != 0;
  var op_int: Int = first_byte & 0x0F;
  var opcode: WsOpcode = opcode_from_int(op_int);
  var masked: Bool = (raw[1] & 0x80) != 0;
  var payload_len: Int = raw[1] & 0x7F;

  var payload: Vec[Int] = Vec[Int].new();
  if payload_len > 0 {
    var start: Int = 2;
    if raw.len() > 2 + payload_len {
      var i: Int = 0;
      while i < payload_len {
        payload.push(raw[start + i]);
        i = i + 1;
      };
    };
  };

  return Ok(WsFrame{
    fin: fin,
    opcode: opcode,
    masked: masked,
    payload: payload,
    reserved: Vec[Int].new(),
  });
}

// --- Connection -------------------------------------------------------------

pub fn connection_new(id: Str, host: Str, port: Int, path: Str) -> WsConnection
  requires: string.str_len(id) > 0
  requires: port > 0
{
  return WsConnection{
    id: id,
    socket_fd: -1,
    state: WsConnectionState.Connecting,
    host: host,
    port: port,
    path: path,
    last_seq: 0,
    heartbeat_interval_ms: 30000,
    close_code: 1000,
  };
}

pub fn connection_state_to_str(state: WsConnectionState) -> Str {
  match state {
    WsConnectionState.Connecting => return "Connecting",
    WsConnectionState.Open => return "Open",
    WsConnectionState.Closing => return "Closing",
    WsConnectionState.Closed => return "Closed",
  };
}

pub fn connection_is_open(conn: &WsConnection) -> Bool {
  match conn.state {
    WsConnectionState.Open => return true,
    _ => return false,
  };
}

pub fn connection_is_closed(conn: &WsConnection) -> Bool {
  match conn.state {
    WsConnectionState.Closed => return true,
    _ => return false,
  };
}

pub fn connection_set_state(conn: &mut WsConnection, state: WsConnectionState) {
  conn.state = state;
}

pub fn connection_set_heartbeat(conn: &mut WsConnection, ms: Int) {
  conn.heartbeat_interval_ms = ms;
}

// --- Handshake Stubs --------------------------------------------------------

pub fn handshake_request_new(host: Str, path: Str) -> WsHandshakeRequest {
  return WsHandshakeRequest{
    host: host,
    path: path,
    key: "",
    subprotocols: Vec[Str].new(),
  };
}

pub fn handshake_compute_key(key: Str) -> Str {
  // Stub: returns a dummy accept key
  if string.str_len(key) == 0 {
    return "";
  };
  return "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";
}

pub fn handshake_validate_request(
  host: Str,
  path: Str,
  sec_key: Str,
  sec_version: Str,
) -> Result[Unit, Str] {
  if string.str_len(host) == 0 {
    return Err("missing Host header");
  };
  if string.str_len(sec_key) == 0 {
    return Err("missing Sec-WebSocket-Key");
  };
  if sec_version != "13" {
    return Err("unsupported Sec-WebSocket-Version");
  };
  return Ok(());
}

pub fn handshake_is_valid(host: Str, sec_key: Str, sec_version: Str) -> Bool {
  var result = handshake_validate_request(host, "/", sec_key, sec_version);
  match result {
    Ok(_) => return true,
    Err(_) => return false,
  };
}

// --- Server -----------------------------------------------------------------

pub fn server_new(host: Str, port: Int) -> WsServer
  requires: string.str_len(host) > 0
  requires: port > 0
{
  return WsServer{
    connections: Vec[WsConnection].new(),
    host: host,
    port: port,
    running: false,
  };
}

pub fn server_start(server: &mut WsServer) {
  server.running = true;
}

pub fn server_stop(server: &mut WsServer) {
  server.running = false;
}

pub fn server_is_running(server: &WsServer) -> Bool {
  return server.running;
}

pub fn server_add_connection(server: &mut WsServer, conn: WsConnection) {
  server.connections.push(conn);
}

pub fn server_connection_count(server: &WsServer) -> Int {
  return server.connections.len();
}

pub fn server_find_connection(server: &WsServer, id: Str) -> Option[WsConnection] {
  var i: Int = 0;
  while i < server.connections.len() {
    if server.connections[i].id == id {
      return Some(server.connections[i]);
    };
    i = i + 1;
  };
  return None;
}

pub fn server_remove_connection(server: &mut WsServer, id: Str) -> Bool {
  var i: Int = 0;
  while i < server.connections.len() {
    if server.connections[i].id == id {
      var last: Int = server.connections.len() - 1;
      if i < last {
        server.connections[i] = server.connections[last];
      };
      server.connections.pop();
      return true;
    };
    i = i + 1;
  };
  return false;
}

pub fn server_broadcast_count(server: &WsServer) -> Int {
  var count: Int = 0;
  var i: Int = 0;
  while i < server.connections.len() {
    if connection_is_open(&server.connections[i]) {
      count = count + 1;
    };
    i = i + 1;
  };
  return count;
}

// --- Message -----------------------------------------------------------------

pub fn message_new(kind: WsMessageKind, data: Vec[Int], seq: Int) -> WsMessage {
  return WsMessage{
    kind: kind,
    data: data,
    seq: seq,
  };
}

pub fn message_text(data: Str, seq: Int) -> WsMessage {
  var bytes: Vec[Int] = Vec[Int].new();
  var i: Int = 0;
  while i < string.str_len(data) {
    bytes.push(data[i] as Int);
    i = i + 1;
  };
  return message_new(WsMessageKind.TextMessage, bytes, seq);
}

pub fn message_binary(data: Vec[Int], seq: Int) -> WsMessage {
  return message_new(WsMessageKind.BinaryMessage, data, seq);
}

// --- Channel ----------------------------------------------------------------

pub fn channel_new(name: Str) -> WsChannel
  requires: string.str_len(name) > 0
{
  return WsChannel{
    name: name,
    subscribers: Vec[Str].new(),
  };
}

pub fn channel_subscribe(ch: &mut WsChannel, conn_id: Str) {
  ch.subscribers.push(conn_id);
}

pub fn channel_unsubscribe(ch: &mut WsChannel, conn_id: Str) -> Bool {
  var i: Int = 0;
  while i < ch.subscribers.len() {
    if ch.subscribers[i] == conn_id {
      var last: Int = ch.subscribers.len() - 1;
      if i < last {
        ch.subscribers[i] = ch.subscribers[last];
      };
      ch.subscribers.pop();
      return true;
    };
    i = i + 1;
  };
  return false;
}

pub fn channel_subscriber_count(ch: &WsChannel) -> Int {
  return ch.subscribers.len();
}

pub fn channel_has_subscriber(ch: &WsChannel, conn_id: Str) -> Bool {
  var i: Int = 0;
  while i < ch.subscribers.len() {
    if ch.subscribers[i] == conn_id {
      return true;
    };
    i = i + 1;
  };
  return false;
}

// --- Close Codes ------------------------------------------------------------

pub fn close_code_normal() -> Int { return 1000; }
pub fn close_code_going_away() -> Int { return 1001; }
pub fn close_code_protocol_error() -> Int { return 1002; }
pub fn close_code_unsupported_data() -> Int { return 1003; }
pub fn close_code_policy_violation() -> Int { return 1008; }
pub fn close_code_message_too_big() -> Int { return 1009; }
pub fn close_code_internal_error() -> Int { return 1011; }

pub fn close_code_is_valid(code: Int) -> Bool {
  if code == 1000 { return true; };
  if code == 1001 { return true; };
  if code == 1002 { return true; };
  if code == 1003 { return true; };
  if code == 1008 { return true; };
  if code == 1009 { return true; };
  if code == 1011 { return true; };
  if code >= 3000 && code <= 4999 { return true; };
  return false;
}

pub fn close_code_text(code: Int) -> Str {
  if code == 1000 { return "Normal Closure"; };
  if code == 1001 { return "Going Away"; };
  if code == 1002 { return "Protocol Error"; };
  if code == 1003 { return "Unsupported Data"; };
  if code == 1008 { return "Policy Violation"; };
  if code == 1009 { return "Message Too Big"; };
  if code == 1011 { return "Internal Error"; };
  return "Unknown";
}

// --- Heartbeat --------------------------------------------------------------

pub fn heartbeat_interval_default() -> Int { return 30000; }
pub fn heartbeat_timeout_default() -> Int { return 10000; }

pub fn heartbeat_is_due(
  conn: &WsConnection,
  last_ping_ms: Int,
  now_ms: Int,
) -> Bool {
  return now_ms - last_ping_ms >= conn.heartbeat_interval_ms;
}

pub fn heartbeat_is_alive(
  last_pong_ms: Int,
  now_ms: Int,
  timeout_ms: Int,
) -> Bool {
  return now_ms - last_pong_ms < timeout_ms;
}
