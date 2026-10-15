// XIOM -- xiom.transport.frames: wire codec (little-endian, one frame per
// datagram)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The compact packet header and every packet kind of the transport wire
// format, written from scratch against the package's own declared layout
// (SPEC.md sec. 4; design reference NETCODE.md sec. 2-3). All multi-byte
// fields are little-endian. One datagram carries exactly one frame.
//
// Header (19 bytes) at absolute offsets:
//   0  version   u8    (FRAME_VERSION; a foreign version refuses)
//   1  flags     u8    (kind = flags & 0x0F, FRAME_FLAG_FRAGMENT = 0x10)
//   2  conn_id   u32
//   6  channel   u8
//   7  seq       u32   (send sequence, per channel)
//   11 ack       u32   (highest contiguous seq received on the channel;
//                       0xFFFFFFFF = "no ack yet", surfaced as -1)
//   15 ack_bits  u32   (bitfield of received seqs below ack; bit d-1 marks
//                       ack-d)
//
// Kinds (flags low nibble) and their fixed tails:
//   FRAME_KIND_HELLO      + protocol_version u16
//   FRAME_KIND_HELLO_ACK  + protocol_version u16
//   FRAME_KIND_DATA       + payload bytes, optionally prefixed by 12 bytes
//                         of fragment metadata when FRAME_FLAG_FRAGMENT:
//                         frag_index u16, frag_count u16, frag_offset u32
//                         (byte offset in the message), frag_total u32
//   FRAME_KIND_ACK        (header only; ack/ack_bits fields are the body)
//   FRAME_KIND_PING       (header only)
//   FRAME_KIND_PONG       (header only)
//   FRAME_KIND_FIN        + reason u8 (FIN_REASON_*)
//
// Hard caps (all typed): a datagram larger than FRAME_MAX_DATAGRAM never
// encodes and never decodes (FRAME_ERR_SIZE); a reassembled message larger
// than FRAME_MAX_MESSAGE is refused (FRAME_ERR_SIZE / FRAME_ERR_FRAG).
// Decode errors always carry the byte offset where the problem starts.
//
// Language notes (XIOM v0.64.5): free functions only; Ok/Err construction
// confined to leaf helpers; every Vec element read binds a typed local;
// widened byte reads mask with `& 0xFF`; decode is total (every read is
// bounds-checked before it happens).

module xiom.transport.frames

use xiom.transport.caps;

// ---------------------------------------------------------------------------
// Wire constants
// ---------------------------------------------------------------------------

/// Wire format version (header byte 0). A peer frame with any other value
/// is refused with FRAME_ERR_VERSION at offset 0.
pub const FRAME_VERSION: Int = 1;

pub const FRAME_HEADER_SIZE: Int = 19;
pub const FRAME_FRAG_META_SIZE: Int = 12;

/// Hard cap: largest datagram the codec will encode or decode (mirrors the
/// shared caps constant so frames stay portable across backends).
pub const FRAME_MAX_DATAGRAM: Int = 65507;

/// Hard cap: largest application chunk in one data frame:
/// 65507 - 19 - 12 = 65476.
pub const FRAME_MAX_PAYLOAD: Int = 65476;

/// Hard cap: largest reassembled message (256 KiB). Fragment metadata
/// declaring more is refused with FRAME_ERR_FRAG.
pub const FRAME_MAX_MESSAGE: Int = 262144;

/// Protocol version exchanged in hello frames is a u16 (0..65535).
pub const FRAME_MAX_PROTOCOL_VERSION: Int = 65535;

// Packet kinds (flags low nibble).
pub const FRAME_KIND_HELLO: Int = 0;
pub const FRAME_KIND_HELLO_ACK: Int = 1;
pub const FRAME_KIND_DATA: Int = 2;
pub const FRAME_KIND_ACK: Int = 3;
pub const FRAME_KIND_PING: Int = 4;
pub const FRAME_KIND_PONG: Int = 5;
pub const FRAME_KIND_FIN: Int = 6;

// Flag bits (flags high nibble).
pub const FRAME_FLAG_FRAGMENT: Int = 16;

// FIN reasons (carried as one byte in FIN frames).
pub const FIN_REASON_NONE: Int = 0;
pub const FIN_REASON_VERSION_MISMATCH: Int = 1;
pub const FIN_REASON_SHUTDOWN: Int = 2;
pub const FIN_REASON_TIMEOUT: Int = 3;

// Decode/encode error kinds (FrameError.kind).
pub const FRAME_ERR_HEADER: Int = 1;
pub const FRAME_ERR_VERSION: Int = 2;
pub const FRAME_ERR_KIND: Int = 3;
pub const FRAME_ERR_FLAGS: Int = 4;
pub const FRAME_ERR_SIZE: Int = 5;
pub const FRAME_ERR_TRUNCATED: Int = 6;
pub const FRAME_ERR_FRAG: Int = 7;
pub const FRAME_ERR_OFFSET: Int = 8;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A typed wire error carrying the byte offset where the problem starts
/// (encode-side validation failures report offset 0: there is no buffer
/// position to blame).
pub type FrameError = {
  kind: Int;
  offset: Int;
  message: Str;
}

/// One decoded (or to-be-encoded) frame. Field set is the union of every
/// kind's fields; `kind` says which are meaningful. `size` is set by
/// decode (bytes consumed from the decode offset) and by encode (total
/// encoded bytes).
pub type Frame = {
  version: Int;
  kind: Int;
  flags: Int;
  conn_id: Int;
  channel: Int;
  seq: Int;
  ack: Int;
  ack_bits: Int;
  protocol_version: Int;
  fin_reason: Int;
  fragment: Bool;
  frag_index: Int;
  frag_count: Int;
  frag_offset: Int;
  frag_total: Int;
  payload: Vec[UInt8];
  size: Int;
}

// ---------------------------------------------------------------------------
// Leaf helpers
// ---------------------------------------------------------------------------

fn _ferr(kind: Int, offset: Int, message: Str) -> FrameError {
  return FrameError { kind: kind, offset: offset, message: message };
}

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], FrameError] {
  return Ok(v);
}

fn _err_bytes(e: FrameError) -> Result[Vec[UInt8], FrameError] {
  return Err(e);
}

fn _ok_frame(f: Frame) -> Result[Frame, FrameError] {
  return Ok(f);
}

fn _err_frame(e: FrameError) -> Result[Frame, FrameError] {
  return Err(e);
}

fn _fin_reason_valid(r: Int) -> Bool {
  if r < 0 { return false; }
  if r > FIN_REASON_TIMEOUT { return false; }
  return true;
}

/// Human-readable kind name (diagnostics/tests).
pub fn frame_kind_name(kind: Int) -> Str {
  if kind == FRAME_KIND_HELLO { return "hello"; }
  if kind == FRAME_KIND_HELLO_ACK { return "hello_ack"; }
  if kind == FRAME_KIND_DATA { return "data"; }
  if kind == FRAME_KIND_ACK { return "ack"; }
  if kind == FRAME_KIND_PING { return "ping"; }
  if kind == FRAME_KIND_PONG { return "pong"; }
  if kind == FRAME_KIND_FIN { return "fin"; }
  return "unknown";
}

// ---------------------------------------------------------------------------
// Little-endian primitives (public: the wire tables in SPEC.md are exact)
// ---------------------------------------------------------------------------

/// Append v as u16 little-endian. v must be in [0, 65535] (validated by
/// the encoders; the primitive masks to the low 16 bits).
pub fn put_u16_le(out: &mut Vec[UInt8], v: Int) {
  let x = v & 65535;
  out.push((x & 255) as UInt8);
  out.push(((x >> 8) & 255) as UInt8);
}

/// Append v as u32 little-endian. v must be in [0, 4294967295].
pub fn put_u32_le(out: &mut Vec[UInt8], v: Int) {
  let x = v & 4294967295;
  out.push((x & 255) as UInt8);
  out.push(((x >> 8) & 255) as UInt8);
  out.push(((x >> 16) & 255) as UInt8);
  out.push(((x >> 24) & 255) as UInt8);
}

/// Read a u16 little-endian at off; total: returns 0 when the buffer is
/// too short (callers validate sizes before relying on the value).
pub fn read_u16_le(buf: &Vec[UInt8], off: Int) -> Int {
  if off < 0 { return 0; }
  if off + 2 > buf.len() { return 0; }
  let b0: UInt8 = buf[off];
  let b1: UInt8 = buf[off + 1];
  let x0 = (b0 as Int) & 255;
  let x1 = (b1 as Int) & 255;
  return x0 | (x1 << 8);
}

/// Read a u32 little-endian at off; total (0 when out of range).
pub fn read_u32_le(buf: &Vec[UInt8], off: Int) -> Int {
  if off < 0 { return 0; }
  if off + 4 > buf.len() { return 0; }
  let b0: UInt8 = buf[off];
  let b1: UInt8 = buf[off + 1];
  let b2: UInt8 = buf[off + 2];
  let b3: UInt8 = buf[off + 3];
  let x0 = (b0 as Int) & 255;
  let x1 = (b1 as Int) & 255;
  let x2 = (b2 as Int) & 255;
  let x3 = (b3 as Int) & 255;
  return x0 | (x1 << 8) | (x2 << 16) | (x3 << 24);
}

fn _push_bytes(out: &mut Vec[UInt8], data: &Vec[UInt8]) {
  var i = 0;
  while i < data.len() {
    let b: UInt8 = data[i];
    out.push(b);
    i = i + 1;
  }
}

// ---------------------------------------------------------------------------
// Frame construction
// ---------------------------------------------------------------------------

/// A frame with every field at its documented default: version
/// FRAME_VERSION, kind as given, no fragment, ack -1 ("no ack yet"),
/// empty payload.
pub fn frame_new(kind: Int) -> Frame {
  var empty: Vec[UInt8] = Vec[UInt8].new();
  return Frame {
    version: FRAME_VERSION;
    kind: kind;
    flags: 0;
    conn_id: 0;
    channel: 0;
    seq: 0;
    ack: -1;
    ack_bits: 0;
    protocol_version: 0;
    fin_reason: FIN_REASON_NONE;
    fragment: false;
    frag_index: 0;
    frag_count: 0;
    frag_offset: 0;
    frag_total: 0;
    payload: empty;
    size: 0;
  };
}

pub fn frame_hello(conn_id: Int, protocol_version: Int) -> Frame {
  var f = frame_new(FRAME_KIND_HELLO);
  f.conn_id = conn_id;
  f.protocol_version = protocol_version;
  return f;
}

pub fn frame_hello_ack(conn_id: Int, protocol_version: Int) -> Frame {
  var f = frame_new(FRAME_KIND_HELLO_ACK);
  f.conn_id = conn_id;
  f.protocol_version = protocol_version;
  return f;
}

pub fn frame_data(conn_id: Int, channel: Int, seq: Int, ack: Int, ack_bits: Int, payload: Vec[UInt8]) -> Frame {
  var f = frame_new(FRAME_KIND_DATA);
  f.conn_id = conn_id;
  f.channel = channel;
  f.seq = seq;
  f.ack = ack;
  f.ack_bits = ack_bits;
  f.payload = payload;
  return f;
}

/// One fragment of a larger message: index/count identify the position,
/// offset/total describe the message byte layout (explicit offsets keep
/// reassembly correct even when the two ends use different datagram
/// sizes).
pub fn frame_data_fragment(conn_id: Int, channel: Int, seq: Int, ack: Int, ack_bits: Int, index: Int, count: Int, offset: Int, total: Int, chunk: Vec[UInt8]) -> Frame {
  var f = frame_new(FRAME_KIND_DATA);
  f.conn_id = conn_id;
  f.channel = channel;
  f.seq = seq;
  f.ack = ack;
  f.ack_bits = ack_bits;
  f.fragment = true;
  f.flags = f.flags | FRAME_FLAG_FRAGMENT;
  f.frag_index = index;
  f.frag_count = count;
  f.frag_offset = offset;
  f.frag_total = total;
  f.payload = chunk;
  return f;
}

pub fn frame_ack(conn_id: Int, channel: Int, ack: Int, ack_bits: Int) -> Frame {
  var f = frame_new(FRAME_KIND_ACK);
  f.conn_id = conn_id;
  f.channel = channel;
  f.ack = ack;
  f.ack_bits = ack_bits;
  return f;
}

pub fn frame_ping(conn_id: Int) -> Frame {
  var f = frame_new(FRAME_KIND_PING);
  f.conn_id = conn_id;
  return f;
}

pub fn frame_pong(conn_id: Int) -> Frame {
  var f = frame_new(FRAME_KIND_PONG);
  f.conn_id = conn_id;
  return f;
}

pub fn frame_fin(conn_id: Int, reason: Int) -> Frame {
  var f = frame_new(FRAME_KIND_FIN);
  f.conn_id = conn_id;
  f.fin_reason = reason;
  return f;
}

// ---------------------------------------------------------------------------
// Encode
// ---------------------------------------------------------------------------

// The u32 wire form of an ack field: -1 (the "no ack yet" sentinel)
// encodes as 0xFFFFFFFF.
fn _ack_u32(v: Int) -> Int {
  if v < 0 { return 4294967295; }
  if v > 4294967295 { return 4294967295; }
  return v;
}

fn _field_u32_ok(v: Int) -> Bool {
  if v < 0 { return false; }
  if v > 4294967295 { return false; }
  return true;
}

fn _field_u8_ok(v: Int) -> Bool {
  if v < 0 { return false; }
  if v > 255 { return false; }
  return true;
}

/// Encode one frame to its exact wire bytes. Validation failures are typed
/// with offset 0 and a message naming the offending field.
pub fn frame_encode(f: &Frame) -> Result[Vec[UInt8], FrameError] {
  if f.version != FRAME_VERSION {
    return _err_bytes(_ferr(FRAME_ERR_VERSION, 0, "frame_encode: unsupported wire version " + f.version.to_str()));
  }
  if f.kind < FRAME_KIND_HELLO || f.kind > FRAME_KIND_FIN {
    return _err_bytes(_ferr(FRAME_ERR_KIND, 0, "frame_encode: unknown kind " + f.kind.to_str()));
  }
  if !_field_u32_ok(f.conn_id) {
    return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: conn_id out of u32 range"));
  }
  if !_field_u8_ok(f.channel) {
    return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: channel out of u8 range"));
  }
  if !_field_u32_ok(f.seq) {
    return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: seq out of u32 range"));
  }
  if f.ack < -1 || f.ack > 4294967295 {
    return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: ack out of range"));
  }
  if !_field_u32_ok(f.ack_bits) {
    return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: ack_bits out of u32 range"));
  }
  var frag = false;
  if f.kind == FRAME_KIND_DATA {
    if f.fragment {
      frag = true;
    }
  } else {
    if f.fragment {
      return _err_bytes(_ferr(FRAME_ERR_FLAGS, 0, "frame_encode: fragment flag on non-data kind"));
    }
  }
  var payload_len = f.payload.len();
  if f.kind == FRAME_KIND_DATA {
    if frag {
      if f.frag_count < 1 || f.frag_count > 65535 {
        return _err_bytes(_ferr(FRAME_ERR_FRAG, 0, "frame_encode: frag_count out of range"));
      }
      if f.frag_index < 0 || f.frag_index >= f.frag_count {
        return _err_bytes(_ferr(FRAME_ERR_FRAG, 0, "frame_encode: frag_index out of range"));
      }
      if f.frag_offset < 0 || f.frag_total < 0 {
        return _err_bytes(_ferr(FRAME_ERR_FRAG, 0, "frame_encode: negative fragment offsets"));
      }
      if f.frag_total > FRAME_MAX_MESSAGE {
        return _err_bytes(_ferr(FRAME_ERR_FRAG, 0, "frame_encode: frag_total above FRAME_MAX_MESSAGE"));
      }
      if f.frag_offset + payload_len > f.frag_total {
        return _err_bytes(_ferr(FRAME_ERR_FRAG, 0, "frame_encode: fragment overruns declared total"));
      }
      if payload_len > FRAME_MAX_PAYLOAD {
        return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: fragment chunk above FRAME_MAX_PAYLOAD"));
      }
    } else {
      if payload_len > FRAME_MAX_PAYLOAD {
        return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: payload above FRAME_MAX_PAYLOAD"));
      }
    }
  } else {
    if payload_len > 0 {
      return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: payload on a fixed-size kind"));
    }
  }
  if f.kind == FRAME_KIND_HELLO || f.kind == FRAME_KIND_HELLO_ACK {
    if f.protocol_version < 0 || f.protocol_version > FRAME_MAX_PROTOCOL_VERSION {
      return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: protocol_version out of u16 range"));
    }
  }
  if f.kind == FRAME_KIND_FIN {
    if !_fin_reason_valid(f.fin_reason) {
      return _err_bytes(_ferr(FRAME_ERR_SIZE, 0, "frame_encode: fin reason out of range"));
    }
  }

  var out: Vec[UInt8] = Vec[UInt8].new();
  out.push(f.version as UInt8);
  var flag_byte = f.kind;
  if frag { flag_byte = flag_byte | FRAME_FLAG_FRAGMENT; }
  out.push(flag_byte as UInt8);
  put_u32_le(&mut out, f.conn_id);
  out.push(f.channel as UInt8);
  put_u32_le(&mut out, f.seq);
  put_u32_le(&mut out, _ack_u32(f.ack));
  put_u32_le(&mut out, f.ack_bits);
  if f.kind == FRAME_KIND_HELLO || f.kind == FRAME_KIND_HELLO_ACK {
    put_u16_le(&mut out, f.protocol_version);
  }
  if f.kind == FRAME_KIND_FIN {
    out.push((f.fin_reason & 255) as UInt8);
  }
  if f.kind == FRAME_KIND_DATA {
    if frag {
      put_u16_le(&mut out, f.frag_index);
      put_u16_le(&mut out, f.frag_count);
      put_u32_le(&mut out, f.frag_offset);
      put_u32_le(&mut out, f.frag_total);
    }
    _push_bytes(&mut out, &f.payload);
  }
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
// Decode
// ---------------------------------------------------------------------------

fn _dkind(flags: Int) -> Int {
  return flags & 15;
}

fn _dflags_bad(flags: Int) -> Bool {
  let high = flags & 240;
  if high == 0 { return false; }
  if high == FRAME_FLAG_FRAGMENT { return false; }
  return true;
}

fn _frame_common(buf: &Vec[UInt8], off: Int) -> Frame {
  var empty: Vec[UInt8] = Vec[UInt8].new();
  let flags = (buf[off + 1] as Int) & 255;
  var ack = read_u32_le(buf, off + 11);
  if ack == 4294967295 { ack = -1; }
  return Frame {
    version: (buf[off] as Int) & 255;
    kind: _dkind(flags);
    flags: flags;
    conn_id: read_u32_le(buf, off + 2);
    channel: (buf[off + 6] as Int) & 255;
    seq: read_u32_le(buf, off + 7);
    ack: ack;
    ack_bits: read_u32_le(buf, off + 15);
    protocol_version: 0;
    fin_reason: FIN_REASON_NONE;
    fragment: false;
    frag_index: 0;
    frag_count: 0;
    frag_offset: 0;
    frag_total: 0;
    payload: empty;
    size: 0;
  };
}

/// Decode exactly one frame starting at off. `size` in the result is the
/// number of bytes the frame occupies (relative to off). Fixed-size kinds
/// refuse trailing bytes (FRAME_ERR_SIZE) so a datagram is always exactly
/// one frame.
pub fn frame_decode(buf: &Vec[UInt8], off: Int) -> Result[Frame, FrameError] {
  let remaining = buf.len() - off;
  if off < 0 || off > buf.len() {
    return _err_frame(_ferr(FRAME_ERR_OFFSET, 0, "frame_decode: offset out of range"));
  }
  if remaining < FRAME_HEADER_SIZE {
    return _err_frame(_ferr(FRAME_ERR_HEADER, off, "frame_decode: buffer shorter than the 19-byte header"));
  }
  let version = (buf[off] as Int) & 255;
  if version != FRAME_VERSION {
    return _err_frame(_ferr(FRAME_ERR_VERSION, off, "frame_decode: unsupported wire version " + version.to_str()));
  }
  let flags = (buf[off + 1] as Int) & 255;
  if _dflags_bad(flags) {
    return _err_frame(_ferr(FRAME_ERR_FLAGS, off + 1, "frame_decode: unknown flag bits"));
  }
  let kind = _dkind(flags);
  if kind > FRAME_KIND_FIN {
    return _err_frame(_ferr(FRAME_ERR_KIND, off + 1, "frame_decode: unknown kind " + kind.to_str()));
  }
  let frag = (flags & FRAME_FLAG_FRAGMENT) != 0;
  if frag && kind != FRAME_KIND_DATA {
    return _err_frame(_ferr(FRAME_ERR_FLAGS, off + 1, "frame_decode: fragment flag on non-data kind"));
  }
  if remaining > FRAME_MAX_DATAGRAM {
    return _err_frame(_ferr(FRAME_ERR_SIZE, off, "frame_decode: datagram above FRAME_MAX_DATAGRAM"));
  }

  if kind == FRAME_KIND_HELLO || kind == FRAME_KIND_HELLO_ACK {
    if remaining < FRAME_HEADER_SIZE + 2 {
      return _err_frame(_ferr(FRAME_ERR_TRUNCATED, off + FRAME_HEADER_SIZE, "frame_decode: buffer ends before protocol_version"));
    }
    if remaining > FRAME_HEADER_SIZE + 2 {
      return _err_frame(_ferr(FRAME_ERR_SIZE, off + FRAME_HEADER_SIZE + 2, "frame_decode: trailing bytes after hello"));
    }
    let pv = read_u16_le(buf, off + FRAME_HEADER_SIZE);
    var f = _frame_common(buf, off);
    f.protocol_version = pv;
    f.size = FRAME_HEADER_SIZE + 2;
    return _ok_frame(f);
  }

  if kind == FRAME_KIND_FIN {
    if remaining < FRAME_HEADER_SIZE + 1 {
      return _err_frame(_ferr(FRAME_ERR_TRUNCATED, off + FRAME_HEADER_SIZE, "frame_decode: buffer ends before fin reason"));
    }
    if remaining > FRAME_HEADER_SIZE + 1 {
      return _err_frame(_ferr(FRAME_ERR_SIZE, off + FRAME_HEADER_SIZE + 1, "frame_decode: trailing bytes after fin"));
    }
    let reason = (buf[off + FRAME_HEADER_SIZE] as Int) & 255;
    var f = _frame_common(buf, off);
    f.fin_reason = reason;
    f.size = FRAME_HEADER_SIZE + 1;
    return _ok_frame(f);
  }

  if kind == FRAME_KIND_ACK || kind == FRAME_KIND_PING || kind == FRAME_KIND_PONG {
    if remaining > FRAME_HEADER_SIZE {
      return _err_frame(_ferr(FRAME_ERR_SIZE, off + FRAME_HEADER_SIZE, "frame_decode: trailing bytes after fixed-size kind"));
    }
    var f = _frame_common(buf, off);
    f.size = FRAME_HEADER_SIZE;
    return _ok_frame(f);
  }

  // DATA
  if frag {
    if remaining < FRAME_HEADER_SIZE + FRAME_FRAG_META_SIZE {
      return _err_frame(_ferr(FRAME_ERR_TRUNCATED, off + FRAME_HEADER_SIZE, "frame_decode: buffer ends inside fragment metadata"));
    }
    let meta = off + FRAME_HEADER_SIZE;
    let index = read_u16_le(buf, meta);
    let count = read_u16_le(buf, meta + 2);
    let foff = read_u32_le(buf, meta + 4);
    let ftotal = read_u32_le(buf, meta + 8);
    if count < 1 || index >= count {
      return _err_frame(_ferr(FRAME_ERR_FRAG, meta, "frame_decode: fragment index/count inconsistent"));
    }
    if ftotal > FRAME_MAX_MESSAGE {
      return _err_frame(_ferr(FRAME_ERR_FRAG, meta + 8, "frame_decode: frag_total above FRAME_MAX_MESSAGE"));
    }
    let chunk_len = remaining - FRAME_HEADER_SIZE - FRAME_FRAG_META_SIZE;
    if foff + chunk_len > ftotal {
      return _err_frame(_ferr(FRAME_ERR_FRAG, meta + 4, "frame_decode: fragment overruns declared total"));
    }
    var payload: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < chunk_len {
      let b: UInt8 = buf[off + FRAME_HEADER_SIZE + FRAME_FRAG_META_SIZE + i];
      payload.push(b);
      i = i + 1;
    }
    var f = _frame_common(buf, off);
    f.fragment = true;
    f.frag_index = index;
    f.frag_count = count;
    f.frag_offset = foff;
    f.frag_total = ftotal;
    f.payload = payload;
    f.size = remaining;
    return _ok_frame(f);
  }

  let chunk_len = remaining - FRAME_HEADER_SIZE;
  if chunk_len > FRAME_MAX_PAYLOAD {
    return _err_frame(_ferr(FRAME_ERR_SIZE, off, "frame_decode: data payload above FRAME_MAX_PAYLOAD"));
  }
  var payload: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < chunk_len {
    let b: UInt8 = buf[off + FRAME_HEADER_SIZE + i];
    payload.push(b);
    i = i + 1;
  }
  var f = _frame_common(buf, off);
  f.payload = payload;
  f.size = remaining;
  return _ok_frame(f);
}
