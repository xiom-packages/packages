// XIOM -- xiom.redis: pure-XIOM Redis RESP2 client (public surface)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Public client surface: connect / disconnect, raw and checked commands,
// pipelines, typed verb wrappers and pub/sub. All names are plain module
// functions (no redis_ prefix). No FFI, no hiredis: the transport is the
// stdlib TCP socket and the wire codec is implemented from the RESP2
// specification.
//
// Companion modules in this package:
//   * xiom.redis.value  (src/value.xi)  -- RedisValue / RedisText /
//                                          RedisError, constants and the
//                                          typed value accessors;
//   * xiom.redis.resp   (src/resp.xi)   -- RESP2 encoder/decoder;
//   * xiom.redis.client (src/client.xi) -- socket session and commands;
//   * xiom.redis.verbs  (src/verbs.xi)  -- typed verb wrappers and pub/sub.
//
// Usage convention (same shape as xiom.ann / xiom.http):
//   use xiom.redis;         // connect, command, get, set, pipeline, ...
//   use xiom.redis.value;   // RedisValue, RedisText, value_* accessors,
//                           // REDIS_* / RESP_* constants
//   use xiom.redis.client;  // RedisConn and RedisError, redis_* fns

module xiom.redis

use xiom.redis.value;
use xiom.redis.client;
use xiom.redis.verbs;

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

/// Connect to host:port over TCP -> Result[RedisConn, RedisError]. Failure
/// is kind REDIS_ERR_CONNECT (connection refused, bad host/port); see
/// xiom.redis.client.redis_connect for the runtime note on Windows.
pub fn connect(host: Str, port: Int) -> Result[RedisConn, RedisError] {
  return redis_connect(host, port);
}

/// Connect and apply timeout_sec as the session read deadline: replies that
/// do not arrive within it fail with kind REDIS_ERR_TIMEOUT. 0.0 blocks.
/// The TCP handshake itself stays OS-bounded (documented in SPEC.md).
pub fn connect_timeout(host: Str, port: Int, timeout_sec: Float64) -> Result[RedisConn, RedisError] {
  return redis_connect_timeout(host, port, timeout_sec);
}

/// Close the connection (also clears the fd; safe twice).
pub fn disconnect(conn: &mut RedisConn) {
  redis_disconnect(conn);
}

/// Set the read deadline for subsequent replies (milliseconds; <= 0 blocks).
pub fn set_read_timeout(conn: &mut RedisConn, timeout_ms: Int) {
  redis_set_read_timeout(conn, timeout_ms);
}

/// Current read deadline in milliseconds (0 = block).
pub fn read_timeout(conn: &RedisConn) -> Int {
  return redis_read_timeout(conn);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// Run one command (args[0] is the verb) and return the raw decoded reply.
/// Server error replies surface as Ok(RedisValue::Error(message)).
pub fn command(conn: &mut RedisConn, args: &Vec[Str]) -> Result[RedisValue, RedisError] {
  return redis_command(conn, args);
}

/// Like command, but a server error reply becomes
/// Err(kind REDIS_ERR_SERVER, message preserved verbatim).
pub fn command_checked(conn: &mut RedisConn, args: &Vec[Str]) -> Result[RedisValue, RedisError] {
  return redis_command_checked(conn, args);
}

/// Send N commands in one write and read N replies in order. Server error
/// replies are preserved as Error values (raw pipeline semantics).
pub fn pipeline(conn: &mut RedisConn, commands: &Vec[Vec[Str]]) -> Result[Vec[RedisValue], RedisError] {
  return redis_pipeline(conn, commands);
}

/// Read exactly one decoded reply from the wire (public push/pipeline
/// primitive; applies the session read deadline).
pub fn read_value(conn: &mut RedisConn) -> Result[RedisValue, RedisError] {
  return redis_read_value(conn);
}

// ---------------------------------------------------------------------------
// Verb wrappers (all typed)
// ---------------------------------------------------------------------------

/// PING -> the server's text reply ("PONG").
pub fn ping(conn: &mut RedisConn) -> Result[Str, RedisError] {
  return redis_ping(conn);
}

/// ECHO message -> the echoed text.
pub fn echo(conn: &mut RedisConn, message: Str) -> Result[Str, RedisError] {
  return redis_echo(conn, message);
}

/// GET key -> RedisText (Missing on a null reply).
pub fn get(conn: &mut RedisConn, key: Str) -> Result[RedisText, RedisError] {
  return redis_get(conn, key);
}

/// SET key value -> true on +OK, false on a null reply.
pub fn set(conn: &mut RedisConn, key: Str, value: Str) -> Result[Bool, RedisError] {
  return redis_set(conn, key, value);
}

/// SET key value EX seconds -> true on +OK.
pub fn set_ex(conn: &mut RedisConn, key: Str, value: Str, seconds: Int) -> Result[Bool, RedisError] {
  return redis_set_ex(conn, key, value, seconds);
}

/// DEL key [key ...] -> number of keys removed.
pub fn del(conn: &mut RedisConn, keys: &Vec[Str]) -> Result[Int, RedisError] {
  return redis_del(conn, keys);
}

/// EXISTS key [key ...] -> number of keys that exist.
pub fn exists(conn: &mut RedisConn, keys: &Vec[Str]) -> Result[Int, RedisError] {
  return redis_exists(conn, keys);
}

/// INCR key -> new value.
pub fn incr(conn: &mut RedisConn, key: Str) -> Result[Int, RedisError] {
  return redis_incr(conn, key);
}

/// DECR key -> new value.
pub fn decr(conn: &mut RedisConn, key: Str) -> Result[Int, RedisError] {
  return redis_decr(conn, key);
}

/// EXPIRE key seconds -> true when the timeout was set.
pub fn expire(conn: &mut RedisConn, key: Str, seconds: Int) -> Result[Bool, RedisError] {
  return redis_expire(conn, key, seconds);
}

/// TTL key -> seconds (-1 no expiry, -2 missing; server integers passed
/// through).
pub fn ttl(conn: &mut RedisConn, key: Str) -> Result[Int, RedisError] {
  return redis_ttl(conn, key);
}

/// MGET key [key ...] -> one RedisText per key, in order.
pub fn mget(conn: &mut RedisConn, keys: &Vec[Str]) -> Result[Vec[RedisText], RedisError] {
  return redis_mget(conn, keys);
}

/// MSET key value [key value ...] -> true on +OK.
pub fn mset(conn: &mut RedisConn, pairs: &Vec[Str]) -> Result[Bool, RedisError] {
  return redis_mset(conn, pairs);
}

// ---------------------------------------------------------------------------
// Pub/sub
// ---------------------------------------------------------------------------

/// SUBSCRIBE channel -> subscription count (normally 1). The connection is
/// in subscribed mode afterwards: only the pub/sub command subset is
/// accepted by the server and messages arrive as push arrays for read_push.
pub fn subscribe(conn: &mut RedisConn, channel: Str) -> Result[Int, RedisError] {
  return redis_subscribe(conn, channel);
}

/// UNSUBSCRIBE channel -> remaining subscription count (normally 0).
pub fn unsubscribe(conn: &mut RedisConn, channel: Str) -> Result[Int, RedisError] {
  return redis_unsubscribe(conn, channel);
}

/// PUBLISH channel message -> number of clients that received the message.
pub fn publish(conn: &mut RedisConn, channel: Str, message: Str) -> Result[Int, RedisError] {
  return redis_publish(conn, channel, message);
}

/// Read one push message with a per-call deadline (milliseconds; 0 blocks):
/// the raw push array (e.g. ["message", channel, payload]) or
/// Err(kind REDIS_ERR_TIMEOUT) when the deadline expires.
pub fn read_push(conn: &mut RedisConn, timeout_ms: Int) -> Result[RedisValue, RedisError] {
  return redis_read_push(conn, timeout_ms);
}
