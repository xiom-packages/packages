// XIOM -- xiom.docx: Word OpenXML (.docx) reader/writer
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) implementation of a minimal, round-trippable
// WordprocessingML subset. A .docx file is a ZIP container; the package
// builds and parses that container itself (local file headers, central
// directory, EOCD) on top of the stdlib DEFLATE stack:
//
//   [Content_Types].xml   stored (method 0)
//   _rels/.rels           stored (method 0)
//   word/document.xml     stored (level 0) or deflated (level 1..9)
//
// The document model is a flat set of parallel vectors plus one
// concatenated UTF-8 text buffer (never Vec[Str], never Vec[StructType]):
//
//   * paragraphs: para_start/para_count index runs;
//   * runs: run_off/run_len index `text`; run_bold/run_italic/run_size
//     carry the style subset (bold, italic, half-point size);
//   * `text_len` is the authoritative byte length of `text`.
//
// ZIP notes:
//   * entries are written with a fixed DOS timestamp (1980-01-01) so the
//     output is byte-deterministic;
//   * reading supports stored entries and DEFLATE streams. The stdlib
//     `deflate_decompress_capped` is tried first (it handles stored, fixed
//     and simple dynamic blocks); when it fails, this module's own
//     stored + fixed-Huffman inflater is used. Dynamic-Huffman streams
//     that use the 16/17/18 repeat codes remain unsupported (documented in
//     SPEC.md);
//   * entry names are validated as printable ASCII on read (the UTF-8 name
//     flag is not set on write).
//
// v0.62.2 notes that shaped this module:
//   * free functions only, no self methods, no lambdas, no Vec[fn], no
//     Vec[StructType], no Vec[Str]; parallel Vec[Int] offsets into one Str
//     / Vec[UInt8] pool;
//   * Ok/Err construction is confined to the tiny leaf helpers below;
//   * every Vec element read is bound to an explicitly typed local first;
//     every UInt8 is widened with `(b as Int) & 0xFF` before Int use;
//   * `&struct.field` is never passed to a `&Vec`/`&mut Vec` parameter
//     (traps 4/12): entry headers are built in locals and appended with
//     indexed pushes;
//   * all u32 little-endian packing is arithmetic (division/modulo) on
//     non-negative Int values -- no `& 0xFF` masking of bit-31 values;
//   * the CRC-32 comes from `xiom.compress.gzip.gzip_crc32` (UInt32) and is
//     widened with `as Int` exactly like the proven `xiom.packet` shape;
//   * `Str` values are materialized with `xiom.string.builder.sb_to_str`
//     only after the bytes were validated as NUL-free.

module xiom.docx

use xiom.string;
use xiom.string.builder;
use xiom.convert;
use xiom.compress.deflate;
use xiom.compress.gzip;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// DOS date for 1980-01-01 (year offset 0, month 1, day 1): deterministic
// ZIP timestamps. DOS time is 00:00:00.
const _DOCX_DOS_DATE: Int = 0x0021;

const _ZIP_LOCAL_SIG: Int = 0x04034B50;
const _ZIP_CENTRAL_SIG: Int = 0x02014B50;
const _ZIP_EOCD_SIG: Int = 0x06054B50;

// Per-entry output ceiling: a decompression-bomb guard for reads.
const _DOCX_MAX_ENTRY: Int = 67108864;

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
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

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[DocxZip, Str].
fn _zip_ok(v: DocxZip) -> Result[DocxZip, Str] {
  return Ok(v);
}

// Err(m) for Result[DocxZip, Str].
fn _zip_err(m: Str) -> Result[DocxZip, Str] {
  return Err(m);
}

// Ok(v) for Result[DocxDoc, Str].
fn _docx_ok(v: DocxDoc) -> Result[DocxDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[DocxDoc, Str].
fn _docx_err(m: Str) -> Result[DocxDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte number `k` (0 = least significant) of the non-negative value `v`.
fn _byte_at(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    q = q / 256;
    i = i + 1;
  };
  return (q % 256) as UInt8;
}

// Append the low `size` bytes of the non-negative value `v`, little-endian.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_at(v, i));
    i = i + 1;
  };
}

// Unsigned little-endian u16 at [pos, pos+2). Caller checks bounds.
fn _le16_at(data: &Vec[UInt8], pos: Int) -> Int {
  let lo: UInt8 = data[pos];
  let hi: UInt8 = data[pos + 1];
  return ((lo as Int) & 0xFF) + ((hi as Int) & 0xFF) * 256;
}

// Unsigned little-endian u32 at [pos, pos+4). Caller checks bounds.
fn _le32_at(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var k = 3;
  while k >= 0 {
    let b: UInt8 = data[pos + k];
    v = v * 256 + ((b as Int) & 0xFF);
    k = k - 1;
  };
  return v;
}

// Copy bytes [start, end) into a fresh vector. Caller checks bounds.
fn _copy_range(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  };
  return out;
}

// Append `s` as raw bytes (UTF-8 opaque; validates NUL).
fn _put_str(out: &mut Vec[UInt8], s: Str) -> Result[Bool, Str] {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if (((b as Int) & 0xFF) == 0) {
      return _err_bool("docx: nul byte in text");
    };
    out.push(b);
    i = i + 1;
  };
  return _ok_bool(true);
}

// First index >= from where byte equals `val`, or -1.
fn _find_byte(data: &Vec[UInt8], from: Int, val: Int) -> Int {
  var i = from;
  while i < data.len() {
    let b: UInt8 = data[i];
    if (((b as Int) & 0xFF) == val) {
      return i;
    };
    i = i + 1;
  };
  return -1;
}

// First index in [from, to) where `needle` occurs, or -1. Naive search.
fn _find_sub(data: &Vec[UInt8], from: Int, to: Int, needle: &Vec[UInt8]) -> Int {
  let m = needle.len();
  if m == 0 || from < 0 {
    return -1;
  };
  if from + m > to {
    return -1;
  };
  var i = from;
  while i + m <= to {
    var k = 0;
    var ok = true;
    while k < m {
      let a: UInt8 = data[i + k];
      let b: UInt8 = needle[k];
      if a != b {
        ok = false;
        k = m;
      } else {
        k = k + 1;
      };
    };
    if ok {
      return i;
    };
    i = i + 1;
  };
  return -1;
}

// First index in [from, to) where the Str `s` occurs, or -1.
fn _find_str_range(data: &Vec[UInt8], from: Int, to: Int, s: Str) -> Int {
  var pat = Vec[UInt8].new();
  let pr = _put_str(&mut pat, s);
  if !pr.is_ok {
    return -1;
  };
  return _find_sub(data, from, to, &pat);
}

// --------------------------------------------------
//  CRC-32 (IEEE 802.3) via the stdlib gzip helper
// --------------------------------------------------

// CRC-32 of `data` as an unsigned 32-bit value in an Int (0..4294967295).
// `UInt32 as Int` zero-extends (xiom.packet precedent), and all packing is
// arithmetic, so no signed masking is involved.
fn _crc32(data: &Vec[UInt8]) -> Int {
  let c: UInt32 = gzip.gzip_crc32(data);
  return c as Int;
}

// --------------------------------------------------
//  DEFLATE: stored + fixed-Huffman inflater (own)
// --------------------------------------------------

fn _pow2(n: Int) -> Int {
  var m = 1;
  var i = 0;
  while i < n {
    m = m * 2;
    i = i + 1;
  };
  return m;
}

fn _if_len_base(code: Int) -> Int {
  if code >= 281 {
    if code == 285 {
      return 258;
    };
    return 131 + (code - 281) * 32;
  };
  if code >= 277 {
    return 67 + (code - 277) * 16;
  };
  if code >= 273 {
    return 35 + (code - 273) * 8;
  };
  if code >= 269 {
    return 19 + (code - 269) * 4;
  };
  if code >= 265 {
    return 11 + (code - 265) * 2;
  };
  return 3 + (code - 257);
}

fn _if_len_extra(code: Int) -> Int {
  if code < 265 || code == 285 {
    return 0;
  };
  if code < 269 {
    return 1;
  };
  if code < 273 {
    return 2;
  };
  if code < 277 {
    return 3;
  };
  if code < 281 {
    return 4;
  };
  return 5;
}

fn _if_dist_base(code: Int) -> Int {
  if code < 4 {
    return code + 1;
  };
  if code < 6 {
    return 5 + (code - 4) * 2;
  };
  if code < 8 {
    return 9 + (code - 6) * 4;
  };
  if code < 10 {
    return 17 + (code - 8) * 8;
  };
  if code < 12 {
    return 33 + (code - 10) * 16;
  };
  if code < 14 {
    return 65 + (code - 12) * 32;
  };
  if code < 16 {
    return 129 + (code - 14) * 64;
  };
  if code < 18 {
    return 257 + (code - 16) * 128;
  };
  if code < 20 {
    return 513 + (code - 18) * 256;
  };
  if code < 22 {
    return 1025 + (code - 20) * 512;
  };
  if code < 24 {
    return 2049 + (code - 22) * 1024;
  };
  if code < 26 {
    return 4097 + (code - 24) * 2048;
  };
  if code < 28 {
    return 8193 + (code - 26) * 4096;
  };
  return 16385 + (code - 28) * 8192;
}

fn _if_dist_extra(code: Int) -> Int {
  if code < 4 {
    return 0;
  };
  if code < 26 {
    return 1 + (code - 4) / 2;
  };
  return 13;
}

// One bit at absolute LSB-first bit position `bp`; -1 when out of range.
fn _bit_at(data: &Vec[UInt8], bp: Int) -> Int {
  let byte_idx = bp / 8;
  if byte_idx < 0 || byte_idx >= data.len() {
    return -1;
  };
  let raw: UInt8 = data[byte_idx];
  let b = (raw as Int) & 0xFF;
  var m = 1;
  var j = 0;
  let bit_in_byte = bp % 8;
  while j < bit_in_byte {
    m = m * 2;
    j = j + 1;
  };
  return (b / m) % 2;
}

// Value of `count` bits starting at `pos`, most significant bit first
// (Huffman code order); -1 when the stream is exhausted.
fn _peek_msb(data: &Vec[UInt8], pos: Int, count: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < count {
    let bit = _bit_at(data, pos + i);
    if bit < 0 {
      return -1;
    };
    v = v * 2 + bit;
    i = i + 1;
  };
  return v;
}

// Value of `count` bits starting at `pos`, least significant bit first
// (integer field order: block header and the length/distance extra bits);
// -1 when the stream is exhausted.
fn _peek_lsb(data: &Vec[UInt8>, pos: Int, count: Int) -> Int {
  var v = 0;
  var mult = 1;
  var i = 0;
  while i < count {
    let bit = _bit_at(data, pos + i);
    if bit < 0 {
      return -1;
    };
    v = v + bit * mult;
    mult = mult * 2;
    i = i + 1;
  };
  return v;
}

// Decode one fixed-Huffman literal/length symbol. Returns (symbol, bits)
// or (-1, 0) on truncation/invalid code.
fn _fx_decode(data: &Vec[UInt8], pos: Int) -> (Int, Int) {
  let v7 = _peek_msb(data, pos, 7);
  if v7 < 0 {
    return (-1, 0);
  };
  if v7 <= 0x17 {
    return (256 + v7, 7);
  };
  let v8 = _peek_msb(data, pos, 8);
  if v8 < 0 {
    return (-1, 0);
  };
  if v8 >= 0x30 && v8 <= 0xBF {
    return (v8 - 0x30, 8);
  };
  if v8 >= 0xC0 && v8 <= 0xC7 {
    return (280 + (v8 - 0xC0), 8);
  };
  let v9 = _peek_msb(data, pos, 9);
  if v9 < 0 {
    return (-1, 0);
  };
  if v9 >= 0x190 && v9 <= 0x1FF {
    return (144 + (v9 - 0x190), 9);
  };
  return (-1, 0);
}

/// Inflate a raw DEFLATE stream with only STORED and FIXED-Huffman block
/// support. Err on dynamic/unknown blocks (the documented limitation).
/// `max_out` is a hard output ceiling.
pub fn docx_inflate_fixed(data: &Vec[UInt8], max_out: Int) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let bit_limit = data.len() * 8 + 64;
  var pos = 0;
  var done = false;
  var blocks = 0;
  while !done {
    blocks = blocks + 1;
    if blocks > 1000000 {
      return _err_bytes("docx: deflate block limit exceeded");
    };
    if pos > bit_limit {
      return _err_bytes("docx: deflate truncated");
    };
    let hdr = _peek_lsb(data, pos, 3);
    if hdr < 0 {
      return _err_bytes("docx: deflate truncated");
    };
    let bfinal = hdr % 2;
    let btype = (hdr / 2) % 4;
    pos = pos + 3;
    if btype == 0 {
      // Stored block: skip to a byte boundary, then LEN/NLEN/raw bytes.
      pos = ((pos + 7) / 8) * 8;
      let bi = pos / 8;
      if bi + 4 > data.len() {
        return _err_bytes("docx: deflate truncated");
      };
      let l0: UInt8 = data[bi];
      let l1: UInt8 = data[bi + 1];
      let n0: UInt8 = data[bi + 2];
      let n1: UInt8 = data[bi + 3];
      let blen = ((l0 as Int) & 0xFF) + ((l1 as Int) & 0xFF) * 256;
      let bnlen = ((n0 as Int) & 0xFF) + ((n1 as Int) & 0xFF) * 256;
      if (blen ^ 65535) != bnlen {
        return _err_bytes("docx: deflate stored length mismatch");
      };
      if bi + 4 + blen > data.len() {
        return _err_bytes("docx: deflate truncated");
      };
      if out.len() + blen > max_out {
        return _err_bytes("docx: deflate output cap exceeded");
      };
      var k = 0;
      while k < blen {
        out.push(data[bi + 4 + k]);
        k = k + 1;
      };
      pos = (bi + 4 + blen) * 8;
    } else if btype == 1 {
      var stream_done = false;
      while !stream_done {
        if pos > bit_limit {
          return _err_bytes("docx: deflate truncated");
        };
        let lit = _fx_decode(data, pos);
        let sym = lit.0;
        if sym < 0 {
          return _err_bytes("docx: deflate truncated");
        };
        pos = pos + lit.1;
        if sym == 256 {
          stream_done = true;
        } else if sym < 256 {
          if out.len() >= max_out {
            return _err_bytes("docx: deflate output cap exceeded");
          };
          out.push((sym as UInt8));
        } else {
          if sym > 285 {
            return _err_bytes("docx: deflate bad length symbol");
          };
          let le = _if_len_extra(sym);
          let ev = _peek_lsb(data, pos, le);
          if ev < 0 {
            return _err_bytes("docx: deflate truncated");
          };
          pos = pos + le;
          let mlen = _if_len_base(sym) + ev;
          let d5 = _peek_msb(data, pos, 5);
          if d5 < 0 {
            return _err_bytes("docx: deflate truncated");
          };
          if d5 >= 30 {
            return _err_bytes("docx: deflate bad distance symbol");
          };
          pos = pos + 5;
          let de = _if_dist_extra(d5);
          let dv = _peek_lsb(data, pos, de);
          if dv < 0 {
            return _err_bytes("docx: deflate truncated");
          };
          pos = pos + de;
          let mdist = _if_dist_base(d5) + dv;
          if mdist > out.len() {
            return _err_bytes("docx: deflate bad distance");
          };
          if out.len() + mlen > max_out {
            return _err_bytes("docx: deflate output cap exceeded");
          };
          var k2 = 0;
          while k2 < mlen {
            out.push(out[out.len() - mdist]);
            k2 = k2 + 1;
          };
        };
      };
    } else {
      if btype == 2 {
        return _err_bytes("docx: deflate dynamic huffman unsupported");
      };
      return _err_bytes("docx: deflate reserved block");
    };
    if bfinal == 1 {
      done = true;
    };
  };
  return _ok_bytes(out);
}

/// Inflate a raw DEFLATE stream: try the stdlib `deflate_decompress_capped`
/// first (stored + fixed + simple dynamic), then fall back to this module's
/// stored + fixed-Huffman inflater.
pub fn docx_inflate_raw(data: &Vec[UInt8], max_out: Int) -> Result[Vec[UInt8], Str] {
  let r = deflate.deflate_decompress_capped(data, max_out);
  if r.is_ok {
    let payload: Vec[UInt8] = r.value;
    return _ok_bytes(payload);
  };
  return docx_inflate_fixed(data, max_out);
}

// --------------------------------------------------
//  ZIP writer
// --------------------------------------------------

/// Streaming ZIP writer state. Entries are appended with
/// `docx_zip_writer_add`; `docx_zip_writer_finish` materializes the final
/// archive (local headers + data, central directory, EOCD).
///
/// Invariant: `name_off`/`name_len`/`methods`/`crcs`/`comp_sizes`/
/// `uncomp_sizes`/`offs` all have exactly `count` elements; every add
/// mirrors each push. `name_off`/`name_len` address `name_pool`.
pub type DocxZipWriter = {
  local: Vec[UInt8];
  central: Vec[UInt8];
  name_pool: Vec[UInt8];
  name_off: Vec[Int];
  name_len: Vec[Int];
  methods: Vec[Int];
  crcs: Vec[Int];
  comp_sizes: Vec[Int];
  uncomp_sizes: Vec[Int];
  offs: Vec[Int];
  count: Int;
}

/// New empty ZIP writer.
pub fn docx_zip_writer_new() -> DocxZipWriter {
  return DocxZipWriter{
    local: Vec[UInt8].new();
    central: Vec[UInt8].new();
    name_pool: Vec[UInt8].new();
    name_off: Vec[Int].new();
    name_len: Vec[Int].new();
    methods: Vec[Int].new();
    crcs: Vec[Int].new();
    comp_sizes: Vec[Int].new();
    uncomp_sizes: Vec[Int].new();
    offs: Vec[Int].new();
    count: 0;
  };
}

/// Number of entries added so far.
pub fn docx_zip_writer_count(w: &DocxZipWriter) -> Int {
  return w.count;
}

/// Append one entry. `level <= 0` stores `data` verbatim (method 0);
/// `level` 1..9 compresses with the stdlib fixed-Huffman DEFLATE encoder
/// (method 8). Entry names must be printable ASCII.
pub fn docx_zip_writer_add(w: &mut DocxZipWriter, name: Str, data: &Vec[UInt8], level: Int) {
  let uncomp_len = data.len();
  var method = 0;
  var comp = Vec[UInt8].new();
  if level > 0 {
    method = 8;
    comp = deflate.deflate_compress_level(data, level);
  } else {
    var i = 0;
    while i < uncomp_len {
      comp.push(data[i]);
      i = i + 1;
    };
  };
  let comp_len = comp.len();
  let crc = _crc32(data);
  let nlen = string.str_len(name);
  let local_off = w.local.len();

  // Local file header (built in a local first: trap 4/12).
  var lh = Vec[UInt8].new();
  _push_le(&mut lh, _ZIP_LOCAL_SIG, 4);
  _push_le(&mut lh, 20, 2);          // version needed
  _push_le(&mut lh, 0, 2);           // general purpose flags
  _push_le(&mut lh, method, 2);      // compression method
  _push_le(&mut lh, 0, 2);           // last mod time
  _push_le(&mut lh, _DOCX_DOS_DATE, 2);
  _push_le(&mut lh, crc, 4);
  _push_le(&mut lh, comp_len, 4);
  _push_le(&mut lh, uncomp_len, 4);
  _push_le(&mut lh, nlen, 2);
  _push_le(&mut lh, 0, 2);           // extra length
  let nr0 = _put_str(&mut lh, name);
  if !nr0.is_ok {
    return;
  };
  var i2 = 0;
  while i2 < lh.len() {
    w.local.push(lh[i2]);
    i2 = i2 + 1;
  };
  i2 = 0;
  while i2 < comp_len {
    w.local.push(comp[i2]);
    i2 = i2 + 1;
  };

  // Central directory entry.
  var ce = Vec[UInt8].new();
  _push_le(&mut ce, _ZIP_CENTRAL_SIG, 4);
  _push_le(&mut ce, 20, 2);          // version made by
  _push_le(&mut ce, 20, 2);          // version needed
  _push_le(&mut ce, 0, 2);           // flags
  _push_le(&mut ce, method, 2);
  _push_le(&mut ce, 0, 2);           // time
  _push_le(&mut ce, _DOCX_DOS_DATE, 2);
  _push_le(&mut ce, crc, 4);
  _push_le(&mut ce, comp_len, 4);
  _push_le(&mut ce, uncomp_len, 4);
  _push_le(&mut ce, nlen, 2);
  _push_le(&mut ce, 0, 2);           // extra length
  _push_le(&mut ce, 0, 2);           // comment length
  _push_le(&mut ce, 0, 2);           // disk number start
  _push_le(&mut ce, 0, 2);           // internal attributes
  _push_le(&mut ce, 0, 4);           // external attributes
  _push_le(&mut ce, local_off, 4);
  let nr1 = _put_str(&mut ce, name);
  if !nr1.is_ok {
    return;
  };
  i2 = 0;
  while i2 < ce.len() {
    w.central.push(ce[i2]);
    i2 = i2 + 1;
  };

  // Mirror every bookkeeping push (trap 16).
  let noff = w.name_pool.len();
  var k = 0;
  while k < nlen {
    w.name_pool.push(string.byte_at(name, k));
    k = k + 1;
  };
  w.name_off.push(noff);
  w.name_len.push(nlen);
  w.methods.push(method);
  w.crcs.push(crc);
  w.comp_sizes.push(comp_len);
  w.uncomp_sizes.push(uncomp_len);
  w.offs.push(local_off);
  w.count = w.count + 1;
}

/// Materialize the archive: local data, central directory, EOCD.
pub fn docx_zip_writer_finish(w: &mut DocxZipWriter) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < w.local.len() {
    out.push(w.local[i]);
    i = i + 1;
  };
  let cd_off = out.len();
  i = 0;
  while i < w.central.len() {
    out.push(w.central[i]);
    i = i + 1;
  };
  let cd_size = w.central.len();
  _push_le(&mut out, _ZIP_EOCD_SIG, 4);
  _push_le(&mut out, 0, 2);          // disk number
  _push_le(&mut out, 0, 2);          // central directory start disk
  _push_le(&mut out, w.count, 2);    // entries on this disk
  _push_le(&mut out, w.count, 2);    // total entries
  _push_le(&mut out, cd_size, 4);
  _push_le(&mut out, cd_off, 4);
  _push_le(&mut out, 0, 2);          // comment length
  return out;
}

// --------------------------------------------------
//  ZIP reader
// --------------------------------------------------

/// Parsed ZIP archive. All per-entry data lives in parallel vectors
/// (never Vec[StructType]); `name_off`/`name_len` address `name_pool`,
/// `pool_off`/`pool_len` address `data_pool` (decompressed payloads).
pub type DocxZip = {
  name_pool: Vec[UInt8];
  name_off: Vec[Int];
  name_len: Vec[Int];
  methods: Vec[Int];
  crcs: Vec[Int];
  comp_sizes: Vec[Int];
  uncomp_sizes: Vec[Int];
  local_offs: Vec[Int];
  payload_off: Vec[Int];
  pool_off: Vec[Int];
  pool_len: Vec[Int];
  data_pool: Vec[UInt8];
}

/// Parse a ZIP archive: EOCD scan, central directory, local headers, entry
/// decompression (stored + deflate), and CRC-32 verification.
pub fn docx_zip_open(data: &Vec[UInt8]) -> Result[DocxZip, Str] {
  let n = data.len();
  if n < 22 {
    return _zip_err("docx: zip too small");
  };
  var eocd = -1;
  var scan = n - 22;
  var floor = n - 22 - 65535;
  if floor < 0 {
    floor = 0;
  };
  while scan >= floor {
    if _le32_at(data, scan) == _ZIP_EOCD_SIG {
      eocd = scan;
      break;
    };
    scan = scan - 1;
  };
  if eocd < 0 {
    return _zip_err("docx: end of central directory not found");
  };
  let disk_no = _le16_at(data, eocd + 4);
  let cd_disk = _le16_at(data, eocd + 6);
  let entries_disk = _le16_at(data, eocd + 8);
  let entries_total = _le16_at(data, eocd + 10);
  let cd_size = _le32_at(data, eocd + 12);
  let cd_off = _le32_at(data, eocd + 16);
  if disk_no != 0 || cd_disk != 0 || entries_disk != entries_total {
    return _zip_err("docx: multi-disk zip not supported");
  };
  if cd_off > n || cd_size > n || cd_off + cd_size > n {
    return _zip_err("docx: central directory out of bounds");
  };
  var z = DocxZip{
    name_pool: Vec[UInt8].new();
    name_off: Vec[Int].new();
    name_len: Vec[Int].new();
    methods: Vec[Int].new();
    crcs: Vec[Int].new();
    comp_sizes: Vec[Int].new();
    uncomp_sizes: Vec[Int].new();
    local_offs: Vec[Int].new();
    payload_off: Vec[Int].new();
    pool_off: Vec[Int].new();
    pool_len: Vec[Int].new();
    data_pool: Vec[UInt8].new();
  };
  var pos = cd_off;
  var i = 0;
  while i < entries_total {
    if pos + 46 > n {
      return _zip_err("docx: truncated central directory");
    };
    if _le32_at(data, pos) != _ZIP_CENTRAL_SIG {
      return _zip_err("docx: bad central directory signature");
    };
    let method = _le16_at(data, pos + 10);
    let crc = _le32_at(data, pos + 16);
    let csize = _le32_at(data, pos + 20);
    let usize_v = _le32_at(data, pos + 24);
    let nlen = _le16_at(data, pos + 28);
    let elen = _le16_at(data, pos + 30);
    let clen = _le16_at(data, pos + 32);
    let loff = _le32_at(data, pos + 42);
    if pos + 46 + nlen + elen + clen > n {
      return _zip_err("docx: truncated central directory");
    };
    let noff = z.name_pool.len();
    var k = 0;
    while k < nlen {
      let nb: UInt8 = data[pos + 46 + k];
      let nbv = (nb as Int) & 0xFF;
      if nbv == 0 {
        return _zip_err("docx: entry name contains nul");
      };
      if nbv < 32 || nbv > 126 {
        return _zip_err("docx: non-ascii entry name");
      };
      z.name_pool.push(nb);
      k = k + 1;
    };
    if loff + 30 > n {
      return _zip_err("docx: local file header out of bounds");
    };
    if _le32_at(data, loff) != _ZIP_LOCAL_SIG {
      return _zip_err("docx: bad local file header signature");
    };
    let l_nlen = _le16_at(data, loff + 26);
    let l_elen = _le16_at(data, loff + 28);
    let p_off = loff + 30 + l_nlen + l_elen;
    if p_off > n || csize > n || p_off + csize > n {
      return _zip_err("docx: entry data out of bounds");
    };
    var payload = Vec[UInt8].new();
    if method == 0 {
      if csize > _DOCX_MAX_ENTRY {
        return _zip_err("docx: entry too large");
      };
      payload = _copy_range(data, p_off, p_off + csize);
    } else if method == 8 {
      if usize_v > _DOCX_MAX_ENTRY || csize > _DOCX_MAX_ENTRY {
        return _zip_err("docx: entry too large");
      };
      let comp = _copy_range(data, p_off, p_off + csize);
      let ir = docx_inflate_raw(&comp, usize_v);
      if !ir.is_ok {
        return _zip_err(ir.error);
      };
      payload = ir.value;
      if payload.len() != usize_v {
        return _zip_err("docx: entry size mismatch");
      };
    } else {
      return _zip_err("docx: unsupported compression method " + convert.int_to_string(method));
    };
    if _crc32(&payload) != crc {
      return _zip_err("docx: crc mismatch");
    };
    let poff = z.data_pool.len();
    var j = 0;
    while j < payload.len() {
      z.data_pool.push(payload[j]);
      j = j + 1;
    };
    z.name_off.push(noff);
    z.name_len.push(nlen);
    z.methods.push(method);
    z.crcs.push(crc);
    z.comp_sizes.push(csize);
    z.uncomp_sizes.push(usize_v);
    z.local_offs.push(loff);
    z.payload_off.push(p_off);
    z.pool_off.push(poff);
    z.pool_len.push(payload.len());
    pos = pos + 46 + nlen + elen + clen;
    i = i + 1;
  };
  return _zip_ok(z);
}

/// Number of entries in a parsed archive.
pub fn docx_zip_count(z: &DocxZip) -> Int {
  return z.pool_off.len();
}

/// Name of entry `i` as a Str (entry index-checked).
pub fn docx_zip_entry_name(z: &DocxZip, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= z.pool_off.len() {
    return _err_str("docx: entry index out of range");
  };
  let off: Int = z.name_off[i];
  let ln: Int = z.name_len[i];
  if off < 0 || ln < 0 || off + ln > z.name_pool.len() {
    return _err_str("docx: inconsistent zip model");
  };
  var buf = Vec[UInt8].new();
  var k = 0;
  while k < ln {
    let b: UInt8 = z.name_pool[off + k];
    if (((b as Int) & 0xFF) == 0) {
      return _err_str("docx: nul byte in entry name");
    };
    buf.push(b);
    k = k + 1;
  };
  return _ok_str(builder.sb_to_str(&buf));
}

/// Index of the entry named `name`, or -1.
pub fn docx_zip_find(z: &DocxZip, name: Str) -> Int {
  let nlen = string.str_len(name);
  var i = 0;
  while i < z.pool_off.len() {
    let off: Int = z.name_off[i];
    let ln: Int = z.name_len[i];
    if ln == nlen && off >= 0 && off + ln <= z.name_pool.len() {
      var ok = true;
      var k = 0;
      while k < nlen {
        let b: UInt8 = z.name_pool[off + k];
        let s: UInt8 = string.byte_at(name, k);
        if b != s {
          ok = false;
          k = nlen;
        } else {
          k = k + 1;
        };
      };
      if ok {
        return i;
      };
    };
    i = i + 1;
  };
  return -1;
}

/// Decompressed payload of entry `i` (entry index-checked).
pub fn docx_zip_entry_data(z: &DocxZip, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= z.pool_off.len() {
    return _err_bytes("docx: entry index out of range");
  };
  let off: Int = z.pool_off[i];
  let ln: Int = z.pool_len[i];
  if off < 0 || ln < 0 || off + ln > z.data_pool.len() {
    return _err_bytes("docx: inconsistent zip model");
  };
  var out = Vec[UInt8].new();
  var k = 0;
  while k < ln {
    out.push(z.data_pool[off + k]);
    k = k + 1;
  };
  return _ok_bytes(out);
}

/// Compression method of entry `i` (0 stored, 8 deflate).
pub fn docx_zip_entry_method(z: &DocxZip, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= z.pool_off.len() {
    return _err_int("docx: entry index out of range");
  };
  let v: Int = z.methods[i];
  return _ok_int(v);
}

/// Uncompressed size of entry `i`.
pub fn docx_zip_entry_size(z: &DocxZip, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= z.pool_off.len() {
    return _err_int("docx: entry index out of range");
  };
  let v: Int = z.uncomp_sizes[i];
  return _ok_int(v);
}

/// Stored CRC-32 of entry `i` (0..4294967295).
pub fn docx_zip_entry_crc(z: &DocxZip, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= z.pool_off.len() {
    return _err_int("docx: entry index out of range");
  };
  let v: Int = z.crcs[i];
  return _ok_int(v);
}

// --------------------------------------------------
//  Document model (docx-read / docx-write / docx-style)
// --------------------------------------------------

/// A parsed or built WordprocessingML document.
///
/// Paragraphs are flat: paragraph `p` owns runs
/// `para_start[p] .. para_start[p] + para_count[p]` in the run arrays.
/// Run `r` owns `text[run_off[r] .. run_off[r] + run_len[r]]` in the single
/// concatenated UTF-8 buffer. Styles: bold, italic, and `run_size` in
/// half-points (0 = unspecified/default).
pub type DocxDoc = {
  para_start: Vec[Int];
  para_count: Vec[Int];
  run_off: Vec[Int];
  run_len: Vec[Int];
  run_bold: Vec[Bool];
  run_italic: Vec[Bool];
  run_size: Vec[Int];
  text: Str;
  text_len: Int;
}

/// Package version string.
pub fn docx_version() -> Str {
  return "0.1.0";
}

/// Convert points to WordprocessingML half-points.
pub fn docx_points_to_half(points: Int) -> Int {
  return points * 2;
}

/// Convert half-points to points (truncating toward zero).
pub fn docx_half_to_points(half: Int) -> Int {
  return half / 2;
}

/// New empty document (no paragraphs, no runs).
pub fn docx_new() -> DocxDoc {
  return DocxDoc{
    para_start: Vec[Int].new();
    para_count: Vec[Int].new();
    run_off: Vec[Int].new();
    run_len: Vec[Int].new();
    run_bold: Vec[Bool].new();
    run_italic: Vec[Bool].new();
    run_size: Vec[Int].new();
    text: "";
    text_len: 0;
  };
}

/// Append an empty paragraph.
pub fn docx_add_paragraph(doc: &mut DocxDoc) {
  doc.para_start.push(doc.run_off.len());
  doc.para_count.push(0);
}

/// Append a run with `text` and the style subset to the last paragraph
/// (a paragraph is created when the document has none). `size` is in
/// half-points; values <= 0 mean unspecified.
pub fn docx_add_run(doc: &mut DocxDoc, text: Str, bold: Bool, italic: Bool, size: Int) {
  if doc.para_start.len() == 0 {
    doc.para_start.push(doc.run_off.len());
    doc.para_count.push(0);
  };
  let n = string.str_len(text);
  doc.run_off.push(doc.text_len);
  doc.run_len.push(n);
  doc.run_bold.push(bold);
  doc.run_italic.push(italic);
  doc.run_size.push(size);
  doc.text = doc.text + text;
  doc.text_len = doc.text_len + n;
  let last = doc.para_count.len() - 1;
  doc.para_count[last] = doc.para_count[last] + 1;
}

/// Number of paragraphs.
pub fn docx_paragraph_count(doc: &DocxDoc) -> Int {
  return doc.para_start.len();
}

/// Number of runs across all paragraphs.
pub fn docx_run_count(doc: &DocxDoc) -> Int {
  return doc.run_off.len();
}

/// Number of runs in paragraph `p`.
pub fn docx_para_run_count(doc: &DocxDoc, p: Int) -> Result[Int, Str] {
  if p < 0 || p >= doc.para_start.len() {
    return _err_int("docx: paragraph index out of range");
  };
  let v: Int = doc.para_count[p];
  return _ok_int(v);
}

/// Text of paragraph `p` (all runs concatenated).
pub fn docx_paragraph_text(doc: &DocxDoc, p: Int) -> Result[Str, Str] {
  if p < 0 || p >= doc.para_start.len() {
    return _err_str("docx: paragraph index out of range");
  };
  let rs: Int = doc.para_start[p];
  let rc: Int = doc.para_count[p];
  if rs < 0 || rc < 0 || rs + rc > doc.run_off.len() {
    return _err_str("docx: inconsistent document model");
  };
  let t: Str = doc.text;
  var buf = Vec[UInt8].new();
  var r = 0;
  while r < rc {
    let ri = rs + r;
    let off: Int = doc.run_off[ri];
    let ln: Int = doc.run_len[ri];
    if off < 0 || ln < 0 || off + ln > doc.text_len {
      return _err_str("docx: inconsistent document model");
    };
    var k = 0;
    while k < ln {
      let b: UInt8 = string.byte_at(t, off + k);
      if (((b as Int) & 0xFF) == 0) {
        return _err_str("docx: nul byte in text");
      };
      buf.push(b);
      k = k + 1;
    };
    r = r + 1;
  };
  return _ok_str(builder.sb_to_str(&buf));
}

/// Text of run `r`.
pub fn docx_run_text(doc: &DocxDoc, r: Int) -> Result[Str, Str] {
  if r < 0 || r >= doc.run_off.len() {
    return _err_str("docx: run index out of range");
  };
  let off: Int = doc.run_off[r];
  let ln: Int = doc.run_len[r];
  if off < 0 || ln < 0 || off + ln > doc.text_len {
    return _err_str("docx: inconsistent document model");
  };
  let t: Str = doc.text;
  var buf = Vec[UInt8].new();
  var k = 0;
  while k < ln {
    let b: UInt8 = string.byte_at(t, off + k);
    if (((b as Int) & 0xFF) == 0) {
      return _err_str("docx: nul byte in text");
    };
    buf.push(b);
    k = k + 1;
  };
  return _ok_str(builder.sb_to_str(&buf));
}

/// Bold flag of run `r`.
pub fn docx_run_bold(doc: &DocxDoc, r: Int) -> Result[Bool, Str] {
  if r < 0 || r >= doc.run_off.len() {
    return _err_bool("docx: run index out of range");
  };
  let v: Bool = doc.run_bold[r];
  return _ok_bool(v);
}

/// Italic flag of run `r`.
pub fn docx_run_italic(doc: &DocxDoc, r: Int) -> Result[Bool, Str] {
  if r < 0 || r >= doc.run_off.len() {
    return _err_bool("docx: run index out of range");
  };
  let v: Bool = doc.run_italic[r];
  return _ok_bool(v);
}

/// Half-point size of run `r` (0 = unspecified).
pub fn docx_run_size(doc: &DocxDoc, r: Int) -> Result[Int, Str] {
  if r < 0 || r >= doc.run_off.len() {
    return _err_int("docx: run index out of range");
  };
  let v: Int = doc.run_size[r];
  return _ok_int(v);
}

// --------------------------------------------------
//  WordprocessingML: document.xml writer
// --------------------------------------------------

// Append `count` bytes of `s` starting at `start`, escaping XML markup
// characters and rejecting control characters invalid in XML 1.0.
fn _put_escaped(out: &mut Vec[UInt8], s: Str, start: Int, count: Int) -> Result[Bool, Str] {
  var k = 0;
  while k < count {
    let b8: UInt8 = string.byte_at(s, start + k);
    let b = (b8 as Int) & 0xFF;
    if b == 0 {
      return _err_bool("docx: nul byte in text");
    };
    if b == 0x26 {
      let r1 = _put_str(out, "&amp;");
      if !r1.is_ok {
        return _err_bool(r1.error);
      };
    } else if b == 0x3C {
      let r2 = _put_str(out, "&lt;");
      if !r2.is_ok {
        return _err_bool(r2.error);
      };
    } else if b == 0x3E {
      let r3 = _put_str(out, "&gt;");
      if !r3.is_ok {
        return _err_bool(r3.error);
      };
    } else if b == 0x22 {
      let r4 = _put_str(out, "&quot;");
      if !r4.is_ok {
        return _err_bool(r4.error);
      };
    } else if b == 0x27 {
      let r5 = _put_str(out, "&apos;");
      if !r5.is_ok {
        return _err_bool(r5.error);
      };
    } else if b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D {
      return _err_bool("docx: control character in text");
    } else {
      out.push(b8);
    };
    k = k + 1;
  };
  return _ok_bool(true);
}

// Build word/document.xml for `doc`.
fn _docx_document_xml(doc: &DocxDoc) -> Result[Vec[UInt8], Str] {
  let text: Str = doc.text;
  var out = Vec[UInt8].new();
  _put_str(&mut out, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>");
  _put_str(&mut out, "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>");
  let pc = doc.para_start.len();
  var p = 0;
  while p < pc {
    let rs: Int = doc.para_start[p];
    let rc: Int = doc.para_count[p];
    if rs < 0 || rc < 0 || rs + rc > doc.run_off.len() {
      return _err_bytes("docx: inconsistent document model");
    };
    _put_str(&mut out, "<w:p>");
    var r = 0;
    while r < rc {
      let ri = rs + r;
      let off: Int = doc.run_off[ri];
      let ln: Int = doc.run_len[ri];
      let bl: Bool = doc.run_bold[ri];
      let it: Bool = doc.run_italic[ri];
      let sz: Int = doc.run_size[ri];
      if off < 0 || ln < 0 || off + ln > doc.text_len {
        return _err_bytes("docx: inconsistent document model");
      };
      _put_str(&mut out, "<w:r>");
      if bl || it || sz > 0 {
        _put_str(&mut out, "<w:rPr>");
        if bl {
          _put_str(&mut out, "<w:b/>");
        };
        if it {
          _put_str(&mut out, "<w:i/>");
        };
        if sz > 0 {
          _put_str(&mut out, "<w:sz w:val=\"");
          builder.sb_push_int(&mut out, sz);
          _put_str(&mut out, "\"/>");
        };
        _put_str(&mut out, "</w:rPr>");
      };
      _put_str(&mut out, "<w:t xml:space=\"preserve\">");
      let er = _put_escaped(&mut out, text, off, ln);
      if !er.is_ok {
        return _err_bytes(er.error);
      };
      _put_str(&mut out, "</w:t></w:r>");
      r = r + 1;
    };
    _put_str(&mut out, "</w:p>");
    p = p + 1;
  };
  _put_str(&mut out, "<w:sectPr/></w:body></w:document>");
  return _ok_bytes(out);
}

/// Serialize `doc` to a .docx byte container with DEFLATE level 6 for
/// `word/document.xml`.
pub fn docx_to_bytes(doc: &DocxDoc) -> Result[Vec[UInt8], Str] {
  return docx_to_bytes_level(doc, 6);
}

/// Serialize `doc`; `level <= 0` stores every part (ZIP method 0),
/// `level` 1..9 deflates `word/document.xml`.
pub fn docx_to_bytes_level(doc: &DocxDoc, level: Int) -> Result[Vec[UInt8], Str] {
  let dr = _docx_document_xml(doc);
  if !dr.is_ok {
    return _err_bytes(dr.error);
  };
  let xml: Vec[UInt8] = dr.value;

  var ct = Vec[UInt8].new();
  _put_str(&mut ct, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>");
  _put_str(&mut ct, "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>");

  var rels = Vec[UInt8].new();
  _put_str(&mut rels, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>");
  _put_str(&mut rels, "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>");

  var w = docx_zip_writer_new();
  docx_zip_writer_add(&mut w, "[Content_Types].xml", &ct, 0);
  docx_zip_writer_add(&mut w, "_rels/.rels", &rels, 0);
  docx_zip_writer_add(&mut w, "word/document.xml", &xml, level);
  return _ok_bytes(docx_zip_writer_finish(&mut w));
}

// --------------------------------------------------
//  WordprocessingML: document.xml reader
// --------------------------------------------------

// True when the tag starting at `<` (index `lt`) has exactly this name
// (opening "w:t" or closing "/w:t") followed by a name delimiter.
fn _tag_name_is(xml: &Vec[UInt8], lt: Int, name: Str) -> Bool {
  let nlen = string.str_len(name);
  var k = 0;
  while k < nlen {
    let i = lt + 1 + k;
    if i >= xml.len() {
      return false;
    };
    let b: UInt8 = xml[i];
    let sv: UInt8 = string.byte_at(name, k);
    if b != sv {
      return false;
    };
    k = k + 1;
  };
  let e = lt + 1 + nlen;
  if e >= xml.len() {
    return false;
  };
  let c: UInt8 = xml[e];
  let cv = (c as Int) & 0xFF;
  if cv == 0x3E || cv == 0x2F || cv == 0x20 {
    return true;
  };
  if cv == 0x09 || cv == 0x0A || cv == 0x0D {
    return true;
  };
  return false;
}

// Index just past the '>' of the tag starting at `lt`, or -1.
fn _tag_end(xml: &Vec[UInt8], lt: Int) -> Int {
  var i = lt + 1;
  while i < xml.len() {
    let b: UInt8 = xml[i];
    if (((b as Int) & 0xFF) == 0x3E) {
      return i + 1;
    };
    i = i + 1;
  };
  return -1;
}

// Name of the tag starting at `lt` (without `<`, `/`, attributes).
fn _tag_name_str(xml: &Vec[UInt8], lt: Int, gt: Int) -> Result[Str, Str] {
  var buf = Vec[UInt8].new();
  var i = lt + 1;
  if i < gt {
    let c0: UInt8 = xml[i];
    if (((c0 as Int) & 0xFF) == 0x2F) {
      i = i + 1;
    };
  };
  while i < gt {
    let b: UInt8 = xml[i];
    let bv = (b as Int) & 0xFF;
    if bv == 0x3E || bv == 0x2F || bv == 0x20 {
      break;
    };
    if bv == 0x09 || bv == 0x0A || bv == 0x0D {
      break;
    };
    if bv == 0 {
      return _err_str("docx: nul byte in xml");
    };
    buf.push(b);
    i = i + 1;
  };
  if buf.len() == 0 {
    return _err_str("docx: malformed xml");
  };
  return _ok_str(builder.sb_to_str(&buf));
}

// Index just past the matching `</name>` starting at `from`, or -1.
fn _skip_to_close(xml: &Vec[UInt8], from: Int, n: Int, name: Str) -> Int {
  var pat = Vec[UInt8].new();
  _put_str(&mut pat, "</");
  _put_str(&mut pat, name);
  _put_str(&mut pat, ">");
  let p = _find_sub(xml, from, n, &pat);
  if p < 0 {
    return -1;
  };
  return p + pat.len();
}

// Read a decimal integer attribute `name` (e.g. "w:val=\"") inside the tag
// spanning [lt, gt), or -1 when absent/non-numeric.
fn _attr_int(xml: &Vec[UInt8>, lt: Int, gt: Int, name: Str) -> Int {
  let p = _find_str_range(xml, lt, gt, name);
  if p < 0 {
    return -1;
  };
  var q = p + string.str_len(name);
  var v = 0;
  var digits = 0;
  while q < gt {
    let b: UInt8 = xml[q];
    let bv = (b as Int) & 0xFF;
    if bv >= 48 && bv <= 57 {
      v = v * 10 + (bv - 48);
      digits = digits + 1;
      q = q + 1;
    } else if bv == 0x22 {
      break;
    } else {
      return -1;
    };
  };
  if digits == 0 {
    return -1;
  };
  return v;
}

// True when xml[start, end) spells exactly `name`.
fn _entity_is(xml: &Vec[UInt8>, start: Int, end: Int, name: Str) -> Bool {
  let nlen = string.str_len(name);
  if end - start != nlen {
    return false;
  };
  var k = 0;
  while k < nlen {
    let b: UInt8 = xml[start + k];
    let sv: UInt8 = string.byte_at(name, k);
    if b != sv {
      return false;
    };
    k = k + 1;
  };
  return true;
}

// Append code point `cp` as UTF-8. Caller validates the range.
fn _push_utf8(out: &mut Vec[UInt8], cp: Int) {
  if cp < 0x80 {
    out.push((cp % 256) as UInt8);
    return;
  };
  if cp < 0x800 {
    out.push(((0xC0 + cp / 64) % 256) as UInt8);
    out.push(((0x80 + cp % 64) % 256) as UInt8);
    return;
  };
  if cp < 0x10000 {
    out.push(((0xE0 + cp / 4096) % 256) as UInt8);
    out.push(((0x80 + (cp / 64) % 64) % 256) as UInt8);
    out.push(((0x80 + cp % 64) % 256) as UInt8);
    return;
  };
  out.push(((0xF0 + cp / 262144) % 256) as UInt8);
  out.push(((0x80 + (cp / 4096) % 64) % 256) as UInt8);
  out.push(((0x80 + (cp / 64) % 64) % 256) as UInt8);
  out.push(((0x80 + cp % 64) % 256) as UInt8);
}

// Decode the entity name in [start, end) (between '&' and ';').
fn _decode_entity(xml: &Vec[UInt8>, start: Int, end: Int, out: &mut Vec[UInt8>) -> Result[Bool, Str] {
  if _entity_is(xml, start, end, "amp") {
    out.push(0x26);
    return _ok_bool(true);
  };
  if _entity_is(xml, start, end, "lt") {
    out.push(0x3C);
    return _ok_bool(true);
  };
  if _entity_is(xml, start, end, "gt") {
    out.push(0x3E);
    return _ok_bool(true);
  };
  if _entity_is(xml, start, end, "quot") {
    out.push(0x22);
    return _ok_bool(true);
  };
  if _entity_is(xml, start, end, "apos") {
    out.push(0x27);
    return _ok_bool(true);
  };
  if end - start < 2 {
    return _err_bool("docx: unknown entity");
  };
  let c0: UInt8 = xml[start];
  if (((c0 as Int) & 0xFF) != 0x23) {
    return _err_bool("docx: unknown entity");
  };
  var i = start + 1;
  var hex = false;
  if i < end {
    let cx: UInt8 = xml[i];
    let cxv = (cx as Int) & 0xFF;
    if cxv == 0x78 || cxv == 0x58 {
      hex = true;
      i = i + 1;
    };
  };
  if i >= end {
    return _err_bool("docx: invalid entity");
  };
  var cp = 0;
  var digits = 0;
  while i < end {
    let b: UInt8 = xml[i];
    let bv = (b as Int) & 0xFF;
    var dv = -1;
    if bv >= 48 && bv <= 57 {
      dv = bv - 48;
    } else if hex && bv >= 97 && bv <= 102 {
      dv = bv - 87;
    } else if hex && bv >= 65 && bv <= 70 {
      dv = bv - 55;
    } else {
      return _err_bool("docx: invalid entity");
    };
    if hex {
      cp = cp * 16 + dv;
    } else {
      cp = cp * 10 + dv;
    };
    digits = digits + 1;
    if cp > 0x10FFFF {
      return _err_bool("docx: invalid entity");
    };
    i = i + 1;
  };
  if digits == 0 {
    return _err_bool("docx: invalid entity");
  };
  if cp == 0 {
    return _err_bool("docx: nul byte in text");
  };
  if cp >= 0xD800 && cp <= 0xDFFF {
    return _err_bool("docx: invalid entity");
  };
  _push_utf8(out, cp);
  return _ok_bool(true);
}

// Append xml[start, end) to `out`, decoding entities and validating that
// the raw bytes are legal XML 1.0 text (no NUL, no other C0 controls).
fn _unescape_into(xml: &Vec[UInt8>, start: Int, end: Int, out: &mut Vec[UInt8>) -> Result[Bool, Str] {
  var i = start;
  while i < end {
    let b8: UInt8 = xml[i];
    let b = (b8 as Int) & 0xFF;
    if b == 0 {
      return _err_bool("docx: nul byte in text");
    };
    if b == 0x26 {
      var semi = i + 1;
      while semi < end {
        let s8: UInt8 = xml[semi];
        if (((s8 as Int) & 0xFF) == 0x3B) {
          break;
        };
        semi = semi + 1;
      };
      if semi >= end {
        return _err_bool("docx: unknown entity");
      };
      let de = _decode_entity(xml, i + 1, semi, out);
      if !de.is_ok {
        return _err_bool(de.error);
      };
      i = semi + 1;
    } else {
      if b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D {
        return _err_bool("docx: control character in text");
      };
      out.push(b8);
      i = i + 1;
    };
  };
  return _ok_bool(true);
}

// Parse word/document.xml into a DocxDoc. Tolerant of unknown elements
// (skipped wholesale), strict about structure and text bytes.
fn _docx_parse_document(xml: &Vec[UInt8>) -> Result[DocxDoc, Str] {
  let n = xml.len();
  let bidx = _find_str_range(xml, 0, n, "<w:body");
  if bidx < 0 {
    return _docx_err("docx: missing w:body");
  };
  let bgt = _tag_end(xml, bidx);
  if bgt < 0 {
    return _docx_err("docx: malformed xml");
  };
  var doc = docx_new();
  var pos = bgt;
  var in_p = false;
  var in_r = false;
  var in_t = false;
  var bold = false;
  var italic = false;
  var sz = 0;
  var tstart = 0;
  var cur = Vec[UInt8].new();
  var closed = false;
  var guard = 0;
  while pos < n {
    guard = guard + 1;
    if guard > 1000000 {
      return _docx_err("docx: malformed xml");
    };
    let lt = _find_byte(xml, pos, 0x3C);
    if lt < 0 {
      break;
    };
    if lt + 1 >= n {
      return _docx_err("docx: malformed xml");
    };
    let gt = _tag_end(xml, lt);
    if gt < 0 {
      return _docx_err("docx: malformed xml");
    };
    let c1: UInt8 = xml[lt + 1];
    let c1v = (c1 as Int) & 0xFF;
    var self_close = false;
    if gt - 2 >= lt + 1 {
      let pb: UInt8 = xml[gt - 2];
      if (((pb as Int) & 0xFF) == 0x2F) {
        self_close = true;
      };
    };
    if c1v == 0x2F {
      // Closing tag.
      if _tag_name_is(xml, lt, "/w:body") {
        closed = true;
        pos = n;
        break;
      };
      if _tag_name_is(xml, lt, "/w:t") {
        if in_t {
          let ur = _unescape_into(xml, tstart, lt, &mut cur);
          if !ur.is_ok {
            return _docx_err(ur.error);
          };
          in_t = false;
        };
      } else if _tag_name_is(xml, lt, "/w:r") {
        if in_t {
          return _docx_err("docx: malformed xml");
        };
        if in_r {
          let txt: Str = builder.sb_to_str(&cur);
          docx_add_run(&mut doc, txt, bold, italic, sz);
          in_r = false;
          bold = false;
          italic = false;
          sz = 0;
          cur = Vec[UInt8].new();
        };
      } else if _tag_name_is(xml, lt, "/w:p") {
        if in_r || in_t {
          return _docx_err("docx: malformed xml");
        };
        in_p = false;
      };
      pos = gt;
    } else {
      // Opening tag.
      if _tag_name_is(xml, lt, "w:p") {
        in_p = true;
        docx_add_paragraph(&mut doc);
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:r") {
        if !in_p {
          return _docx_err("docx: run outside paragraph");
        };
        in_r = true;
        bold = false;
        italic = false;
        sz = 0;
        cur = Vec[UInt8].new();
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:rPr") {
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:b") {
        bold = true;
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:i") {
        italic = true;
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:sz") {
        let v = _attr_int(xml, lt, gt, "w:val=\"");
        if v >= 0 {
          sz = v;
        };
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:t") {
        if !in_r {
          return _docx_err("docx: text outside run");
        };
        in_t = true;
        tstart = gt;
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:document") {
        pos = gt;
      } else if _tag_name_is(xml, lt, "w:body") {
        pos = gt;
      } else if self_close {
        pos = gt;
      } else {
        let nr = _tag_name_str(xml, lt, gt);
        if !nr.is_ok {
          return _docx_err(nr.error);
        };
        let cname: Str = nr.value;
        let np = _skip_to_close(xml, gt, n, cname);
        if np < 0 {
          return _docx_err("docx: malformed xml");
        };
        pos = np;
      };
    };
  };
  if !closed {
    return _docx_err("docx: unterminated xml");
  };
  return _docx_ok(doc);
}

// --------------------------------------------------
//  Package read / write
// --------------------------------------------------

/// Parse a .docx byte container: ZIP open, required-part check and
/// word/document.xml parsing.
pub fn docx_from_bytes(buffer: &Vec[UInt8]) -> Result[DocxDoc, Str] {
  let zr = docx_zip_open(buffer);
  if !zr.is_ok {
    return _docx_err(zr.error);
  };
  let z: DocxZip = zr.value;
  if docx_zip_find(&z, "[Content_Types].xml") < 0 {
    return _docx_err("docx: missing [Content_Types].xml");
  };
  if docx_zip_find(&z, "_rels/.rels") < 0 {
    return _docx_err("docx: missing _rels/.rels");
  };
  let di = docx_zip_find(&z, "word/document.xml");
  if di < 0 {
    return _docx_err("docx: missing word/document.xml");
  };
  let dr = docx_zip_entry_data(&z, di);
  if !dr.is_ok {
    return _docx_err(dr.error);
  };
  let xml: Vec[UInt8] = dr.value;
  return _docx_parse_document(&xml);
}
