// XIOM -- xiom.postgres wire codec (PostgreSQL Frontend/Backend Protocol v3)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure byte codec for the PostgreSQL v3 wire protocol: frontend message
// builders (StartupMessage, PasswordMessage, Query, Terminate, SASL
// initial/response) and the backend message decoder (Authentication,
// ParameterStatus, BackendKeyData, ReadyForQuery, RowDescription, DataRow,
// CommandComplete, EmptyQueryResponse, ErrorResponse, NoticeResponse,
// NotificationResponse). No sockets and no global state: every function is
// a pure transform over byte vectors. The protocol layout is the public
// "Frontend/Backend Protocol" documentation -- see PROVENANCE.md.

module xiom.postgres.wire

use xiom.string;

// ------------------------------------------------------------------ constants

/// Protocol version 3.0 as the 32-bit StartupMessage field (0x00030000).
pub const PG_PROTOCOL_V3: Int = 196608;

/// Decode-side bound for a single backend message (16 MiB). A declared
/// length above this is a typed protocol error, never an allocation.
pub const PG_MAX_MESSAGE_BYTES: Int = 16777216;

// PgError.kind values (the typed error taxonomy).
pub const PG_ERR_CONNECTION: Int = 1;
pub const PG_ERR_PROTOCOL: Int = 2;
pub const PG_ERR_AUTH: Int = 3;
pub const PG_ERR_SERVER: Int = 4;
pub const PG_ERR_TIMEOUT: Int = 5;
pub const PG_ERR_UNSUPPORTED_AUTH: Int = 6;

// Authentication request codes carried by backend 'R' messages.
pub const AUTH_OK: Int = 0;
pub const AUTH_CLEARTEXT: Int = 3;
pub const AUTH_MD5: Int = 5;
pub const AUTH_SASL: Int = 10;
pub const AUTH_SASL_CONTINUE: Int = 11;
pub const AUTH_SASL_FINAL: Int = 12;

// Frontend/backend message type bytes used below (decimal ASCII):
// 'R'=82 'S'=83 'K'=75 'Z'=90 'T'=84 'D'=68 'C'=67 'I'=73 'E'=69
// 'N'=78 'A'=65 'p'=112 'Q'=81 'X'=88

// ------------------------------------------------------------------ types

/// One field of an ErrorResponse/NoticeResponse ('E'/'N') message: the
/// one-character field code plus its NUL-terminated value.
pub type PgErrField = {
  code: Str;
  value: Str;
}

/// Typed error returned by every xiom.postgres operation.
///
/// `kind` is one of the PG_ERR_* constants. `code` is the server SQLSTATE
/// (ErrorResponse field C) or "" when the error is client-side. `offset` is
/// the absolute byte offset a protocol/decode error was found at, or -1
/// when the error has no wire offset. `fields` preserves every server field
/// (S/V/C/M/D/H/P/F/L/R/...) verbatim.
pub type PgError = {
  kind: Int;
  message: Str;
  code: Str;
  severity: Str;
  detail: Str;
  hint: Str;
  position: Int;
  offset: Int;
  fields: Vec[PgErrField];
}

/// One RowDescription field. Text-format simple queries always report
/// `format == 0`; `type_size == -1` means variable length.
pub type PgField = {
  name: Str;
  table_oid: Int;
  column_id: Int;
  type_oid: Int;
  type_size: Int;
  type_mod: Int;
  format: Int;
}

/// One decoded backend message. Only the fields relevant to `msg_type` are
/// populated; every other field keeps its documented empty value. For 'E'
/// and 'N' messages the severity/code/message/detail/hint/position fields
/// are the decoded identity of the server's field list, and err_fields
/// keeps every field verbatim.
pub type PgMsg = {
  msg_type: Str;
  length: Int;
  start: Int;
  next: Int;
  auth_code: Int;
  salt: Vec[UInt8];
  sasl_data: Vec[UInt8];
  mechanisms: Vec[Str];
  param_name: Str;
  param_value: Str;
  pid: Int;
  secret: Int;
  status: Str;
  fields: Vec[PgField];
  values: Vec[Option[Str]];
  tag: Str;
  affected: Int;
  err_fields: Vec[PgErrField];
  severity: Str;
  code: Str;
  message: Str;
  detail: Str;
  hint: Str;
  position: Int;
  channel: Str;
  payload: Str;
}

// ------------------------------------------------------------------ errors

fn perr(kind: Int, message: Str, offset: Int) -> PgError {
  return PgError{
    kind: kind;
    message: message;
    code: "";
    severity: "";
    detail: "";
    hint: "";
    position: 0;
    offset: offset;
    fields: Vec[PgErrField].new();
  };
}

/// Protocol/decode error at a byte offset.
pub fn err_protocol(message: Str, offset: Int) -> PgError {
  return perr(PG_ERR_PROTOCOL, message, offset);
}

/// Connection-level error (no wire offset).
pub fn err_connection(message: Str) -> PgError {
  return perr(PG_ERR_CONNECTION, message, -1);
}

/// Timeout error (no wire offset).
pub fn err_timeout(message: Str) -> PgError {
  return perr(PG_ERR_TIMEOUT, message, -1);
}

/// Authentication/authorization error (no wire offset).
pub fn err_auth(message: Str) -> PgError {
  return perr(PG_ERR_AUTH, message, -1);
}

/// Unsupported authentication mechanism error (no wire offset).
pub fn err_unsupported_auth(message: Str) -> PgError {
  return perr(PG_ERR_UNSUPPORTED_AUTH, message, -1);
}

/// Wrap a decoded ErrorResponse ('E') message as kind PG_ERR_SERVER,
/// preserving the SQLSTATE and the full field list.
pub fn server_error_from(m: &PgMsg) -> PgError {
  return PgError{
    kind: PG_ERR_SERVER;
    message: m.message;
    code: m.code;
    severity: m.severity;
    detail: m.detail;
    hint: m.hint;
    position: m.position;
    offset: -1;
    fields: m.err_fields;
  };
}

// ------------------------------------------------------------------ byte helpers

fn str_of_bytes(b: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

fn one_char(b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(b as UInt8);
  return Str::from_utf8(v);
}

fn push_i32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v >> 24) & 0xFF) as UInt8);
  out.push(((v >> 16) & 0xFF) as UInt8);
  out.push(((v >> 8) & 0xFF) as UInt8);
  out.push((v & 0xFF) as UInt8);
}

fn push_bytes(out: &mut Vec[UInt8], b: &Vec[UInt8]) {
  var i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
}

fn push_cstr(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  out.push(0);
}

fn signed16(v: Int) -> Int {
  if v >= 32768 {
    return v - 65536;
  }
  return v;
}

fn signed32(v: Int) -> Int {
  if v >= 2147483648 {
    return v - 4294967296;
  }
  return v;
}

fn has_zero_byte(b: &Vec[UInt8]) -> Int {
  var i = 0;
  while i < b.len() {
    if b[i] == (0 as UInt8) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// ------------------------------------------------------------------ reads

/// Read an unsigned 32-bit big-endian value in [off, limit).
/// Err carries offset == limit when fewer than 4 bytes remain.
pub fn read_i32(buf: &Vec[UInt8], off: Int, limit: Int) -> Result[Int, PgError] {
  if off < 0 {
    return Err(err_protocol("read before start of buffer", off));
  }
  if off + 4 > limit {
    return Err(err_protocol("truncated 32-bit field", limit));
  }
  var v = 0;
  var i = 0;
  while i < 4 {
    v = (v << 8) | (buf[off + i] as Int);
    i = i + 1;
  }
  return Ok(v);
}

/// Read an unsigned 16-bit big-endian value in [off, limit).
pub fn read_i16(buf: &Vec[UInt8], off: Int, limit: Int) -> Result[Int, PgError] {
  if off < 0 {
    return Err(err_protocol("read before start of buffer", off));
  }
  if off + 2 > limit {
    return Err(err_protocol("truncated 16-bit field", limit));
  }
  var v = (buf[off] as Int) << 8;
  v = v | (buf[off + 1] as Int);
  return Ok(v);
}

/// Read one byte in [off, limit).
pub fn read_u8(buf: &Vec[UInt8], off: Int, limit: Int) -> Result[Int, PgError] {
  if off < 0 {
    return Err(err_protocol("read before start of buffer", off));
  }
  if off >= limit {
    return Err(err_protocol("truncated byte field", limit));
  }
  return Ok(buf[off] as Int);
}

/// One decoded NUL-terminated string field: its value plus the offset just
/// past the terminating NUL.
pub type PgCStr = {
  value: Str;
  next: Int;
}

/// Read a NUL-terminated string in [off, limit).
pub fn read_cstr(buf: &Vec[UInt8], off: Int, limit: Int) -> Result[PgCStr, PgError] {
  if off < 0 {
    return Err(err_protocol("read before start of buffer", off));
  }
  var i = off;
  while i < limit {
    if buf[i] == (0 as UInt8) {
      var out = Vec[UInt8].new();
      var j = off;
      while j < i {
        out.push(buf[j]);
        j = j + 1;
      }
      return Ok(PgCStr{ value: Str::from_utf8(out); next: i + 1 });
    }
    i = i + 1;
  }
  return Err(err_protocol("unterminated string field", limit));
}

/// Copy n bytes at [off, off+n) bounded by limit.
pub fn read_bytes(buf: &Vec[UInt8], off: Int, n: Int, limit: Int) -> Result[Vec[UInt8], PgError] {
  if off < 0 || n < 0 {
    return Err(err_protocol("negative read range", off));
  }
  if off + n > limit {
    return Err(err_protocol("truncated byte field", limit));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(buf[off + i]);
    i = i + 1;
  }
  return Ok(out);
}

// ------------------------------------------------------------------ builders

fn build_typed(kind: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(kind as UInt8);
  push_i32(&mut out, body.len() + 4);
  push_bytes(&mut out, body);
  return out;
}

/// StartupMessage (no type byte): protocol 3.0 with user/database params.
pub fn build_startup(user: Str, database: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_i32(&mut body, PG_PROTOCOL_V3);
  push_cstr(&mut body, "user");
  push_cstr(&mut body, user);
  push_cstr(&mut body, "database");
  push_cstr(&mut body, database);
  body.push(0);
  var out = Vec[UInt8].new();
  push_i32(&mut out, body.len() + 4);
  push_bytes(&mut out, &body);
  return out;
}

/// PasswordMessage ('p'): cleartext or MD5 response, NUL-terminated.
pub fn build_password(password: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_cstr(&mut body, password);
  return build_typed(112, &body);
}

/// SASLInitialResponse ('p'): mechanism + Int32 length + the initial
/// client-first bytes (raw, no NUL terminator per the protocol).
pub fn build_sasl_initial(mechanism: Str, initial: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_cstr(&mut body, mechanism);
  push_i32(&mut body, initial.len());
  var i = 0;
  while i < initial.len() {
    body.push(initial.byte_at(i));
    i = i + 1;
  }
  return build_typed(112, &body);
}

/// SASLResponse ('p'): the raw client-final message (protocol framing has
/// no NUL terminator on the SASL payload).
pub fn build_sasl_response(response: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  var i = 0;
  while i < response.len() {
    body.push(response.byte_at(i));
    i = i + 1;
  }
  return build_typed(112, &body);
}

/// Simple Query ('Q'), NUL-terminated SQL text.
pub fn build_query(sql: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_cstr(&mut body, sql);
  return build_typed(81, &body);
}

/// Terminate ('X'), empty body.
pub fn build_terminate() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  return build_typed(88, &body);
}

// ------------------------------------------------------------------ tags

/// Rows affected by a CommandComplete tag: the trailing decimal word when
/// present ("SELECT 5" -> 5, "INSERT 0 3" -> 3, "UPDATE 2" -> 2), else 0
/// ("CREATE TABLE", "BEGIN", empty).
pub fn pg_tag_affected(tag: Str) -> Int {
  let n = tag.len();
  if n == 0 {
    return 0;
  }
  var end = n;
  while end > 0 && tag.byte_at(end - 1) == (32 as UInt8) {
    end = end - 1;
  }
  if end == 0 {
    return 0;
  }
  var start = 0;
  var k = end;
  while k > 0 {
    if tag.byte_at(k - 1) == (32 as UInt8) {
      start = k;
      k = 0;
    } else {
      k = k - 1;
    }
  }
  if start >= end {
    return 0;
  }
  let token = string.str_slice(tag, start, end);
  let pr = string.str_to_int(token);
  match pr {
    Ok(v) => {
      if v >= 0 {
        return v;
      }
      return 0;
    },
    Err(_) => {
      return 0;
    },
  }
  return 0;
}

// ------------------------------------------------------------------ decode

fn empty_msg() -> PgMsg {
  return PgMsg{
    msg_type: "";
    length: 0;
    start: 0;
    next: 0;
    auth_code: -1;
    salt: Vec[UInt8].new();
    sasl_data: Vec[UInt8].new();
    mechanisms: Vec[Str].new();
    param_name: "";
    param_value: "";
    pid: -1;
    secret: -1;
    status: "";
    fields: Vec[PgField].new();
    values: Vec[Option[Str]].new();
    tag: "";
    affected: 0;
    err_fields: Vec[PgErrField].new();
    severity: "";
    code: "";
    message: "";
    detail: "";
    hint: "";
    position: 0;
    channel: "";
    payload: "";
  };
}

fn copy_err_identity(m: PgMsg) -> PgMsg {
  var out = m;
  var i = 0;
  while i < out.err_fields.len() {
    let f = out.err_fields[i];
    let c = f.code;
    if string.str_compare(c, "S") == 0 {
      out.severity = f.value;
    } elif string.str_compare(c, "V") == 0 {
      if out.severity.len() == 0 {
        out.severity = f.value;
      }
    } elif string.str_compare(c, "C") == 0 {
      out.code = f.value;
    } elif string.str_compare(c, "M") == 0 {
      out.message = f.value;
    } elif string.str_compare(c, "D") == 0 {
      out.detail = f.value;
    } elif string.str_compare(c, "H") == 0 {
      out.hint = f.value;
    } elif string.str_compare(c, "P") == 0 {
      let pr = string.str_to_int(f.value);
      match pr {
        Ok(v) => {
          out.position = v;
        },
        Err(_) => {
          out.position = 0;
        },
      }
    }
    i = i + 1;
  }
  return out;
}

fn decode_auth(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let cr = read_i32(buf, body, end);
  var code = 0;
  match cr {
    Ok(v) => {
      code = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  out.auth_code = code;
  if code == AUTH_MD5 {
    let sr = read_bytes(buf, body + 4, 4, end);
    match sr {
      Ok(s) => {
        out.salt = s;
      },
      Err(e) => {
        return Err(e);
      },
    }
  } elif code == AUTH_SASL {
    var pos = body + 4;
    var done = false;
    while !done {
      let nr = read_cstr(buf, pos, end);
      match nr {
        Ok(cs) => {
          if cs.value.len() == 0 {
            done = true;
          } else {
            out.mechanisms.push(cs.value);
            pos = cs.next;
          }
        },
        Err(e) => {
          return Err(e);
        },
      }
    }
  } elif code == AUTH_SASL_CONTINUE || code == AUTH_SASL_FINAL {
    let dr = read_bytes(buf, body + 4, end - (body + 4), end);
    match dr {
      Ok(d) => {
        out.sasl_data = d;
      },
      Err(e) => {
        return Err(e);
      },
    }
  }
  return Ok(out);
}

fn decode_parameter_status(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let nr = read_cstr(buf, body, end);
  var np = end;
  match nr {
    Ok(cs) => {
      out.param_name = cs.value;
      np = cs.next;
    },
    Err(e) => {
      return Err(e);
    },
  }
  let vr = read_cstr(buf, np, end);
  match vr {
    Ok(cs2) => {
      out.param_value = cs2.value;
    },
    Err(e) => {
      return Err(e);
    },
  }
  return Ok(out);
}

fn decode_backend_key(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let pr = read_i32(buf, body, end);
  var pid = 0;
  match pr {
    Ok(v) => {
      pid = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  let sr = read_i32(buf, body + 4, end);
  var secret = 0;
  match sr {
    Ok(v) => {
      secret = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  out.pid = pid;
  out.secret = secret;
  return Ok(out);
}

fn decode_ready(buf: &Vec<UInt8>, m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let sr = read_u8(buf, body, end);
  var st = 0;
  match sr {
    Ok(v) => {
      st = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  if st != 73 && st != 84 && st != 69 {
    return Err(err_protocol("invalid ReadyForQuery status byte", body));
  }
  out.status = one_char(st);
  return Ok(out);
}

fn decode_row_description(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let nr = read_i16(buf, body, end);
  var count = 0;
  match nr {
    Ok(v) => {
      count = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  var pos = body + 2;
  var i = 0;
  while i < count {
    let name_r = read_cstr(buf, pos, end);
    var name = "";
    match name_r {
      Ok(cs) => {
        name = cs.value;
        pos = cs.next;
      },
      Err(e) => {
        return Err(e);
      },
    }
    let t_r = read_i32(buf, pos, end);
    var table_oid = 0;
    match t_r {
      Ok(v) => {
        table_oid = v;
      },
      Err(e) => {
        return Err(e);
      },
    }
    let c_r = read_i16(buf, pos + 4, end);
    var column_id = 0;
    match c_r {
      Ok(v) => {
        column_id = v;
      },
      Err(e) => {
        return Err(e);
      },
    }
    let ty_r = read_i32(buf, pos + 6, end);
    var type_oid = 0;
    match ty_r {
      Ok(v) => {
        type_oid = v;
      },
      Err(e) => {
        return Err(e);
      },
    }
    let sz_r = read_i16(buf, pos + 10, end);
    var type_size = 0;
    match sz_r {
      Ok(v) => {
        type_size = signed16(v);
      },
      Err(e) => {
        return Err(e);
      },
    }
    let tm_r = read_i32(buf, pos + 12, end);
    var type_mod = 0;
    match tm_r {
      Ok(v) => {
        type_mod = signed32(v);
      },
      Err(e) => {
        return Err(e);
      },
    }
    let fm_r = read_i16(buf, pos + 16, end);
    var format = 0;
    match fm_r {
      Ok(v) => {
        format = v;
      },
      Err(e) => {
        return Err(e);
      },
    }
    pos = pos + 18;
    out.fields.push(PgField{
      name: name;
      table_oid: table_oid;
      column_id: column_id;
      type_oid: type_oid;
      type_size: type_size;
      type_mod: type_mod;
      format: format;
    });
    i = i + 1;
  }
  return Ok(out);
}

fn decode_data_row(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let nr = read_i16(buf, body, end);
  var count = 0;
  match nr {
    Ok(v) => {
      count = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  var pos = body + 2;
  var i = 0;
  while i < count {
    let lr = read_i32(buf, pos, end);
    var len = 0;
    match lr {
      Ok(v) => {
        len = v;
      },
      Err(e) => {
        return Err(e);
      },
    }
    pos = pos + 4;
    if len == 4294967295 {
      out.values.push(None);
    } else {
      let br = read_bytes(buf, pos, len, end);
      var bytes = Vec[UInt8].new();
      match br {
        Ok(b) => {
          bytes = b;
        },
        Err(e) => {
          return Err(e);
        },
      }
      let zi = has_zero_byte(&bytes);
      if zi >= 0 {
        return Err(err_protocol("NUL byte inside text-format value", pos + zi));
      }
      out.values.push(Some(str_of_bytes(&bytes)));
      pos = pos + len;
    }
    i = i + 1;
  }
  return Ok(out);
}

fn decode_command_complete(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let tr = read_cstr(buf, body, end);
  match tr {
    Ok(cs) => {
      out.tag = cs.value;
      out.affected = pg_tag_affected(cs.value);
    },
    Err(e) => {
      return Err(e);
    },
  }
  return Ok(out);
}

fn decode_error_response(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  var pos = body;
  var done = false;
  while !done {
    let fr = read_u8(buf, pos, end);
    var fb = 0;
    match fr {
      Ok(v) => {
        fb = v;
      },
      Err(e) => {
        return Err(e);
      },
    }
    if fb == 0 {
      done = true;
    } else {
      let vr = read_cstr(buf, pos + 1, end);
      match vr {
        Ok(cs) => {
          out.err_fields.push(PgErrField{ code: one_char(fb); value: cs.value });
          pos = cs.next;
        },
        Err(e) => {
          return Err(e);
        },
      }
    }
  }
  out = copy_err_identity(out);
  return Ok(out);
}

fn decode_notification(buf: &Vec[UInt8], m: PgMsg, body: Int, end: Int) -> Result[PgMsg, PgError] {
  var out = m;
  let pr = read_i32(buf, body, end);
  var pid = 0;
  match pr {
    Ok(v) => {
      pid = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  let cr = read_cstr(buf, body + 4, end);
  var channel = "";
  var pos = end;
  match cr {
    Ok(cs) => {
      channel = cs.value;
      pos = cs.next;
    },
    Err(e) => {
      return Err(e);
    },
  }
  let yr = read_cstr(buf, pos, end);
  var payload = "";
  match yr {
    Ok(cs2) => {
      payload = cs2.value;
    },
    Err(e) => {
      return Err(e);
    },
  }
  out.pid = pid;
  out.channel = channel;
  out.payload = payload;
  return Ok(out);
}

/// Decode one complete backend message starting at byte `start`.
///
/// The returned message's `next` field is the offset just past the message,
/// so callers can walk a buffer that holds several messages. Every
/// structural failure is a typed PG_ERR_PROTOCOL error whose `offset` names
/// the byte where decoding could not continue (the offending byte for an
/// invalid value, the first missing byte for a truncation, the message end
/// when a nested field overruns its declared length).
pub fn wire_decode(buf: &Vec[UInt8], start: Int) -> Result[PgMsg, PgError] {
  let blen = buf.len();
  if start < 0 {
    return Err(err_protocol("negative message offset", start));
  }
  if start >= blen {
    return Err(err_protocol("message offset past end of input", start));
  }
  let tb = buf[start] as Int;
  let lr = read_i32(buf, start + 1, blen);
  var len = 0;
  match lr {
    Ok(v) => {
      len = v;
    },
    Err(e) => {
      return Err(e);
    },
  }
  if len < 4 {
    return Err(err_protocol("message length below 4", start + 1));
  }
  if len > PG_MAX_MESSAGE_BYTES {
    return Err(err_protocol("message length above decode cap", start + 1));
  }
  let next = start + 1 + len;
  if next > blen {
    return Err(err_protocol("message extends past end of input", blen));
  }
  var m = empty_msg();
  m.msg_type = one_char(tb);
  m.length = len;
  m.start = start;
  m.next = next;
  let body = start + 5;
  if tb == 82 {
    return decode_auth(buf, m, body, next);
  }
  if tb == 83 {
    return decode_parameter_status(buf, m, body, next);
  }
  if tb == 75 {
    return decode_backend_key(buf, m, body, next);
  }
  if tb == 90 {
    return decode_ready(buf, m, body, next);
  }
  if tb == 84 {
    return decode_row_description(buf, m, body, next);
  }
  if tb == 68 {
    return decode_data_row(buf, m, body, next);
  }
  if tb == 67 {
    return decode_command_complete(buf, m, body, next);
  }
  if tb == 73 {
    return Ok(m);
  }
  if tb == 69 {
    return decode_error_response(buf, m, body, next);
  }
  if tb == 78 {
    return decode_error_response(buf, m, body, next);
  }
  if tb == 65 {
    return decode_notification(buf, m, body, next);
  }
  return Err(err_protocol("unknown backend message type", start));
}
