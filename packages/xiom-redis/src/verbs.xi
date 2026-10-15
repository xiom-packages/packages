// XIOM -- xiom.redis.verbs: typed command wrappers (client verbs + pub/sub)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// One typed wrapper per supported command family. Every wrapper routes the
// reply through redis_command_checked, so a server error reply surfaces as
// Err(kind REDIS_ERR_SERVER, message preserved) instead of a raw Error
// value; unexpected reply shapes are typed REDIS_ERR_PROTOCOL failures and
// are never coerced. The public plain-name surface is re-exported by the
// package root module xiom.redis.

module xiom.redis.verbs

use xiom.string.compare;
use xiom.redis.value;
use xiom.redis.client;

// ---------------------------------------------------------------------------
// Constructors (leaf helpers)
// ---------------------------------------------------------------------------

fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn _protocol_error(code: Int, msg: Str) -> RedisError {
  return redis_error(REDIS_ERR_PROTOCOL, code, msg);
}

fn _ok_text(s: Str) -> Result[Str, RedisError] {
  return Ok(s);
}

fn _err_text(e: RedisError) -> Result[Str, RedisError] {
  return Err(e);
}

fn _ok_int(v: Int) -> Result[Int, RedisError] {
  return Ok(v);
}

fn _err_int(e: RedisError) -> Result[Int, RedisError] {
  return Err(e);
}

fn _ok_bool(v: Bool) -> Result[Bool, RedisError] {
  return Ok(v);
}

fn _err_bool(e: RedisError) -> Result[Bool, RedisError] {
  return Err(e);
}

fn _ok_maybe(m: RedisText) -> Result[RedisText, RedisError] {
  return Ok(m);
}

fn _err_maybe(e: RedisError) -> Result[RedisText, RedisError] {
  return Err(e);
}

fn _ok_maybes(v: Vec[RedisText]) -> Result[Vec[RedisText], RedisError] {
  return Ok(v);
}

fn _err_maybes(e: RedisError) -> Result[Vec[RedisText], RedisError] {
  return Err(e);
}

// ---------------------------------------------------------------------------
// Shared reply extraction (typed; never guesses)
// ---------------------------------------------------------------------------

fn _expect_text(v: RedisValue, what: Str) -> Result[Str, RedisError] {
  let t = value_text(&v);
  if !t.is_ok {
    return _err_text(_protocol_error(0, "redis: " + what + " expected a simple/bulk text reply"));
  }
  return _ok_text(t.value);
}

fn _expect_int(v: RedisValue, what: Str) -> Result[Int, RedisError] {
  let t = value_int(&v);
  if !t.is_ok {
    return _err_int(_protocol_error(0, "redis: " + what + " expected an integer reply"));
  }
  return _ok_int(t.value);
}

fn _expect_ok(v: RedisValue, what: Str) -> Result[Bool, RedisError] {
  if value_is_nil(&v) {
    return _ok_bool(false);
  }
  let t = value_text(&v);
  if !t.is_ok {
    return _err_bool(_protocol_error(0, "redis: " + what + " expected +OK or a null reply"));
  }
  let s: Str = t.value;
  if _streq(s, "OK") {
    return _ok_bool(true);
  }
  return _err_bool(_protocol_error(0, "redis: " + what + " unexpected text reply: " + s));
}

// ---------------------------------------------------------------------------
// Verb wrappers
// ---------------------------------------------------------------------------

/// PING -> the server's text reply (normally "PONG").
pub fn redis_ping(conn: &mut RedisConn) -> Result[Str, RedisError] {
  var args: Vec[Str] = Vec[Str].new();
  args.push("PING");
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_text(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_text(v, "PING");
}

/// ECHO message -> the echoed text.
pub fn redis_echo(conn: &mut RedisConn, message: Str) -> Result[Str, RedisError] {
  var args: Vec[Str] = Vec[Str].new();
  args.push("ECHO");
  args.push(message);
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_text(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_text(v, "ECHO");
}

/// GET key -> Missing when the key does not exist (RESP null bulk), Text
/// otherwise.
pub fn redis_get(conn: &mut RedisConn, key: Str) -> Result[RedisText, RedisError] {
  if key.len() == 0 {
    return _err_maybe(_protocol_error(0, "redis: GET requires a non-empty key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("GET");
  args.push(key);
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_maybe(r.error);
  }
  let v: RedisValue = r.value;
  let m = value_maybe_text(&v);
  if !m.is_ok {
    return _err_maybe(_protocol_error(0, "redis: GET expected a bulk text reply or null"));
  }
  return _ok_maybe(m.value);
}

/// SET key value -> true on +OK, false on a null reply (SET with NX/XX).
pub fn redis_set(conn: &mut RedisConn, key: Str, value: Str) -> Result[Bool, RedisError] {
  if key.len() == 0 {
    return _err_bool(_protocol_error(0, "redis: SET requires a non-empty key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("SET");
  args.push(key);
  args.push(value);
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_ok(v, "SET");
}

/// SET key value EX seconds -> true on +OK.
pub fn redis_set_ex(conn: &mut RedisConn, key: Str, value: Str, seconds: Int) -> Result[Bool, RedisError] {
  if key.len() == 0 {
    return _err_bool(_protocol_error(0, "redis: SET requires a non-empty key"));
  }
  if seconds <= 0 {
    return _err_bool(_protocol_error(0, "redis: SET EX requires a positive expiry"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("SET");
  args.push(key);
  args.push(value);
  args.push("EX");
  args.push(seconds.to_str());
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_ok(v, "SET EX");
}

/// DEL key [key ...] -> number of keys removed.
pub fn redis_del(conn: &mut RedisConn, keys: &Vec[Str]) -> Result[Int, RedisError] {
  if keys.len() == 0 {
    return _err_int(_protocol_error(0, "redis: DEL requires at least one key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("DEL");
  var i = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    args.push(k);
    i = i + 1;
  }
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_int(v, "DEL");
}

/// EXISTS key [key ...] -> number of keys that exist.
pub fn redis_exists(conn: &mut RedisConn, keys: &Vec[Str]) -> Result[Int, RedisError] {
  if keys.len() == 0 {
    return _err_int(_protocol_error(0, "redis: EXISTS requires at least one key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("EXISTS");
  var i = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    args.push(k);
    i = i + 1;
  }
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_int(v, "EXISTS");
}

/// INCR key -> the new integer value.
pub fn redis_incr(conn: &mut RedisConn, key: Str) -> Result[Int, RedisError] {
  if key.len() == 0 {
    return _err_int(_protocol_error(0, "redis: INCR requires a non-empty key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("INCR");
  args.push(key);
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_int(v, "INCR");
}

/// DECR key -> the new integer value.
pub fn redis_decr(conn: &mut RedisConn, key: Str) -> Result[Int, RedisError] {
  if key.len() == 0 {
    return _err_int(_protocol_error(0, "redis: DECR requires a non-empty key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("DECR");
  args.push(key);
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_int(v, "DECR");
}

/// EXPIRE key seconds -> true when the timeout was set.
pub fn redis_expire(conn: &mut RedisConn, key: Str, seconds: Int) -> Result[Bool, RedisError] {
  if key.len() == 0 {
    return _err_bool(_protocol_error(0, "redis: EXPIRE requires a non-empty key"));
  }
  if seconds <= 0 {
    return _err_bool(_protocol_error(0, "redis: EXPIRE requires positive seconds"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("EXPIRE");
  args.push(key);
  args.push(seconds.to_str());
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: RedisValue = r.value;
  let n = _expect_int(v, "EXPIRE");
  if !n.is_ok {
    return _err_bool(n.error);
  }
  let code: Int = n.value;
  return _ok_bool(code == 1);
}

/// TTL key -> seconds to live (-1 no expiry, -2 missing key; the server's
/// integers are passed through).
pub fn redis_ttl(conn: &mut RedisConn, key: Str) -> Result[Int, RedisError] {
  if key.len() == 0 {
    return _err_int(_protocol_error(0, "redis: TTL requires a non-empty key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("TTL");
  args.push(key);
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_int(v, "TTL");
}

/// MGET key [key ...] -> one RedisText per key, in order (Missing where the
/// server replied with a null bulk).
pub fn redis_mget(conn: &mut RedisConn, keys: &Vec[Str]) -> Result[Vec[RedisText], RedisError] {
  if keys.len() == 0 {
    return _err_maybes(_protocol_error(0, "redis: MGET requires at least one key"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("MGET");
  var i = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    args.push(k);
    i = i + 1;
  }
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_maybes(r.error);
  }
  let v: RedisValue = r.value;
  let arr = value_array(&v);
  if !arr.is_ok {
    return _err_maybes(_protocol_error(0, "redis: MGET expected an array reply"));
  }
  let items: Vec[RedisValue] = arr.value;
  var out: Vec[RedisText] = Vec[RedisText].new();
  i = 0;
  while i < items.len() {
    let e: RedisValue = items[i];
    let m = value_maybe_text(&e);
    if !m.is_ok {
      return _err_maybes(_protocol_error(0, "redis: MGET element is neither text nor null"));
    }
    let mt: RedisText = m.value;
    out.push(mt);
    i = i + 1;
  }
  return _ok_maybes(out);
}

/// MSET key value [key value ...] -> true on +OK. `pairs` must alternate
/// key/value and be non-empty.
pub fn redis_mset(conn: &mut RedisConn, pairs: &Vec[Str]) -> Result[Bool, RedisError] {
  let n = pairs.len();
  if n == 0 || (n % 2) != 0 {
    return _err_bool(_protocol_error(0, "redis: MSET requires an even, non-zero number of key/value arguments"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("MSET");
  var i = 0;
  while i < n {
    let a: Str = pairs[i];
    args.push(a);
    i = i + 1;
  }
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_ok(v, "MSET");
}

// ---------------------------------------------------------------------------
// Pub/sub (honest mode switch: after SUBSCRIBE the connection accepts only
// the pub/sub command subset; replies arrive as push arrays that read_push
// consumes one by one)
// ---------------------------------------------------------------------------

fn _redis_subscribe_impl(conn: &mut RedisConn, verb: Str, channel: Str) -> Result[Int, RedisError] {
  if channel.len() == 0 {
    return _err_int(_protocol_error(0, "redis: " + verb + " requires a non-empty channel"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push(verb);
  args.push(channel);
  let r = redis_command(conn, &args);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: RedisValue = r.value;
  if value_kind(&v) == REDIS_VALUE_ERROR {
    let m = value_error_message(&v);
    return _err_int(redis_error(REDIS_ERR_SERVER, 0, m));
  }
  let arr = value_array(&v);
  if !arr.is_ok {
    return _err_int(_protocol_error(0, "redis: " + verb + " expected an array confirmation"));
  }
  let items: Vec[RedisValue] = arr.value;
  if items.len() < 3 {
    return _err_int(_protocol_error(0, "redis: " + verb + " confirmation is shorter than 3 elements"));
  }
  let third: RedisValue = items[2];
  let count = value_int(&third);
  if !count.is_ok {
    return _err_int(_protocol_error(0, "redis: " + verb + " confirmation count is not an integer"));
  }
  return _ok_int(count.value);
}

/// SUBSCRIBE channel -> active subscription count from the confirmation
/// (normally 1). After this call the connection is in subscribed mode.
pub fn redis_subscribe(conn: &mut RedisConn, channel: Str) -> Result[Int, RedisError] {
  return _redis_subscribe_impl(conn, "SUBSCRIBE", channel);
}

/// UNSUBSCRIBE channel -> remaining subscription count (normally 0).
pub fn redis_unsubscribe(conn: &mut RedisConn, channel: Str) -> Result[Int, RedisError] {
  return _redis_subscribe_impl(conn, "UNSUBSCRIBE", channel);
}

/// PUBLISH channel message -> number of clients that received the message.
pub fn redis_publish(conn: &mut RedisConn, channel: Str, message: Str) -> Result[Int, RedisError] {
  if channel.len() == 0 {
    return _err_int(_protocol_error(0, "redis: PUBLISH requires a non-empty channel"));
  }
  var args: Vec[Str] = Vec[Str].new();
  args.push("PUBLISH");
  args.push(channel);
  args.push(message);
  let r = redis_command_checked(conn, &args);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: RedisValue = r.value;
  return _expect_int(v, "PUBLISH");
}

/// Read one push message with an explicit deadline for this call only
/// (milliseconds; 0 blocks). The returned value is the raw push array
/// (e.g. ["message", channel, payload]); a deadline expiry is
/// Err(kind REDIS_ERR_TIMEOUT). The connection's configured read timeout is
/// restored afterwards.
pub fn redis_read_push(conn: &mut RedisConn, timeout_ms: Int) -> Result[RedisValue, RedisError] {
  if timeout_ms < 0 {
    return _err_value(redis_error(REDIS_ERR_TIMEOUT, 0, "redis: negative push deadline"));
  }
  let saved = redis_read_timeout(conn);
  redis_set_read_timeout(conn, timeout_ms);
  let r = redis_read_value(conn);
  redis_set_read_timeout(conn, saved);
  return r;
}

fn _err_value(e: RedisError) -> Result[RedisValue, RedisError] {
  return Err(e);
}
