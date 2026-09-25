// XIOM -- xiom.safetensors: pure-XIOM safetensors container codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A dependency-free reader and builder for the safetensors container
// format:
//
//   [8 bytes] little-endian u64 N (header length in bytes)
//   [N bytes] JSON header (ASCII-only in this subset)
//   [rest]    tensor data section
//
// `data_offsets` in the header are relative to the start of the data
// section, i.e. absolute byte 8 + N in the container. The header is parsed
// as a constrained JSON subset: a top-level object maps a tensor name to an
// object with exactly the keys "dtype" (string), "shape" (array of
// non-negative integers) and "data_offsets" (array of two non-negative
// integers). Strings support the escapes \\ \" \n \t and \uXXXX with an
// ASCII-only code point (0x20..0x7E). Nested objects, floats, negative
// integers, null/bool and non-ASCII bytes are rejected with deterministic
// Err(Str) messages (see SPEC.md for the full catalog).
//
// Supported dtype tokens (bytes per element): F64 8, F32 4, F16 2, BF16 2,
// I64 8, I32 4, I16 2, I8 1, U8 1, BOOL 1, F8_E4M3 1, F8_E5M2 1. Any other
// token is passed through opaquely: it parses and round-trips, but shape
// size validation is skipped for it (st_dtype_size returns 0). See SPEC.md
// for the grammar, API contract, error catalog and documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles).
//   * Str values read out of a Vec[Str] are bound to a typed local and
//     compared with str_compare, never with `==` (BUG-17 lowering).
//   * every UInt8 is widened with `(b as Int) & 0xFF` before entering Int
//     arithmetic or comparisons.
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected (that reads as an empty vector); callers bind a local first.
//   * parallel Vec fields are only appended by st_builder_add and st_parse,
//     where every push is mirrored across the sibling arrays.

module xiom.safetensors

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

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

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
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

// Ok(v) for Result[SafetensorsFile, Str].
fn _ok_file(v: SafetensorsFile) -> Result[SafetensorsFile, Str] {
  return Ok(v);
}

// Err(m) for Result[SafetensorsFile, Str].
fn _err_file(m: Str) -> Result[SafetensorsFile, Str] {
  return Err(m);
}

// Ok(v) for Result[TensorInfo, Str].
fn _ok_info(v: TensorInfo) -> Result[TensorInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[TensorInfo, Str].
fn _err_info(m: Str) -> Result[TensorInfo, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed safetensors header.
///
/// Tensors are stored in declaration order in parallel vectors (the pinned
/// compiler miscompiles Vec[StructType], so there is no per-tensor struct
/// vector): `names[i]`/`dtypes[i]` are the tensor's name and dtype token,
/// `ranks[i]` is its rank, `dims[shape_offsets[i]..shape_offsets[i + 1]]`
/// are its dimensions (shape_offsets has one sentinel entry at the end),
/// and `offsets_start[i]`/`offsets_end[i]` are its data offsets relative to
/// the start of the data section. `header_len` is the raw N from the
/// container prefix, `data_start` is the absolute offset of the data
/// section (8 + N) and `data_len` is the number of payload bytes after it.
///
/// Fields are implementation details; use the st_* accessors below. A value
/// is only produced by st_parse, so the invariants (validated offsets,
/// matching shapes for documented dtypes, unique names) always hold.
pub type SafetensorsFile = {
  names: Vec[Str];
  dtypes: Vec[Str];
  ranks: Vec[Int];
  shape_offsets: Vec[Int];
  dims: Vec[Int];
  offsets_start: Vec[Int];
  offsets_end: Vec[Int];
  header_len: Int;
  data_start: Int;
  data_len: Int;
}

/// Accumulating builder for one safetensors container.
///
/// Tensors are appended in call order with st_builder_add; the data payload
/// is the concatenation of the added byte slices and each tensor's
/// data_offsets are relative to that payload, exactly as the format
/// requires. st_builder_finish emits the 8-byte prefix, the header JSON
/// padded with spaces to a multiple of 8 bytes, and the payload.
///
/// Fields are implementation details; use the st_builder_* functions.
pub type SafetensorsBuilder = {
  names: Vec[Str];
  dtypes: Vec[Str];
  ranks: Vec[Int];
  shape_offsets: Vec[Int];
  dims: Vec[Int];
  payload: Vec[UInt8];
  offsets_start: Vec[Int];
  offsets_end: Vec[Int];
}

// Internal cursor over the header JSON string.
type StParser = {
  src: Str;
  len: Int;
  pos: Int;
}

// Internal result of parsing one tensor-info object.
type TensorInfo = {
  dtype: Str;
  has_dtype: Bool;
  dims: Vec[Int];
  has_shape: Bool;
  off_start: Int;
  off_end: Int;
  has_offsets: Bool;
}

// --------------------------------------------------
//  Lexical helpers
// --------------------------------------------------

// "<prefix> at byte <pos>" error text (all parser errors carry a byte
// position; the position is deterministic for a given input).
fn _at(msg: Str, pos: Int) -> Str {
  return "safetensors: " + msg + " at byte " + convert.int_to_string(pos);
}

// Append the low 8 bytes of non-negative `v` in little-endian order.
fn _push_u64_le(out: &mut Vec[UInt8], v: Int) {
  var q = v;
  var k = 0;
  while k < 8 {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    out.push(r as UInt8);
    q = (q - r) / 256;
    k = k + 1;
  }
}

// True when `s` is non-empty and every byte is printable ASCII (0x20..0x7E).
fn _is_printable_ascii(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    let b0 = string.byte_at(s, i);
    let b = (b0 as Int) & 0xFF;
    if b < 32 {
      return false;
    }
    if b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Append the JSON string body for `s` (escapes `"`, `\`, LF and TAB; other
// bytes are copied verbatim -- callers validate printable ASCII first).
fn _push_json_string(sb: &mut Vec[UInt8], s: Str) {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b0 = string.byte_at(s, i);
    let b = (b0 as Int) & 0xFF;
    if b == 34 {
      builder.sb_push_str(sb, "\\\"");
    } elif b == 92 {
      builder.sb_push_str(sb, "\\\\");
    } elif b == 10 {
      builder.sb_push_str(sb, "\\n");
    } elif b == 9 {
      builder.sb_push_str(sb, "\\t");
    } else {
      sb.push(b as UInt8);
    }
    i = i + 1;
  }
}

// One-byte ASCII Str (b must be in 0x20..0x7E).
fn _byte_str(b: Int) -> Str {
  var v = Vec[UInt8].new();
  v.push(b as UInt8);
  return builder.sb_to_str(&v);
}

// --------------------------------------------------
//  Parser primitives
// --------------------------------------------------

// Next raw byte at the cursor, or -1 at end of input (non-advancing).
fn _peek(p: &mut StParser) -> Int {
  if p.pos >= p.len {
    return -1;
  }
  let b0 = string.byte_at(p.src, p.pos);
  return (b0 as Int) & 0xFF;
}

// Skip space, TAB, LF and CR.
fn _skip_ws(p: &mut StParser) {
  var more = true;
  while more {
    if p.pos >= p.len {
      return;
    }
    let b0 = string.byte_at(p.src, p.pos);
    let b = (b0 as Int) & 0xFF;
    if b == 32 || b == 9 || b == 10 || b == 13 {
      p.pos = p.pos + 1;
    } else {
      more = false;
    }
  }
}

// Hex digit value of a byte, or -1.
fn _hex_val(c: Int) -> Int {
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

// Parse a non-negative integer (no sign, no leading zeros, <= INT64_MAX).
fn _p_int(p: &mut StParser) -> Result[Int, Str] {
  let start = p.pos;
  if p.pos >= p.len {
    return _err_int(_at("expected non-negative integer", p.pos));
  }
  let b0 = string.byte_at(p.src, p.pos);
  let first = (b0 as Int) & 0xFF;
  if first == 45 {
    return _err_int(_at("negative integers are not supported", p.pos));
  }
  if first < 48 || first > 57 {
    return _err_int(_at("expected non-negative integer", p.pos));
  }
  if first == 48 {
    p.pos = p.pos + 1;
    if p.pos < p.len {
      let nb0 = string.byte_at(p.src, p.pos);
      let nb = (nb0 as Int) & 0xFF;
      if nb >= 48 && nb <= 57 {
        return _err_int(_at("leading zero in integer", start));
      }
    }
    return _ok_int(0);
  }
  var v: Int = 0;
  var more = true;
  while more {
    if p.pos >= p.len {
      more = false;
    } else {
      let d0 = string.byte_at(p.src, p.pos);
      let d = (d0 as Int) & 0xFF;
      if d < 48 || d > 57 {
        more = false;
      } else {
        if v > 922337203685477580 {
          return _err_int(_at("integer out of range", start));
        }
        v = v * 10;
        if v > 9223372036854775807 - (d - 48) {
          return _err_int(_at("integer out of range", start));
        }
        v = v + (d - 48);
        p.pos = p.pos + 1;
      }
    }
  }
  return _ok_int(v);
}

// Parse an array of non-negative integers: `[`, ints separated by `,`, `]`.
// An empty array is allowed (a scalar tensor shape).
fn _p_int_array(p: &mut StParser) -> Result[Vec[Int], Str] {
  p.pos = p.pos + 1;
  var out = Vec[Int].new();
  _skip_ws(p);
  if _peek(p) == 93 {
    p.pos = p.pos + 1;
    return _ok_ints(out);
  }
  var more = true;
  while more {
    _skip_ws(p);
    let ir = _p_int(p);
    if !ir.is_ok {
      return _err_ints(ir.error);
    }
    let iv: Int = ir.value;
    out.push(iv);
    _skip_ws(p);
    let b = _peek(p);
    if b == 44 {
      p.pos = p.pos + 1;
    } elif b == 93 {
      p.pos = p.pos + 1;
      more = false;
    } else {
      return _err_ints(_at("expected ',' or ']'", p.pos));
    }
  }
  return _ok_ints(out);
}

// Parse a JSON string; the cursor must be on the opening quote. Supported
// escapes: \\ \" \n \t and \uXXXX with an ASCII code point 0x20..0x7E.
// Raw bytes must be printable ASCII.
fn _p_string(p: &mut StParser) -> Result[Str, Str] {
  p.pos = p.pos + 1;
  return _p_string_loop(p, "");
}

// Recursive body of _p_string.
fn _p_string_loop(p: &mut StParser, acc: Str) -> Result[Str, Str] {
  if p.pos >= p.len {
    return _err_str("safetensors: unterminated string");
  }
  let b0 = string.byte_at(p.src, p.pos);
  let b = (b0 as Int) & 0xFF;
  if b == 34 {
    p.pos = p.pos + 1;
    return _ok_str(acc);
  }
  if b == 92 {
    return _p_string_escape(p, acc);
  }
  if b < 32 {
    return _err_str(_at("control character in string", p.pos));
  }
  if b > 126 {
    return _err_str(_at("non-ASCII byte in string", p.pos));
  }
  p.pos = p.pos + 1;
  return _p_string_loop(p, acc + _byte_str(b));
}

// Parse one escape sequence; the cursor is on the backslash.
fn _p_string_escape(p: &mut StParser, acc: Str) -> Result[Str, Str] {
  p.pos = p.pos + 1;
  if p.pos >= p.len {
    return _err_str("safetensors: unterminated string");
  }
  let e0 = string.byte_at(p.src, p.pos);
  let e = (e0 as Int) & 0xFF;
  if e == 92 {
    p.pos = p.pos + 1;
    return _p_string_loop(p, acc + "\\");
  }
  if e == 34 {
    p.pos = p.pos + 1;
    return _p_string_loop(p, acc + "\"");
  }
  if e == 110 {
    p.pos = p.pos + 1;
    return _p_string_loop(p, acc + "\n");
  }
  if e == 116 {
    p.pos = p.pos + 1;
    return _p_string_loop(p, acc + "\t");
  }
  if e == 117 {
    return _p_unicode(p, acc);
  }
  return _err_str(_at("unsupported escape", p.pos));
}

// Parse the four hex digits of a \u escape (cursor on `u`); only printable
// ASCII code points are accepted.
fn _p_unicode(p: &mut StParser, acc: Str) -> Result[Str, Str] {
  let us = p.pos;
  p.pos = p.pos + 1;
  if p.pos + 4 > p.len {
    return _err_str("safetensors: unterminated string");
  }
  var v: Int = 0;
  var k = 0;
  while k < 4 {
    let c0 = string.byte_at(p.src, p.pos + k);
    let c = (c0 as Int) & 0xFF;
    let d = _hex_val(c);
    if d < 0 {
      return _err_str(_at("invalid \\u escape", p.pos + k));
    }
    v = v * 16 + d;
    k = k + 1;
  }
  if v < 32 || v > 126 {
    return _err_str(_at("non-printable \\u escape", us));
  }
  p.pos = p.pos + 4;
  return _p_string_loop(p, acc + _byte_str(v));
}

// --------------------------------------------------
//  Header parser
// --------------------------------------------------

// Parse one tensor-info object; the cursor is on `{`. All three keys are
// mandatory; unknown keys (including "__metadata__", whose value is a
// nested object) and duplicate keys are rejected.
fn _p_tensor(p: &mut StParser) -> Result[TensorInfo, Str] {
  p.pos = p.pos + 1;
  var info = TensorInfo{
    dtype: "";
    has_dtype: false;
    dims: Vec[Int].new();
    has_shape: false;
    off_start: 0;
    off_end: 0;
    has_offsets: false;
  };
  _skip_ws(p);
  if _peek(p) == 125 {
    return _err_info("safetensors: tensor object is empty");
  }
  var more = true;
  while more {
    _skip_ws(p);
    if _peek(p) != 34 {
      return _err_info(_at("expected '\"' for tensor key", p.pos));
    }
    let key_r = _p_string(p);
    if !key_r.is_ok {
      return _err_info(key_r.error);
    }
    let key: Str = key_r.value;
    _skip_ws(p);
    if _peek(p) != 58 {
      return _err_info(_at("expected ':'", p.pos));
    }
    p.pos = p.pos + 1;
    _skip_ws(p);
    if compare.str_compare(key, "dtype") == 0 {
      if info.has_dtype {
        return _err_info("safetensors: duplicate key 'dtype'");
      }
      if _peek(p) != 34 {
        return _err_info(_at("dtype must be a string", p.pos));
      }
      let v_r = _p_string(p);
      if !v_r.is_ok {
        return _err_info(v_r.error);
      }
      let dv: Str = v_r.value;
      info.dtype = dv;
      info.has_dtype = true;
    } elif compare.str_compare(key, "shape") == 0 {
      if info.has_shape {
        return _err_info("safetensors: duplicate key 'shape'");
      }
      if _peek(p) != 91 {
        return _err_info(_at("shape must be an array", p.pos));
      }
      let a_r = _p_int_array(p);
      if !a_r.is_ok {
        return _err_info(a_r.error);
      }
      let dv: Vec[Int] = a_r.value;
      info.dims = dv;
      info.has_shape = true;
    } elif compare.str_compare(key, "data_offsets") == 0 {
      if info.has_offsets {
        return _err_info("safetensors: duplicate key 'data_offsets'");
      }
      if _peek(p) != 91 {
        return _err_info(_at("data_offsets must be an array", p.pos));
      }
      let a_r = _p_int_array(p);
      if !a_r.is_ok {
        return _err_info(a_r.error);
      }
      let vals: Vec[Int] = a_r.value;
      if vals.len() != 2 {
        return _err_info("safetensors: data_offsets must contain exactly two integers");
      }
      let s0: Int = vals[0];
      let s1: Int = vals[1];
      info.off_start = s0;
      info.off_end = s1;
      info.has_offsets = true;
    } else {
      return _err_info("safetensors: unknown tensor key '" + key + "'");
    }
    _skip_ws(p);
    let b = _peek(p);
    if b == 44 {
      p.pos = p.pos + 1;
    } elif b == 125 {
      p.pos = p.pos + 1;
      more = false;
    } else {
      return _err_info(_at("expected ',' or '}'", p.pos));
    }
  }
  if !info.has_dtype {
    return _err_info("safetensors: missing key 'dtype'");
  }
  if !info.has_shape {
    return _err_info("safetensors: missing key 'shape'");
  }
  if !info.has_offsets {
    return _err_info("safetensors: missing key 'data_offsets'");
  }
  return _ok_info(info);
}

// Parse the top-level header object and validate the assembled tensor
// table. `header_len` is the raw N from the container prefix, `data_start`
// is the absolute data-section offset (8 + N) and `data_len` the number of
// payload bytes.
fn _p_top(p: &mut StParser, header_len: Int, data_start: Int, data_len: Int) -> Result[SafetensorsFile, Str] {
  _skip_ws(p);
  if _peek(p) != 123 {
    return _err_file(_at("expected '{'", p.pos));
  }
  p.pos = p.pos + 1;
  var names = Vec[Str].new();
  var dtypes = Vec[Str].new();
  var ranks = Vec[Int].new();
  var shape_offsets = Vec[Int].new();
  shape_offsets.push(0);
  var dims = Vec[Int].new();
  var offsets_start = Vec[Int].new();
  var offsets_end = Vec[Int].new();
  _skip_ws(p);
  if _peek(p) == 125 {
    p.pos = p.pos + 1;
  } else {
    var more = true;
    while more {
      _skip_ws(p);
      if _peek(p) != 34 {
        return _err_file(_at("expected '\"' for tensor name", p.pos));
      }
      let name_r = _p_string(p);
      if !name_r.is_ok {
        return _err_file(name_r.error);
      }
      let name: Str = name_r.value;
      if string.str_len(name) == 0 {
        return _err_file("safetensors: tensor name must not be empty");
      }
      if compare.str_compare(name, "__metadata__") == 0 {
        return _err_file("safetensors: '__metadata__' metadata objects are not supported");
      }
      var di = 0;
      var dup = false;
      while di < names.len() {
        let existing: Str = names[di];
        if compare.str_compare(existing, name) == 0 {
          dup = true;
        }
        di = di + 1;
      }
      if dup {
        return _err_file("safetensors: duplicate tensor name '" + name + "'");
      }
      _skip_ws(p);
      if _peek(p) != 58 {
        return _err_file(_at("expected ':'", p.pos));
      }
      p.pos = p.pos + 1;
      _skip_ws(p);
      if _peek(p) != 123 {
        return _err_file(_at("tensor value must be an object", p.pos));
      }
      let info_r = _p_tensor(p);
      if !info_r.is_ok {
        return _err_file(info_r.error);
      }
      let info: TensorInfo = info_r.value;
      if string.str_len(info.dtype) == 0 {
        return _err_file("safetensors: dtype must not be empty for tensor '" + name + "'");
      }
      names.push(name);
      dtypes.push(info.dtype);
      ranks.push(info.dims.len());
      var dk = 0;
      while dk < info.dims.len() {
        let dv: Int = info.dims[dk];
        dims.push(dv);
        dk = dk + 1;
      }
      shape_offsets.push(dims.len());
      offsets_start.push(info.off_start);
      offsets_end.push(info.off_end);
      _skip_ws(p);
      let b = _peek(p);
      if b == 44 {
        p.pos = p.pos + 1;
      } elif b == 125 {
        p.pos = p.pos + 1;
        more = false;
      } else {
        return _err_file(_at("expected ',' or '}'", p.pos));
      }
    }
  }
  _skip_ws(p);
  if p.pos != p.len {
    return _err_file(_at("trailing data", p.pos));
  }
  var f = SafetensorsFile{
    names: names;
    dtypes: dtypes;
    ranks: ranks;
    shape_offsets: shape_offsets;
    dims: dims;
    offsets_start: offsets_start;
    offsets_end: offsets_end;
    header_len: header_len;
    data_start: data_start;
    data_len: data_len;
  };
  let vr = _validate_file(&f);
  if !vr.is_ok {
    return _err_file(vr.error);
  }
  return _ok_file(f);
}

// --------------------------------------------------
//  Semantic validation
// --------------------------------------------------

// Element count of a shape: 1 for a scalar (empty shape), -1 on a negative
// dimension or signed overflow.
fn _shape_count(f: &SafetensorsFile, i: Int) -> Result[Int, Str] {
  let from: Int = f.shape_offsets[i];
  let to: Int = f.shape_offsets[i + 1];
  var v: Int = 1;
  var k = from;
  while k < to {
    let d: Int = f.dims[k];
    if d < 0 {
      return _err_int("safetensors: negative shape dimension");
    }
    if d == 0 {
      v = 0;
    } elif v > 9223372036854775807 / d {
      return _err_int("safetensors: shape product overflows");
    } else {
      v = v * d;
    }
    k = k + 1;
  }
  return _ok_int(v);
}

// Documented bytes per element for a dtype token, 0 when the token is
// passed through opaquely.
fn _dtype_size(dtype: Str) -> Int {
  if compare.str_compare(dtype, "F64") == 0 { return 8; }
  if compare.str_compare(dtype, "F32") == 0 { return 4; }
  if compare.str_compare(dtype, "F16") == 0 { return 2; }
  if compare.str_compare(dtype, "BF16") == 0 { return 2; }
  if compare.str_compare(dtype, "I64") == 0 { return 8; }
  if compare.str_compare(dtype, "I32") == 0 { return 4; }
  if compare.str_compare(dtype, "I16") == 0 { return 2; }
  if compare.str_compare(dtype, "I8") == 0 { return 1; }
  if compare.str_compare(dtype, "U8") == 0 { return 1; }
  if compare.str_compare(dtype, "BOOL") == 0 { return 1; }
  if compare.str_compare(dtype, "F8_E4M3") == 0 { return 1; }
  if compare.str_compare(dtype, "F8_E5M2") == 0 { return 1; }
  return 0;
}

// Validate the tensor table: offsets form a monotonic non-overlapping
// sequence inside the data section, and for documented dtypes the shape
// product times the element size equals the declared span. Unknown dtype
// tokens skip the size check (documented pass-through).
fn _validate_file(f: &SafetensorsFile) -> Result[Int, Str] {
  let n: Int = f.names.len();
  var i = 0;
  while i < n {
    let s: Int = f.offsets_start[i];
    let e: Int = f.offsets_end[i];
    let nm: Str = f.names[i];
    if s > e {
      return _err_int("safetensors: data_offsets start > end for tensor '" + nm + "'");
    }
    if e > f.data_len {
      return _err_int("safetensors: data_offsets exceed data section for tensor '" + nm + "'");
    }
    if i > 0 {
      let prev: Int = f.offsets_end[i - 1];
      if s < prev {
        return _err_int("safetensors: data_offsets not monotonic for tensor '" + nm + "'");
      }
    }
    let dt: Str = f.dtypes[i];
    let w = _dtype_size(dt);
    if w > 0 {
      let cr = _shape_count(f, i);
      if !cr.is_ok {
        return _err_int(cr.error);
      }
      let cnt: Int = cr.value;
      if cnt > 9223372036854775807 / w {
        return _err_int("safetensors: shape product overflows for tensor '" + nm + "'");
      }
      let expected = cnt * w;
      let span = e - s;
      if expected != span {
        return _err_int("safetensors: shape size does not match data length for tensor '" + nm + "'");
      }
    }
    i = i + 1;
  }
  return _ok_int(0);
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse a whole safetensors container: read the 8-byte little-endian
/// header length N, parse the N header bytes as the documented JSON subset,
/// and validate the tensor table. The buffer is not retained; pass it to
/// st_tensor_bytes afterwards to read payload spans.
///
/// Err(Str) with a deterministic message for a short buffer, an oversized
/// or empty header, a NUL byte in the header, malformed JSON, unsupported
/// value kinds, duplicate names/keys and invalid offsets (see SPEC.md).
pub fn st_parse(buffer: &Vec[UInt8]) -> Result[SafetensorsFile, Str] {
  let total: Int = buffer.len();
  if total < 8 {
    return _err_file("safetensors: buffer too small for header length");
  }
  let b0 = ((buffer[0] as Int) & 0xFF);
  let b1 = ((buffer[1] as Int) & 0xFF);
  let b2 = ((buffer[2] as Int) & 0xFF);
  let b3 = ((buffer[3] as Int) & 0xFF);
  let b4 = ((buffer[4] as Int) & 0xFF);
  let b5 = ((buffer[5] as Int) & 0xFF);
  let b6 = ((buffer[6] as Int) & 0xFF);
  let b7 = ((buffer[7] as Int) & 0xFF);
  let lo = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
  let hi = b4 + b5 * 256 + b6 * 65536 + b7 * 16777216;
  if hi >= 2147483648 {
    return _err_file("safetensors: header length out of range");
  }
  let n = lo + hi * 4294967296;
  if n > total - 8 {
    return _err_file("safetensors: header length exceeds buffer");
  }
  if n == 0 {
    return _err_file("safetensors: header is empty");
  }
  var hb = Vec[UInt8].new();
  var k = 0;
  while k < n {
    let raw: UInt8 = buffer[8 + k];
    let byte_val = (raw as Int) & 0xFF;
    if byte_val == 0 {
      return _err_file("safetensors: header contains NUL byte");
    }
    hb.push(raw);
    k = k + 1;
  }
  let header = builder.sb_to_str(&hb);
  var p = StParser{ src: header; len: n; pos: 0 };
  let data_start = 8 + n;
  let data_len = total - data_start;
  return _p_top(&mut p, n, data_start, data_len);
}

/// Number of tensors in the file.
pub fn st_tensor_count(f: &SafetensorsFile) -> Int {
  return f.names.len();
}

/// Raw header length N (the u64 stored in the first 8 bytes). The builder
/// emits N as a multiple of 8; st_parse accepts any N.
pub fn st_header_len(f: &SafetensorsFile) -> Int {
  return f.header_len;
}

/// Absolute offset of the first data-section byte (always 8 + N).
pub fn st_data_start(f: &SafetensorsFile) -> Int {
  return f.data_start;
}

/// Number of bytes in the container after the header.
pub fn st_data_len(f: &SafetensorsFile) -> Int {
  return f.data_len;
}

// Shared bounds check for tensor indices.
fn _in_range(f: &SafetensorsFile, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  return i < f.names.len();
}

/// Tensor name at index `i`.
/// Err("safetensors: tensor index out of range") when `i` is out of bounds.
pub fn st_tensor_name(f: &SafetensorsFile, i: Int) -> Result[Str, Str] {
  if !_in_range(f, i) {
    return _err_str("safetensors: tensor index out of range");
  }
  let v: Vec[Str] = f.names;
  let s: Str = v[i];
  return _ok_str(s);
}

/// Dtype token at index `i` (verbatim; see st_dtype_size for the documented
/// tokens).
/// Err("safetensors: tensor index out of range") when `i` is out of bounds.
pub fn st_tensor_dtype(f: &SafetensorsFile, i: Int) -> Result[Str, Str] {
  if !_in_range(f, i) {
    return _err_str("safetensors: tensor index out of range");
  }
  let v: Vec[Str] = f.dtypes;
  let s: Str = v[i];
  return _ok_str(s);
}

/// Rank (number of dimensions) of tensor `i`; 0 for a scalar.
/// Err("safetensors: tensor index out of range") when `i` is out of bounds.
pub fn st_tensor_rank(f: &SafetensorsFile, i: Int) -> Result[Int, Str] {
  if !_in_range(f, i) {
    return _err_int("safetensors: tensor index out of range");
  }
  let from: Int = f.shape_offsets[i];
  let to: Int = f.shape_offsets[i + 1];
  return _ok_int(to - from);
}

/// Dimension `d` of tensor `i` (0-based).
/// Err("safetensors: tensor index out of range") / Err("safetensors: dim
/// index out of range") on out-of-bounds indices.
pub fn st_tensor_dim(f: &SafetensorsFile, i: Int, d: Int) -> Result[Int, Str] {
  if !_in_range(f, i) {
    return _err_int("safetensors: tensor index out of range");
  }
  if d < 0 {
    return _err_int("safetensors: dim index out of range");
  }
  let from: Int = f.shape_offsets[i];
  let to: Int = f.shape_offsets[i + 1];
  if d >= to - from {
    return _err_int("safetensors: dim index out of range");
  }
  let v: Int = f.dims[from + d];
  return _ok_int(v);
}

/// Start of tensor `i`'s payload, relative to the data section.
/// Err("safetensors: tensor index out of range") when `i` is out of bounds.
pub fn st_tensor_offset_start(f: &SafetensorsFile, i: Int) -> Result[Int, Str] {
  if !_in_range(f, i) {
    return _err_int("safetensors: tensor index out of range");
  }
  let v: Int = f.offsets_start[i];
  return _ok_int(v);
}

/// End (exclusive) of tensor `i`'s payload, relative to the data section.
/// Err("safetensors: tensor index out of range") when `i` is out of bounds.
pub fn st_tensor_offset_end(f: &SafetensorsFile, i: Int) -> Result[Int, Str] {
  if !_in_range(f, i) {
    return _err_int("safetensors: tensor index out of range");
  }
  let v: Int = f.offsets_end[i];
  return _ok_int(v);
}

/// Payload length of tensor `i` in bytes (end - start).
/// Err("safetensors: tensor index out of range") when `i` is out of bounds.
pub fn st_tensor_data_len(f: &SafetensorsFile, i: Int) -> Result[Int, Str] {
  if !_in_range(f, i) {
    return _err_int("safetensors: tensor index out of range");
  }
  let s: Int = f.offsets_start[i];
  let e: Int = f.offsets_end[i];
  return _ok_int(e - s);
}

/// Copy tensor `i`'s payload bytes out of `container` (the same buffer that
/// was parsed). The bytes live at absolute [data_start + start,
/// data_start + end); complexity O(span).
///
/// Err("safetensors: tensor index out of range") for a bad index and
/// Err("safetensors: container is smaller than the tensor data") when
/// `container` is shorter than the declared span.
pub fn st_tensor_bytes(f: &SafetensorsFile, i: Int, container: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_in_range(f, i) {
    return _err_bytes("safetensors: tensor index out of range");
  }
  let s: Int = f.offsets_start[i];
  let e: Int = f.offsets_end[i];
  let base: Int = f.data_start;
  let limit: Int = container.len();
  if base + e > limit {
    return _err_bytes("safetensors: container is smaller than the tensor data");
  }
  var out = Vec[UInt8].new();
  var k = base + s;
  while k < base + e {
    let raw: UInt8 = container[k];
    out.push(raw);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Index of the tensor named `name` (declaration order).
/// Err("safetensors: tensor not found: '<name>'") when no tensor matches.
pub fn st_find_tensor(f: &SafetensorsFile, name: Str) -> Result[Int, Str] {
  let v: Vec[Str] = f.names;
  var i = 0;
  while i < v.len() {
    let s: Str = v[i];
    if compare.str_compare(s, name) == 0 {
      return _ok_int(i);
    }
    i = i + 1;
  }
  return _err_int("safetensors: tensor not found: '" + name + "'");
}

/// Bytes per element for a documented dtype token, 0 for any other token
/// (opaque pass-through: no shape/size validation is performed for it).
pub fn st_dtype_size(dtype: Str) -> Int {
  return _dtype_size(dtype);
}

/// Element count of a shape vector: the product of the dimensions, 1 for an
/// empty shape (scalar), 0 when any dimension is 0, and -1 on a negative
/// dimension or signed overflow. Integer only; no rounding.
pub fn st_shape_element_count(dims: &Vec[Int]) -> Int {
  var v: Int = 1;
  var k = 0;
  while k < dims.len() {
    let d: Int = dims[k];
    if d < 0 {
      return -1;
    }
    if d == 0 {
      v = 0;
    } elif v > 9223372036854775807 / d {
      return -1;
    } else {
      v = v * d;
    }
    k = k + 1;
  }
  return v;
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// Create an empty builder.
pub fn st_builder_new() -> SafetensorsBuilder {
  var b = SafetensorsBuilder{
    names: Vec[Str].new();
    dtypes: Vec[Str].new();
    ranks: Vec[Int].new();
    shape_offsets: Vec[Int].new();
    dims: Vec[Int].new();
    payload: Vec[UInt8].new();
    offsets_start: Vec[Int].new();
    offsets_end: Vec[Int].new();
  };
  b.shape_offsets.push(0);
  return b;
}

/// Number of tensors added so far.
pub fn st_builder_tensor_count(b: &SafetensorsBuilder) -> Int {
  return b.names.len();
}

/// Total payload length accumulated so far (the future data-section size).
pub fn st_builder_payload_len(b: &SafetensorsBuilder) -> Int {
  return b.payload.len();
}

/// Append one tensor: `name` and `dtype` are printable-ASCII tokens, `dims`
/// the shape (empty for a scalar) and `data` the raw little-endian payload
/// bytes. The payload is concatenated in call order and the emitted
/// data_offsets are relative to the start of that concatenation.
///
/// Returns the new tensor's index. For a documented fixed-width dtype the
/// shape element count times the element size must equal data.len();
/// unknown dtype tokens are passed through without a size check.
///
/// Err(Str) for an empty or non-ASCII name/dtype, a duplicate name, a
/// negative dimension, a shape-product overflow or a data-length mismatch.
pub fn st_builder_add(b: &mut SafetensorsBuilder, name: Str, dtype: Str, dims: &Vec[Int], data: &Vec[UInt8]) -> Result[Int, Str] {
  if string.str_len(name) == 0 {
    return _err_int("safetensors: builder: tensor name must not be empty");
  }
  if !_is_printable_ascii(name) {
    return _err_int("safetensors: builder: tensor name must be printable ASCII");
  }
  if string.str_len(dtype) == 0 {
    return _err_int("safetensors: builder: dtype must not be empty");
  }
  if !_is_printable_ascii(dtype) {
    return _err_int("safetensors: builder: dtype must be printable ASCII");
  }
  var i = 0;
  while i < b.names.len() {
    let existing: Str = b.names[i];
    if compare.str_compare(existing, name) == 0 {
      return _err_int("safetensors: builder: duplicate tensor name '" + name + "'");
    }
    i = i + 1;
  }
  var cnt: Int = 1;
  var k = 0;
  while k < dims.len() {
    let d: Int = dims[k];
    if d < 0 {
      return _err_int("safetensors: builder: negative dimension for tensor '" + name + "'");
    }
    if d == 0 {
      cnt = 0;
    } elif cnt > 9223372036854775807 / d {
      return _err_int("safetensors: builder: shape product overflows for tensor '" + name + "'");
    } else {
      cnt = cnt * d;
    }
    k = k + 1;
  }
  let w = _dtype_size(dtype);
  if w > 0 {
    if cnt > 9223372036854775807 / w {
      return _err_int("safetensors: builder: shape product overflows for tensor '" + name + "'");
    }
    let expected = cnt * w;
    if expected != data.len() {
      return _err_int("safetensors: builder: data length does not match shape for tensor '" + name + "'");
    }
  }
  let start = b.payload.len();
  b.names.push(name);
  b.dtypes.push(dtype);
  b.ranks.push(dims.len());
  var dk = 0;
  while dk < dims.len() {
    let dv: Int = dims[dk];
    b.dims.push(dv);
    dk = dk + 1;
  }
  b.shape_offsets.push(b.dims.len());
  var pk = 0;
  while pk < data.len() {
    let raw: UInt8 = data[pk];
    b.payload.push(raw);
    pk = pk + 1;
  }
  b.offsets_start.push(start);
  b.offsets_end.push(b.payload.len());
  return _ok_int(b.names.len() - 1);
}

// Compact header JSON for the builder contents, without padding. Keys are
// emitted in a fixed order: dtype, shape, data_offsets.
fn _builder_header(b: &SafetensorsBuilder) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_str(&mut sb, "{");
  var i = 0;
  while i < b.names.len() {
    if i > 0 {
      builder.sb_push_str(&mut sb, ",");
    }
    builder.sb_push_str(&mut sb, "\"");
    let nm: Str = b.names[i];
    _push_json_string(&mut sb, nm);
    builder.sb_push_str(&mut sb, "\":{\"dtype\":\"");
    let dt: Str = b.dtypes[i];
    _push_json_string(&mut sb, dt);
    builder.sb_push_str(&mut sb, "\",\"shape\":[");
    let from: Int = b.shape_offsets[i];
    let to: Int = b.shape_offsets[i + 1];
    var k = from;
    while k < to {
      if k > from {
        builder.sb_push_str(&mut sb, ",");
      }
      let dv: Int = b.dims[k];
      builder.sb_push_str(&mut sb, convert.int_to_string(dv));
      k = k + 1;
    }
    builder.sb_push_str(&mut sb, "],\"data_offsets\":[");
    let os: Int = b.offsets_start[i];
    let oe: Int = b.offsets_end[i];
    builder.sb_push_str(&mut sb, convert.int_to_string(os));
    builder.sb_push_str(&mut sb, ",");
    builder.sb_push_str(&mut sb, convert.int_to_string(oe));
    builder.sb_push_str(&mut sb, "]}");
    i = i + 1;
  }
  builder.sb_push_str(&mut sb, "}");
  return builder.sb_to_str(&sb);
}

/// Compact header JSON for the current builder contents (no padding).
pub fn st_builder_header_json(b: &SafetensorsBuilder) -> Str {
  return _builder_header(b);
}

/// Serialize the container: 8-byte little-endian header length, the compact
/// header JSON padded with spaces (0x20) so the header length is a multiple
/// of 8, then the concatenated payload. The data section therefore starts
/// 8-byte aligned at absolute offset 8 + N.
pub fn st_builder_finish(b: &SafetensorsBuilder) -> Vec[UInt8] {
  let header = _builder_header(b);
  let hlen = string.str_len(header);
  var padded = hlen;
  while padded % 8 != 0 {
    padded = padded + 1;
  }
  var out = Vec[UInt8].new();
  _push_u64_le(&mut out, padded);
  builder.sb_push_str(&mut out, header);
  var k = hlen;
  while k < padded {
    out.push(32 as UInt8);
    k = k + 1;
  }
  var i = 0;
  while i < b.payload.len() {
    let raw: UInt8 = b.payload[i];
    out.push(raw);
    i = i + 1;
  }
  return out;
}
