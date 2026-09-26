// XIOM -- xiom.sparse: Android sparse image codec (parse and canonical build)
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.sparse placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// An Android sparse image is a 28-byte little-endian file header followed by
// `total_chunks` 12-byte chunk headers and their bodies. `sparse_parse`
// validates the header and every chunk and returns a `SparseImage`: a flat
// index built from five parallel vectors (chunk types, block counts, body
// offsets, body lengths and fill values; no Vec of structs). Raw/fill/crc32
// bodies stay in the source buffer and are located by the recorded spans;
// `sparse_build` writes a canonical header plus chunk headers and bodies
// from the same parallel vectors. See SPEC.md for the byte layout,
// validation order, error catalog and the crc32 / trailing-byte policies.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Result payloads in larger functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * all little-endian packing/extraction is arithmetic (modulo/division),
//     which is exact for values with bit 31 set (`& 0xFF` on such values
//     miscompiles; see the xiom.gpt / xiom.msgpack precedents).
//   * raw body length is checked as `body % block_size == 0` plus
//     `body / block_size == blocks` instead of `blocks * block_size == body`
//     so no multiplication in a parser or builder can overflow a signed Int.
//   * Str values are never compared with `==` in the module; the tests route
//     every string comparison through xiom.string.compare.str_compare.

module xiom.sparse

use xiom.convert;

// Chunk type tags as stored (little-endian u16). A chunk header is
// { type u16; reserved u16; chunk_size u32; total_size u32 }.
pub const SPARSE_CHUNK_RAW: Int = 0xCAC1;
pub const SPARSE_CHUNK_FILL: Int = 0xCAC2;
pub const SPARSE_CHUNK_DONT_CARE: Int = 0xCAC3;
pub const SPARSE_CHUNK_CRC32: Int = 0xCAC4;

// Fixed sizes carried in the self-describing header.
pub const SPARSE_FILE_HEADER_SIZE: Int = 28;
pub const SPARSE_CHUNK_HEADER_SIZE: Int = 12;

// File magic 0xED26FF3A, written as a decimal literal (bit 31 is set; see
// the module header).
pub const SPARSE_MAGIC: Int = 3978755898;

const _SPARSE_U32_MAX: Int = 4294967295;
const _SPARSE_MAJOR: Int = 1;
const _SPARSE_MINOR: Int = 0;
const _SPARSE_INT64_MAX: Int = 9223372036854775807;

/// Parsed sparse image index. The scalar fields are the file header values;
/// the vectors are the flat parallel chunk columns, one element per chunk in
/// file order. `chunk_blocks` counts blocks for raw/fill/don't-care chunks
/// and is 0 for crc32 chunks; `data_offsets`/`data_lengths` locate each body
/// inside the source buffer (crc32 bodies included) and are 0/0 for
/// don't-care chunks. Fields are implementation details; callers should go
/// through the free functions below.
pub type SparseImage = {
  major: Int;
  minor: Int;
  file_header_size: Int;
  chunk_header_size: Int;
  block_size: Int;
  total_blocks: Int;
  total_chunks: Int;
  image_checksum: Int;
  chunk_types: Vec[Int];
  chunk_blocks: Vec[Int];
  data_offsets: Vec[Int];
  data_lengths: Vec[Int];
  fill_values: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[SparseImage, Str].
fn _ok_image(v: SparseImage) -> Result[SparseImage, Str] {
  return Ok(v);
}

// Err(m) for Result[SparseImage, Str].
fn _err_image(m: Str) -> Result[SparseImage, Str] {
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

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian u16 at `off` (0..65535); callers guarantee the bounds.
fn _u16le(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256;
}

// Little-endian u32 at `off` (0..2^32-1); callers guarantee the bounds.
// Accumulated byte by byte so no shift touches bit 31 (see the module
// header).
fn _u32le(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + _byte(data, off + i);
    i = i - 1;
  }
  return v;
}

// Byte number `k` of `v` (0 = least significant). Arithmetic only: `& 0xFF`
// on values with bit 31 set miscompiles in v0.61.3, and this form is exact
// for positive values up to 2^32-1 (the only range this module writes).
fn _byte_at(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low 16 bits of `v` in little-endian order.
fn _push_u16le(out: &mut Vec[UInt8], v: Int) {
  out.push(_byte_at(v, 0));
  out.push(_byte_at(v, 1));
}

// Append the low 32 bits of `v` in little-endian order.
fn _push_u32le(out: &mut Vec[UInt8], v: Int) {
  out.push(_byte_at(v, 0));
  out.push(_byte_at(v, 1));
  out.push(_byte_at(v, 2));
  out.push(_byte_at(v, 3));
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// True when `ctype` is one of the four documented chunk types.
fn _type_known(ctype: Int) -> Bool {
  if ctype == SPARSE_CHUNK_RAW { return true; }
  if ctype == SPARSE_CHUNK_FILL { return true; }
  if ctype == SPARSE_CHUNK_DONT_CARE { return true; }
  if ctype == SPARSE_CHUNK_CRC32 { return true; }
  return false;
}

// Safe row count for the five parallel chunk vectors: their common minimum,
// so a hand-built index with drifted vectors cannot index past any of them.
fn _row_count(t: &SparseImage) -> Int {
  var n = t.chunk_types.len();
  if t.chunk_blocks.len() < n { n = t.chunk_blocks.len(); }
  if t.data_offsets.len() < n { n = t.data_offsets.len(); }
  if t.data_lengths.len() < n { n = t.data_lengths.len(); }
  if t.fill_values.len() < n { n = t.fill_values.len(); }
  return n;
}

// --------------------------------------------------
//  Public API -- parsing
// --------------------------------------------------

/// Parse and validate an Android sparse image.
///
/// Validation order (first failure wins): a buffer shorter than 28 bytes is
/// Err("sparse: truncated header"); the u32 magic must be 0xED26FF3A ->
/// Err("sparse: bad magic"); the major/minor version must be 1.0 ->
/// Err("sparse: unsupported version"); the file header size must be 28 ->
/// Err("sparse: bad file header size"); the chunk header size must be 12 ->
/// Err("sparse: bad chunk header size"); the block size must be nonzero and
/// a multiple of 4 -> Err("sparse: bad block size").
///
/// Chunks are then walked in file order while fewer than `total_chunks`
/// chunks have been read and the buffer is not exhausted. A partial chunk
/// header is Err("sparse: truncated chunk header"); an unknown type is
/// Err("sparse: unknown chunk type"); a nonzero reserved field is
/// Err("sparse: nonzero chunk reserved"); a total size below 12 is
/// Err("sparse: bad chunk total size"); a body that does not fit is
/// Err("sparse: chunk overruns buffer"); a body inconsistent with the
/// declared type/size is Err("sparse: bad chunk size") (raw: `chunk_size`
/// blocks of `block_size` bytes; fill: exactly 4 bytes; don't-care: exactly
/// 0 bytes; crc32: exactly 4 bytes and `chunk_size` == 4, counted as 0
/// blocks). After the walk: fewer chunks than declared is Err("sparse:
/// chunk count mismatch"); leftover bytes after the last declared chunk are
/// Err("sparse: trailing bytes"); a block sum that differs from the header
/// `total_blocks` (crc32 chunks contribute 0) is Err("sparse: block count
/// mismatch").
///
/// A 28-byte header declaring zero chunks and zero blocks parses to an empty
/// index; zero-block raw/fill/don't-care chunks are accepted. The returned
/// index points into `data`, which must stay alive for span reads.
/// Params: data - the whole sparse file, read only.
/// Returns: Ok(SparseImage) with five parallel vectors of equal length.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(data.len()).
pub fn sparse_parse(data: &Vec[UInt8]) -> Result[SparseImage, Str] {
  let n = data.len();
  if n < SPARSE_FILE_HEADER_SIZE {
    return _err_image("sparse: truncated header");
  }
  if _u32le(data, 0) != SPARSE_MAGIC {
    return _err_image("sparse: bad magic");
  }
  let major: Int = _u16le(data, 4);
  let minor: Int = _u16le(data, 6);
  if major != _SPARSE_MAJOR {
    return _err_image("sparse: unsupported version");
  }
  if minor != _SPARSE_MINOR {
    return _err_image("sparse: unsupported version");
  }
  let file_header_size: Int = _u16le(data, 8);
  if file_header_size != SPARSE_FILE_HEADER_SIZE {
    return _err_image("sparse: bad file header size");
  }
  let chunk_header_size: Int = _u16le(data, 10);
  if chunk_header_size != SPARSE_CHUNK_HEADER_SIZE {
    return _err_image("sparse: bad chunk header size");
  }
  let block_size: Int = _u32le(data, 12);
  if block_size < 1 {
    return _err_image("sparse: bad block size");
  }
  if block_size % 4 != 0 {
    return _err_image("sparse: bad block size");
  }
  let total_blocks: Int = _u32le(data, 16);
  let total_chunks: Int = _u32le(data, 20);
  let image_checksum: Int = _u32le(data, 24);
  var chunk_types = Vec[Int].new();
  var chunk_blocks = Vec[Int].new();
  var data_offsets = Vec[Int].new();
  var data_lengths = Vec[Int].new();
  var fill_values = Vec[Int].new();
  var pos: Int = file_header_size;
  var count: Int = 0;
  var block_sum: Int = 0;
  while count < total_chunks && pos < n {
    if n - pos < chunk_header_size {
      return _err_image("sparse: truncated chunk header");
    }
    let ctype: Int = _u16le(data, pos);
    let reserved: Int = _u16le(data, pos + 2);
    let chunk_size: Int = _u32le(data, pos + 4);
    let total_size: Int = _u32le(data, pos + 8);
    if !_type_known(ctype) {
      return _err_image("sparse: unknown chunk type");
    }
    if reserved != 0 {
      return _err_image("sparse: nonzero chunk reserved");
    }
    if total_size < chunk_header_size {
      return _err_image("sparse: bad chunk total size");
    }
    let body: Int = total_size - chunk_header_size;
    if body > n - pos - chunk_header_size {
      return _err_image("sparse: chunk overruns buffer");
    }
    var blocks: Int = 0;
    var fill_value: Int = 0;
    if ctype == SPARSE_CHUNK_RAW {
      if body % block_size != 0 {
        return _err_image("sparse: bad chunk size");
      }
      if body / block_size != chunk_size {
        return _err_image("sparse: bad chunk size");
      }
      blocks = chunk_size;
    } elif ctype == SPARSE_CHUNK_FILL {
      if body != 4 {
        return _err_image("sparse: bad chunk size");
      }
      blocks = chunk_size;
      fill_value = _u32le(data, pos + chunk_header_size);
    } elif ctype == SPARSE_CHUNK_DONT_CARE {
      if body != 0 {
        return _err_image("sparse: bad chunk size");
      }
      blocks = chunk_size;
    } else {
      if chunk_size != 4 {
        return _err_image("sparse: bad chunk size");
      }
      if body != 4 {
        return _err_image("sparse: bad chunk size");
      }
      blocks = 0;
    }
    chunk_types.push(ctype);
    chunk_blocks.push(blocks);
    data_offsets.push(pos + chunk_header_size);
    data_lengths.push(body);
    fill_values.push(fill_value);
    block_sum = block_sum + blocks;
    count = count + 1;
    pos = pos + total_size;
  }
  if count != total_chunks {
    return _err_image("sparse: chunk count mismatch");
  }
  if pos != n {
    return _err_image("sparse: trailing bytes");
  }
  if block_sum != total_blocks {
    return _err_image("sparse: block count mismatch");
  }
  let image = SparseImage{
    major: major;
    minor: minor;
    file_header_size: file_header_size;
    chunk_header_size: chunk_header_size;
    block_size: block_size;
    total_blocks: total_blocks;
    total_chunks: total_chunks;
    image_checksum: image_checksum;
    chunk_types: chunk_types;
    chunk_blocks: chunk_blocks;
    data_offsets: data_offsets;
    data_lengths: data_lengths;
    fill_values: fill_values;
  };
  return _ok_image(image);
}

// --------------------------------------------------
//  Public API -- header accessors
// --------------------------------------------------

/// Header major version; 1 after a successful parse. Complexity: O(1).
pub fn sparse_major_version(t: &SparseImage) -> Int {
  return t.major;
}

/// Header minor version; 0 after a successful parse. Complexity: O(1).
pub fn sparse_minor_version(t: &SparseImage) -> Int {
  return t.minor;
}

/// Version as "major.minor" (e.g. "1.0"); never fails. Complexity: O(1).
pub fn sparse_version(t: &SparseImage) -> Str {
  let a: Int = t.major;
  let b: Int = t.minor;
  return convert.int_to_string(a) + "." + convert.int_to_string(b);
}

/// File header size field in bytes; 28 after a successful parse.
/// Complexity: O(1).
pub fn sparse_file_header_size(t: &SparseImage) -> Int {
  return t.file_header_size;
}

/// Chunk header size field in bytes; 12 after a successful parse.
/// Complexity: O(1).
pub fn sparse_chunk_header_size(t: &SparseImage) -> Int {
  return t.chunk_header_size;
}

/// Block size in bytes (nonzero, a multiple of 4 after a successful parse).
/// Complexity: O(1).
pub fn sparse_block_size(t: &SparseImage) -> Int {
  return t.block_size;
}

/// Header total block count (u32), including fill and don't-care blocks and
/// excluding crc32 chunks. Complexity: O(1).
pub fn sparse_total_blocks(t: &SparseImage) -> Int {
  return t.total_blocks;
}

/// Header total chunk count (u32). A parsed image matches
/// `sparse_chunk_count`; a hand-built image may not.
/// Complexity: O(1).
pub fn sparse_total_chunks(t: &SparseImage) -> Int {
  return t.total_chunks;
}

/// Stored image checksum (u32), raw: the codec never computes or verifies
/// it. Complexity: O(1).
pub fn sparse_image_checksum(t: &SparseImage) -> Int {
  return t.image_checksum;
}

/// Expanded image size in bytes: `total_blocks * block_size`; -1 when either
/// field is negative or the product does not fit a signed 64-bit Int.
/// Complexity: O(1).
pub fn sparse_expanded_size(t: &SparseImage) -> Int {
  let b: Int = t.block_size;
  let n: Int = t.total_blocks;
  if b < 0 { return -1; }
  if n < 0 { return -1; }
  if b != 0 && n > _SPARSE_INT64_MAX / b { return -1; }
  return n * b;
}

// --------------------------------------------------
//  Public API -- chunk index accessors
// --------------------------------------------------

/// Number of usable index rows: the minimum length of the five parallel
/// vectors, so a hand-built index with drifted vectors reports the safe
/// maximum. A parsed image reports the chunk count.
/// Complexity: O(1).
pub fn sparse_chunk_count(t: &SparseImage) -> Int {
  return _row_count(t);
}

/// Chunk type of chunk `i` (51905 raw / 51906 fill / 51907 don't-care /
/// 51908 crc32), or -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn sparse_chunk_type(t: &SparseImage, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.chunk_types.len() { return -1; }
  let v: Int = t.chunk_types[i];
  return v;
}

/// Block count of chunk `i` (0 for crc32 chunks), or -1 when `i` is negative
/// or out of range. Complexity: O(1).
pub fn sparse_chunk_blocks(t: &SparseImage, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.chunk_blocks.len() { return -1; }
  let v: Int = t.chunk_blocks[i];
  return v;
}

/// Absolute offset in the source buffer of chunk `i`'s body (for a raw
/// chunk: the first data byte; fill: the 4-byte fill value; don't-care: the
/// position where a body would start; crc32: the 4-byte checksum), or -1
/// when `i` is negative or out of range. Complexity: O(1).
pub fn sparse_chunk_data_offset(t: &SparseImage, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.data_offsets.len() { return -1; }
  let v: Int = t.data_offsets[i];
  return v;
}

/// Body length in bytes of chunk `i` (0 for don't-care chunks), or -1 when
/// `i` is negative or out of range. Complexity: O(1).
pub fn sparse_chunk_data_length(t: &SparseImage, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.data_lengths.len() { return -1; }
  let v: Int = t.data_lengths[i];
  return v;
}

/// Fill value (u32) of fill chunk `i`; -1 when `i` is negative, out of
/// range, or the chunk is not a fill chunk. Complexity: O(1).
pub fn sparse_chunk_fill_value(t: &SparseImage, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.fill_values.len() { return -1; }
  let ctype: Int = t.chunk_types[i];
  if ctype != SPARSE_CHUNK_FILL { return -1; }
  let v: Int = t.fill_values[i];
  return v;
}

/// Running block offset of chunk `i`: the sum of the block counts of chunks
/// 0..i-1 (crc32 chunks add 0). 0 for the first chunk; -1 when `i` is
/// negative or out of range. Complexity: O(i).
pub fn sparse_chunk_block_offset(t: &SparseImage, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _row_count(t) { return -1; }
  var off: Int = 0;
  var k = 0;
  while k < i {
    let b: Int = t.chunk_blocks[k];
    off = off + b;
    k = k + 1;
  }
  return off;
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

/// Build a canonical sparse image from parallel chunk vectors.
///
/// The header is always: magic 0xED26FF3A, major 1, minor 0, file header
/// size 28, chunk header size 12, the caller's `block_size`, the computed
/// total block count, the number of chunks, and `image_checksum` verbatim.
/// Chunks are emitted in order, each with a zero reserved field and its body
/// copied verbatim: raw -> `chunk_size` = blocks and total size
/// `12 + body.len()`; fill -> `chunk_size` = blocks and total size 16;
/// don't-care -> `chunk_size` = blocks and total size 12; crc32 ->
/// `chunk_size` = 4 and total size 16, contributing 0 blocks to the header
/// total. An image whose chunks are all raw is the usual case, and the
/// builder is otherwise general so any parsed index can be re-emitted.
///
/// Every check runs before the first byte is written, and the result is a
/// fresh vector, so an Err returns no partial image.
///
/// Params: block_size - nonzero multiple of 4; chunk_types/chunk_blocks/
/// chunk_bodies - equal-length parallel vectors; image_checksum - raw u32.
/// Returns: Ok(bytes) holding the complete image.
/// Error case: Err("sparse: bad block size"); Err("sparse: bad image
/// checksum") for a checksum outside 0..2^32-1; Err("sparse: chunk vector
/// mismatch") for unequal vector lengths; Err("sparse: unknown chunk
/// type"); Err("sparse: bad chunk blocks") for a negative/oversized block
/// count or a nonzero crc32 block count; Err("sparse: bad chunk body") when a
/// body length is inconsistent with its type (raw: exact multiple of
/// `block_size` and quotient equal to the block count; fill/crc32: exactly 4
/// bytes; don't-care: exactly 0); Err("sparse: too many blocks") when the
/// non-crc32 block sum exceeds 2^32-1.
/// Complexity: O(total body bytes).
pub fn sparse_build(block_size: Int, chunk_types: &Vec[Int], chunk_blocks: &Vec[Int], chunk_bodies: &Vec[Vec[UInt8]], image_checksum: Int) -> Result[Vec[UInt8], Str] {
  if block_size < 1 {
    return _err_bytes("sparse: bad block size");
  }
  if block_size % 4 != 0 {
    return _err_bytes("sparse: bad block size");
  }
  if image_checksum < 0 {
    return _err_bytes("sparse: bad image checksum");
  }
  if image_checksum > _SPARSE_U32_MAX {
    return _err_bytes("sparse: bad image checksum");
  }
  if chunk_types.len() != chunk_blocks.len() {
    return _err_bytes("sparse: chunk vector mismatch");
  }
  if chunk_types.len() != chunk_bodies.len() {
    return _err_bytes("sparse: chunk vector mismatch");
  }
  let total_chunks: Int = chunk_types.len();
  var total_blocks: Int = 0;
  var i = 0;
  while i < total_chunks {
    let ctype: Int = chunk_types[i];
    let blocks: Int = chunk_blocks[i];
    let body: Vec[UInt8] = chunk_bodies[i];
    if !_type_known(ctype) {
      return _err_bytes("sparse: unknown chunk type");
    }
    if blocks < 0 {
      return _err_bytes("sparse: bad chunk blocks");
    }
    if blocks > _SPARSE_U32_MAX {
      return _err_bytes("sparse: bad chunk blocks");
    }
    if ctype == SPARSE_CHUNK_CRC32 && blocks != 0 {
      return _err_bytes("sparse: bad chunk blocks");
    }
    let body_len: Int = body.len();
    if ctype == SPARSE_CHUNK_RAW {
      if body_len % block_size != 0 {
        return _err_bytes("sparse: bad chunk body");
      }
      if body_len / block_size != blocks {
        return _err_bytes("sparse: bad chunk body");
      }
    } elif ctype == SPARSE_CHUNK_FILL {
      if body_len != 4 {
        return _err_bytes("sparse: bad chunk body");
      }
    } elif ctype == SPARSE_CHUNK_DONT_CARE {
      if body_len != 0 {
        return _err_bytes("sparse: bad chunk body");
      }
    } else {
      if body_len != 4 {
        return _err_bytes("sparse: bad chunk body");
      }
    }
    if ctype != SPARSE_CHUNK_CRC32 {
      total_blocks = total_blocks + blocks;
    }
    i = i + 1;
  }
  if total_blocks > _SPARSE_U32_MAX {
    return _err_bytes("sparse: too many blocks");
  }
  var out = Vec[UInt8].new();
  _push_u32le(&mut out, SPARSE_MAGIC);
  _push_u16le(&mut out, _SPARSE_MAJOR);
  _push_u16le(&mut out, _SPARSE_MINOR);
  _push_u16le(&mut out, SPARSE_FILE_HEADER_SIZE);
  _push_u16le(&mut out, SPARSE_CHUNK_HEADER_SIZE);
  _push_u32le(&mut out, block_size);
  _push_u32le(&mut out, total_blocks);
  _push_u32le(&mut out, total_chunks);
  _push_u32le(&mut out, image_checksum);
  var c = 0;
  while c < total_chunks {
    let ctype2: Int = chunk_types[c];
    let blocks2: Int = chunk_blocks[c];
    let body2: Vec[UInt8] = chunk_bodies[c];
    let body_len2: Int = body2.len();
    _push_u16le(&mut out, ctype2);
    _push_u16le(&mut out, 0);
    if ctype2 == SPARSE_CHUNK_CRC32 {
      _push_u32le(&mut out, 4);
    } else {
      _push_u32le(&mut out, blocks2);
    }
    _push_u32le(&mut out, SPARSE_CHUNK_HEADER_SIZE + body_len2);
    _push_bytes(&mut out, &body2);
    c = c + 1;
  }
  return _ok_bytes(out);
}
