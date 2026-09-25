// XIOM -- xiom.gguf: pure-XIOM GGUF container header codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A dependency-free reader and header builder for the GGUF container
// format (llama.cpp model files), version 2 and 3:
//
//   [4]  magic "GGUF"
//   [4]  u32 LE version (2 or 3)
//   [8]  u64 LE tensor count
//   [8]  u64 LE metadata KV count
//   N x  metadata KV: name (u64 len + bytes), value type u32, value
//   M x  tensor info: name, rank u32, dims u64[], ggml type u32, offset u64
//   [pad] zero padding to the alignment boundary
//   [..]  tensor data section (offsets are relative to its start)
//
// Documented subset: every integer KV value must fit in Int (values with
// the u64 sign bit set and negative i64 values are rejected with a clear
// error); i8/i16/i32 are sign-extended; f32/f64 values are preserved as
// their raw little-endian bytes written as lowercase hex text (no float
// arithmetic); strings and names must be printable ASCII (0x20..0x7E) with
// no NUL byte; arrays must be homogeneous and may not nest. Tensor payload
// extents are not validated (no ggml size table); only the declared offset
// is checked against the data section length. See SPEC.md for the full
// grammar, API contract, error catalog and limitations.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * Str values read out of a Vec[Str] are bound to a typed local and
//     compared with str_compare, never with `==` (BUG-17 lowering).
//   * every UInt8 is widened with `(b as Int) & 0xFF` before arithmetic.
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected (that reads as an empty vector); callers bind a local first.
//   * parallel Vec fields are only appended in gguf_parse and the
//     gguf_builder_add_* functions, where every push is mirrored.

module xiom.gguf

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Gguf, Str].
fn _ok_gguf(v: Gguf) -> Result[Gguf, Str] {
  return Ok(v);
}

// Err(m) for Result[Gguf, Str].
fn _err_gguf(m: Str) -> Result[Gguf, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed GGUF header.
///
/// Metadata entries and tensors are stored in declaration order in parallel
/// vectors (the pinned compiler miscompiles Vec[StructType], so there is no
/// per-entry struct vector). For KV entry i:
///   * `kv_keys[i]` / `kv_types[i]` are its name and value type code;
///   * `kv_ints[i]` holds integer/bool values (0/1 for bool);
///   * `kv_strs[i]` holds string values, or the lowercase hex form of a
///     f32/f64 value's raw little-endian bytes;
///   * `kv_arr_type[i]`, `kv_arr_count[i]` and `kv_arr_off[i]` describe an
///     array value: element type, element count and the start index into
///     `arr_ints` / `arr_strs` (0 for non-array entries).
/// For tensor i: `t_names[i]`, `t_ndims[i]`, `t_type[i]`, `t_offsets[i]`
/// and `t_dims_off[i]` (start index into `dims`, which has one sentinel
/// entry at the end). `data_offset` is the absolute offset of the data
/// section and `data_len` the number of bytes after it.
///
/// Fields are implementation details; use the gguf_* accessors. A value is
/// only produced by gguf_parse, so the invariants always hold.
pub type Gguf = {
  version: Int;
  tensor_count_decl: Int;
  kv_count_decl: Int;
  alignment: Int;
  data_offset: Int;
  data_len: Int;
  kv_keys: Vec[Str];
  kv_types: Vec[Int];
  kv_ints: Vec[Int];
  kv_strs: Vec[Str];
  kv_arr_type: Vec[Int];
  kv_arr_count: Vec[Int];
  kv_arr_off: Vec[Int];
  arr_ints: Vec[Int];
  arr_strs: Vec[Str];
  t_names: Vec[Str];
  t_ndims: Vec[Int];
  t_types: Vec[Int];
  t_offsets: Vec[Int];
  t_dims_off: Vec[Int];
  dims: Vec[Int];
}

/// Accumulating builder for a GGUF header.
///
/// Metadata and tensors are appended in call order; gguf_builder_finish
/// emits magic/version/counts/entries and zero padding up to the alignment
/// boundary, so the caller can append tensor payloads directly afterwards.
/// Tensor offsets are caller-supplied and relative to the data section.
/// Fields are implementation details; use the gguf_builder_* functions.
pub type GgufBuilder = {
  keys: Vec[Str];
  types: Vec[Int];
  ints: Vec[Int];
  strs: Vec[Str];
  arr_types: Vec[Int];
  arr_counts: Vec[Int];
  arr_offs: Vec[Int];
  arr_ints: Vec[Int];
  arr_strs: Vec[Str];
  t_names: Vec[Str];
  t_ndims: Vec[Int];
  t_types: Vec[Int];
  t_offsets: Vec[Int];
  t_dims_off: Vec[Int];
  dims: Vec[Int];
  alignment: Int;
}

// --------------------------------------------------
//  Byte readers
// --------------------------------------------------

// Byte `pos` of `buf` widened to 0..255. Callers bound-check first.
fn _byte_at(buf: &Vec[UInt8], pos: Int) -> Int {
  let raw: UInt8 = buf[pos];
  return (raw as Int) & 0xFF;
}

// Little-endian u32 at `pos`.
fn _rd_u32(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  if pos + 4 > total {
    return _err_int("gguf: truncated value");
  }
  let b0 = _byte_at(buf, pos);
  let b1 = _byte_at(buf, pos + 1);
  let b2 = _byte_at(buf, pos + 2);
  let b3 = _byte_at(buf, pos + 3);
  return _ok_int(b0 + b1 * 256 + b2 * 65536 + b3 * 16777216);
}

// Little-endian u64 at `pos`, rejected when it does not fit in Int.
fn _rd_u64(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  if pos + 8 > total {
    return _err_int("gguf: truncated value");
  }
  let b0 = _byte_at(buf, pos);
  let b1 = _byte_at(buf, pos + 1);
  let b2 = _byte_at(buf, pos + 2);
  let b3 = _byte_at(buf, pos + 3);
  let b4 = _byte_at(buf, pos + 4);
  let b5 = _byte_at(buf, pos + 5);
  let b6 = _byte_at(buf, pos + 6);
  let b7 = _byte_at(buf, pos + 7);
  let lo = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
  let hi = b4 + b5 * 256 + b6 * 65536 + b7 * 16777216;
  if hi >= 2147483648 {
    return _err_int("gguf: integer out of Int range");
  }
  return _ok_int(lo + hi * 4294967296);
}

// Signed 8-bit value at `pos`.
fn _rd_i8(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  if pos + 1 > total {
    return _err_int("gguf: truncated value");
  }
  let v = _byte_at(buf, pos);
  if v >= 128 {
    return _ok_int(v - 256);
  }
  return _ok_int(v);
}

// Signed 16-bit little-endian value at `pos`.
fn _rd_i16(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  if pos + 2 > total {
    return _err_int("gguf: truncated value");
  }
  let lo = _byte_at(buf, pos);
  let hi = _byte_at(buf, pos + 1);
  let v = lo + hi * 256;
  if v >= 32768 {
    return _ok_int(v - 65536);
  }
  return _ok_int(v);
}

// Signed 32-bit little-endian value at `pos`.
fn _rd_i32(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Int, Str] {
  let ur = _rd_u32(buf, total, pos);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v = ur.value;
  if v >= 2147483648 {
    return _ok_int(v - 4294967296);
  }
  return _ok_int(v);
}

// Length-prefixed (u64) printable-ASCII string at `pos`.
fn _rd_str(buf: &Vec[UInt8], total: Int, pos: Int) -> Result[Str, Str] {
  let lr = _rd_u64(buf, total, pos);
  if !lr.is_ok {
    return _err_str(lr.error);
  }
  let n = lr.value;
  if pos + 8 + n > total {
    return _err_str("gguf: string length exceeds buffer");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < n {
    let c = _byte_at(buf, pos + 8 + k);
    if c == 0 {
      return _err_str("gguf: string contains NUL byte");
    }
    if c < 32 {
      return _err_str("gguf: string is not printable ASCII");
    }
    if c > 126 {
      return _err_str("gguf: string is not printable ASCII");
    }
    out.push((c as UInt8));
    k = k + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

// Lowercase hex text for `n` bytes at `pos` (f32/f64 raw payloads).
fn _hex_quad(v: Int) -> Str {
  var digits = "0123456789abcdef";
  let hi = v / 16;
  let lo = v % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// Raw bytes at `pos` as lowercase hex text; bounds are pre-checked.
fn _rd_hex(buf: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var acc = "";
  var k = 0;
  while k < n {
    acc = acc + _hex_quad(_byte_at(buf, pos + k));
    k = k + 1;
  }
  return acc;
}

// Number of bytes `_rd_str` consumes for a validated string value.
fn _str_consumed(s: Str) -> Int {
  return 8 + string.str_len(s);
}

// True when every byte of `s` is hex text of even length.
fn _hex_ok(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 {
    return false;
  }
  if n % 2 != 0 {
    return false;
  }
  var k = 0;
  while k < n {
    let c = string.byte_at(s, k);
    let v = (c as Int) & 0xFF;
    let is_digit = v >= 48 && v <= 57;
    let is_lower = v >= 97 && v <= 102;
    if !is_digit && !is_lower {
      return false;
    }
    k = k + 1;
  }
  return true;
}

// Hex value of one lowercase/uppercase hex digit (0..15, -1 when invalid).
fn _hex_digit(c: Int) -> Int {
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  if c >= 97 && c <= 102 {
    return c - 87;
  }
  if c >= 65 && c <= 70 {
    return c - 55;
  }
  return -1;
}

// Append the bytes encoded by hex text `s`; Err when it is not hex.
fn _hex_push(out: &mut Vec[UInt8], s: Str) -> Result[Int, Str] {
  if !_hex_ok(s) {
    return _err_int("gguf: invalid hex payload");
  }
  let n = string.str_len(s);
  var k = 0;
  while k < n {
    let hi = _hex_digit(string.byte_at(s, k));
    let lo = _hex_digit(string.byte_at(s, k + 1));
    out.push(((hi * 16 + lo) as UInt8));
    k = k + 2;
  }
  return _ok_int(n / 2);
}

// --------------------------------------------------
//  Small predicates
// --------------------------------------------------

// True when `v` is a positive power of two.
fn _is_pow2(v: Int) -> Bool {
  if v < 1 {
    return false;
  }
  var q = v;
  while q > 1 {
    if q % 2 != 0 {
      return false;
    }
    q = q / 2;
  }
  return true;
}

// Type codes 0..12 as documented in the module header.
fn _type_known(t: Int) -> Bool {
  if t < 0 {
    return false;
  }
  return t <= 12;
}

// Integer-like value types (used for general.alignment lookup).
fn _type_is_integer(t: Int) -> Bool {
  if t == 0 || t == 1 || t == 2 || t == 3 || t == 4 || t == 5 {
    return true;
  }
  if t == 7 || t == 10 || t == 11 {
    return true;
  }
  return false;
}

// Float value types (raw-byte hex payloads).
fn _type_is_float(t: Int) -> Bool {
  return t == 6 || t == 12;
}

// True when `s` equals `want` (BUG-17 safe).
fn _str_is(s: Str, want: Str) -> Bool {
  return compare.str_compare(s, want) == 0;
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// Read one metadata value of `t` at `pos` and append its storage slots.
// `pos` is advanced through the returned `value`.
fn _parse_kv_value(g: &mut Gguf, buf: &Vec[UInt8], total: Int, pos_in: Int, key: Str, t: Int) -> Result[Int, Str] {
  var pos = pos_in;
  var iv = 0;
  var sv = "";
  var at = 0;
  var ac = 0;
  var aoff = g.arr_ints.len();
  if t == 0 {
    let r = _rd_i8(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    iv = r.value;
    pos = pos + 1;
  } else if t == 1 {
    let r = _rd_i8(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    iv = r.value;
    pos = pos + 1;
  } else if t == 2 {
    if pos + 2 > total { return _err_int("gguf: truncated value"); }
    let lo = _byte_at(buf, pos);
    let hi = _byte_at(buf, pos + 1);
    iv = lo + hi * 256;
    pos = pos + 2;
  } else if t == 3 {
    let r = _rd_i16(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    iv = r.value;
    pos = pos + 2;
  } else if t == 4 {
    let r = _rd_u32(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    iv = r.value;
    pos = pos + 4;
  } else if t == 5 {
    let r = _rd_i32(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    iv = r.value;
    pos = pos + 4;
  } else if t == 6 {
    if pos + 4 > total { return _err_int("gguf: truncated value"); }
    sv = _rd_hex(buf, pos, 4);
    pos = pos + 4;
  } else if t == 7 {
    if pos + 1 > total { return _err_int("gguf: truncated value"); }
    let v = _byte_at(buf, pos);
    if v != 0 && v != 1 { return _err_int("gguf: boolean value out of range"); }
    iv = v;
    pos = pos + 1;
  } else if t == 8 {
    let r = _rd_str(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    sv = r.value;
    pos = pos + _str_consumed(sv);
  } else if t == 9 {
    let er = _rd_u32(buf, total, pos);
    if !er.is_ok { return _err_int(er.error); }
    let et = er.value;
    if !_type_known(et) { return _err_int("gguf: unknown value type"); }
    if et == 9 { return _err_int("gguf: nested arrays are not supported"); }
    let cr = _rd_u64(buf, total, pos + 4);
    if !cr.is_ok { return _err_int(cr.error); }
    let cnt = cr.value;
    if cnt > 1048576 { return _err_int("gguf: bad array element count"); }
    at = et;
    ac = cnt;
    pos = pos + 12;
    var e = 0;
    while e < cnt {
      if et == 0 || et == 1 {
        let r = _rd_i8(buf, total, pos);
        if !r.is_ok { return _err_int(r.error); }
        g.arr_ints.push(r.value);
        pos = pos + 1;
      } else if et == 2 {
        if pos + 2 > total { return _err_int("gguf: truncated value"); }
        let lo = _byte_at(buf, pos);
        let hi = _byte_at(buf, pos + 1);
        g.arr_ints.push(lo + hi * 256);
        pos = pos + 2;
      } else if et == 3 {
        let r = _rd_i16(buf, total, pos);
        if !r.is_ok { return _err_int(r.error); }
        g.arr_ints.push(r.value);
        pos = pos + 2;
      } else if et == 4 {
        let r = _rd_u32(buf, total, pos);
        if !r.is_ok { return _err_int(r.error); }
        g.arr_ints.push(r.value);
        pos = pos + 4;
      } else if et == 5 {
        let r = _rd_i32(buf, total, pos);
        if !r.is_ok { return _err_int(r.error); }
        g.arr_ints.push(r.value);
        pos = pos + 4;
      } else if et == 6 {
        if pos + 4 > total { return _err_int("gguf: truncated value"); }
        g.arr_strs.push(_rd_hex(buf, pos, 4));
        pos = pos + 4;
      } else if et == 7 {
        if pos + 1 > total { return _err_int("gguf: truncated value"); }
        let v = _byte_at(buf, pos);
        if v != 0 && v != 1 { return _err_int("gguf: boolean value out of range"); }
        g.arr_ints.push(v);
        pos = pos + 1;
      } else if et == 8 {
        let r = _rd_str(buf, total, pos);
        if !r.is_ok { return _err_int(r.error); }
        g.arr_strs.push(r.value);
        pos = pos + _str_consumed(r.value);
      } else if et == 10 {
        let r = _rd_u64(buf, total, pos);
        if !r.is_ok { return _err_int(r.error); }
        g.arr_ints.push(r.value);
        pos = pos + 8;
      } else if et == 11 {
        let r = _rd_u64(buf, total, pos);
        if !r.is_ok { return _err_int(r.error); }
        g.arr_ints.push(r.value);
        pos = pos + 8;
      } else {
        // et == 12
        if pos + 8 > total { return _err_int("gguf: truncated value"); }
        g.arr_strs.push(_rd_hex(buf, pos, 8));
        pos = pos + 8;
      }
      e = e + 1;
    }
  } else if t == 10 {
    let r = _rd_u64(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    iv = r.value;
    pos = pos + 8;
  } else if t == 11 {
    let r = _rd_u64(buf, total, pos);
    if !r.is_ok { return _err_int(r.error); }
    iv = r.value;
    pos = pos + 8;
  } else if t == 12 {
    if pos + 8 > total { return _err_int("gguf: truncated value"); }
    sv = _rd_hex(buf, pos, 8);
    pos = pos + 8;
  } else {
    return _err_int("gguf: unknown value type");
  }
  g.kv_keys.push(key);
  g.kv_types.push(t);
  g.kv_ints.push(iv);
  g.kv_strs.push(sv);
  g.kv_arr_type.push(at);
  g.kv_arr_count.push(ac);
  g.kv_arr_off.push(aoff);
  return _ok_int(pos);
}

/// Parse a whole GGUF buffer (header plus, optionally, the data section).
///
/// Returns Err(Str) with a deterministic message for a short buffer, bad
/// magic, unsupported version, out-of-range counts/values, truncated
/// entries, non-printable strings, unknown/nested array types, duplicate
/// tensor names, invalid alignment, a data offset past the buffer, and
/// tensor offsets past the data section (see SPEC.md).
pub fn gguf_parse(buffer: &Vec[UInt8]) -> Result[Gguf, Str] {
  let total = buffer.len();
  if total < 24 {
    return _err_gguf("gguf: buffer too small for header");
  }
  if _byte_at(buffer, 0) != 71 {
    return _err_gguf("gguf: bad magic");
  }
  if _byte_at(buffer, 1) != 71 {
    return _err_gguf("gguf: bad magic");
  }
  if _byte_at(buffer, 2) != 85 {
    return _err_gguf("gguf: bad magic");
  }
  if _byte_at(buffer, 3) != 70 {
    return _err_gguf("gguf: bad magic");
  }
  let vr = _rd_u32(buffer, total, 4);
  if !vr.is_ok {
    return _err_gguf(vr.error);
  }
  let version = vr.value;
  if version != 2 && version != 3 {
    return _err_gguf("gguf: unsupported version");
  }
  let tr = _rd_u64(buffer, total, 8);
  if !tr.is_ok {
    return _err_gguf(tr.error);
  }
  let tensor_decl = tr.value;
  let kr = _rd_u64(buffer, total, 16);
  if !kr.is_ok {
    return _err_gguf(kr.error);
  }
  let kv_decl = kr.value;
  if tensor_decl > 1048576 || kv_decl > 1048576 {
    return _err_gguf("gguf: count out of range");
  }
  var g = Gguf{
    version: version;
    tensor_count_decl: tensor_decl;
    kv_count_decl: kv_decl;
    alignment: 32;
    data_offset: 0;
    data_len: 0;
    kv_keys: Vec[Str].new();
    kv_types: Vec[Int].new();
    kv_ints: Vec[Int].new();
    kv_strs: Vec[Str].new();
    kv_arr_type: Vec[Int].new();
    kv_arr_count: Vec[Int].new();
    kv_arr_off: Vec[Int].new();
    arr_ints: Vec[Int].new();
    arr_strs: Vec[Str].new();
    t_names: Vec[Str].new();
    t_ndims: Vec[Int].new();
    t_types: Vec[Int].new();
    t_offsets: Vec[Int].new();
    t_dims_off: Vec[Int].new();
    dims: Vec[Int].new();
  };
  var pos = 24;
  var i = 0;
  while i < kv_decl {
    let keyr = _rd_str(buffer, total, pos);
    if !keyr.is_ok {
      return _err_gguf(keyr.error);
    }
    let key: Str = keyr.value;
    pos = pos + _str_consumed(key);
    let tyr = _rd_u32(buffer, total, pos);
    if !tyr.is_ok {
      return _err_gguf(tyr.error);
    }
    let t = tyr.value;
    if !_type_known(t) {
      return _err_gguf("gguf: unknown value type");
    }
    pos = pos + 4;
    let vres = _parse_kv_value(&mut g, buffer, total, pos, key, t);
    if !vres.is_ok {
      return _err_gguf(vres.error);
    }
    pos = vres.value;
    i = i + 1;
  }
  var ti = 0;
  while ti < tensor_decl {
    let nr = _rd_str(buffer, total, pos);
    if !nr.is_ok {
      return _err_gguf(nr.error);
    }
    let name: Str = nr.value;
    pos = pos + _str_consumed(name);
    let dnr = _rd_u32(buffer, total, pos);
    if !dnr.is_ok {
      return _err_gguf(dnr.error);
    }
    let ndims = dnr.value;
    if ndims > 64 {
      return _err_gguf("gguf: tensor rank exceeds limit");
    }
    pos = pos + 4;
    let dim_off = g.dims.len();
    var d = 0;
    while d < ndims {
      let dr = _rd_u64(buffer, total, pos);
      if !dr.is_ok {
        return _err_gguf(dr.error);
      }
      g.dims.push(dr.value);
      pos = pos + 8;
      d = d + 1;
    }
    let ttr = _rd_u32(buffer, total, pos);
    if !ttr.is_ok {
      return _err_gguf(ttr.error);
    }
    let ttype = ttr.value;
    if !_type_known(ttype) {
      return _err_gguf("gguf: bad tensor type");
    }
    if ttype == 8 || ttype == 9 {
      return _err_gguf("gguf: bad tensor type");
    }
    pos = pos + 4;
    let ofr = _rd_u64(buffer, total, pos);
    if !ofr.is_ok {
      return _err_gguf(ofr.error);
    }
    let toff = ofr.value;
    pos = pos + 8;
    var dup = 0;
    var p = 0;
    while p < g.t_names.len() {
      let prev: Str = g.t_names[p];
      if _str_is(prev, name) {
        dup = 1;
      }
      p = p + 1;
    }
    if dup == 1 {
      return _err_gguf("gguf: duplicate tensor name");
    }
    g.t_names.push(name);
    g.t_ndims.push(ndims);
    g.t_types.push(ttype);
    g.t_offsets.push(toff);
    g.t_dims_off.push(dim_off);
    ti = ti + 1;
  }
  // Alignment: `general.alignment` overrides the 32-byte default.
  var alignment = 32;
  var ki = 0;
  while ki < g.kv_keys.len() {
    let k: Str = g.kv_keys[ki];
    if _str_is(k, "general.alignment") {
      let kt: Int = g.kv_types[ki];
      if !_type_is_integer(kt) {
        return _err_gguf("gguf: alignment is not an integer");
      }
      alignment = g.kv_ints[ki];
    }
    ki = ki + 1;
  }
  if alignment < 1 || alignment > 1048576 || !_is_pow2(alignment) {
    return _err_gguf("gguf: alignment is not a power of two");
  }
  let rem = pos % alignment;
  if rem != 0 {
    pos = pos + (alignment - rem);
  }
  if pos > total {
    return _err_gguf("gguf: data section offset exceeds buffer");
  }
  let data_len = total - pos;
  var tcheck = 0;
  while tcheck < g.t_offsets.len() {
    let off: Int = g.t_offsets[tcheck];
    if off > data_len {
      return _err_gguf("gguf: tensor offset exceeds data section");
    }
    tcheck = tcheck + 1;
  }
  g.alignment = alignment;
  g.data_offset = pos;
  g.data_len = data_len;
  return _ok_gguf(g);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// GGUF version (2 or 3).
pub fn gguf_version(g: &Gguf) -> Int {
  return g.version;
}

/// Number of metadata KV entries.
pub fn gguf_kv_count(g: &Gguf) -> Int {
  return g.kv_keys.len();
}

/// Number of tensors.
pub fn gguf_tensor_count(g: &Gguf) -> Int {
  return g.t_names.len();
}

/// Effective alignment (the `general.alignment` value or the 32 default).
pub fn gguf_alignment(g: &Gguf) -> Int {
  return g.alignment;
}

/// Absolute offset of the tensor data section.
pub fn gguf_data_offset(g: &Gguf) -> Int {
  return g.data_offset;
}

/// Number of bytes after the data-section offset in the parsed buffer.
pub fn gguf_data_len(g: &Gguf) -> Int {
  return g.data_len;
}

// Shared bounds check for KV indices.
fn _kv_in_range(g: &Gguf, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  return i < g.kv_keys.len();
}

/// KV key at index `i`.
/// Err("gguf: key index out of range") when `i` is out of bounds.
pub fn gguf_kv_key(g: &Gguf, i: Int) -> Result[Str, Str] {
  if !_kv_in_range(g, i) {
    return _err_str("gguf: key index out of range");
  }
  let v: Vec[Str] = g.kv_keys;
  let s: Str = v[i];
  return _ok_str(s);
}

/// Value type code at index `i` (0..12, see SPEC.md).
/// Err("gguf: key index out of range") when `i` is out of bounds.
pub fn gguf_kv_type(g: &Gguf, i: Int) -> Result[Int, Str] {
  if !_kv_in_range(g, i) {
    return _err_int("gguf: key index out of range");
  }
  let v: Vec[Int] = g.kv_types;
  let t: Int = v[i];
  return _ok_int(t);
}

/// Integer/bool value at index `i`.
/// Err("gguf: key index out of range") when `i` is out of bounds; Err
/// ("gguf: value is not an integer") for other types.
pub fn gguf_kv_int(g: &Gguf, i: Int) -> Result[Int, Str] {
  if !_kv_in_range(g, i) {
    return _err_int("gguf: key index out of range");
  }
  let v: Vec[Int] = g.kv_types;
  let t: Int = v[i];
  if !_type_is_integer(t) {
    return _err_int("gguf: value is not an integer");
  }
  let iv: Vec[Int] = g.kv_ints;
  let n: Int = iv[i];
  return _ok_int(n);
}

/// String value (or float raw-byte hex text) at index `i`.
/// Err("gguf: key index out of range") when `i` is out of bounds; Err
/// ("gguf: value is not a string") for other types.
pub fn gguf_kv_str(g: &Gguf, i: Int) -> Result[Str, Str] {
  if !_kv_in_range(g, i) {
    return _err_str("gguf: key index out of range");
  }
  let v: Vec[Int] = g.kv_types;
  let t: Int = v[i];
  if t != 8 && t != 6 && t != 12 {
    return _err_str("gguf: value is not a string");
  }
  let sv: Vec[Str] = g.kv_strs;
  let s: Str = sv[i];
  return _ok_str(s);
}

/// Array element type at index `i` (Err for non-array values).
pub fn gguf_kv_arr_type(g: &Gguf, i: Int) -> Result[Int, Str] {
  if !_kv_in_range(g, i) {
    return _err_int("gguf: key index out of range");
  }
  let v: Vec[Int] = g.kv_types;
  let t: Int = v[i];
  if t != 9 {
    return _err_int("gguf: value is not an array");
  }
  let at: Vec[Int] = g.kv_arr_type;
  let e: Int = at[i];
  return _ok_int(e);
}

/// Array element count at index `i` (Err for non-array values).
pub fn gguf_kv_arr_count(g: &Gguf, i: Int) -> Result[Int, Str] {
  if !_kv_in_range(g, i) {
    return _err_int("gguf: key index out of range");
  }
  let v: Vec[Int] = g.kv_types;
  let t: Int = v[i];
  if t != 9 {
    return _err_int("gguf: value is not an array");
  }
  let ac: Vec[Int] = g.kv_arr_count;
  let n: Int = ac[i];
  return _ok_int(n);
}

/// Integer array element `e` of entry `i`.
pub fn gguf_kv_arr_int(g: &Gguf, i: Int, e: Int) -> Result[Int, Str] {
  if !_kv_in_range(g, i) {
    return _err_int("gguf: key index out of range");
  }
  let at: Vec[Int] = g.kv_arr_type;
  let ac: Vec[Int] = g.kv_arr_count;
  let ao: Vec[Int] = g.kv_arr_off;
  let et: Int = at[i];
  let cnt: Int = ac[i];
  if !_type_is_integer(et) {
    return _err_int("gguf: array is not an integer array");
  }
  if e < 0 || e >= cnt {
    return _err_int("gguf: array element out of range");
  }
  let off: Int = ao[i];
  let iv: Vec[Int] = g.arr_ints;
  let n: Int = iv[off + e];
  return _ok_int(n);
}

/// String/float array element `e` of entry `i`.
pub fn gguf_kv_arr_str(g: &Gguf, i: Int, e: Int) -> Result[Str, Str] {
  if !_kv_in_range(g, i) {
    return _err_str("gguf: key index out of range");
  }
  let at: Vec[Int] = g.kv_arr_type;
  let ac: Vec[Int] = g.kv_arr_count;
  let ao: Vec[Int] = g.kv_arr_off;
  let et: Int = at[i];
  let cnt: Int = ac[i];
  if et != 8 && et != 6 && et != 12 {
    return _err_str("gguf: array is not a string array");
  }
  if e < 0 || e >= cnt {
    return _err_str("gguf: array element out of range");
  }
  let off: Int = ao[i];
  let sv: Vec[Str] = g.arr_strs;
  let s: Str = sv[off + e];
  return _ok_str(s);
}

/// Index of the first KV entry named `key` (Err("gguf: key not found")).
pub fn gguf_find_kv(g: &Gguf, key: Str) -> Result[Int, Str] {
  var i = 0;
  while i < g.kv_keys.len() {
    let k: Str = g.kv_keys[i];
    if _str_is(k, key) {
      return _ok_int(i);
    }
    i = i + 1;
  }
  return _err_int("gguf: key not found");
}

// Shared bounds check for tensor indices.
fn _t_in_range(g: &Gguf, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  return i < g.t_names.len();
}

/// Tensor name at index `i`.
/// Err("gguf: tensor index out of range") when `i` is out of bounds.
pub fn gguf_tensor_name(g: &Gguf, i: Int) -> Result[Str, Str] {
  if !_t_in_range(g, i) {
    return _err_str("gguf: tensor index out of range");
  }
  let v: Vec[Str] = g.t_names;
  let s: Str = v[i];
  return _ok_str(s);
}

/// Tensor rank (0 for a scalar).
/// Err("gguf: tensor index out of range") when `i` is out of bounds.
pub fn gguf_tensor_ndims(g: &Gguf, i: Int) -> Result[Int, Str] {
  if !_t_in_range(g, i) {
    return _err_int("gguf: tensor index out of range");
  }
  let v: Vec[Int] = g.t_ndims;
  let n: Int = v[i];
  return _ok_int(n);
}

/// Tensor ggml type code.
/// Err("gguf: tensor index out of range") when `i` is out of bounds.
pub fn gguf_tensor_type(g: &Gguf, i: Int) -> Result[Int, Str] {
  if !_t_in_range(g, i) {
    return _err_int("gguf: tensor index out of range");
  }
  let v: Vec[Int] = g.t_types;
  let t: Int = v[i];
  return _ok_int(t);
}

/// Tensor offset relative to the data section.
/// Err("gguf: tensor index out of range") when `i` is out of bounds.
pub fn gguf_tensor_offset(g: &Gguf, i: Int) -> Result[Int, Str] {
  if !_t_in_range(g, i) {
    return _err_int("gguf: tensor index out of range");
  }
  let v: Vec[Int] = g.t_offsets;
  let o: Int = v[i];
  return _ok_int(o);
}

/// Tensor dimension `d`.
pub fn gguf_tensor_dim(g: &Gguf, i: Int, d: Int) -> Result[Int, Str] {
  if !_t_in_range(g, i) {
    return _err_int("gguf: tensor index out of range");
  }
  let nd: Vec[Int] = g.t_ndims;
  let n: Int = nd[i];
  if d < 0 || d >= n {
    return _err_int("gguf: dimension index out of range");
  }
  let offs: Vec[Int] = g.t_dims_off;
  let off: Int = offs[i];
  let dd: Vec[Int] = g.dims;
  let v: Int = dd[off + d];
  return _ok_int(v);
}

/// Index of the first tensor named `name` (Err("gguf: tensor not found")).
pub fn gguf_find_tensor(g: &Gguf, name: Str) -> Result[Int, Str] {
  var i = 0;
  while i < g.t_names.len() {
    let n: Str = g.t_names[i];
    if _str_is(n, name) {
      return _ok_int(i);
    }
    i = i + 1;
  }
  return _err_int("gguf: tensor not found");
}

/// Documented name of a ggml type code (unknown codes are "unknown").
pub fn gguf_type_name(t: Int) -> Str {
  if t == 0 { return "u8"; }
  if t == 1 { return "i8"; }
  if t == 2 { return "u16"; }
  if t == 3 { return "i16"; }
  if t == 4 { return "u32"; }
  if t == 5 { return "i32"; }
  if t == 6 { return "f32"; }
  if t == 7 { return "bool"; }
  if t == 8 { return "string"; }
  if t == 9 { return "array"; }
  if t == 10 { return "u64"; }
  if t == 11 { return "i64"; }
  if t == 12 { return "f64"; }
  return "unknown";
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

// Little-endian writer for `n` bytes of non-negative `v`.
fn _wr_uint(out: &mut Vec[UInt8], v: Int, n: Int) {
  var q = v;
  var k = 0;
  while k < n {
    var r = q % 256;
    if r < 0 {
      r = r + 256;
    }
    out.push((r as UInt8));
    q = (q - r) / 256;
    k = k + 1;
  }
}

// Length-prefixed (u64) string writer.
fn _wr_str(out: &mut Vec[UInt8], s: Str) {
  let n = string.str_len(s);
  _wr_uint(out, n, 8);
  var k = 0;
  while k < n {
    let c = string.byte_at(s, k);
    out.push(c);
    k = k + 1;
  }
}

// Mirror one KV entry across every parallel builder array.
fn _b_push_entry(b: &mut GgufBuilder, key: Str, t: Int, iv: Int, sv: Str, at: Int, ac: Int, aoff: Int) {
  b.keys.push(key);
  b.types.push(t);
  b.ints.push(iv);
  b.strs.push(sv);
  b.arr_types.push(at);
  b.arr_counts.push(ac);
  b.arr_offs.push(aoff);
}

/// New empty builder with the default alignment 32.
pub fn gguf_builder_new() -> GgufBuilder {
  return GgufBuilder{
    keys: Vec[Str].new();
    types: Vec[Int].new();
    ints: Vec[Int].new();
    strs: Vec[Str].new();
    arr_types: Vec[Int].new();
    arr_counts: Vec[Int].new();
    arr_offs: Vec[Int].new();
    arr_ints: Vec[Int].new();
    arr_strs: Vec[Str].new();
    t_names: Vec[Str].new();
    t_ndims: Vec[Int].new();
    t_types: Vec[Int].new();
    t_offsets: Vec[Int].new();
    t_dims_off: Vec[Int].new();
    dims: Vec[Int].new();
    alignment: 32;
  };
}

/// Set the alignment (positive power of two, <= 1048576).
pub fn gguf_builder_set_alignment(b: &mut GgufBuilder, a: Int) -> Result[Int, Str] {
  if a < 1 || a > 1048576 || !_is_pow2(a) {
    return _err_int("gguf: alignment is not a power of two");
  }
  b.alignment = a;
  return _ok_int(a);
}

/// Append an integer/bool KV entry (types 0..5, 7, 10, 11).
pub fn gguf_builder_add_kv_int(b: &mut GgufBuilder, key: Str, t: Int, v: Int) -> Result[Int, Str] {
  if !_type_is_integer(t) {
    return _err_int("gguf: bad integer type");
  }
  if !_str_is(key, "") {
    if !_is_printable_key(key) {
      return _err_int("gguf: key is not printable ASCII");
    }
  }
  if t == 7 {
    if v != 0 && v != 1 {
      return _err_int("gguf: boolean value out of range");
    }
  }
  _b_push_entry(b, key, t, v, "", 0, 0, 0);
  return _ok_int(0);
}

/// Append a string KV entry (type 8).
pub fn gguf_builder_add_kv_str(b: &mut GgufBuilder, key: Str, v: Str) -> Result[Int, Str] {
  if !_str_is(key, "") {
    if !_is_printable_key(key) {
      return _err_int("gguf: key is not printable ASCII");
    }
  }
  if !_str_is(v, "") {
    if !_is_printable_key(v) {
      return _err_int("gguf: string is not printable ASCII");
    }
  }
  _b_push_entry(b, key, 8, 0, v, 0, 0, 0);
  return _ok_int(0);
}

/// Append a f32/f64 KV entry (type 6 or 12) from raw-byte hex text.
pub fn gguf_builder_add_kv_float(b: &mut GgufBuilder, key: Str, t: Int, hex: Str) -> Result[Int, Str] {
  if !_type_is_float(t) {
    return _err_int("gguf: bad float type");
  }
  if t == 6 && string.str_len(hex) != 8 {
    return _err_int("gguf: invalid hex payload");
  }
  if t == 12 && string.str_len(hex) != 16 {
    return _err_int("gguf: invalid hex payload");
  }
  if !_hex_ok(hex) {
    return _err_int("gguf: invalid hex payload");
  }
  _b_push_entry(b, key, t, 0, hex, 0, 0, 0);
  return _ok_int(0);
}

/// Append an array KV entry (type 9) of integers/bools (element types
/// 0..5, 7, 10, 11) with elements from `vals`.
pub fn gguf_builder_add_kv_arr_int(b: &mut GgufBuilder, key: Str, et: Int, vals: &Vec[Int]) -> Result[Int, Str] {
  if !_type_is_integer(et) {
    return _err_int("gguf: array is not an integer array");
  }
  if !_str_is(key, "") {
    if !_is_printable_key(key) {
      return _err_int("gguf: key is not printable ASCII");
    }
  }
  if vals.len() > 1048576 {
    return _err_int("gguf: bad array element count");
  }
  let aoff = b.arr_ints.len();
  if et == 7 {
    var i = 0;
    while i < vals.len() {
      let v: Int = vals[i];
      if v != 0 && v != 1 {
        return _err_int("gguf: boolean value out of range");
      }
      i = i + 1;
    }
  }
  var j = 0;
  while j < vals.len() {
    let v2: Int = vals[j];
    b.arr_ints.push(v2);
    j = j + 1;
  }
  _b_push_entry(b, key, 9, 0, "", et, vals.len(), aoff);
  return _ok_int(0);
}

/// Append an array KV entry (type 9) of strings (element type 8).
pub fn gguf_builder_add_kv_arr_str(b: &mut GgufBuilder, key: Str, vals: &Vec[Str]) -> Result[Int, Str] {
  if !_str_is(key, "") {
    if !_is_printable_key(key) {
      return _err_int("gguf: key is not printable ASCII");
    }
  }
  if vals.len() > 1048576 {
    return _err_int("gguf: bad array element count");
  }
  var i = 0;
  while i < vals.len() {
    let v: Str = vals[i];
    if !_str_is(v, "") {
      if !_is_printable_key(v) {
        return _err_int("gguf: string is not printable ASCII");
      }
    }
    i = i + 1;
  }
  let aoff = b.arr_strs.len();
  var j = 0;
  while j < vals.len() {
    let v2: Str = vals[j];
    b.arr_strs.push(v2);
    j = j + 1;
  }
  _b_push_entry(b, key, 9, 0, "", 8, vals.len(), aoff);
  return _ok_int(0);
}

/// Append a tensor info entry (name, dims, ggml type, data-section offset).
pub fn gguf_builder_add_tensor(b: &mut GgufBuilder, name: Str, dims: &Vec[Int], t: Int, offset: Int) -> Result[Int, Str] {
  if !_is_printable_key(name) {
    return _err_int("gguf: name is not printable ASCII");
  }
  if !_type_known(t) || t == 8 || t == 9 {
    return _err_int("gguf: bad tensor type");
  }
  if dims.len() > 64 {
    return _err_int("gguf: tensor rank exceeds limit");
  }
  var i = 0;
  while i < dims.len() {
    let d: Int = dims[i];
    if d < 0 {
      return _err_int("gguf: negative dimension");
    }
    i = i + 1;
  }
  var k = 0;
  while k < b.t_names.len() {
    let prev: Str = b.t_names[k];
    if _str_is(prev, name) {
      return _err_int("gguf: duplicate tensor name");
    }
    k = k + 1;
  }
  let off = b.dims.len();
  var j = 0;
  while j < dims.len() {
    let d2: Int = dims[j];
    b.dims.push(d2);
    j = j + 1;
  }
  b.t_names.push(name);
  b.t_ndims.push(dims.len());
  b.t_types.push(t);
  b.t_offsets.push(offset);
  b.t_dims_off.push(off);
  return _ok_int(0);
}

// Write the value body of builder entry `i` (everything after the type).
fn _wr_kv_value(out: &mut Vec[UInt8], b: &GgufBuilder, i: Int) -> Result[Int, Str] {
  let tv: Vec[Int] = b.types;
  let t: Int = tv[i];
  if _type_is_integer(t) || t == 6 || t == 12 {
    if t == 0 || t == 1 {
      _wr_uint(out, b.ints[i], 1);
      return _ok_int(0);
    }
    if t == 2 || t == 3 {
      _wr_uint(out, b.ints[i], 2);
      return _ok_int(0);
    }
    if t == 4 || t == 5 || t == 6 {
      if t == 6 {
        let sv0: Vec[Str] = b.strs;
        let h: Str = sv0[i];
        return _hex_push(out, h);
      }
      _wr_uint(out, b.ints[i], 4);
      return _ok_int(0);
    }
    if t == 7 {
      _wr_uint(out, b.ints[i], 1);
      return _ok_int(0);
    }
    if t == 10 || t == 11 {
      _wr_uint(out, b.ints[i], 8);
      return _ok_int(0);
    }
    let svf: Vec[Str] = b.strs;
    let h2: Str = svf[i];
    return _hex_push(out, h2);
  }
  if t == 8 {
    let sv: Vec[Str] = b.strs;
    let s: Str = sv[i];
    _wr_str(out, s);
    return _ok_int(0);
  }
  // array (type 9)
  let atv: Vec[Int] = b.arr_types;
  let acv: Vec[Int] = b.arr_counts;
  let aov: Vec[Int] = b.arr_offs;
  let et: Int = atv[i];
  let cnt: Int = acv[i];
  let off: Int = aov[i];
  _wr_uint(out, et, 4);
  _wr_uint(out, cnt, 8);
  var e = 0;
  while e < cnt {
    if et == 0 || et == 1 || et == 7 {
      let ivv: Vec[Int] = b.arr_ints;
      _wr_uint(out, ivv[off + e], 1);
    } else if et == 2 || et == 3 {
      let ivv2: Vec[Int] = b.arr_ints;
      _wr_uint(out, ivv2[off + e], 2);
    } else if et == 4 || et == 5 {
      let ivv3: Vec[Int] = b.arr_ints;
      _wr_uint(out, ivv3[off + e], 4);
    } else if et == 10 || et == 11 {
      let ivv4: Vec[Int] = b.arr_ints;
      _wr_uint(out, ivv4[off + e], 8);
    } else if et == 8 {
      let svv: Vec[Str] = b.arr_strs;
      let s2: Str = svv[off + e];
      _wr_str(out, s2);
    } else if et == 6 {
      let svv2: Vec[Str] = b.arr_strs;
      let h3: Str = svv2[off + e];
      let r3 = _hex_push(out, h3);
      if !r3.is_ok {
        return _err_int(r3.error);
      }
    } else {
      let svv3: Vec[Str] = b.arr_strs;
      let h4: Str = svv3[off + e];
      let r4 = _hex_push(out, h4);
      if !r4.is_ok {
        return _err_int(r4.error);
      }
    }
    e = e + 1;
  }
  return _ok_int(0);
}

/// Emit the complete header (magic, version, counts, KV entries, tensor
/// infos and zero padding to the alignment boundary). The caller appends
/// tensor payloads; offsets were supplied to gguf_builder_add_tensor.
pub fn gguf_builder_finish(b: &GgufBuilder) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  out.push((71 as UInt8));
  out.push((71 as UInt8));
  out.push((85 as UInt8));
  out.push((70 as UInt8));
  _wr_uint(&mut out, 3, 4);
  _wr_uint(&mut out, b.t_names.len(), 8);
  // A non-default alignment is declared with an implicit general.alignment
  // KV unless the caller already added one, so built headers round-trip.
  var implicit = 0;
  if b.alignment != 32 {
    var found = 0;
    var q = 0;
    while q < b.keys.len() {
      let kq: Vec[Str] = b.keys;
      let kk: Str = kq[q];
      if _str_is(kk, "general.alignment") {
        found = 1;
      }
      q = q + 1;
    }
    if found == 0 {
      implicit = 1;
    }
  }
  _wr_uint(&mut out, b.keys.len() + implicit, 8);
  if implicit == 1 {
    _wr_str(&mut out, "general.alignment");
    _wr_uint(&mut out, 4, 4);
    _wr_uint(&mut out, b.alignment, 4);
  }
  var i = 0;
  while i < b.keys.len() {
    let kv: Vec[Str] = b.keys;
    let key: Str = kv[i];
    _wr_str(&mut out, key);
    let tv: Vec[Int] = b.types;
    let t: Int = tv[i];
    _wr_uint(&mut out, t, 4);
    let vr = _wr_kv_value(&mut out, b, i);
    if !vr.is_ok {
      return _err_bytes(vr.error);
    }
    i = i + 1;
  }
  var ti = 0;
  while ti < b.t_names.len() {
    let nv: Vec[Str] = b.t_names;
    let name: Str = nv[ti];
    _wr_str(&mut out, name);
    let ndv: Vec[Int] = b.t_ndims;
    let nd: Int = ndv[ti];
    _wr_uint(&mut out, nd, 4);
    let offv: Vec[Int] = b.t_dims_off;
    let off: Int = offv[ti];
    var d = 0;
    while d < nd {
      let dd: Vec[Int] = b.dims;
      _wr_uint(&mut out, dd[off + d], 8);
      d = d + 1;
    }
    let ttv: Vec[Int] = b.t_types;
    _wr_uint(&mut out, ttv[ti], 4);
    let tov: Vec[Int] = b.t_offsets;
    _wr_uint(&mut out, tov[ti], 8);
    ti = ti + 1;
  }
  let rem = out.len() % b.alignment;
  if rem != 0 {
    var pad = b.alignment - rem;
    while pad > 0 {
      out.push((0 as UInt8));
      pad = pad - 1;
    }
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Key validation used by the builder
// --------------------------------------------------

// True when `s` is non-empty and every byte is printable ASCII.
fn _is_printable_key(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 {
    return false;
  }
  var k = 0;
  while k < n {
    let c = string.byte_at(s, k);
    let v = (c as Int) & 0xFF;
    if v < 32 || v > 126 {
      return false;
    }
    k = k + 1;
  }
  return true;
}
