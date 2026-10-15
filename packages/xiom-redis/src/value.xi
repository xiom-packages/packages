// XIOM -- xiom.redis.value: RESP value model, error taxonomy and accessors
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The typed value model shared by the whole package: RedisValue (one decoded
// RESP2 reply), RedisText (optional text for verbs whose reply may be null)
// and RedisError (the typed failure). Also the public error-kind /
// protocol-code / value-kind constants, the documented caps, and the typed
// value accessors. The wire codec lives in xiom.redis.resp; the socket
// session in xiom.redis.client; the verb wrappers in xiom.redis.verbs.
//
// Language notes (XIOM v0.64.4): free functions only; Ok/Err construction is
// confined to the tiny leaf helpers below; every Vec element read binds a
// typed local; Str payloads are never compared in this module.

module xiom.redis.value

// ---------------------------------------------------------------------------
// Error kinds (RedisError.kind)
// ---------------------------------------------------------------------------

pub const REDIS_ERR_NONE: Int = 0;
pub const REDIS_ERR_CONNECT: Int = 1;
pub const REDIS_ERR_PROTOCOL: Int = 2;
pub const REDIS_ERR_TIMEOUT: Int = 3;
pub const REDIS_ERR_SERVER: Int = 4;
pub const REDIS_ERR_CLOSED: Int = 5;
pub const REDIS_ERR_TYPE: Int = 6;

// ---------------------------------------------------------------------------
// Protocol error codes (RedisError.code for kind REDIS_ERR_PROTOCOL)
// ---------------------------------------------------------------------------

pub const RESP_ERR_TYPE: Int = 1;
pub const RESP_ERR_LENGTH: Int = 2;
pub const RESP_ERR_TRUNCATED: Int = 3;
pub const RESP_ERR_DEPTH: Int = 4;
pub const RESP_ERR_SIZE: Int = 5;
pub const RESP_ERR_TERMINATOR: Int = 6;
pub const RESP_ERR_INTEGER: Int = 7;
pub const RESP_ERR_EMPTY: Int = 8;
pub const RESP_ERR_OFFSET: Int = 9;

// ---------------------------------------------------------------------------
// Value kinds (value_kind)
// ---------------------------------------------------------------------------

pub const REDIS_VALUE_NIL: Int = 0;
pub const REDIS_VALUE_SIMPLE: Int = 1;
pub const REDIS_VALUE_ERROR: Int = 2;
pub const REDIS_VALUE_INTEGER: Int = 3;
pub const REDIS_VALUE_BULK: Int = 4;
pub const REDIS_VALUE_ARRAY: Int = 5;
pub const REDIS_VALUE_NULL_ARRAY: Int = 6;

// ---------------------------------------------------------------------------
// Documented caps (typed: RESP_ERR_SIZE / RESP_ERR_DEPTH on breach)
// ---------------------------------------------------------------------------

pub const RESP_MAX_DEPTH: Int = 32;
pub const RESP_MAX_BULK: Int = 67108864;
pub const RESP_MAX_ARRAY: Int = 1048576;
pub const RESP_MAX_REPLY: Int = 134217728;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A typed transport/protocol failure. `kind` is one of REDIS_ERR_*; `code`
/// is a RESP_ERR_* protocol code (0 for non-protocol kinds); `message` names
/// the offending token or the server-provided text (kind REDIS_ERR_SERVER).
pub type RedisError = {
  kind: Int;
  code: Int;
  message: Str;
}

/// One decoded RESP2 reply value. Null bulk ($-1) is `Nil`; null array
/// (*-1) is `NullArray`; protocol-level server errors (`-...`) are `Error`
/// values carrying the server's message verbatim.
pub enum RedisValue {
  Nil,
  NullArray,
  Simple(value: Str),
  Error(message: Str),
  Integer(value: Int),
  Bulk(value: Str),
  Array(items: Vec[RedisValue]),
}

/// Optional text result for verbs whose reply may legitimately be null
/// (GET, MGET elements, RPOP): `Missing` is a RESP null, `Text` a reply.
pub enum RedisText {
  Missing,
  Text(value: Str),
}

// ---------------------------------------------------------------------------
// Constructors (leaf helpers)
// ---------------------------------------------------------------------------

/// Build a typed error. `kind` REDIS_ERR_*, `code` RESP_ERR_* (0 if none).
pub fn redis_error(kind: Int, code: Int, message: Str) -> RedisError {
  return RedisError { kind: kind, code: code, message: message };
}

fn _type_error(message: Str) -> RedisError {
  return RedisError { kind: REDIS_ERR_TYPE, code: 0, message: message };
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

fn _ok_values(v: Vec[RedisValue]) -> Result[Vec[RedisValue], RedisError] {
  return Ok(v);
}

fn _err_values(e: RedisError) -> Result[Vec[RedisValue], RedisError] {
  return Err(e);
}

fn _ok_maybe(m: RedisText) -> Result[RedisText, RedisError] {
  return Ok(m);
}

fn _err_maybe(e: RedisError) -> Result[RedisText, RedisError] {
  return Err(e);
}

fn _ok_value(v: RedisValue) -> Result[RedisValue, RedisError] {
  return Ok(v);
}

fn _err_value(e: RedisError) -> Result[RedisValue, RedisError] {
  return Err(e);
}

// ---------------------------------------------------------------------------
// Typed value accessors
// ---------------------------------------------------------------------------

/// Kind of a decoded value: REDIS_VALUE_*.
pub fn value_kind(v: &RedisValue) -> Int {
  match v {
    Nil => { return REDIS_VALUE_NIL; },
    NullArray => { return REDIS_VALUE_NULL_ARRAY; },
    Simple(s) => { return REDIS_VALUE_SIMPLE; },
    Error(m) => { return REDIS_VALUE_ERROR; },
    Integer(i) => { return REDIS_VALUE_INTEGER; },
    Bulk(s) => { return REDIS_VALUE_BULK; },
    Array(items) => { return REDIS_VALUE_ARRAY; },
  }
}

/// True for the null bulk reply ($-1) only.
pub fn value_is_nil(v: &RedisValue) -> Bool {
  return value_kind(v) == REDIS_VALUE_NIL;
}

/// True for either RESP null form: null bulk ($-1) or null array (*-1).
pub fn value_is_null(v: &RedisValue) -> Bool {
  let k = value_kind(v);
  return k == REDIS_VALUE_NIL || k == REDIS_VALUE_NULL_ARRAY;
}

/// The server error text of an `Error` value; "" for all other kinds.
pub fn value_error_message(v: &RedisValue) -> Str {
  match v {
    Error(m) => { return m; },
    _ => {},
  }
  return "";
}

/// The text of a simple-string or bulk-string reply; any other kind is
/// Err(kind REDIS_ERR_TYPE).
pub fn value_text(v: &RedisValue) -> Result[Str, RedisError] {
  match v {
    Simple(s) => { return _ok_text(s); },
    Bulk(s) => { return _ok_text(s); },
    _ => {},
  }
  return _err_text(_type_error("redis.value: value is not a text reply (simple/bulk)"));
}

/// The integer of an integer reply; any other kind is
/// Err(kind REDIS_ERR_TYPE).
pub fn value_int(v: &RedisValue) -> Result[Int, RedisError] {
  match v {
    Integer(i) => { return _ok_int(i); },
    _ => {},
  }
  return _err_int(_type_error("redis.value: value is not an integer reply"));
}

/// Nil / null-array -> Missing; simple/bulk text -> Text; any other kind is
/// Err(kind REDIS_ERR_TYPE).
pub fn value_maybe_text(v: &RedisValue) -> Result[RedisText, RedisError] {
  if value_is_null(v) {
    let m: RedisText = Missing;
    return _ok_maybe(m);
  }
  let t = value_text(v);
  if !t.is_ok {
    return _err_maybe(_type_error("redis.value: value is not a text reply (simple/bulk) or null"));
  }
  let s: Str = t.value;
  let m: RedisText = Text(value: s);
  return _ok_maybe(m);
}

/// Number of elements in an array reply; 0 for every other kind.
pub fn value_array_len(v: &RedisValue) -> Int {
  match v {
    Array(items) => { return items.len(); },
    _ => {},
  }
  return 0;
}

/// Copy of the elements of an array reply; any other kind is
/// Err(kind REDIS_ERR_TYPE).
pub fn value_array(v: &RedisValue) -> Result[Vec[RedisValue], RedisError] {
  match v {
    Array(items) => {
      var out: Vec[RedisValue] = Vec[RedisValue].new();
      var i = 0;
      let n = items.len();
      while i < n {
        let e: RedisValue = items[i];
        out.push(e);
        i = i + 1;
      }
      return _ok_values(out);
    },
    _ => {},
  }
  return _err_values(_type_error("redis.value: value is not an array reply"));
}

/// Copy of element `i` of an array reply (0-based). Out-of-range or a
/// non-array value is Err(kind REDIS_ERR_TYPE).
pub fn value_at(v: &RedisValue, i: Int) -> Result[RedisValue, RedisError] {
  match v {
    Array(items) => {
      let n = items.len();
      if i < 0 || i >= n {
        return _err_value(_type_error("redis.value: array index out of range"));
      }
      let e: RedisValue = items[i];
      return _ok_value(e);
    },
    _ => {},
  }
  return _err_value(_type_error("redis.value: value is not an array reply"));
}
