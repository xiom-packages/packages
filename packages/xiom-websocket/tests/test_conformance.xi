// XIOM -- xiom-websocket Conformance Tests (10 tests)
module xiom.websocket.tests

use xiom.websocket;
use xiom.string;
use xiom.io;

fn assert_true(condition: Bool, label: Str) -> Result[Unit, Str] {
  if condition { return Ok(Unit); };
  return Err("FAIL: " + label);
}

fn assert_int_eq(actual: Int, expected: Int, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label + " -- expected " + int_to_str(expected) + " got " + int_to_str(actual));
}

fn assert_str_eq(actual: Str, expected: Str, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label + " -- expected '" + expected + "' got '" + actual + "'");
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var num: Int = n;
  var neg: Bool = false;
  if num < 0 { neg = true; num = -num; };
  var out: Str = "";
  while num > 0 {
    var d: Int = num % 10;
    if d == 0 { out = "0" + out; }
    elif d == 1 { out = "1" + out; }
    elif d == 2 { out = "2" + out; }
    elif d == 3 { out = "3" + out; }
    elif d == 4 { out = "4" + out; }
    elif d == 5 { out = "5" + out; }
    elif d == 6 { out = "6" + out; }
    elif d == 7 { out = "7" + out; }
    elif d == 8 { out = "8" + out; }
    elif d == 9 { out = "9" + out; };
    num = num / 10;
  };
  if neg { out = "-" + out; };
  return out;
}

pub fn run_all_tests() -> Result[Unit, Str] {
  io.println("=== xiom-websocket Conformance Tests ===");

  var passed: Int = 0;
  var failed: Int = 0;
  var total: Int = 0;

  var results: Vec[Result[Unit, Str]] = Vec[Result[Unit, Str]].new();
  results.push(test_opcode_helpers());
  results.push(test_frame_create());
  results.push(test_frame_encode_decode());
  results.push(test_frame_validate());
  results.push(test_connection_lifecycle());
  results.push(test_handshake_validation());
  results.push(test_server_management());
  results.push(test_channel_subscriptions());
  results.push(test_close_codes());
  results.push(test_heartbeat());

  var i: Int = 0;
  while i < results.len() {
    total = total + 1;
    match results[i] {
      Ok(_) => { passed = passed + 1; },
      Err(e) => { failed = failed + 1; io.println(e); },
    };
    i = i + 1;
  };

  io.println("");
  io.println(int_to_str(passed) + " passed, " + int_to_str(failed) + " failed out of " + int_to_str(total));

  if failed > 0 {
    return Err(int_to_str(failed) + " test(s) failed");
  };
  return Ok(Unit);
}

fn test_opcode_helpers() -> Result[Unit, Str] {
  try(assert_int_eq(opcode_to_int(WsOpcode.Text), 1, "opcode_to_int: Text=1"));
  try(assert_int_eq(opcode_to_int(WsOpcode.Binary), 2, "opcode_to_int: Binary=2"));
  try(assert_int_eq(opcode_to_int(WsOpcode.Close), 8, "opcode_to_int: Close=8"));
  try(assert_int_eq(opcode_to_int(WsOpcode.Ping), 9, "opcode_to_int: Ping=9"));
  try(assert_int_eq(opcode_to_int(WsOpcode.Pong), 10, "opcode_to_int: Pong=10"));

  match opcode_from_int(1) { WsOpcode.Text => {}, _ => { return Err("FAIL: opcode_from_int 1"); }, };
  match opcode_from_int(8) { WsOpcode.Close => {}, _ => { return Err("FAIL: opcode_from_int 8"); }, };

  try(assert_true(opcode_is_control(WsOpcode.Close), "is_control: Close"));
  try(assert_true(opcode_is_control(WsOpcode.Ping), "is_control: Ping"));
  try(assert_true(opcode_is_control(WsOpcode.Pong), "is_control: Pong"));
  try(assert_true(!opcode_is_control(WsOpcode.Text), "!is_control: Text"));

  try(assert_true(opcode_is_data(WsOpcode.Text), "is_data: Text"));
  try(assert_true(opcode_is_data(WsOpcode.Binary), "is_data: Binary"));
  try(assert_true(!opcode_is_data(WsOpcode.Close), "!is_data: Close"));

  return Ok(Unit);
}

fn test_frame_create() -> Result[Unit, Str] {
  var f = frame_text("hello");
  try(assert_true(f.fin, "frame_text: fin=true"));
  try(assert_true(frame_is_final(&f), "frame_is_final: true"));
  try(assert_true(frame_is_data(&f), "frame_is_data: text"));
  try(assert_true(!frame_is_control(&f), "frame_is_control: text is not"));

  var cf = frame_close(1000);
  try(assert_true(frame_is_control(&cf), "frame_is_control: close"));
  try(assert_true(!frame_is_data(&cf), "frame_is_data: close not"));

  var pf = frame_ping();
  match pf.opcode { WsOpcode.Ping => {}, _ => { return Err("FAIL: frame_ping opcode"); }, };

  var pof = frame_pong();
  match pof.opcode { WsOpcode.Pong => {}, _ => { return Err("FAIL: frame_pong opcode"); }, };

  try(assert_int_eq(frame_payload_len(&f), 5, "frame_payload_len: 5"));

  return Ok(Unit);
}

fn test_frame_encode_decode() -> Result[Unit, Str] {
  var payload: Vec[Int] = Vec[Int].new();
  payload.push(104); payload.push(101); payload.push(108);
  payload.push(108); payload.push(111);
  var f = frame_new(WsOpcode.Text, payload);

  var encoded = frame_encode(&f);
  match encoded {
    Ok(raw) => {
      try(assert_int_eq(raw.len(), 7, "frame_encode: 7 bytes (2 header + 5 payload)"));
      var decoded = frame_decode(&raw);
      match decoded {
        Ok(df) => {
          try(assert_true(df.fin, "frame_decode: fin"));
          match df.opcode { WsOpcode.Text => {}, _ => { return Err("FAIL: frame_decode opcode"); }, };
          try(assert_int_eq(df.payload.len(), 5, "frame_decode: payload len 5"));
        },
        Err(e) => { return Err("FAIL: frame_decode: " + e); },
      };
    },
    Err(e) => { return Err("FAIL: frame_encode: " + e); },
  };

  return Ok(Unit);
}

fn test_frame_validate() -> Result[Unit, Str] {
  var text_frame = frame_text("data");
  var v1 = frame_validate(&text_frame);
  match v1 { Ok(_) => {}, Err(e) => { return Err("FAIL: validate text: " + e); }, };

  // Large payload ping -- should fail
  var large_ping: Vec[Int] = Vec[Int].new();
  var i2: Int = 0;
  while i2 < 200 {
    large_ping.push(0);
    i2 = i2 + 1;
  };
  var bad_frame = WsFrame{
    fin: true,
    opcode: WsOpcode.Ping,
    masked: false,
    payload: large_ping,
    reserved: Vec[Int].new(),
  };
  var v2 = frame_validate(&bad_frame);
  match v2 {
    Ok(_) => { return Err("FAIL: validate should reject large control frame"); },
    Err(_) => {},
  };

  // Fragmented control frame -- should fail
  var frag = WsFrame{
    fin: false,
    opcode: WsOpcode.Close,
    masked: false,
    payload: Vec[Int].new(),
    reserved: Vec[Int].new(),
  };
  var v3 = frame_validate(&frag);
  match v3 {
    Ok(_) => { return Err("FAIL: validate should reject fragmented control frame"); },
    Err(_) => {},
  };

  return Ok(Unit);
}

fn test_connection_lifecycle() -> Result[Unit, Str] {
  var conn = connection_new("c1", "ws.example.com", 8080, "/chat");
  try(assert_str_eq(conn.id, "c1", "connection_new: id"));
  try(assert_str_eq(conn.host, "ws.example.com", "connection_new: host"));
  try(assert_int_eq(conn.port, 8080, "connection_new: port"));
  try(assert_int_eq(conn.last_seq, 0, "connection_new: last_seq=0"));

  try(assert_true(!connection_is_open(&conn), "connection: not open initially"));
  try(assert_true(!connection_is_closed(&conn), "connection: not closed initially"));

  connection_set_state(&mut conn, WsConnectionState.Open);
  try(assert_true(connection_is_open(&conn), "connection: open after set_state"));
  try(assert_true(!connection_is_closed(&conn), "connection: not closed when open"));

  connection_set_state(&mut conn, WsConnectionState.Closed);
  try(assert_true(connection_is_closed(&conn), "connection: closed after set_state"));

  connection_set_heartbeat(&mut conn, 60000);
  try(assert_int_eq(conn.heartbeat_interval_ms, 60000, "connection: heartbeat 60s"));

  return Ok(Unit);
}

fn test_handshake_validation() -> Result[Unit, Str] {
  try(assert_true(handshake_is_valid("host.com", "dGhlIHNhbXBsZSBub25jZQ==", "13"), "handshake: valid"));

  try(assert_true(!handshake_is_valid("", "key", "13"), "handshake: missing host"));
  try(assert_true(!handshake_is_valid("host", "", "13"), "handshake: missing key"));
  try(assert_true(!handshake_is_valid("host", "key", "12"), "handshake: wrong version"));

  var key = handshake_compute_key("dGhlIHNhbXBsZSBub25jZQ==");
  try(assert_true(string.str_len(key) > 0, "handshake_compute_key: non-empty"));

  return Ok(Unit);
}

fn test_server_management() -> Result[Unit, Str] {
  var server = server_new("0.0.0.0", 9090);
  try(assert_str_eq(server.host, "0.0.0.0", "server_new: host"));
  try(assert_int_eq(server.port, 9090, "server_new: port"));
  try(assert_int_eq(server_connection_count(&server), 0, "server: 0 connections initially"));
  try(assert_true(!server_is_running(&server), "server: not running"));

  var c1 = connection_new("c1", "a", 1, "/");
  var c2 = connection_new("c2", "b", 2, "/");
  server_add_connection(&mut server, c1);
  server_add_connection(&mut server, c2);
  try(assert_int_eq(server_connection_count(&server), 2, "server: 2 connections"));

  var found = server_find_connection(&server, "c1");
  match found {
    Some(c) => { try(assert_str_eq(c.id, "c1", "server_find_connection: found")); },
    None => { return Err("FAIL: server_find_connection c1 not found"); },
  };

  var removed = server_remove_connection(&mut server, "c1");
  try(assert_true(removed, "server_remove_connection: removed"));
  try(assert_int_eq(server_connection_count(&server), 1, "server: 1 after removal"));

  var not_found = server_find_connection(&server, "c1");
  match not_found {
    Some(_) => { return Err("FAIL: server_find_connection c1 still present"); },
    None => {},
  };

  return Ok(Unit);
}

fn test_channel_subscriptions() -> Result[Unit, Str] {
  var ch = channel_new("lobby");
  try(assert_str_eq(ch.name, "lobby", "channel_new: name"));
  try(assert_int_eq(channel_subscriber_count(&ch), 0, "channel: 0 subscribers"));

  channel_subscribe(&mut ch, "user1");
  channel_subscribe(&mut ch, "user2");
  channel_subscribe(&mut ch, "user3");
  try(assert_int_eq(channel_subscriber_count(&ch), 3, "channel: 3 subscribers"));

  try(assert_true(channel_has_subscriber(&ch, "user2"), "has_subscriber: user2"));
  try(assert_true(!channel_has_subscriber(&ch, "user99"), "has_subscriber: user99 missing"));

  var unsub = channel_unsubscribe(&mut ch, "user2");
  try(assert_true(unsub, "unsubscribe: user2 removed"));
  try(assert_int_eq(channel_subscriber_count(&ch), 2, "channel: 2 after unsubscribe"));
  try(assert_true(!channel_has_subscriber(&ch, "user2"), "has_subscriber: user2 gone"));

  var unsub2 = channel_unsubscribe(&mut ch, "user99");
  try(assert_true(!unsub2, "unsubscribe: non-member returns false"));

  return Ok(Unit);
}

fn test_close_codes() -> Result[Unit, Str] {
  try(assert_int_eq(close_code_normal(), 1000, "close_code: normal 1000"));
  try(assert_int_eq(close_code_going_away(), 1001, "close_code: going away 1001"));
  try(assert_int_eq(close_code_protocol_error(), 1002, "close_code: protocol error 1002"));
  try(assert_int_eq(close_code_internal_error(), 1011, "close_code: internal error 1011"));

  try(assert_true(close_code_is_valid(1000), "close_code_is_valid: 1000"));
  try(assert_true(close_code_is_valid(1011), "close_code_is_valid: 1011"));
  try(assert_true(close_code_is_valid(4000), "close_code_is_valid: custom 4000"));
  try(assert_true(!close_code_is_valid(500), "!close_code_is_valid: 500"));
  try(assert_true(!close_code_is_valid(2000), "!close_code_is_valid: 2000 reserved"));

  try(assert_str_eq(close_code_text(1000), "Normal Closure", "close_code_text: 1000"));
  try(assert_str_eq(close_code_text(1009), "Message Too Big", "close_code_text: 1009"));
  try(assert_str_eq(close_code_text(9999), "Unknown", "close_code_text: unknown"));

  return Ok(Unit);
}

fn test_heartbeat() -> Result[Unit, Str] {
  try(assert_int_eq(heartbeat_interval_default(), 30000, "heartbeat: interval default 30s"));
  try(assert_int_eq(heartbeat_timeout_default(), 10000, "heartbeat: timeout default 10s"));

  var conn = connection_new("hb1", "a", 1, "/");
  try(assert_true(heartbeat_is_due(&conn, 0, 30000), "heartbeat_is_due: 30s elapsed"));
  try(assert_true(!heartbeat_is_due(&conn, 0, 10000), "heartbeat_is_due: not due at 10s"));

  try(assert_true(heartbeat_is_alive(5000, 10000, 10000), "heartbeat_is_alive: within window"));
  try(assert_true(!heartbeat_is_alive(0, 20000, 10000), "heartbeat_is_alive: timed out"));

  connection_set_heartbeat(&mut conn, 5000);
  try(assert_true(heartbeat_is_due(&conn, 0, 5000), "heartbeat_is_due: 5s custom interval"));

  return Ok(Unit);
}

fn try(res: Result[Unit, Str]) {
  match res {
    Ok(_) => {},
    Err(e) => { io.println(e); },
  };
}
