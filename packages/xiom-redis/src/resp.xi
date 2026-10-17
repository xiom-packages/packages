// XIOM -- xiom.redis.resp: RESP2 wire codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM implementation of the Redis serialization protocol (RESP2),
// written from the published protocol specification:
//
//   * encode: a command is an array of bulk strings; the exact wire bytes
//     are "*<n>\r\n" then "$<len>\r\n<arg>\r\n" per argument;
//   * decode: simple string (+), error (-), integer (:), bulk string ($,
//     including $-1 null), array (*, including *-1 null array) with nested
//     arrays, and hard caps on depth, bulk size, array length and the
//     assembled reply size;
//   * every failure is a typed RedisError (from xiom.redis.value) with kind
//     REDIS_ERR_PROTOCOL and a numeric RESP_ERR_* code plus a message; the
//     streaming decoder also reports NeedMore so a caller can read more
//     bytes from a socket.
//
// Language notes (XIOM v0.64.4): free functions only; Ok/Err construction is
// confined to the tiny leaf helpers below; widened byte reads mask with
// `& 0xFF`; every Vec element read binds a typed local; the three arity
// guards that compute `end - start` implement the relative consumed-length
// contract of RespDone.

module xiom.redis.resp

use xiom.redis.value;

// ---------------------------------------------------------------------------
// Wire marker bytes
// ---------------------------------------------------------------------------

const _B_CR: UInt8 = 13u8;
const _B_LF: UInt8 = 10u8;
const _I_CR: Int = 13;
const _I_LF: Int = 10;
const _I_PLUS: Int = 43;
const _I_MINUS: Int = 45;
const _I_COLON: Int = 58;
const _I_DOLLAR: Int = 36;
const _I_STAR: Int = 42;
const _I_ZERO: Int = 48;
const _I_NINE: Int = 57;
const _I_INT_MAX: Int = 9223372036854775807;

// ---------------------------------------------------------------------------
// Decode outcome
// ---------------------------------------------------------------------------

/// Completed decode: the value plus the number of bytes it occupies in the
/// buffer, relative to the offset the decode started at.
pub type RespDone = {
  value: RedisValue;
  consumed: Int;
}

/// Streaming decode outcome: Done (value + consumed), NeedMore (the buffer
/// ends inside a value; read more bytes and retry), Bad (typed error).
pub enum RespOutcome {
  Done(done: RespDone),
  NeedMore,
  Bad(error: RedisError),
}

// ---------------------------------------------------------------------------
// Constructors (leaf helpers)
// ---------------------------------------------------------------------------

fn _ok_value(v: RedisValue) -> Result[RedisValue, RedisError] {
  return Ok(v);
}

fn _err_value(e: RedisError) -> Result[RedisValue, RedisError] {
  return Err(e);
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

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], RedisError] {
  return Ok(v);
}

fn _err_bytes(e: RedisError) -> Result[Vec[UInt8], RedisError] {
  return Err(e);
}

fn _proto(code: Int, message: Str) -> RedisError {
  return RedisError { kind: REDIS_ERR_PROTOCOL, code: code, message: message };
}

// Outcome constructors. `_done` takes the absolute end offset and the start
// offset and reports the relative consumed length (end_offset - start).
fn _done(v: RedisValue, end_offset: Int, start: Int) -> RespOutcome {
  var payload: RespDone = RespDone { value: v, consumed: end_offset - start };
  return Done(done: payload);
}

fn _need_more() -> RespOutcome {
  return NeedMore;
}

fn _bad(e: RedisError) -> RespOutcome {
  return Bad(error: e);
}

// Value constructors.
fn _val_nil() -> RedisValue {
  return Nil;
}

fn _val_null_array() -> RedisValue {
  return NullArray;
}

fn _val_simple(s: Str) -> RedisValue {
  return Simple(value: s);
}

fn _val_error(m: Str) -> RedisValue {
  return Error(message: m);
}

fn _val_integer(v: Int) -> RedisValue {
  return Integer(value: v);
}

fn _val_bulk(s: Str) -> RedisValue {
  return Bulk(value: s);
}

fn _val_array(items: Vec[RedisValue]) -> RedisValue {
  return Array(items: items);
}

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

fn _push_crlf(out: &mut Vec[UInt8]) {
  out.push(_B_CR);
  out.push(_B_LF);
}

fn _push_str_bytes(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  let n = s.len();
  while i < n {
    let b: UInt8 = s.byte_at(i);
    out.push(b);
    i = i + 1;
  }
}

// Append the decimal representation of a non-negative Int (validated by the
// caller); bytes are built directly so the wire form is unambiguous.
fn _push_int_bytes(out: &mut Vec[UInt8], v: Int) {
  if v <= 0 {
    out.push(_I_ZERO as UInt8);
    return;
  }
  var digits: Vec[UInt8] = Vec[UInt8].new();
  var t = v;
  while t > 0 {
    let d = t % 10;
    digits.push((_I_ZERO + d) as UInt8);
    t = t / 10;
  }
  var i = digits.len() - 1;
  while i >= 0 {
    let b: UInt8 = digits[i];
    out.push(b);
    i = i - 1;
  }
}

/// Encode one Redis command as an array of bulk strings and return the exact
/// wire bytes. Err(RedisError) with kind REDIS_ERR_PROTOCOL and code
/// RESP_ERR_EMPTY (no arguments) or RESP_ERR_SIZE (an argument exceeds
/// RESP_MAX_BULK).
pub fn resp_encode_command_bytes(args: &Vec[Str]) -> Result[Vec[UInt8], RedisError] {
  let n = args.len();
  if n <= 0 {
    return _err_bytes(_proto(RESP_ERR_EMPTY, "redis.resp: empty command (no arguments)"));
  }
  var i = 0;
  while i < n {
    let a: Str = args[i];
    if a.len() > RESP_MAX_BULK {
      return _err_bytes(_proto(RESP_ERR_SIZE, "redis.resp: argument exceeds the 64 MiB bulk cap"));
    }
    i = i + 1;
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  out.push(_I_STAR as UInt8);
  _push_int_bytes(&mut out, n);
  _push_crlf(&mut out);
  i = 0;
  while i < n {
    let a: Str = args[i];
    out.push(_I_DOLLAR as UInt8);
    _push_int_bytes(&mut out, a.len());
    _push_crlf(&mut out);
    _push_str_bytes(&mut out, a);
    _push_crlf(&mut out);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Encode one Redis command and return the wire bytes as a byte-exact Str.
pub fn resp_encode_command(args: &Vec[Str]) -> Result[Str, RedisError] {
  let enc = resp_encode_command_bytes(args);
  if !enc.is_ok {
    return _err_text(enc.error);
  }
  let bytes: Vec[UInt8] = enc.value;
  return _ok_text(Str::from_utf8(bytes));
}

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

// Scan for the CRLF that ends a header line starting at `start`.
// Returns the index of the CR, -1 when no LF is present yet (NeedMore) and
// -2 when an LF appears without a preceding CR (garbage terminator).
fn _scan_crlf(buf: &Vec[UInt8], start: Int) -> Int {
  var i = start;
  let n = buf.len();
  while i < n {
    let b: Int = (buf[i] as Int) & 0xFF;
    if b == _I_LF {
      if i > start {
        let p: Int = (buf[i - 1] as Int) & 0xFF;
        if p == _I_CR {
          return i - 1;
        }
      }
      return -2;
    }
    i = i + 1;
  }
  return -1;
}

// Copy buf[start..end) into a fresh Str (byte-exact).
fn _text_between(buf: &Vec[UInt8], start: Int, end: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = start;
  while i < end {
    let b: UInt8 = buf[i];
    out.push(b);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// Parse a decimal integer from buf[start..end); leading '-' or '+' accepted.
fn _parse_int_range(buf: &Vec[UInt8], start: Int, end: Int) -> Result[Int, RedisError] {
  if start >= end {
    return _err_int(_proto(RESP_ERR_INTEGER, "redis.resp: empty integer field"));
  }
  var i = start;
  var neg = false;
  let b0: Int = (buf[start] as Int) & 0xFF;
  if b0 == _I_MINUS {
    neg = true;
    i = start + 1;
  } elif b0 == _I_PLUS {
    i = start + 1;
  }
  if i >= end {
    return _err_int(_proto(RESP_ERR_INTEGER, "redis.resp: integer field has no digits"));
  }
  var v = 0;
  while i < end {
    let c: Int = (buf[i] as Int) & 0xFF;
    if c < _I_ZERO || c > _I_NINE {
      return _err_int(_proto(RESP_ERR_INTEGER, "redis.resp: non-numeric character in integer field"));
    }
    if v > 922337203685477580 {
      return _err_int(_proto(RESP_ERR_INTEGER, "redis.resp: integer field out of range"));
    }
    let d = c - _I_ZERO;
    if v == 922337203685477580 && d > 7 {
      return _err_int(_proto(RESP_ERR_INTEGER, "redis.resp: integer field out of range"));
    }
    v = v * 10 + d;
    i = i + 1;
  }
  if neg {
    v = 0 - v;
  }
  return _ok_int(v);
}

// Parse the reply at buf[off] with a nesting budget. See RespOutcome.
fn _parse(buf: &Vec[UInt8], off: Int, depth: Int) -> RespOutcome {
  let n = buf.len();
  if off >= n {
    return _need_more();
  }
  if depth > RESP_MAX_DEPTH {
    return _bad(_proto(RESP_ERR_DEPTH, "redis.resp: nesting exceeds the 32-level depth cap"));
  }
  let mark: Int = (buf[off] as Int) & 0xFF;

  if mark == _I_PLUS {
    let cr = _scan_crlf(buf, off + 1);
    if cr == -1 {
      return _need_more();
    }
    if cr == -2 {
      return _bad(_proto(RESP_ERR_TERMINATOR, "redis.resp: LF without CR inside a simple string"));
    }
    let text = _text_between(buf, off + 1, cr);
    return _done(_val_simple(text), cr + 2, off);
  }

  if mark == _I_MINUS {
    let cr = _scan_crlf(buf, off + 1);
    if cr == -1 {
      return _need_more();
    }
    if cr == -2 {
      return _bad(_proto(RESP_ERR_TERMINATOR, "redis.resp: LF without CR inside an error reply"));
    }
    let text = _text_between(buf, off + 1, cr);
    return _done(_val_error(text), cr + 2, off);
  }

  if mark == _I_COLON {
    let cr = _scan_crlf(buf, off + 1);
    if cr == -1 {
      return _need_more();
    }
    if cr == -2 {
      return _bad(_proto(RESP_ERR_TERMINATOR, "redis.resp: LF without CR inside an integer reply"));
    }
    let num = _parse_int_range(buf, off + 1, cr);
    if !num.is_ok {
      return _bad(num.error);
    }
    let v: Int = num.value;
    return _done(_val_integer(v), cr + 2, off);
  }

  if mark == _I_DOLLAR {
    let cr = _scan_crlf(buf, off + 1);
    if cr == -1 {
      return _need_more();
    }
    if cr == -2 {
      return _bad(_proto(RESP_ERR_TERMINATOR, "redis.resp: LF without CR inside a bulk length"));
    }
    let lenr = _parse_int_range(buf, off + 1, cr);
    if !lenr.is_ok {
      return _bad(lenr.error);
    }
    let blen: Int = lenr.value;
    if blen == -1 {
      return _done(_val_nil(), cr + 2, off);
    }
    if blen < 0 {
      return _bad(_proto(RESP_ERR_LENGTH, "redis.resp: negative bulk length (only $-1 is null)"));
    }
    if blen > RESP_MAX_BULK {
      return _bad(_proto(RESP_ERR_SIZE, "redis.resp: bulk length exceeds the 64 MiB cap"));
    }
    let payload_start = cr + 2;
    let end = payload_start + blen;
    if end + 2 > n {
      return _need_more();
    }
    let t0: Int = (buf[end] as Int) & 0xFF;
    let t1: Int = (buf[end + 1] as Int) & 0xFF;
    if t0 != _I_CR || t1 != _I_LF {
      return _bad(_proto(RESP_ERR_TERMINATOR, "redis.resp: bulk payload not terminated by CRLF"));
    }
    let payload = _text_between(buf, payload_start, end);
    return _done(_val_bulk(payload), end + 2, off);
  }

  if mark == _I_STAR {
    let cr = _scan_crlf(buf, off + 1);
    if cr == -1 {
      return _need_more();
    }
    if cr == -2 {
      return _bad(_proto(RESP_ERR_TERMINATOR, "redis.resp: LF without CR inside an array length"));
    }
    let cntr = _parse_int_range(buf, off + 1, cr);
    if !cntr.is_ok {
      return _bad(cntr.error);
    }
    let count: Int = cntr.value;
    if count == -1 {
      return _done(_val_null_array(), cr + 2, off);
    }
    if count < 0 {
      return _bad(_proto(RESP_ERR_LENGTH, "redis.resp: negative array length (only *-1 is null)"));
    }
    if count > RESP_MAX_ARRAY {
      return _bad(_proto(RESP_ERR_SIZE, "redis.resp: array length exceeds the 1048576 element cap"));
    }
    if depth >= RESP_MAX_DEPTH {
      return _bad(_proto(RESP_ERR_DEPTH, "redis.resp: nesting exceeds the 32-level depth cap"));
    }
    var items: Vec[RedisValue] = Vec[RedisValue].new();
    var pos = cr + 2;
    var k = 0;
    while k < count {
      let child = _parse(buf, pos, depth + 1);
      match child {
        Done(d) => {
          let v: RedisValue = d.value;
          let used: Int = d.consumed;
          items.push(v);
          pos = pos + used;
        },
        NeedMore => {
          return _need_more();
        },
        Bad(e) => {
          return _bad(e);
        },
      };
      k = k + 1;
    }
    return _done(_val_array(items), pos, off);
  }

  return _bad(_proto(RESP_ERR_TYPE, "redis.resp: unknown reply type marker"));
}

/// Streaming decode of the reply at buf[off]: Done(value, consumed) when a
/// complete value is present, NeedMore when the buffer ends mid-value (the
/// caller should read more bytes and retry), Bad(error) for malformed input.
pub fn resp_decode_at(buf: &Vec[UInt8], off: Int) -> RespOutcome {
  if off < 0 {
    return _bad(_proto(RESP_ERR_OFFSET, "redis.resp: negative decode offset"));
  }
  return _parse(buf, off, 0);
}

/// Decode exactly one reply at buf[off]; an incomplete buffer is
/// Err(kind REDIS_ERR_PROTOCOL, code RESP_ERR_TRUNCATED).
pub fn resp_decode(buf: &Vec[UInt8], off: Int) -> Result[RedisValue, RedisError] {
  let o = resp_decode_at(buf, off);
  match o {
    Done(d) => {
      let v: RedisValue = d.value;
      return _ok_value(v);
    },
    NeedMore => {
      return _err_value(_proto(RESP_ERR_TRUNCATED, "redis.resp: incomplete reply (truncated buffer)"));
    },
    Bad(e) => {
      let e2: RedisError = e;
      return _err_value(e2);
    },
  }
}
