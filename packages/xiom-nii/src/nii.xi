// XIOM -- xiom.nii: pure-XIOM NIfTI-1 header codec
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.nii placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A dependency-free codec for the 348-byte NIfTI-1 header. The header is a
// fixed little-endian record on disk; some writers emit the same record with
// every multi-byte field byteswapped (big-endian). nii_parse detects both by
// decoding sizeof_hdr as little-endian first and, when that is not 348, as
// big-endian, then normalizes the fields into the canonical little-endian
// form. nii_to_bytes re-emits the canonical 348 bytes.
//
// Layout anchors (see SPEC.md for the full table): dim[8] int16 at 40,
// datatype int16 at 70, bitpix int16 at 72, pixdim[8] float32 at 76,
// vox_offset float32 at 108, descrip char[80] at 148, aux_file char[24] at
// 228, qform_code/sform_code int16 at 252/254, quatern_b/c/d and
// qoffset_x/y/z float32 at 256..280, srow_x/y/z float32[4] at 280..328,
// intent_name char[16] at 328 and magic char[4] at 344 ("n+1\0" single file
// or "ni1\0" header pair). The documented datatype table covers
// NIFTI_TYPE_UINT8 (2) through NIFTI_TYPE_FLOAT64 (64).
//
// Float32 fields are exposed as raw 4-byte little-endian tokens (Vec[UInt8])
// and as 8-character lowercase hex strings; no Float64 storage or arithmetic
// is used anywhere. The only float semantics applied are the IEEE-754 sign
// bit for vox_offset >= 0 validation and raw byte equality.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles).
//   * every UInt8 read is widened with `(b as Int) & 0xFF` before entering
//     Int arithmetic or comparisons.
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected: every read binds the field to a typed local first, and every
//     builder mutation copies the field out, edits the local and writes it
//     back.
//   * endianness normalization uses one explicit swap list that mirrors the
//     layout table, in file order, including the legacy unused fields.

module xiom.nii

use xiom.string;
use xiom.string.builder;
use xiom.convert;
use xiom.encoding.hex;

// --------------------------------------------------
//  Documented constants
// --------------------------------------------------

/// Canonical NIfTI-1 header length in bytes (the only accepted sizeof_hdr).
pub const NII_HEADER_LEN: Int = 348;

/// Magic kind of a single-file header: `n+1\0`; image data follows the
/// header at vox_offset.
pub const NII_MAGIC_SINGLE: Int = 0;

/// Magic kind of a header-pair header: `ni1\0`; voxels live in an external
/// .img file.
pub const NII_MAGIC_PAIR: Int = 1;

/// Extension-flag value that means "no extensions after the header".
pub const NII_EXT_NONE: Int = 0;

/// nii_ext_flag result when the buffer ends at byte 348, so the flag byte is
/// not present.
pub const NII_EXT_UNKNOWN: Int = -1;

// Float field ids for nii_float_raw / nii_float_hex /
// nii_builder_set_float. pixdim[] and srow_*[4] have dedicated accessors
// because they are indexed.
pub const NII_FLOAT_VOX_OFFSET: Int = 0;
pub const NII_FLOAT_SCL_SLOPE: Int = 1;
pub const NII_FLOAT_SCL_INTER: Int = 2;
pub const NII_FLOAT_CAL_MAX: Int = 3;
pub const NII_FLOAT_CAL_MIN: Int = 4;
pub const NII_FLOAT_SLICE_DURATION: Int = 5;
pub const NII_FLOAT_TOFFSET: Int = 6;
pub const NII_FLOAT_INTENT_P1: Int = 7;
pub const NII_FLOAT_INTENT_P2: Int = 8;
pub const NII_FLOAT_INTENT_P3: Int = 9;
pub const NII_FLOAT_QUATERN_B: Int = 10;
pub const NII_FLOAT_QUATERN_C: Int = 11;
pub const NII_FLOAT_QUATERN_D: Int = 12;
pub const NII_FLOAT_QOFFSET_X: Int = 13;
pub const NII_FLOAT_QOFFSET_Y: Int = 14;
pub const NII_FLOAT_QOFFSET_Z: Int = 15;

// Field offsets in the 348-byte header (canonical little-endian record).
const _OFF_SIZEOF_HDR: Int = 0;
const _OFF_EXTENTS: Int = 32;
const _OFF_SESSION_ERROR: Int = 36;
const _OFF_DIM: Int = 40;
const _OFF_INTENT_P1: Int = 56;
const _OFF_INTENT_P2: Int = 60;
const _OFF_INTENT_P3: Int = 64;
const _OFF_INTENT_CODE: Int = 68;
const _OFF_DATATYPE: Int = 70;
const _OFF_BITPIX: Int = 72;
const _OFF_SLICE_START: Int = 74;
const _OFF_PIXDIM: Int = 76;
const _OFF_VOX_OFFSET: Int = 108;
const _OFF_SCL_SLOPE: Int = 112;
const _OFF_SCL_INTER: Int = 116;
const _OFF_SLICE_END: Int = 120;
const _OFF_SLICE_CODE: Int = 122;
const _OFF_XYZT_UNITS: Int = 123;
const _OFF_CAL_MAX: Int = 124;
const _OFF_CAL_MIN: Int = 128;
const _OFF_SLICE_DURATION: Int = 132;
const _OFF_TOFFSET: Int = 136;
const _OFF_GLMAX: Int = 140;
const _OFF_GLMIN: Int = 144;
const _OFF_DESCRIP: Int = 148;
const _OFF_AUX_FILE: Int = 228;
const _OFF_QFORM_CODE: Int = 252;
const _OFF_SFORM_CODE: Int = 254;
const _OFF_QUATERN_B: Int = 256;
const _OFF_QUATERN_C: Int = 260;
const _OFF_QUATERN_D: Int = 264;
const _OFF_QOFFSET_X: Int = 268;
const _OFF_QOFFSET_Y: Int = 272;
const _OFF_QOFFSET_Z: Int = 276;
const _OFF_SROW_X: Int = 280;
const _OFF_INTENT_NAME: Int = 328;
const _OFF_MAGIC: Int = 344;

const _DESCRIP_LEN: Int = 80;
const _AUX_FILE_LEN: Int = 24;
const _INTENT_NAME_LEN: Int = 16;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[NiftiHeader, Str].
fn _ok_header(v: NiftiHeader) -> Result[NiftiHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[NiftiHeader, Str].
fn _err_header(m: Str) -> Result[NiftiHeader, Str] {
  return Err(m);
}

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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed NIfTI-1 header.
///
/// `raw` always holds the canonical little-endian 348 bytes: a big-endian
/// source buffer is byteswapped once at parse time. `swapped` records that
/// the source was big-endian, and `ext_flag` is the extension-flag byte at
/// absolute offset 348 (0 = no extensions, nonzero = extensions present) or
/// NII_EXT_UNKNOWN when the buffer ends at the header.
///
/// Fields are implementation details; use the nii_* accessors. A value is
/// only produced by nii_parse, so the validated invariants (sizeof_hdr 348,
/// non-negative dims, documented datatype with matching bitpix, valid magic,
/// non-negative vox_offset) always hold.
pub type NiftiHeader = {
  raw: Vec[UInt8];
  swapped: Bool;
  ext_flag: Int;
}

/// Accumulating builder for one canonical little-endian NIfTI-1 header.
///
/// nii_builder_new starts from a valid single-file header (magic `n+1`) and
/// the nii_builder_set_* functions overwrite individual fields; every setter
/// validates its input and leaves the builder unchanged on Err.
/// nii_builder_finish re-validates the assembled bytes and returns them.
///
/// Fields are implementation details; use the nii_builder_* functions.
pub type NiftiBuilder = {
  raw: Vec[UInt8];
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte_at(v: &Vec[UInt8], pos: Int) -> Int {
  let b: UInt8 = v[pos];
  return (b as Int) & 0xFF;
}

// Unsigned little-endian u16 at `off`.
fn _read_u16_le(v: &Vec[UInt8], off: Int) -> Int {
  return _byte_at(v, off) + _byte_at(v, off + 1) * 256;
}

// Signed little-endian i16 at `off` (two's complement).
fn _read_i16_le(v: &Vec[UInt8], off: Int) -> Int {
  var x = _read_u16_le(v, off);
  if x >= 32768 { x = x - 65536; }
  return x;
}

// Unsigned little-endian u32 at `off`.
fn _read_u32_le(v: &Vec[UInt8], off: Int) -> Int {
  let b0 = _byte_at(v, off);
  let b1 = _byte_at(v, off + 1);
  let b2 = _byte_at(v, off + 2);
  let b3 = _byte_at(v, off + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Unsigned big-endian u32 at `off` (used only for sizeof_hdr detection).
fn _read_u32_be(v: &Vec[UInt8], off: Int) -> Int {
  let b0 = _byte_at(v, off);
  let b1 = _byte_at(v, off + 1);
  let b2 = _byte_at(v, off + 2);
  let b3 = _byte_at(v, off + 3);
  return b3 + b2 * 256 + b1 * 65536 + b0 * 16777216;
}

// Store `val` as a little-endian i16 at `off`; negative values use two's
// complement and callers guarantee val >= -32768.
fn _write_u16_le(v: &mut Vec[UInt8], off: Int, val: Int) {
  var x = val;
  if x < 0 { x = x + 65536; }
  v[off] = (x % 256) as UInt8;
  v[off + 1] = ((x / 256) % 256) as UInt8;
  return;
}

// Store non-negative `val` as a little-endian u32 at `off`.
fn _write_u32_le(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = (val % 256) as UInt8;
  v[off + 1] = ((val / 256) % 256) as UInt8;
  v[off + 2] = ((val / 65536) % 256) as UInt8;
  v[off + 3] = ((val / 16777216) % 256) as UInt8;
  return;
}

// Copy 4 raw bytes from `raw` into `v` at `off`.
fn _write_raw4(v: &mut Vec[UInt8], off: Int, raw: &Vec[UInt8]) {
  var i = 0;
  while i < 4 {
    let b: UInt8 = raw[i];
    v[off + i] = b;
    i = i + 1;
  }
  return;
}

// Copy 4 bytes at `off` out of `v` (little-endian raw float token).
fn _copy4(v: &Vec[UInt8], off: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    let b: UInt8 = v[off + i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Store `val` as a little-endian i16 inside a builder. Writing through the
// mutable reference avoids the copy-out/copy-back borrow pattern that the
// pinned compiler flags with advisory E001.
fn _store_u16_le(b: &mut NiftiBuilder, off: Int, val: Int) {
  var x = val;
  if x < 0 { x = x + 65536; }
  b.raw[off] = (x % 256) as UInt8;
  b.raw[off + 1] = ((x / 256) % 256) as UInt8;
  return;
}

// Store one byte inside a builder; callers guarantee val is in 0..255.
fn _store_u8(b: &mut NiftiBuilder, off: Int, val: Int) {
  b.raw[off] = val as UInt8;
  return;
}

// Copy 4 raw bytes into a builder at `off`.
fn _store_raw4(b: &mut NiftiBuilder, off: Int, raw: &Vec[UInt8]) {
  var i = 0;
  while i < 4 {
    let x: UInt8 = raw[i];
    b.raw[off + i] = x;
    i = i + 1;
  }
  return;
}

// Reverse the `size` bytes at `off` in place.
fn _swap_at(v: &mut Vec[UInt8], off: Int, size: Int) {
  var i = 0;
  var j = size - 1;
  while i < j {
    let a: UInt8 = v[off + i];
    let b: UInt8 = v[off + j];
    v[off + i] = b;
    v[off + j] = a;
    i = i + 1;
    j = j - 1;
  }
  return;
}

// Byteswap every multi-byte field of a big-endian header in place, in file
// order, so the record becomes the canonical little-endian form. Single-byte
// fields (regular, dim_info, slice_code, xyzt_units, all char arrays and the
// magic) need no action.
fn _normalize_to_le(v: &mut Vec[UInt8]) {
  _swap_at(v, _OFF_SIZEOF_HDR, 4);
  _swap_at(v, _OFF_EXTENTS, 4);
  _swap_at(v, _OFF_SESSION_ERROR, 2);
  var i = 0;
  while i < 8 {
    _swap_at(v, _OFF_DIM + i * 2, 2);
    i = i + 1;
  }
  _swap_at(v, _OFF_INTENT_P1, 4);
  _swap_at(v, _OFF_INTENT_P2, 4);
  _swap_at(v, _OFF_INTENT_P3, 4);
  _swap_at(v, _OFF_INTENT_CODE, 2);
  _swap_at(v, _OFF_DATATYPE, 2);
  _swap_at(v, _OFF_BITPIX, 2);
  _swap_at(v, _OFF_SLICE_START, 2);
  i = 0;
  while i < 8 {
    _swap_at(v, _OFF_PIXDIM + i * 4, 4);
    i = i + 1;
  }
  _swap_at(v, _OFF_VOX_OFFSET, 4);
  _swap_at(v, _OFF_SCL_SLOPE, 4);
  _swap_at(v, _OFF_SCL_INTER, 4);
  _swap_at(v, _OFF_SLICE_END, 2);
  _swap_at(v, _OFF_CAL_MAX, 4);
  _swap_at(v, _OFF_CAL_MIN, 4);
  _swap_at(v, _OFF_SLICE_DURATION, 4);
  _swap_at(v, _OFF_TOFFSET, 4);
  _swap_at(v, _OFF_GLMAX, 4);
  _swap_at(v, _OFF_GLMIN, 4);
  _swap_at(v, _OFF_QFORM_CODE, 2);
  _swap_at(v, _OFF_SFORM_CODE, 2);
  _swap_at(v, _OFF_QUATERN_B, 4);
  _swap_at(v, _OFF_QUATERN_C, 4);
  _swap_at(v, _OFF_QUATERN_D, 4);
  _swap_at(v, _OFF_QOFFSET_X, 4);
  _swap_at(v, _OFF_QOFFSET_Y, 4);
  _swap_at(v, _OFF_QOFFSET_Z, 4);
  i = 0;
  while i < 12 {
    _swap_at(v, _OFF_SROW_X + i * 4, 4);
    i = i + 1;
  }
  return;
}

// Magic kind of a canonical header: NII_MAGIC_SINGLE for `n+1\0`,
// NII_MAGIC_PAIR for `ni1\0`, -1 for anything else.
fn _magic_kind_of(v: &Vec[UInt8]) -> Int {
  if _byte_at(v, _OFF_MAGIC) == 110 && _byte_at(v, _OFF_MAGIC + 1) == 43 {
    if _byte_at(v, _OFF_MAGIC + 2) == 49 && _byte_at(v, _OFF_MAGIC + 3) == 0 {
      return NII_MAGIC_SINGLE;
    }
  }
  if _byte_at(v, _OFF_MAGIC) == 110 && _byte_at(v, _OFF_MAGIC + 1) == 105 {
    if _byte_at(v, _OFF_MAGIC + 2) == 49 && _byte_at(v, _OFF_MAGIC + 3) == 0 {
      return NII_MAGIC_PAIR;
    }
  }
  return -1;
}

// True when the IEEE-754 float32 at `off` has its sign bit set. Bit layout:
// the sign is bit 7 of the last little-endian byte; no float arithmetic.
fn _float_sign_negative(v: &Vec[UInt8], off: Int) -> Bool {
  let hi = _byte_at(v, off + 3);
  return (hi & 128) == 128;
}

// Text field bytes from `off` up to the first NUL (or `size` bytes when no
// NUL is present). The slice handed to sb_to_str is NUL-free by construction.
fn _text_at(v: &Vec[UInt8], off: Int, size: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  var stop = false;
  while i < size && !stop {
    let b: UInt8 = v[off + i];
    let val = (b as Int) & 0xFF;
    if val == 0 {
      stop = true;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Datatype table
// --------------------------------------------------

/// Documented bitpix for a NIfTI-1 datatype code, or -1 when the code is not
/// in the documented NIFTI_TYPE_UINT8..NIFTI_TYPE_FLOAT64 range.
pub fn nii_datatype_bitpix(datatype: Int) -> Int {
  if datatype == 2 { return 8; }
  if datatype == 4 { return 16; }
  if datatype == 8 { return 32; }
  if datatype == 16 { return 32; }
  if datatype == 32 { return 64; }
  if datatype == 64 { return 64; }
  return -1;
}

/// Documented NIfTI-1 datatype name for a code, or "" when the code is not
/// in the documented table.
pub fn nii_datatype_name(datatype: Int) -> Str {
  if datatype == 2 { return "NIFTI_TYPE_UINT8"; }
  if datatype == 4 { return "NIFTI_TYPE_INT16"; }
  if datatype == 8 { return "NIFTI_TYPE_INT32"; }
  if datatype == 16 { return "NIFTI_TYPE_FLOAT32"; }
  if datatype == 32 { return "NIFTI_TYPE_COMPLEX64"; }
  if datatype == 64 { return "NIFTI_TYPE_FLOAT64"; }
  return "";
}

/// True when `datatype` is in the documented table.
pub fn nii_datatype_known(datatype: Int) -> Bool {
  return nii_datatype_bitpix(datatype) >= 0;
}

// --------------------------------------------------
//  Validation
// --------------------------------------------------

/// Validate a canonical little-endian header, in the documented order:
/// (1) sizeof_hdr == 348, (2) all dim[] >= 0, (3) datatype in the table,
/// (4) bitpix == nii_datatype_bitpix(datatype), (5) magic matches,
/// (6) vox_offset >= 0 (IEEE-754 sign bit clear).
fn _validate_header_bytes(v: &Vec[UInt8]) -> Result[Unit, Str] {
  let size = _read_u32_le(v, _OFF_SIZEOF_HDR);
  if size != NII_HEADER_LEN {
    return _err_unit("nii: unsupported sizeof_hdr " + convert.int_to_string(size));
  }
  var i = 0;
  while i < 8 {
    let d = _read_i16_le(v, _OFF_DIM + i * 2);
    if d < 0 {
      return _err_unit("nii: negative dimension");
    }
    i = i + 1;
  }
  let datatype = _read_i16_le(v, _OFF_DATATYPE);
  let want = nii_datatype_bitpix(datatype);
  if want < 0 {
    return _err_unit("nii: unknown datatype " + convert.int_to_string(datatype));
  }
  let bits = _read_i16_le(v, _OFF_BITPIX);
  if bits != want {
    return _err_unit("nii: bitpix does not match datatype");
  }
  if _magic_kind_of(v) < 0 {
    return _err_unit("nii: invalid magic");
  }
  if _float_sign_negative(v, _OFF_VOX_OFFSET) {
    return _err_unit("nii: negative vox_offset");
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a NIfTI-1 header buffer.
///
/// `buffer` must be at least 348 bytes. sizeof_hdr is decoded little-endian
/// first and big-endian second; a big-endian header is byteswapped into the
/// canonical little-endian form and flagged by nii_swapped. The header is
/// validated in the documented order (see SPEC.md), so a returned header
/// satisfies every rule. When at least 4 bytes follow the header, byte 348
/// is read into nii_ext_flag (0 = no extensions); otherwise the flag is
/// NII_EXT_UNKNOWN. Extra trailing bytes are ignored.
///
/// Err(Str) messages: `nii: buffer too small for header`,
/// `nii: unsupported sizeof_hdr <n>` (n is the little-endian decode of bytes
/// 0..4), and the validation catalog.
pub fn nii_parse(buffer: &Vec[UInt8]) -> Result[NiftiHeader, Str] {
  let total = buffer.len();
  if total < NII_HEADER_LEN {
    return _err_header("nii: buffer too small for header");
  }
  let le = _read_u32_le(buffer, _OFF_SIZEOF_HDR);
  var swapped = false;
  if le != NII_HEADER_LEN {
    let be = _read_u32_be(buffer, _OFF_SIZEOF_HDR);
    if be != NII_HEADER_LEN {
      return _err_header("nii: unsupported sizeof_hdr " + convert.int_to_string(le));
    }
    swapped = true;
  }
  var raw = Vec[UInt8].new();
  var i = 0;
  while i < NII_HEADER_LEN {
    let b: UInt8 = buffer[i];
    raw.push(b);
    i = i + 1;
  }
  if swapped {
    _normalize_to_le(&mut raw);
  }
  let vr = _validate_header_bytes(&raw);
  if !vr.is_ok {
    let msg: Str = vr.error;
    return _err_header(msg);
  }
  var ext = NII_EXT_UNKNOWN;
  if total >= NII_HEADER_LEN + 4 {
    let eb: UInt8 = buffer[NII_HEADER_LEN];
    ext = (eb as Int) & 0xFF;
  }
  let header_raw: Vec[UInt8] = raw;
  let hdr = NiftiHeader{ raw: header_raw; swapped: swapped; ext_flag: ext; };
  return _ok_header(hdr);
}

/// Re-emit the canonical little-endian 348 header bytes. A header parsed
/// from a big-endian source comes out in canonical little-endian form.
/// Complexity: O(348).
pub fn nii_to_bytes(h: &NiftiHeader) -> Vec[UInt8] {
  let raw: Vec[UInt8] = h.raw;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < raw.len() {
    let b: UInt8 = raw[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

/// True when the source buffer was big-endian and got byteswapped at parse
/// time.
pub fn nii_swapped(h: &NiftiHeader) -> Bool {
  return h.swapped;
}

/// Extension-flag byte at absolute offset 348: 0 means no extensions,
/// nonzero means extensions are present; NII_EXT_UNKNOWN when the parsed
/// buffer ended at the header. Never validated (any byte is reported as-is).
pub fn nii_ext_flag(h: &NiftiHeader) -> Int {
  return h.ext_flag;
}

// --------------------------------------------------
//  Scalar accessors
// --------------------------------------------------

/// sizeof_hdr field; always 348 for a parsed header.
pub fn nii_sizeof_hdr(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_u32_le(&raw, _OFF_SIZEOF_HDR);
}

/// dim[0]: the number of dimensions declared by the header.
pub fn nii_dim_count(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_DIM);
}

/// dim[i] for i in 0..7 (0 is the dimension count, 1..7 the extents).
/// Err("nii: dim index out of range") when i is outside 0..7.
pub fn nii_dim(h: &NiftiHeader, i: Int) -> Result[Int, Str] {
  if i < 0 || i > 7 {
    return _err_int("nii: dim index out of range");
  }
  let raw: Vec[UInt8] = h.raw;
  return _ok_int(_read_i16_le(&raw, _OFF_DIM + i * 2));
}

/// datatype code (see nii_datatype_bitpix / nii_datatype_name).
pub fn nii_datatype(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_DATATYPE);
}

/// bitpix field; always equal to nii_datatype_bitpix(nii_datatype(h)) for a
/// parsed header.
pub fn nii_bitpix(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_BITPIX);
}

/// intent_code (0 when no intent is declared; not otherwise validated).
pub fn nii_intent_code(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_INTENT_CODE);
}

/// qform_code: 0 unknown, 1 scanner, 2 aligned, 3 talairach, 4 mni.
pub fn nii_qform_code(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_QFORM_CODE);
}

/// sform_code: same code set as qform_code.
pub fn nii_sform_code(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_SFORM_CODE);
}

/// slice_start (first slice index in the acquisition order).
pub fn nii_slice_start(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_SLICE_START);
}

/// slice_end (last slice index; -1 when not applicable).
pub fn nii_slice_end(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _read_i16_le(&raw, _OFF_SLICE_END);
}

/// slice_code (0..255 slice timing order code).
pub fn nii_slice_code(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _byte_at(&raw, _OFF_SLICE_CODE);
}

/// xyzt_units packed byte: low 3 bits hold the space unit, bits 3..5 the
/// time unit.
pub fn nii_xyzt_units(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _byte_at(&raw, _OFF_XYZT_UNITS);
}

/// Magic kind: NII_MAGIC_SINGLE (`n+1\0`, single file) or NII_MAGIC_PAIR
/// (`ni1\0`, header pair). Always valid for a parsed header.
pub fn nii_magic_kind(h: &NiftiHeader) -> Int {
  let raw: Vec[UInt8] = h.raw;
  return _magic_kind_of(&raw);
}

// --------------------------------------------------
//  Text accessors
// --------------------------------------------------

/// descrip field (up to 80 bytes), trimmed at the first NUL byte.
pub fn nii_descrip(h: &NiftiHeader) -> Str {
  let raw: Vec[UInt8] = h.raw;
  return _text_at(&raw, _OFF_DESCRIP, _DESCRIP_LEN);
}

/// aux_file field (up to 24 bytes), trimmed at the first NUL byte.
pub fn nii_aux_file(h: &NiftiHeader) -> Str {
  let raw: Vec[UInt8] = h.raw;
  return _text_at(&raw, _OFF_AUX_FILE, _AUX_FILE_LEN);
}

/// intent_name field (up to 16 bytes), trimmed at the first NUL byte.
pub fn nii_intent_name(h: &NiftiHeader) -> Str {
  let raw: Vec[UInt8] = h.raw;
  return _text_at(&raw, _OFF_INTENT_NAME, _INTENT_NAME_LEN);
}

// --------------------------------------------------
//  Raw float tokens
// --------------------------------------------------

/// Lowercase hex of a raw byte token (2 characters per byte, "" for empty).
pub fn nii_raw_hex(v: &Vec[UInt8]) -> Str {
  return hex.hex_encode(v);
}

// Field id -> header offset, or -1 when the id is not documented.
fn _float_field_offset(field: Int) -> Int {
  if field == 0 { return _OFF_VOX_OFFSET; }
  if field == 1 { return _OFF_SCL_SLOPE; }
  if field == 2 { return _OFF_SCL_INTER; }
  if field == 3 { return _OFF_CAL_MAX; }
  if field == 4 { return _OFF_CAL_MIN; }
  if field == 5 { return _OFF_SLICE_DURATION; }
  if field == 6 { return _OFF_TOFFSET; }
  if field == 7 { return _OFF_INTENT_P1; }
  if field == 8 { return _OFF_INTENT_P2; }
  if field == 9 { return _OFF_INTENT_P3; }
  if field == 10 { return _OFF_QUATERN_B; }
  if field == 11 { return _OFF_QUATERN_C; }
  if field == 12 { return _OFF_QUATERN_D; }
  if field == 13 { return _OFF_QOFFSET_X; }
  if field == 14 { return _OFF_QOFFSET_Y; }
  if field == 15 { return _OFF_QOFFSET_Z; }
  return -1;
}

/// Raw 4-byte little-endian float32 token for a singleton float field
/// (field ids are the NII_FLOAT_* constants).
/// Err("nii: float field out of range") for an undocumented id.
pub fn nii_float_raw(h: &NiftiHeader, field: Int) -> Result[Vec[UInt8], Str] {
  let off = _float_field_offset(field);
  if off < 0 {
    return _err_bytes("nii: float field out of range");
  }
  let raw: Vec[UInt8] = h.raw;
  return _ok_bytes(_copy4(&raw, off));
}

/// Lowercase 8-character hex token for a singleton float field.
/// Err("nii: float field out of range") for an undocumented id.
pub fn nii_float_hex(h: &NiftiHeader, field: Int) -> Result[Str, Str] {
  let r = nii_float_raw(h, field);
  if !r.is_ok {
    let msg: Str = r.error;
    return _err_str(msg);
  }
  let v: Vec[UInt8] = r.value;
  return _ok_str(hex.hex_encode(&v));
}

/// Raw 4-byte little-endian token for pixdim[i], i in 0..7.
/// Err("nii: pixdim index out of range") otherwise.
pub fn nii_pixdim_raw(h: &NiftiHeader, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i > 7 {
    return _err_bytes("nii: pixdim index out of range");
  }
  let raw: Vec[UInt8] = h.raw;
  return _ok_bytes(_copy4(&raw, _OFF_PIXDIM + i * 4));
}

/// Lowercase 8-character hex token for pixdim[i].
/// Err("nii: pixdim index out of range") otherwise.
pub fn nii_pixdim_hex(h: &NiftiHeader, i: Int) -> Result[Str, Str] {
  let r = nii_pixdim_raw(h, i);
  if !r.is_ok {
    let msg: Str = r.error;
    return _err_str(msg);
  }
  let v: Vec[UInt8] = r.value;
  return _ok_str(hex.hex_encode(&v));
}

/// Raw 4-byte little-endian token for srow_{row}[col], row in 0..2 and col in
/// 0..3 (the 12 srow_x/y/z float32 values).
/// Err("nii: srow index out of range") otherwise.
pub fn nii_srow_raw(h: &NiftiHeader, row: Int, col: Int) -> Result[Vec[UInt8], Str] {
  if row < 0 || row > 2 || col < 0 || col > 3 {
    return _err_bytes("nii: srow index out of range");
  }
  let raw: Vec[UInt8] = h.raw;
  return _ok_bytes(_copy4(&raw, _OFF_SROW_X + row * 16 + col * 4));
}

/// Lowercase 8-character hex token for srow_{row}[col].
/// Err("nii: srow index out of range") otherwise.
pub fn nii_srow_hex(h: &NiftiHeader, row: Int, col: Int) -> Result[Str, Str] {
  let r = nii_srow_raw(h, row, col);
  if !r.is_ok {
    let msg: Str = r.error;
    return _err_str(msg);
  }
  let v: Vec[UInt8] = r.value;
  return _ok_str(hex.hex_encode(&v));
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// Create a builder holding the documented canonical single-file header:
/// sizeof_hdr 348, dim [3,1,1,1,1,1,1,1], datatype NIFTI_TYPE_UINT8 with
/// bitpix 8, pixdim[0..7] = 1.0f (raw 0000803f), vox_offset = 352.0f
/// (raw 0000b043), every other byte zero and magic `n+1\0`.
pub fn nii_builder_new() -> NiftiBuilder {
  var raw = Vec[UInt8].new();
  var i = 0;
  while i < NII_HEADER_LEN {
    raw.push(0 as UInt8);
    i = i + 1;
  }
  _write_u32_le(&mut raw, _OFF_SIZEOF_HDR, NII_HEADER_LEN);
  _write_u16_le(&mut raw, _OFF_DIM, 3);
  i = 1;
  while i < 8 {
    _write_u16_le(&mut raw, _OFF_DIM + i * 2, 1);
    i = i + 1;
  }
  _write_u16_le(&mut raw, _OFF_DATATYPE, 2);
  _write_u16_le(&mut raw, _OFF_BITPIX, 8);
  var pixdim_one = Vec[UInt8].new();
  pixdim_one.push(0 as UInt8);
  pixdim_one.push(0 as UInt8);
  pixdim_one.push(128 as UInt8);
  pixdim_one.push(63 as UInt8);
  i = 0;
  while i < 8 {
    _write_raw4(&mut raw, _OFF_PIXDIM + i * 4, &pixdim_one);
    i = i + 1;
  }
  var vox_offset_default = Vec[UInt8].new();
  vox_offset_default.push(0 as UInt8);
  vox_offset_default.push(0 as UInt8);
  vox_offset_default.push(176 as UInt8);
  vox_offset_default.push(67 as UInt8);
  _write_raw4(&mut raw, _OFF_VOX_OFFSET, &vox_offset_default);
  raw[_OFF_MAGIC] = 110 as UInt8;
  raw[_OFF_MAGIC + 1] = 43 as UInt8;
  raw[_OFF_MAGIC + 2] = 49 as UInt8;
  raw[_OFF_MAGIC + 3] = 0 as UInt8;
  return NiftiBuilder{ raw: raw };
}

/// Validate the assembled header (same rules and order as nii_parse) and
/// return the canonical 348 little-endian bytes. Errors leave the builder
/// unchanged. Complexity: O(348).
pub fn nii_builder_finish(b: &NiftiBuilder) -> Result[Vec[UInt8], Str] {
  let raw: Vec[UInt8] = b.raw;
  let vr = _validate_header_bytes(&raw);
  if !vr.is_ok {
    let msg: Str = vr.error;
    return _err_bytes(msg);
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < raw.len() {
    let x: UInt8 = raw[i];
    out.push(x);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Set dim[i] for i in 0..7.
/// Err("nii: dim index out of range") for i outside 0..7;
/// Err("nii: negative dimension") for v < 0;
/// Err("nii: dimension out of range") for v > 32767.
pub fn nii_builder_set_dim(b: &mut NiftiBuilder, i: Int, v: Int) -> Result[Unit, Str] {
  if i < 0 || i > 7 {
    return _err_unit("nii: dim index out of range");
  }
  if v < 0 {
    return _err_unit("nii: negative dimension");
  }
  if v > 32767 {
    return _err_unit("nii: dimension out of range");
  }
  _store_u16_le(b, _OFF_DIM + i * 2, v);
  return _ok_unit();
}

/// Set datatype to a documented code and bitpix to its documented value in
/// one step.
/// Err("nii: unknown datatype <n>") for an undocumented code.
pub fn nii_builder_set_datatype(b: &mut NiftiBuilder, datatype: Int) -> Result[Unit, Str] {
  let bits = nii_datatype_bitpix(datatype);
  if bits < 0 {
    return _err_unit("nii: unknown datatype " + convert.int_to_string(datatype));
  }
  _store_u16_le(b, _OFF_DATATYPE, datatype);
  _store_u16_le(b, _OFF_BITPIX, bits);
  return _ok_unit();
}

/// Set one singleton float field from a raw 4-byte little-endian token
/// (field ids are the NII_FLOAT_* constants).
/// Err("nii: float field out of range") for an undocumented id;
/// Err("nii: float token must be 4 bytes") when token.len() != 4.
pub fn nii_builder_set_float(b: &mut NiftiBuilder, field: Int, token: &Vec[UInt8]) -> Result[Unit, Str] {
  let off = _float_field_offset(field);
  if off < 0 {
    return _err_unit("nii: float field out of range");
  }
  if token.len() != 4 {
    return _err_unit("nii: float token must be 4 bytes");
  }
  _store_raw4(b, off, token);
  return _ok_unit();
}

/// Set pixdim[i] from a raw 4-byte little-endian token.
/// Err("nii: pixdim index out of range") for i outside 0..7;
/// Err("nii: float token must be 4 bytes") when token.len() != 4.
pub fn nii_builder_set_pixdim(b: &mut NiftiBuilder, i: Int, token: &Vec[UInt8]) -> Result[Unit, Str] {
  if i < 0 || i > 7 {
    return _err_unit("nii: pixdim index out of range");
  }
  if token.len() != 4 {
    return _err_unit("nii: float token must be 4 bytes");
  }
  _store_raw4(b, _OFF_PIXDIM + i * 4, token);
  return _ok_unit();
}

/// Set srow_{row}[col] from a raw 4-byte little-endian token, row in 0..2 and
/// col in 0..3.
/// Err("nii: srow index out of range") otherwise;
/// Err("nii: float token must be 4 bytes") when token.len() != 4.
pub fn nii_builder_set_srow(b: &mut NiftiBuilder, row: Int, col: Int, token: &Vec[UInt8]) -> Result[Unit, Str] {
  if row < 0 || row > 2 || col < 0 || col > 3 {
    return _err_unit("nii: srow index out of range");
  }
  if token.len() != 4 {
    return _err_unit("nii: float token must be 4 bytes");
  }
  _store_raw4(b, _OFF_SROW_X + row * 16 + col * 4, token);
  return _ok_unit();
}

/// Set qform_code (0..32767; 0 unknown, 1 scanner, 2 aligned, 3 talairach,
/// 4 mni).
/// Err("nii: form code out of range") otherwise.
pub fn nii_builder_set_qform_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str] {
  if v < 0 || v > 32767 {
    return _err_unit("nii: form code out of range");
  }
  _store_u16_le(b, _OFF_QFORM_CODE, v);
  return _ok_unit();
}

/// Set sform_code (0..32767; same code set as qform_code).
/// Err("nii: form code out of range") otherwise.
pub fn nii_builder_set_sform_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str] {
  if v < 0 || v > 32767 {
    return _err_unit("nii: form code out of range");
  }
  _store_u16_le(b, _OFF_SFORM_CODE, v);
  return _ok_unit();
}

/// Set intent_code (0..32767; 0 means none).
/// Err("nii: intent code out of range") otherwise.
pub fn nii_builder_set_intent_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str] {
  if v < 0 || v > 32767 {
    return _err_unit("nii: intent code out of range");
  }
  _store_u16_le(b, _OFF_INTENT_CODE, v);
  return _ok_unit();
}

/// Set slice_start to any signed 16-bit value.
/// Err("nii: slice index out of range") outside -32768..32767.
pub fn nii_builder_set_slice_start(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str] {
  if v < -32768 || v > 32767 {
    return _err_unit("nii: slice index out of range");
  }
  _store_u16_le(b, _OFF_SLICE_START, v);
  return _ok_unit();
}

/// Set slice_end to any signed 16-bit value (-1 is the documented "not
/// applicable" value).
/// Err("nii: slice index out of range") outside -32768..32767.
pub fn nii_builder_set_slice_end(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str] {
  if v < -32768 || v > 32767 {
    return _err_unit("nii: slice index out of range");
  }
  _store_u16_le(b, _OFF_SLICE_END, v);
  return _ok_unit();
}

/// Set slice_code (0..255).
/// Err("nii: slice code out of range") otherwise.
pub fn nii_builder_set_slice_code(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str] {
  if v < 0 || v > 255 {
    return _err_unit("nii: slice code out of range");
  }
  _store_u8(b, _OFF_SLICE_CODE, v);
  return _ok_unit();
}

/// Set xyzt_units (0..255; low 3 bits space unit, bits 3..5 time unit).
/// Err("nii: units out of range") otherwise.
pub fn nii_builder_set_xyzt_units(b: &mut NiftiBuilder, v: Int) -> Result[Unit, Str] {
  if v < 0 || v > 255 {
    return _err_unit("nii: units out of range");
  }
  _store_u8(b, _OFF_XYZT_UNITS, v);
  return _ok_unit();
}

/// Set the magic kind: NII_MAGIC_SINGLE (`n+1\0`) or NII_MAGIC_PAIR
/// (`ni1\0`).
/// Err("nii: invalid magic kind") otherwise.
pub fn nii_builder_set_magic(b: &mut NiftiBuilder, kind: Int) -> Result[Unit, Str] {
  if kind != NII_MAGIC_SINGLE && kind != NII_MAGIC_PAIR {
    return _err_unit("nii: invalid magic kind");
  }
  if kind == NII_MAGIC_SINGLE {
    b.raw[_OFF_MAGIC] = 110 as UInt8;
    b.raw[_OFF_MAGIC + 1] = 43 as UInt8;
    b.raw[_OFF_MAGIC + 2] = 49 as UInt8;
    b.raw[_OFF_MAGIC + 3] = 0 as UInt8;
  } else {
    b.raw[_OFF_MAGIC] = 110 as UInt8;
    b.raw[_OFF_MAGIC + 1] = 105 as UInt8;
    b.raw[_OFF_MAGIC + 2] = 49 as UInt8;
    b.raw[_OFF_MAGIC + 3] = 0 as UInt8;
  }
  return _ok_unit();
}

// Write `s` into the text field at `off` of length `size`, NUL-padding the
// rest. The caller guarantees size >= 1.
fn _set_text_field(b: &mut NiftiBuilder, off: Int, size: Int, s: Str) -> Result[Unit, Str] {
  let n = string.str_len(s);
  if n > size {
    return _err_unit("nii: text too long");
  }
  var i = 0;
  while i < size {
    if i < n {
      let c: UInt8 = string.byte_at(s, i);
      b.raw[off + i] = c;
    } else {
      b.raw[off + i] = 0 as UInt8;
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Set descrip (at most 80 bytes, NUL-padded).
/// Err("nii: text too long") when the string exceeds 80 bytes.
pub fn nii_builder_set_descrip(b: &mut NiftiBuilder, s: Str) -> Result[Unit, Str] {
  return _set_text_field(b, _OFF_DESCRIP, _DESCRIP_LEN, s);
}

/// Set aux_file (at most 24 bytes, NUL-padded).
/// Err("nii: text too long") when the string exceeds 24 bytes.
pub fn nii_builder_set_aux_file(b: &mut NiftiBuilder, s: Str) -> Result[Unit, Str] {
  return _set_text_field(b, _OFF_AUX_FILE, _AUX_FILE_LEN, s);
}

/// Set intent_name (at most 16 bytes, NUL-padded).
/// Err("nii: text too long") when the string exceeds 16 bytes.
pub fn nii_builder_set_intent_name(b: &mut NiftiBuilder, s: Str) -> Result[Unit, Str] {
  return _set_text_field(b, _OFF_INTENT_NAME, _INTENT_NAME_LEN, s);
}
