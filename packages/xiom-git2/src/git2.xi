// XIOM -- xiom.git2: Git object and pack-file codec with a DEFLATE decoder
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Scope: the STRUCTURE layer of Git repositories plus a
// self-contained DEFLATE/zlib decoder over flat Vec[UInt8] buffers:
//
//   (a) zlib (RFC 1950) and DEFLATE (RFC 1951): two-byte zlib header with
//       CM/FCHECK validation (FDICT rejected, CINFO/FLEVEL recorded), stored
//       blocks (BTYPE 00), fixed-Huffman blocks (01), dynamic-Huffman blocks
//       (10), LZ77 back-references with the RFC length/distance tables, and
//       the four-byte big-endian Adler-32 trailer (verified locally). The
//       decoder writes into a caller-provided Vec[UInt8] and returns the
//       offset just past the decoded stream.
//   (b) loose objects: the "<type> <size>\0" header (blob/tree/commit/tag),
//       the canonical object-type table and the zlib-compressed payload;
//       tree entries are mode ASCII-octal + space + name + NUL + raw id
//       (20 bytes SHA-1, or 32 bytes for SHA-256 repositories) with the Git
//       sort order enforced; commit/tag header lines (tree, parent*, author,
//       committer, encoding, gpgsig and unknown keys, with folded
//       continuation lines) and the blank-line message boundary are decoded.
//   (c) pack files: "PACK" magic, version u32 (2 or 3), object-count u32;
//       entry headers with the 4-bit size + 3-bit type first byte and 7-bit
//       big-endian continuation groups (types 1 COMMIT, 2 TREE, 3 BLOB,
//       4 TAG, 6 OFS_DELTA, 7 REF_DELTA); the OFS_DELTA negative-offset
//       varint (with the +1 per group rule) and the REF_DELTA raw base id;
//       delta application (source/target size varints, the copy/insert
//       opcode table with copy-size/copy-offset byte bit encodings); the
//       20-byte pack trailer checksum is preserved raw (SHA-1 is a
//       caller-side concern) and the full entry walk inflates every entry.
//   (d) pack index v2: magic 0xFF744F63 + version 2, 256-entry fanout table
//       (monotonic, fanout[255] == object count), sorted raw object ids,
//       CRC-32 table, 4-byte offsets with the MSB set switching to the
//       64-bit offset table, and the pack/idx checksum trailers. Lookup is a
//       binary search bounded by the fanout bucket; CRC verification uses a
//       local table-less reflected CRC-32 (poly 0xEDB88320, check value
//       0xCBF43926 for "123456789").
//
// Out of scope: SHA-1/SHA-256 hashing and object-id computation, pack/idx
// checksum verification (raw checksums are preserved), repository layout,
// refs, index (staging) files, and REF_DELTA chain resolution (a REF_DELTA
// needs an external base resolved through the idx).
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[i] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int]/Vec[Str] element reads are bound to typed locals; Str values
//     are compared through xiom.string.str_compare only (BUG 17 discipline).
//   * bit fields are decoded with multiplication/division/modulo arithmetic
//     only (no shifts; sign-bit tests avoided, so an offset whose bit 31 is
//     set is detected with `value >= 2147483648`).
//   * `&mut Int` out-params are avoided: multi-value internal results travel
//     as small structs (_Bits, _Huff, _Varint) behind &mut struct refs.
//   * `&struct.field` is never passed where a &Vec parameter is expected.
// See SPEC.md for the byte layouts, error catalog and the DEFLATE subset.

module xiom.git2

use xiom.convert;
use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Object type codes (matching the pack format numbering).
pub const GIT2_TYPE_NONE: Int = 0;
pub const GIT2_TYPE_COMMIT: Int = 1;
pub const GIT2_TYPE_TREE: Int = 2;
pub const GIT2_TYPE_BLOB: Int = 3;
pub const GIT2_TYPE_TAG: Int = 4;
pub const GIT2_TYPE_OFS_DELTA: Int = 6;
pub const GIT2_TYPE_REF_DELTA: Int = 7;

// Object id sizes in bytes.
pub const GIT2_SHA1_SIZE: Int = 20;
pub const GIT2_SHA256_SIZE: Int = 32;

// Canonical tree entry modes (octal values).
pub const GIT2_MODE_TREE: Int = 16384;
pub const GIT2_MODE_BLOB: Int = 33188;
pub const GIT2_MODE_BLOB_EXEC: Int = 33261;
pub const GIT2_MODE_LINK: Int = 40960;
pub const GIT2_MODE_SUBMODULE: Int = 57344;

// Layout sizes.
pub const GIT2_PACK_HEADER_SIZE: Int = 12;
pub const GIT2_PACK_TRAILER_SIZE: Int = 20;
pub const GIT2_ZLIB_HEADER_SIZE: Int = 2;
pub const GIT2_ZLIB_TRAILER_SIZE: Int = 4;
pub const GIT2_IDX_FANOUT_SIZE: Int = 1024;
pub const GIT2_IDX_HEADER_SIZE: Int = 8;

// Pack index v2 magic 0xFF744F63 as a big-endian 32-bit value.
pub const GIT2_IDX_MAGIC: Int = 4285812579;

// Adler-32 modulus.
pub const GIT2_ADLER_MOD: Int = 65521;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A decoded loose object: the validated canonical type, the declared size
/// (which always equals payload.len()), the header size in bytes (up to and
/// including the NUL) and the payload bytes.
pub type GitLooseObject = {
  object_type: Int;
  type_name: Str;
  declared_size: Int;
  header_size: Int;
  payload: Vec[UInt8];
}

/// A walked tree payload. One entry per parallel index: `entry_offset` is the
/// payload offset of the mode field, `entry_mode` the mode as an ASCII-octal
/// Str, `entry_mode_value` its numeric value, `entry_name` the NUL-free name,
/// and `entry_id` the raw id bytes flattened (id_size bytes per entry,
/// 20 for SHA-1 repositories and 32 for SHA-256). `entry_count` always equals
/// the length of every parallel vector.
pub type GitTree = {
  id_size: Int;
  entry_count: Int;
  entry_offset: Vec[Int];
  entry_mode: Vec[Str];
  entry_mode_value: Vec[Int];
  entry_name: Vec[Str];
  entry_id: Vec[UInt8];
}

/// A parsed commit header plus message. `tree` is the raw tree id (id_size
/// bytes); `parent_id` is the flattened raw parent ids (`parent_count` of
/// them); `author`/`committer`/`encoding`/`gpgsig` hold the raw header values
/// ("" when absent; folded continuation lines are joined with LF);
/// `other_keys` lists unknown header keys in order; `header_end` is the
/// payload offset of the first message byte and `message` the message.
pub type GitCommit = {
  id_size: Int;
  tree: Vec[UInt8];
  parent_count: Int;
  parent_id: Vec[UInt8];
  author: Str;
  committer: Str;
  encoding: Str;
  gpgsig: Str;
  other_keys: Vec[Str];
  header_end: Int;
  message: Str;
}

/// A parsed annotated tag header plus message. `object_id` is the raw target
/// id; `target_type` is the pack-format type code of the target (1 COMMIT,
/// 2 TREE, 3 BLOB, 4 TAG) and `target_type_raw` the raw `type` value;
/// `tag_name` is the `tag` value; `tagger` is "" when absent; `gpgsig` holds
/// the (unfolded) signature when present.
pub type GitTag = {
  id_size: Int;
  object_id: Vec[UInt8];
  target_type: Int;
  target_type_raw: Str;
  tag_name: Str;
  tagger: Str;
  gpgsig: Str;
  other_keys: Vec[Str];
  header_end: Int;
  message: Str;
}

/// A parsed pack header: version (2 or 3), object count and the fixed header
/// size (12).
pub type GitPackHeader = {
  version: Int;
  object_count: Int;
  header_size: Int;
}

/// One parsed pack entry header. `size` is the declared uncompressed size of
/// this entry's data (for delta entries, the size of the delta payload);
/// `data_offset` is the first byte of the zlib stream; `base_offset` is the
/// absolute offset of the base entry for OFS_DELTA (-1 otherwise) and
/// `base_distance` the raw negative-offset varint value (-1 otherwise);
/// `base_id` is the raw base id for REF_DELTA (empty otherwise).
pub type GitPackEntryHeader = {
  entry_type: Int;
  size: Int;
  header_size: Int;
  data_offset: Int;
  base_offset: Int;
  base_distance: Int;
  base_id: Vec[UInt8];
}

/// A fully walked pack file. Every entry was inflated; `entry_data` holds the
/// decompressed bytes flattened and `entry_data_off[i]` locates entry i
/// (length `entry_out_size[i]`, which equals the declared `entry_size[i]`).
/// `entry_end` is the offset just past the entry's zlib stream (including
/// its Adler-32 trailer), so the CRC-32 span of entry i is
/// [entry_offset[i], entry_end[i]). `entry_base_id` is flattened with id_size
/// bytes per entry (all zero unless the entry is a REF_DELTA). `checksum` is
/// the raw 20-byte pack trailer.
pub type GitPack = {
  version: Int;
  object_count: Int;
  entry_type: Vec[Int];
  entry_offset: Vec[Int];
  entry_header_size: Vec[Int];
  entry_data_offset: Vec[Int];
  entry_end: Vec[Int];
  entry_size: Vec[Int];
  entry_out_size: Vec[Int];
  entry_base_offset: Vec[Int];
  entry_base_distance: Vec[Int];
  entry_base_id: Vec[UInt8];
  entry_data: Vec[UInt8];
  entry_data_off: Vec[Int];
  checksum: Vec[UInt8];
}

/// A parsed pack index (version 2). `fanout` is the 256-entry cumulative
/// fanout table, `id` the sorted raw object ids flattened (id_size per
/// object), `crc` the stored CRC-32 values, `raw_offset` the stored 4-byte
/// offsets, `large_index` -1 or the index into `large_offset`, `offset` the
/// resolved 64-bit offsets, and the two trailers are preserved raw.
pub type GitIndex = {
  version: Int;
  count: Int;
  id_size: Int;
  fanout: Vec[Int];
  id: Vec[UInt8];
  crc: Vec[Int];
  raw_offset: Vec[Int];
  large_index: Vec[Int];
  large_offset: Vec[Int];
  offset: Vec[Int];
  pack_checksum: Vec[UInt8];
  idx_checksum: Vec[UInt8];
}

// --------------------------------------------------
//  Internal state types
// --------------------------------------------------

// LSB-first bit reader over a Vec[UInt8]: `pos` is the current byte and
// `bit` (0..7) the next bit inside it.
type _Bits = {
  pos: Int;
  bit: Int;
}

// Canonical Huffman decoding table: `count[len]` is the number of codes of
// that length (1..15; index 0 unused) and `symbol` the symbols sorted by
// (length, symbol).
type _Huff = {
  count: Vec[Int];
  symbol: Vec[Int];
}

// A decoded base-128 varint: `value` and the offset just past it.
type _Varint = {
  value: Int;
  next: Int;
}

// Flattened commit/tag header document: one logical header per parallel
// index (continuation lines folded into the previous value), plus the offset
// of the first message byte.
type _Doc = {
  key: Vec[Str];
  value: Vec[Str];
  line_start: Vec[Int];
  value_start: Vec[Int];
  message_start: Int;
}

// --------------------------------------------------
//  Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
//  return a Result directly, so every fallible public fn returns through
//  these)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[GitLooseObject, Str].
fn _ok_loose(v: GitLooseObject) -> Result[GitLooseObject, Str] {
  return Ok(v);
}

// Err(m) for Result[GitLooseObject, Str].
fn _err_loose(m: Str) -> Result[GitLooseObject, Str] {
  return Err(m);
}

// Ok(v) for Result[GitTree, Str].
fn _ok_tree(v: GitTree) -> Result[GitTree, Str] {
  return Ok(v);
}

// Err(m) for Result[GitTree, Str].
fn _err_tree(m: Str) -> Result[GitTree, Str] {
  return Err(m);
}

// Ok(v) for Result[GitCommit, Str].
fn _ok_commit(v: GitCommit) -> Result[GitCommit, Str] {
  return Ok(v);
}

// Err(m) for Result[GitCommit, Str].
fn _err_commit(m: Str) -> Result[GitCommit, Str] {
  return Err(m);
}

// Ok(v) for Result[GitTag, Str].
fn _ok_tag(v: GitTag) -> Result[GitTag, Str] {
  return Ok(v);
}

// Err(m) for Result[GitTag, Str].
fn _err_tag(m: Str) -> Result[GitTag, Str] {
  return Err(m);
}

// Ok(v) for Result[GitPackHeader, Str].
fn _ok_phead(v: GitPackHeader) -> Result[GitPackHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[GitPackHeader, Str].
fn _err_phead(m: Str) -> Result[GitPackHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[GitPackEntryHeader, Str].
fn _ok_pentry(v: GitPackEntryHeader) -> Result[GitPackEntryHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[GitPackEntryHeader, Str].
fn _err_pentry(m: Str) -> Result[GitPackEntryHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[GitPack, Str].
fn _ok_pack(v: GitPack) -> Result[GitPack, Str] {
  return Ok(v);
}

// Err(m) for Result[GitPack, Str].
fn _err_pack(m: Str) -> Result[GitPack, Str] {
  return Err(m);
}

// Ok(v) for Result[GitIndex, Str].
fn _ok_pidx(v: GitIndex) -> Result[GitIndex, Str] {
  return Ok(v);
}

// Err(m) for Result[GitIndex, Str].
fn _err_pidx(m: Str) -> Result[GitIndex, Str] {
  return Err(m);
}

// Ok(v) for Result[_Varint, Str].
fn _ok_varint(v: _Varint) -> Result[_Varint, Str] {
  return Ok(v);
}

// Err(m) for Result[_Varint, Str].
fn _err_varint(m: Str) -> Result[_Varint, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Basic helpers
// --------------------------------------------------

/// Package version string. Complexity: O(1).
pub fn git2_version() -> Str {
  return "0.1.0";
}

/// SHA-1 raw id size in bytes (20). Complexity: O(1).
pub fn git2_sha1_size() -> Int {
  return 20;
}

/// SHA-256 raw id size in bytes (32). Complexity: O(1).
pub fn git2_sha256_size() -> Int {
  return 32;
}

/// Size of the fixed pack header in bytes (12). Complexity: O(1).
pub fn git2_pack_header_size() -> Int {
  return 12;
}

/// Size of the pack trailer checksum in bytes (20). Complexity: O(1).
pub fn git2_pack_trailer_size() -> Int {
  return 20;
}

/// Size of the zlib header in bytes (2). Complexity: O(1).
pub fn git2_zlib_header_size() -> Int {
  return 2;
}

/// Size of the zlib Adler-32 trailer in bytes (4). Complexity: O(1).
pub fn git2_zlib_trailer_size() -> Int {
  return 4;
}

/// Pack index v2 magic value (0xFF744F63). Complexity: O(1).
pub fn git2_idx_magic() -> Int {
  return 4285812579;
}

/// Pack index fanout table size in bytes (256 * 4). Complexity: O(1).
pub fn git2_idx_fanout_size() -> Int {
  return 1024;
}

/// Canonical name of an object type code ("commit", "tree", "blob", "tag" or
/// "" for unknown / delta codes). Complexity: O(1).
pub fn git2_object_type_name(t: Int) -> Str {
  if t == 1 { return "commit"; }
  if t == 2 { return "tree"; }
  if t == 3 { return "blob"; }
  if t == 4 { return "tag"; }
  return "";
}

/// Pack-format type code of a canonical object type name (0 when unknown,
/// case-sensitive exact match). Complexity: O(name length).
pub fn git2_object_type_code(name: Str) -> Int {
  if _str_eq(name, "commit") { return 1; }
  if _str_eq(name, "tree") { return 2; }
  if _str_eq(name, "blob") { return 3; }
  if _str_eq(name, "tag") { return 4; }
  return 0;
}

// Unsigned byte at index i (callers guarantee the bounds).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Big-endian unsigned 32-bit value at off (callers guarantee the bounds).
fn _be32(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) * 16777216 + _b(data, off + 1) * 65536 + _b(data, off + 2) * 256 + _b(data, off + 3);
}

// Append one message with an absolute byte offset: "<base> at <off>".
fn _at(base: Str, off: Int) -> Str {
  return base + " at " + convert.int_to_string(off);
}

// True when a and b compare equal via the stdlib string comparison.
fn _str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

// Append data[start, end) to out.
fn _append_range(out: &mut Vec[UInt8], data: &Vec[UInt8], start: Int, end: Int) {
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
}

// Append every byte of src to out.
fn _append_all(out: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
}

// A Vec[Int] of n zeros.
fn _zeros_int(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(0);
    i = i + 1;
  }
  return v;
}

// Build a Str from the bytes of data[start, end). Callers guarantee the range
// is NUL-free so the NUL-terminated result preserves every byte.
fn _str_range(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = start;
  while i < end {
    builder.sb_push_byte(&mut sb, data[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Index of the first 0x00 byte in data[start, end), or -1.
fn _find_nul(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var i = start;
  while i < end {
    if _b(data, i) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// Value 0..15 of an ASCII hex digit, or -1.
fn _hexval(b: Int) -> Int {
  if b >= 48 && b <= 57 { return b - 48; }
  if b >= 97 && b <= 102 { return b - 87; }
  if b >= 65 && b <= 70 { return b - 55; }
  return -1;
}

// True when s is non-empty, even-length and all ASCII hex digits.
fn _hex_str_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  if n % 2 != 0 { return false; }
  var i = 0;
  while i < n {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    if _hexval(c) < 0 { return false; }
    i = i + 1;
  }
  return true;
}

// Decode an even-length ASCII hex Str into raw bytes. Callers validate.
fn _hex_decode_str(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let hi = _hexval((string.byte_at(s, i) as Int) & 0xFF);
    let lo = _hexval((string.byte_at(s, i + 1) as Int) & 0xFF);
    out.push((hi * 16 + lo) as UInt8);
    i = i + 2;
  }
  return out;
}

// Bytewise comparison of two id_size-byte ids at a_off and b_off in data:
// -1, 0 or 1.
fn _id_range_cmp(data: &Vec[UInt8], a_off: Int, b_off: Int, size: Int) -> Int {
  var i = 0;
  while i < size {
    let x = _b(data, a_off + i);
    let y = _b(data, b_off + i);
    if x < y { return -1; }
    if x > y { return 1; }
    i = i + 1;
  }
  return 0;
}

// --------------------------------------------------
//  CRC-32 and Adler-32 (table-less, pure arithmetic)
// --------------------------------------------------

// CRC-32 of data[start, end): init 0xFFFFFFFF, reflected polynomial
// 0xEDB88320, final XOR 0xFFFFFFFF. Returns 0..4294967295.
fn _crc32_range(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var c = 4294967295;
  var i = start;
  while i < end {
    let b = _b(data, i);
    c = c ^ b;
    var k = 0;
    while k < 8 {
      if c % 2 == 1 {
        c = c / 2 ^ 3988292384;
      } else {
        c = c / 2;
      }
      k = k + 1;
    }
    i = i + 1;
  }
  return c ^ 4294967295;
}

/// CRC-32 (IEEE, zlib/PKZIP polynomial) of a whole buffer: init 0xFFFFFFFF,
/// reflected polynomial 0xEDB88320, final XOR 0xFFFFFFFF. The check value of
/// "123456789" is 0xCBF43926 (3421780262) and an empty buffer hashes to 0.
/// Complexity: O(data.len()).
pub fn git2_crc32(data: &Vec[UInt8]) -> Int {
  return _crc32_range(data, 0, data.len());
}

/// CRC-32 of data[start, end). Callers guarantee 0 <= start <= end <=
/// data.len(). Complexity: O(end - start).
pub fn git2_crc32_range(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  return _crc32_range(data, start, end);
}

// Adler-32 of v[start, end): a starts at 1, b at 0, mod 65521, result
// b * 65536 + a. All intermediates stay below 2^31.
fn _adler_seg(v: &Vec[UInt8], start: Int, end: Int) -> Int {
  var a = 1;
  var b = 0;
  var i = start;
  while i < end {
    let x = _b(v, i);
    a = (a + x) % 65521;
    b = (b + a) % 65521;
    i = i + 1;
  }
  return b * 65536 + a;
}

/// Adler-32 (RFC 1950) of a whole buffer. The empty buffer hashes to 1 and
/// "hello" to 103547413 (0x062C0215). Complexity: O(data.len()).
pub fn git2_adler32(data: &Vec[UInt8]) -> Int {
  return _adler_seg(data, 0, data.len());
}

/// Adler-32 of data[start, end). Callers guarantee 0 <= start <= end <=
/// data.len(). Complexity: O(end - start).
pub fn git2_adler32_range(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  return _adler_seg(data, start, end);
}

// --------------------------------------------------
//  DEFLATE (RFC 1951) and zlib (RFC 1950)
// --------------------------------------------------

// New bit reader positioned at byte `pos`, bit 0.
fn _bits_new(pos: Int) -> _Bits {
  return _Bits{
    pos: pos;
    bit: 0;
  };
}

// Bits remaining in data from the reader position (>= 0).
fn _bits_left(data: &Vec[UInt8], br: &mut _Bits) -> Int {
  let n = data.len();
  return (n - br.pos) * 8 - br.bit;
}

// Read n (0..16) bits LSB-first. Callers guarantee _bits_left >= n.
fn _bits_take(data: &Vec[UInt8], br: &mut _Bits, n: Int) -> Int {
  var v = 0;
  var mult = 1;
  var i = 0;
  while i < n {
    let byte = _b(data, br.pos);
    var div = 1;
    var k = 0;
    while k < br.bit {
      div = div * 2;
      k = k + 1;
    }
    let bit = (byte / div) % 2;
    v = v + bit * mult;
    mult = mult * 2;
    br.bit = br.bit + 1;
    if br.bit == 8 {
      br.bit = 0;
      br.pos = br.pos + 1;
    }
    i = i + 1;
  }
  return v;
}

// Skip to the next byte boundary (DEFLATE stored-block alignment).
fn _bits_align(br: &mut _Bits) {
  if br.bit != 0 {
    br.bit = 0;
    br.pos = br.pos + 1;
  }
}

// New empty Huffman table.
fn _huff_new() -> _Huff {
  var c = Vec[Int].new();
  var i = 0;
  while i < 16 {
    c.push(0);
    i = i + 1;
  }
  return _Huff{
    count: c;
    symbol: Vec[Int].new();
  };
}

// Build the canonical table from the first n entries of `lengths` (each
// 0..15). Returns "" on success or an offset-free error message.
fn _huff_build(h: &mut _Huff, lengths: &Vec[Int], n: Int) -> Str {
  var i = 0;
  while i < 16 {
    h.count[i] = 0;
    i = i + 1;
  }
  i = 0;
  while i < n {
    let l: Int = lengths[i];
    if l < 0 || l > 15 { return "git2: invalid code length"; }
    h.count[l] = h.count[l] + 1;
    i = i + 1;
  }
  var offs = Vec[Int].new();
  offs.push(0);
  var s = 0;
  var len = 1;
  while len <= 15 {
    offs.push(s);
    s = s + h.count[len];
    len = len + 1;
  }
  h.symbol = Vec[Int].new();
  i = 0;
  while i < n {
    h.symbol.push(0);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let l: Int = lengths[i];
    if l != 0 {
      let o: Int = offs[l];
      h.symbol[o] = i;
      offs[l] = o + 1;
    }
    i = i + 1;
  }
  return "";
}

// Decode one Huffman symbol: the symbol (>= 0), -1 for an invalid code or
// -2 when the input runs out mid-code.
fn _huff_decode(data: &Vec[UInt8], br: &mut _Bits, h: &_Huff) -> Int {
  var code = 0;
  var first = 0;
  var index = 0;
  var len = 1;
  while len <= 15 {
    if _bits_left(data, br) < 1 { return -2; }
    let bit = _bits_take(data, br, 1);
    code = code * 2 + bit;
    let cnt: Int = h.count[len];
    if code - first < cnt {
      let si = index + (code - first);
      let sym: Int = h.symbol[si];
      return sym;
    }
    index = index + cnt;
    first = first + cnt;
    first = first * 2;
    len = len + 1;
  }
  return -1;
}

// RFC 1951 literal/length base lengths for symbols 257..285.
fn _length_bases() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(3);
  v.push(4);
  v.push(5);
  v.push(6);
  v.push(7);
  v.push(8);
  v.push(9);
  v.push(10);
  v.push(11);
  v.push(13);
  v.push(15);
  v.push(17);
  v.push(19);
  v.push(23);
  v.push(27);
  v.push(31);
  v.push(35);
  v.push(43);
  v.push(51);
  v.push(59);
  v.push(67);
  v.push(83);
  v.push(99);
  v.push(115);
  v.push(131);
  v.push(163);
  v.push(195);
  v.push(227);
  v.push(258);
  return v;
}

// RFC 1951 extra bits for length symbols 257..285.
fn _length_extras() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(1);
  v.push(1);
  v.push(1);
  v.push(1);
  v.push(2);
  v.push(2);
  v.push(2);
  v.push(2);
  v.push(3);
  v.push(3);
  v.push(3);
  v.push(3);
  v.push(4);
  v.push(4);
  v.push(4);
  v.push(4);
  v.push(5);
  v.push(5);
  v.push(5);
  v.push(5);
  v.push(0);
  return v;
}

// RFC 1951 distance base values for symbols 0..29.
fn _dist_bases() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(1);
  v.push(2);
  v.push(3);
  v.push(4);
  v.push(5);
  v.push(7);
  v.push(9);
  v.push(13);
  v.push(17);
  v.push(25);
  v.push(33);
  v.push(49);
  v.push(65);
  v.push(97);
  v.push(129);
  v.push(193);
  v.push(257);
  v.push(385);
  v.push(513);
  v.push(769);
  v.push(1025);
  v.push(1537);
  v.push(2049);
  v.push(3073);
  v.push(4097);
  v.push(6145);
  v.push(8193);
  v.push(12289);
  v.push(16385);
  v.push(24577);
  return v;
}

// RFC 1951 extra bits for distance symbols 0..29.
fn _dist_extras() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(0);
  v.push(1);
  v.push(1);
  v.push(2);
  v.push(2);
  v.push(3);
  v.push(3);
  v.push(4);
  v.push(4);
  v.push(5);
  v.push(5);
  v.push(6);
  v.push(6);
  v.push(7);
  v.push(7);
  v.push(8);
  v.push(8);
  v.push(9);
  v.push(9);
  v.push(10);
  v.push(10);
  v.push(11);
  v.push(11);
  v.push(12);
  v.push(12);
  v.push(13);
  v.push(13);
  return v;
}

// RFC 1951 code-length-code transmission order.
fn _cl_order() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(16);
  v.push(17);
  v.push(18);
  v.push(0);
  v.push(8);
  v.push(7);
  v.push(9);
  v.push(6);
  v.push(10);
  v.push(5);
  v.push(11);
  v.push(4);
  v.push(12);
  v.push(3);
  v.push(13);
  v.push(2);
  v.push(14);
  v.push(1);
  v.push(15);
  return v;
}

// Code lengths of the fixed literal/length alphabet (288 entries).
fn _fixed_lit_lengths() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i <= 143 {
    v.push(8);
    i = i + 1;
  }
  i = 144;
  while i <= 255 {
    v.push(9);
    i = i + 1;
  }
  i = 256;
  while i <= 279 {
    v.push(7);
    i = i + 1;
  }
  i = 280;
  while i <= 287 {
    v.push(8);
    i = i + 1;
  }
  return v;
}

// Code lengths of the fixed distance alphabet (30 used entries; symbols
// 30 and 31 never appear).
fn _fixed_dist_lengths() -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < 30 {
    v.push(5);
    i = i + 1;
  }
  return v;
}

// Decode one stored (BTYPE 00) block. Returns "" on success.
fn _decode_stored(data: &Vec[UInt8], br: &mut _Bits, out: &mut Vec[UInt8]) -> Str {
  _bits_align(br);
  if br.pos + 4 > data.len() {
    return _at("git2: truncated stored block", br.pos);
  }
  let len = _b(data, br.pos) + _b(data, br.pos + 1) * 256;
  let nlen = _b(data, br.pos + 2) + _b(data, br.pos + 3) * 256;
  if len + nlen != 65535 {
    return _at("git2: stored block length check failed", br.pos);
  }
  if br.pos + 4 + len > data.len() {
    return _at("git2: truncated stored block", br.pos);
  }
  _append_range(out, data, br.pos + 4, br.pos + 4 + len);
  br.pos = br.pos + 4 + len;
  br.bit = 0;
  return "";
}

// Decode the symbol stream of one Huffman block (fixed or dynamic) until the
// end-of-block symbol. Returns "" on success.
fn _decode_huffman_block(data: &Vec[UInt8], br: &mut _Bits, out: &mut Vec[UInt8], lit: &_Huff, dist: &_Huff) -> Str {
  let lbases = _length_bases();
  let lextras = _length_extras();
  let dbases = _dist_bases();
  let dextras = _dist_extras();
  var keep = 1;
  while keep == 1 {
    if _bits_left(data, br) < 1 {
      return _at("git2: truncated huffman block", br.pos);
    }
    let sym = _huff_decode(data, br, lit);
    if sym == -2 { return _at("git2: truncated huffman block", br.pos); }
    if sym == -1 { return _at("git2: invalid literal/length code", br.pos); }
    if sym < 256 {
      out.push(sym as UInt8);
    } elif sym == 256 {
      return "";
    } else {
      if sym > 285 {
        return _at("git2: invalid length symbol", br.pos);
      }
      let li = sym - 257;
      let lb: Int = lbases[li];
      let lx: Int = lextras[li];
      if _bits_left(data, br) < lx {
        return _at("git2: truncated length extra bits", br.pos);
      }
      let length = lb + _bits_take(data, br, lx);
      if _bits_left(data, br) < 1 {
        return _at("git2: truncated huffman block", br.pos);
      }
      let dsym = _huff_decode(data, br, dist);
      if dsym == -2 { return _at("git2: truncated huffman block", br.pos); }
      if dsym == -1 || dsym > 29 {
        return _at("git2: invalid distance code", br.pos);
      }
      let db: Int = dbases[dsym];
      let dx: Int = dextras[dsym];
      if _bits_left(data, br) < dx {
        return _at("git2: truncated distance extra bits", br.pos);
      }
      let distance = db + _bits_take(data, br, dx);
      if distance < 1 || distance > out.len() {
        return _at("git2: distance too far back", br.pos);
      }
      var src = out.len() - distance;
      var k = 0;
      while k < length {
        let b: UInt8 = out[src];
        out.push(b);
        src = src + 1;
        k = k + 1;
      }
    }
  }
  return "";
}

// Decode a fixed-Huffman (BTYPE 01) block. Returns "" on success.
fn _decode_fixed(data: &Vec[UInt8], br: &mut _Bits, out: &mut Vec[UInt8]) -> Str {
  var lit = _huff_new();
  let ll = _fixed_lit_lengths();
  let e1 = _huff_build(&mut lit, &ll, 288);
  if e1.len() > 0 { return _at(e1, br.pos); }
  var dist = _huff_new();
  let dl = _fixed_dist_lengths();
  let e2 = _huff_build(&mut dist, &dl, 30);
  if e2.len() > 0 { return _at(e2, br.pos); }
  return _decode_huffman_block(data, br, out, &lit, &dist);
}

// Decode a dynamic-Huffman (BTYPE 10) block header and its symbols.
// Returns "" on success.
fn _decode_dynamic(data: &Vec[UInt8], br: &mut _Bits, out: &mut Vec[UInt8]) -> Str {
  if _bits_left(data, br) < 14 {
    return _at("git2: truncated dynamic header", br.pos);
  }
  let hlit = _bits_take(data, br, 5) + 257;
  let hdist = _bits_take(data, br, 5) + 1;
  let hclen = _bits_take(data, br, 4) + 4;
  if hlit > 286 {
    return _at("git2: too many literal/length codes", br.pos);
  }
  if hdist > 30 {
    return _at("git2: too many distance codes", br.pos);
  }
  let order = _cl_order();
  var cl = _zeros_int(19);
  var i = 0;
  while i < hclen {
    if _bits_left(data, br) < 3 {
      return _at("git2: truncated dynamic header", br.pos);
    }
    let v = _bits_take(data, br, 3);
    let oi: Int = order[i];
    cl[oi] = v;
    i = i + 1;
  }
  var clh = _huff_new();
  let e1 = _huff_build(&mut clh, &cl, 19);
  if e1.len() > 0 { return _at(e1, br.pos); }
  let total = hlit + hdist;
  var lengths = Vec[Int].new();
  i = 0;
  while i < total {
    lengths.push(0);
    i = i + 1;
  }
  var filled = 0;
  while filled < total {
    if _bits_left(data, br) < 1 {
      return _at("git2: truncated dynamic lengths", br.pos);
    }
    let sym = _huff_decode(data, br, &clh);
    if sym == -2 { return _at("git2: truncated dynamic lengths", br.pos); }
    if sym == -1 { return _at("git2: invalid code length symbol", br.pos); }
    if sym <= 15 {
      lengths[filled] = sym;
      filled = filled + 1;
    } elif sym == 16 {
      if filled == 0 {
        return _at("git2: repeat with no previous length", br.pos);
      }
      if _bits_left(data, br) < 2 {
        return _at("git2: truncated dynamic lengths", br.pos);
      }
      let rep = 3 + _bits_take(data, br, 2);
      if filled + rep > total {
        return _at("git2: code length repeat overflow", br.pos);
      }
      let prev: Int = lengths[filled - 1];
      var k = 0;
      while k < rep {
        lengths[filled] = prev;
        filled = filled + 1;
        k = k + 1;
      }
    } else {
      var rep = 0;
      if sym == 17 {
        if _bits_left(data, br) < 3 {
          return _at("git2: truncated dynamic lengths", br.pos);
        }
        rep = 3 + _bits_take(data, br, 3);
      } else {
        if _bits_left(data, br) < 7 {
          return _at("git2: truncated dynamic lengths", br.pos);
        }
        rep = 11 + _bits_take(data, br, 7);
      }
      if filled + rep > total {
        return _at("git2: code length repeat overflow", br.pos);
      }
      var k = 0;
      while k < rep {
        lengths[filled] = 0;
        filled = filled + 1;
        k = k + 1;
      }
    }
  }
  let eob: Int = lengths[256];
  if eob == 0 {
    return _at("git2: missing end-of-block code", br.pos);
  }
  var lit = _huff_new();
  let e2 = _huff_build(&mut lit, &lengths, hlit);
  if e2.len() > 0 { return _at(e2, br.pos); }
  var dl = Vec[Int].new();
  i = 0;
  while i < hdist {
    let lv: Int = lengths[hlit + i];
    dl.push(lv);
    i = i + 1;
  }
  var dist = _huff_new();
  let e3 = _huff_build(&mut dist, &dl, hdist);
  if e3.len() > 0 { return _at(e3, br.pos); }
  return _decode_huffman_block(data, br, out, &lit, &dist);
}

// Core DEFLATE block loop (shared by the raw and zlib entry points).
fn _inflate_stream(data: &Vec[UInt8], start: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if start < 0 || start > data.len() {
    return _err_int(_at("git2: bad deflate start", start));
  }
  var br = _bits_new(start);
  var final = 0;
  while final == 0 {
    if _bits_left(data, &mut br) < 3 {
      return _err_int(_at("git2: truncated deflate block header", br.pos));
    }
    final = _bits_take(data, &mut br, 1);
    let btype = _bits_take(data, &mut br, 2);
    var e = "";
    if btype == 0 {
      e = _decode_stored(data, &mut br, out);
    } elif btype == 1 {
      e = _decode_fixed(data, &mut br, out);
    } elif btype == 2 {
      e = _decode_dynamic(data, &mut br, out);
    } else {
      return _err_int(_at("git2: invalid deflate block type", br.pos));
    }
    if e.len() > 0 {
      return _err_int(e);
    }
  }
  var endpos = br.pos;
  if br.bit != 0 {
    endpos = br.pos + 1;
  }
  return _ok_int(endpos);
}

// Inflate one zlib stream located at `start`: validates the header, decodes
// the DEFLATE payload into out and verifies the Adler-32 trailer. Returns
// the offset just past the four-byte trailer.
fn _zlib_inflate_at(z: &Vec[UInt8], start: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  if start < 0 || start + 2 > z.len() {
    return _err_int(_at("git2: truncated zlib header", start));
  }
  let cmf = _b(z, start);
  let flg = _b(z, start + 1);
  if cmf % 16 != 8 {
    return _err_int(_at("git2: unsupported zlib method", start));
  }
  if cmf / 16 > 7 {
    return _err_int(_at("git2: invalid zlib window size", start));
  }
  if (cmf * 256 + flg) % 31 != 0 {
    return _err_int(_at("git2: bad zlib fcheck", start));
  }
  if (flg / 32) % 2 == 1 {
    return _err_int(_at("git2: zlib preset dictionary unsupported", start));
  }
  let out_start = out.len();
  let r = _inflate_stream(z, start + 2, out);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let end: Int = r.value;
  if end + 4 > z.len() {
    return _err_int(_at("git2: truncated zlib trailer", end));
  }
  let stored = _be32(z, end);
  let computed = _adler_seg(out, out_start, out.len());
  if stored != computed {
    return _err_int(_at("git2: adler mismatch", end));
  }
  return _ok_int(end + 4);
}

/// Raw DEFLATE decoder (RFC 1951). Decodes the stream starting at byte
/// `start` and APPENDS the output to `out`; returns the offset just past the
/// final block (the first byte after the last byte carrying stream bits).
///
/// Supported: stored (00), fixed-Huffman (01) and dynamic-Huffman (10)
/// blocks, all RFC length/distance codes, and overlapping LZ77 copies.
/// Rejected with a "git2: ... at <offset>" message: truncated headers,
/// truncations inside any code or extra bits, invalid block type 3, invalid
/// or incomplete codes, invalid length/distance symbols, distance 0 or a
/// distance larger than the output produced so far, and code-length repeat
/// overflows. Complexity: O(input + output).
pub fn git2_deflate_decode_into(data: &Vec[UInt8], start: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  return _inflate_stream(data, start, out);
}

/// zlib decoder (RFC 1950) for a whole buffer. Validates CMF/FLG (method 8,
/// CINFO <= 7, FCHECK, FDICT rejected), decodes the DEFLATE payload into
/// `out` and verifies the big-endian Adler-32 trailer. Returns the number of
/// bytes consumed, which must equal z.len(); trailing bytes after the
/// trailer are rejected. Complexity: O(input + output).
pub fn git2_zlib_decode_into(z: &Vec[UInt8], out: &mut Vec[UInt8]) -> Result[Int, Str] {
  let r = _zlib_inflate_at(z, 0, out);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let end: Int = r.value;
  if end != z.len() {
    return _err_int(_at("git2: trailing bytes after zlib stream", end));
  }
  return _ok_int(end);
}

/// zlib decoder returning a fresh buffer (see git2_zlib_decode_into).
/// Complexity: O(input + output).
pub fn git2_zlib_decode(z: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = _zlib_inflate_at(z, 0, &mut out);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  let end: Int = r.value;
  if end != z.len() {
    return _err_bytes(_at("git2: trailing bytes after zlib stream", end));
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Loose objects
// --------------------------------------------------

/// Split and validate a DECOMPRESSED loose-object buffer:
/// "<type> <size>\0<payload>". The type must be blob, tree, commit or tag;
/// the size must be canonical decimal (no leading zeros except the single
/// digit 0, no sign, no empty field) and must equal the payload length. The
/// returned object_type uses the pack-format codes (3 blob, 2 tree,
/// 1 commit, 4 tag) and header_size is the byte count up to and including
/// the NUL. Complexity: O(buffer length).
pub fn git2_loose_split(raw: &Vec[UInt8]) -> Result[GitLooseObject, Str] {
  let n = raw.len();
  if n == 0 {
    return _err_loose(_at("git2: empty loose header", 0));
  }
  let nul = _find_nul(raw, 0, n);
  if nul < 0 {
    return _err_loose(_at("git2: loose header missing NUL", 0));
  }
  var sp = -1;
  var i = 0;
  while i < nul {
    if _b(raw, i) == 32 {
      sp = i;
      break;
    }
    i = i + 1;
  }
  if sp < 0 {
    return _err_loose(_at("git2: loose header missing type separator", 0));
  }
  if sp == 0 {
    return _err_loose(_at("git2: loose header missing type", 0));
  }
  let tname = _str_range(raw, 0, sp);
  let tcode = git2_object_type_code(tname);
  if tcode == 0 {
    return _err_loose(_at("git2: unknown loose object type", 0));
  }
  let size_start = sp + 1;
  if size_start >= nul {
    return _err_loose(_at("git2: loose header missing size", size_start));
  }
  let digits = nul - size_start;
  var size = 0;
  i = size_start;
  while i < nul {
    let c = _b(raw, i);
    if c < 48 || c > 57 {
      return _err_loose(_at("git2: loose size is not decimal", i));
    }
    if i == size_start && c == 48 && digits > 1 {
      return _err_loose(_at("git2: loose size has leading zero", i));
    }
    if size > 922337203685477579 {
      return _err_loose(_at("git2: loose size overflow", i));
    }
    size = size * 10 + (c - 48);
    i = i + 1;
  }
  let payload_start = nul + 1;
  let avail = n - payload_start;
  if size != avail {
    return _err_loose(_at("git2: loose size mismatch", payload_start));
  }
  var payload = Vec[UInt8].new();
  _append_range(&mut payload, raw, payload_start, n);
  return _ok_loose(GitLooseObject{
    object_type: tcode;
    type_name: tname;
    declared_size: size;
    header_size: payload_start;
    payload: payload;
  });
}

/// Decode one zlib-compressed loose object: inflate (strict, Adler-verified)
/// and split the "<type> <size>\0" header. Complexity: O(input + output).
pub fn git2_loose_parse(zdata: &Vec[UInt8]) -> Result[GitLooseObject, Str] {
  var raw = Vec[UInt8].new();
  let r = git2_zlib_decode_into(zdata, &mut raw);
  if !r.is_ok {
    return _err_loose(r.error);
  }
  let r2 = git2_loose_split(&raw);
  if !r2.is_ok {
    return _err_loose(r2.error);
  }
  let v: GitLooseObject = r2.value;
  return _ok_loose(v);
}

// --------------------------------------------------
//  Tree payloads
// --------------------------------------------------

// Effective sort byte at position i of a tree name: the raw byte, a '/'
// (47) one past the end when the entry is a directory (mode 040000), or -1
// past the end otherwise. Git orders directory names as if a slash were
// appended and leaves other modes as plain names.
fn _tree_eff_byte(data: &Vec[UInt8], off: Int, len: Int, is_tree: Int, i: Int) -> Int {
  if i < len {
    return _b(data, off + i);
  }
  if i == len && is_tree == 1 {
    return 47;
  }
  return -1;
}

// Git tree-entry ordering comparison of two name ranges. Returns -1, 0 or 1.
fn _tree_key_cmp(data: &Vec[UInt8], a_off: Int, a_len: Int, a_tree: Int, b_off: Int, b_len: Int, b_tree: Int) -> Int {
  var maxn = a_len;
  if b_len > maxn { maxn = b_len; }
  var i = 0;
  while i <= maxn {
    let ca = _tree_eff_byte(data, a_off, a_len, a_tree, i);
    let cb = _tree_eff_byte(data, b_off, b_len, b_tree, i);
    if ca != cb {
      if ca < cb { return -1; }
      return 1;
    }
    if ca < 0 { return 0; }
    i = i + 1;
  }
  return 0;
}

// Append one tree entry; every parallel vector receives exactly one entry.
fn _tree_push(t: &mut GitTree, off: Int, mode: Str, mval: Int, name: Str, id: &Vec[UInt8]) {
  t.entry_offset.push(off);
  t.entry_mode.push(mode);
  t.entry_mode_value.push(mval);
  t.entry_name.push(name);
  var i = 0;
  while i < id.len() {
    t.entry_id.push(id[i]);
    i = i + 1;
  }
}

/// Walk a raw tree payload: repeated entries of the form
/// "<mode ASCII-octal> <name>\0<raw id>". `id_size` must be 20 (SHA-1) or 32
/// (SHA-256). Each mode is 1..6 octal digits with no leading zero; each name
/// is non-empty and contains neither 0x00 nor '/'; ids are raw bytes. Entries
/// must be strictly increasing under the Git tree sort order (directory names
/// compare as if a trailing '/' were appended); duplicates and out-of-order
/// entries are rejected with byte offsets. An empty payload yields an empty
/// tree. Complexity: O(payload length).
pub fn git2_tree_walk(payload: &Vec[UInt8], id_size: Int) -> Result[GitTree, Str] {
  if id_size != 20 && id_size != 32 {
    return _err_tree(_at("git2: bad id size", 0));
  }
  let n = payload.len();
  var t = GitTree{
    id_size: id_size;
    entry_count: 0;
    entry_offset: Vec[Int].new();
    entry_mode: Vec[Str].new();
    entry_mode_value: Vec[Int].new();
    entry_name: Vec[Str].new();
    entry_id: Vec[UInt8].new();
  };
  var pos = 0;
  var prev_mode = -1;
  var prev_name_start = 0;
  var prev_name_len = 0;
  var first = 1;
  while pos < n {
    let entry_off = pos;
    let mode_start = pos;
    if _b(payload, pos) == 48 {
      return _err_tree(_at("git2: tree mode has leading zero", mode_start));
    }
    var mode = 0;
    var digits = 0;
    while pos < n && digits < 7 {
      let c = _b(payload, pos);
      if c < 48 || c > 55 { break; }
      mode = mode * 8 + (c - 48);
      pos = pos + 1;
      digits = digits + 1;
    }
    if digits == 0 {
      return _err_tree(_at("git2: invalid tree mode", mode_start));
    }
    if digits > 6 {
      return _err_tree(_at("git2: tree mode too long", mode_start));
    }
    if pos >= n {
      return _err_tree(_at("git2: truncated tree entry", pos));
    }
    if _b(payload, pos) != 32 {
      return _err_tree(_at("git2: missing tree mode separator", pos));
    }
    let mode_end = pos;
    pos = pos + 1;
    let name_start = pos;
    var name_end = -1;
    while pos < n {
      let c = _b(payload, pos);
      if c == 0 {
        name_end = pos;
        break;
      }
      if c == 47 {
        return _err_tree(_at("git2: tree name contains slash", pos));
      }
      pos = pos + 1;
    }
    if name_end < 0 {
      return _err_tree(_at("git2: unterminated tree name", name_start));
    }
    let name_len = name_end - name_start;
    if name_len == 0 {
      return _err_tree(_at("git2: empty tree name", name_start));
    }
    let id_start = name_end + 1;
    if id_start + id_size > n {
      return _err_tree(_at("git2: truncated tree id", id_start));
    }
    var is_tree = 0;
    if mode == 16384 { is_tree = 1; }
    if first == 0 {
      let c = _tree_key_cmp(payload, prev_name_start, prev_name_len, prev_mode, name_start, name_len, is_tree);
      if c == 0 {
        return _err_tree(_at("git2: duplicate tree entry", entry_off));
      }
      if c > 0 {
        return _err_tree(_at("git2: tree entries out of order", entry_off));
      }
    }
    let mode_str = _str_range(payload, mode_start, mode_end);
    let name_str = _str_range(payload, name_start, name_end);
    var id = Vec[UInt8].new();
    _append_range(&mut id, payload, id_start, id_start + id_size);
    _tree_push(&mut t, entry_off, mode_str, mode, name_str, &id);
    t.entry_count = t.entry_count + 1;
    prev_mode = is_tree;
    prev_name_start = name_start;
    prev_name_len = name_len;
    first = 0;
    pos = id_start + id_size;
  }
  return _ok_tree(t);
}

/// Number of tree entries. Complexity: O(1).
pub fn git2_tree_entry_count(t: &GitTree) -> Int {
  return t.entry_count;
}

/// ASCII-octal mode of tree entry i. Err("git2: index out of range") when i
/// is negative or >= git2_tree_entry_count. Complexity: O(1).
pub fn git2_tree_mode(t: &GitTree, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= t.entry_count {
    return _err_str("git2: index out of range");
  }
  let v: Str = t.entry_mode[i];
  return _ok_str(v);
}

/// Name of tree entry i (NUL-free by construction). Err("git2: index out of
/// range") when i is negative or >= git2_tree_entry_count. Complexity: O(1).
pub fn git2_tree_name(t: &GitTree, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= t.entry_count {
    return _err_str("git2: index out of range");
  }
  let v: Str = t.entry_name[i];
  return _ok_str(v);
}

/// Byte k (0 .. id_size-1) of tree entry i's raw id. Err("git2: index out of
/// range") when i or k is out of range. Complexity: O(1).
pub fn git2_tree_id_byte(t: &GitTree, i: Int, k: Int) -> Result[Int, Str] {
  if i < 0 || i >= t.entry_count {
    return _err_int("git2: index out of range");
  }
  if k < 0 || k >= t.id_size {
    return _err_int("git2: index out of range");
  }
  let sz: Int = t.id_size;
  let b: UInt8 = t.entry_id[i * sz + k];
  return _ok_int((b as Int) & 0xFF);
}

// --------------------------------------------------
//  Commit and tag headers
// --------------------------------------------------

// Append one logical header line.
fn _doc_push(d: &mut _Doc, key: Str, value: Str, line_start: Int, value_start: Int) {
  d.key.push(key);
  d.value.push(value);
  d.line_start.push(line_start);
  d.value_start.push(value_start);
}

// Parse LF-separated header lines into d. A line starting with a space is a
// folded continuation of the previous value (joined with LF, leading space
// stripped); the first empty line ends the header and starts the message.
// Returns "" on success or a message with byte offsets.
fn _doc_parse(data: &Vec[UInt8], d: &mut _Doc) -> Str {
  let n = data.len();
  var pos = 0;
  var have = 0;
  var cur_key = "";
  var cur_val = "";
  var cur_start = 0;
  var cur_vstart = 0;
  d.message_start = n;
  while pos < n {
    let line_start = pos;
    var e = line_start;
    while e < n {
      if _b(data, e) == 10 {
        break;
      }
      e = e + 1;
    }
    if e == line_start {
      if have == 1 {
        _doc_push(d, cur_key, cur_val, cur_start, cur_vstart);
        have = 0;
      }
      if e < n {
        d.message_start = e + 1;
      } else {
        d.message_start = e;
      }
      return "";
    }
    if _find_nul(data, line_start, e) >= 0 {
      return _at("git2: NUL byte in header line", line_start);
    }
    if _b(data, line_start) == 32 {
      if have == 0 {
        return _at("git2: continuation without header", line_start);
      }
      let chunk = _str_range(data, line_start + 1, e);
      cur_val = cur_val + "\n" + chunk;
    } else {
      if have == 1 {
        _doc_push(d, cur_key, cur_val, cur_start, cur_vstart);
        have = 0;
      }
      var sp = -1;
      var k2 = line_start;
      while k2 < e {
        if _b(data, k2) == 32 {
          sp = k2;
          break;
        }
        k2 = k2 + 1;
      }
      if sp < 0 {
        return _at("git2: header line without value", line_start);
      }
      if sp == line_start {
        return _at("git2: header line without key", line_start);
      }
      var kk = line_start;
      while kk < sp {
        let kb = _b(data, kk);
        if kb < 33 || kb > 126 {
          return _at("git2: invalid header key byte", kk);
        }
        kk = kk + 1;
      }
      cur_key = _str_range(data, line_start, sp);
      cur_val = _str_range(data, sp + 1, e);
      cur_start = line_start;
      cur_vstart = sp + 1;
      have = 1;
    }
    pos = e + 1;
  }
  if have == 1 {
    _doc_push(d, cur_key, cur_val, cur_start, cur_vstart);
  }
  d.message_start = n;
  return "";
}

// New empty header document.
fn _doc_new() -> _Doc {
  return _Doc{
    key: Vec[Str].new();
    value: Vec[Str].new();
    line_start: Vec[Int].new();
    value_start: Vec[Int].new();
    message_start: 0;
  };
}

/// Parse a commit payload: the `tree` header (must come first, exactly
/// once; a 40- or 64-hex id selecting SHA-1/SHA-256), zero or more `parent`
/// headers, the required `author` and `committer` headers, optional
/// `encoding` and `gpgsig` headers (folded continuation lines joined with
/// LF) and any unknown keys (collected in `other_keys`). The first empty
/// line starts the message; a payload with no empty line has an empty
/// message and `header_end` == payload length. Ids are decoded to raw bytes
/// and the message is materialized as a Str (NUL bytes are rejected).
/// Complexity: O(payload length).
pub fn git2_commit_parse(payload: &Vec[UInt8]) -> Result[GitCommit, Str] {
  var d = _doc_new();
  let e0 = _doc_parse(payload, &mut d);
  if e0.len() > 0 {
    return _err_commit(e0);
  }
  let nk: Int = d.key.len();
  if nk == 0 {
    return _err_commit("git2: empty commit header");
  }
  let k0: Str = d.key[0];
  if !_str_eq(k0, "tree") {
    let ls0: Int = d.line_start[0];
    return _err_commit(_at("git2: commit tree must be first", ls0));
  }
  var tree = Vec[UInt8].new();
  var parents = Vec[UInt8].new();
  var parent_count = 0;
  var author = "";
  var committer = "";
  var encoding = "";
  var gpgsig = "";
  var other = Vec[Str].new();
  var tree_seen = 0;
  var author_seen = 0;
  var committer_seen = 0;
  var encoding_seen = 0;
  var gpgsig_seen = 0;
  var id_size = 0;
  var i = 0;
  while i < nk {
    let k: Str = d.key[i];
    let v: Str = d.value[i];
    let vs: Int = d.value_start[i];
    let ls: Int = d.line_start[i];
    if _str_eq(k, "tree") {
      if tree_seen != 0 {
        return _err_commit(_at("git2: duplicate tree header", ls));
      }
      if !_hex_str_ok(v) {
        return _err_commit(_at("git2: invalid tree id", vs));
      }
      let hl = v.len();
      if hl != 40 && hl != 64 {
        return _err_commit(_at("git2: invalid tree id length", vs));
      }
      id_size = hl / 2;
      tree = _hex_decode_str(v);
      tree_seen = 1;
    } elif _str_eq(k, "parent") {
      if tree_seen == 0 {
        return _err_commit(_at("git2: commit parent before tree", ls));
      }
      if !_hex_str_ok(v) {
        return _err_commit(_at("git2: invalid parent id", vs));
      }
      if v.len() != id_size * 2 {
        return _err_commit(_at("git2: parent id length mismatch", vs));
      }
      let pb = _hex_decode_str(v);
      _append_all(&mut parents, &pb);
      parent_count = parent_count + 1;
    } elif _str_eq(k, "author") {
      if author_seen != 0 {
        return _err_commit(_at("git2: duplicate author header", ls));
      }
      author = v;
      author_seen = 1;
    } elif _str_eq(k, "committer") {
      if committer_seen != 0 {
        return _err_commit(_at("git2: duplicate committer header", ls));
      }
      committer = v;
      committer_seen = 1;
    } elif _str_eq(k, "encoding") {
      if encoding_seen != 0 {
        return _err_commit(_at("git2: duplicate encoding header", ls));
      }
      encoding = v;
      encoding_seen = 1;
    } elif _str_eq(k, "gpgsig") {
      if gpgsig_seen != 0 {
        return _err_commit(_at("git2: duplicate gpgsig header", ls));
      }
      gpgsig = v;
      gpgsig_seen = 1;
    } else {
      other.push(k);
    }
    i = i + 1;
  }
  if tree_seen == 0 {
    return _err_commit("git2: commit missing tree");
  }
  if author_seen == 0 {
    return _err_commit("git2: commit missing author");
  }
  if committer_seen == 0 {
    return _err_commit("git2: commit missing committer");
  }
  let ms: Int = d.message_start;
  let nul_at = _find_nul(payload, ms, payload.len());
  if nul_at >= 0 {
    return _err_commit(_at("git2: NUL byte in commit message", nul_at));
  }
  let message = _str_range(payload, ms, payload.len());
  return _ok_commit(GitCommit{
    id_size: id_size;
    tree: tree;
    parent_count: parent_count;
    parent_id: parents;
    author: author;
    committer: committer;
    encoding: encoding;
    gpgsig: gpgsig;
    other_keys: other;
    header_end: ms;
    message: message;
  });
}

/// Parse an annotated tag payload: the `object` header (must come first,
/// exactly once; 40- or 64-hex id), the `type` header (blob/tree/commit/tag),
/// the `tag` name, and optional `tagger` and `gpgsig` headers plus unknown
/// keys. The first empty line starts the message. Complexity:
/// O(payload length).
pub fn git2_tag_parse(payload: &Vec[UInt8]) -> Result[GitTag, Str] {
  var d = _doc_new();
  let e0 = _doc_parse(payload, &mut d);
  if e0.len() > 0 {
    return _err_tag(e0);
  }
  let nk: Int = d.key.len();
  if nk == 0 {
    return _err_tag("git2: empty tag header");
  }
  let k0: Str = d.key[0];
  if !_str_eq(k0, "object") {
    let ls0: Int = d.line_start[0];
    return _err_tag(_at("git2: tag object must be first", ls0));
  }
  var object_id = Vec[UInt8].new();
  var target_type = 0;
  var target_raw = "";
  var tag_name = "";
  var tagger = "";
  var gpgsig = "";
  var other = Vec[Str].new();
  var object_seen = 0;
  var type_seen = 0;
  var name_seen = 0;
  var tagger_seen = 0;
  var gpgsig_seen = 0;
  var id_size = 0;
  var i = 0;
  while i < nk {
    let k: Str = d.key[i];
    let v: Str = d.value[i];
    let vs: Int = d.value_start[i];
    let ls: Int = d.line_start[i];
    if _str_eq(k, "object") {
      if object_seen != 0 {
        return _err_tag(_at("git2: duplicate object header", ls));
      }
      if !_hex_str_ok(v) {
        return _err_tag(_at("git2: invalid object id", vs));
      }
      let hl = v.len();
      if hl != 40 && hl != 64 {
        return _err_tag(_at("git2: invalid object id length", vs));
      }
      id_size = hl / 2;
      object_id = _hex_decode_str(v);
      object_seen = 1;
    } elif _str_eq(k, "type") {
      if type_seen != 0 {
        return _err_tag(_at("git2: duplicate type header", ls));
      }
      let tc = git2_object_type_code(v);
      if tc == 0 {
        return _err_tag(_at("git2: unknown tag object type", vs));
      }
      target_type = tc;
      target_raw = v;
      type_seen = 1;
    } elif _str_eq(k, "tag") {
      if name_seen != 0 {
        return _err_tag(_at("git2: duplicate tag header", ls));
      }
      if v.len() == 0 {
        return _err_tag(_at("git2: empty tag name", vs));
      }
      tag_name = v;
      name_seen = 1;
    } elif _str_eq(k, "tagger") {
      if tagger_seen != 0 {
        return _err_tag(_at("git2: duplicate tagger header", ls));
      }
      tagger = v;
      tagger_seen = 1;
    } elif _str_eq(k, "gpgsig") {
      if gpgsig_seen != 0 {
        return _err_tag(_at("git2: duplicate gpgsig header", ls));
      }
      gpgsig = v;
      gpgsig_seen = 1;
    } else {
      other.push(k);
    }
    i = i + 1;
  }
  if object_seen == 0 {
    return _err_tag("git2: tag missing object");
  }
  if type_seen == 0 {
    return _err_tag("git2: tag missing type");
  }
  if name_seen == 0 {
    return _err_tag("git2: tag missing tag name");
  }
  let ms: Int = d.message_start;
  let nul_at = _find_nul(payload, ms, payload.len());
  if nul_at >= 0 {
    return _err_tag(_at("git2: NUL byte in tag message", nul_at));
  }
  let message = _str_range(payload, ms, payload.len());
  return _ok_tag(GitTag{
    id_size: id_size;
    object_id: object_id;
    target_type: target_type;
    target_type_raw: target_raw;
    tag_name: tag_name;
    tagger: tagger;
    gpgsig: gpgsig;
    other_keys: other;
    header_end: ms;
    message: message;
  });
}

/// Number of parents recorded in a parsed commit. Complexity: O(1).
pub fn git2_commit_parent_count(c: &GitCommit) -> Int {
  return c.parent_count;
}

/// Byte k (0 .. id_size-1) of the commit's raw tree id. Err("git2: index out
/// of range") when k is out of range. Complexity: O(1).
pub fn git2_commit_tree_byte(c: &GitCommit, k: Int) -> Result[Int, Str] {
  if k < 0 || k >= c.id_size {
    return _err_int("git2: index out of range");
  }
  let b: UInt8 = c.tree[k];
  return _ok_int((b as Int) & 0xFF);
}

/// Byte k (0 .. id_size-1) of parent i's raw id. Err("git2: index out of
/// range") when i or k is out of range. Complexity: O(1).
pub fn git2_commit_parent_byte(c: &GitCommit, i: Int, k: Int) -> Result[Int, Str] {
  if i < 0 || i >= c.parent_count {
    return _err_int("git2: index out of range");
  }
  if k < 0 || k >= c.id_size {
    return _err_int("git2: index out of range");
  }
  let sz: Int = c.id_size;
  let b: UInt8 = c.parent_id[i * sz + k];
  return _ok_int((b as Int) & 0xFF);
}

// --------------------------------------------------
//  Delta payloads
// --------------------------------------------------

// Read one base-128 little-endian varint at pos (groups of 7 bits, low group
// first; at most 8 continuation groups). Returns the value and the next
// offset.
fn _varint7_read(data: &Vec[UInt8], pos: Int) -> Result[_Varint, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_varint(_at("git2: truncated delta size", pos));
  }
  var value = 0;
  var mult = 1;
  var p = pos;
  var groups = 0;
  var keep = 1;
  while keep == 1 {
    if p >= n {
      return _err_varint(_at("git2: truncated delta size", p));
    }
    let b = _b(data, p);
    value = value + (b % 128) * mult;
    p = p + 1;
    if b / 128 == 0 {
      keep = 0;
    } else {
      groups = groups + 1;
      if groups > 8 {
        return _err_varint(_at("git2: oversized delta size", pos));
      }
      mult = mult * 128;
    }
  }
  return _ok_varint(_Varint{
    value: value;
    next: p;
  });
}

/// Apply a Git delta to `base`. The delta begins with the source size and
/// target size varints (base-128 little-endian, low group first); the opcode
/// stream then alternates copy opcodes (bit 7 set; bits 0..3 select offset
/// bytes 1, 2, 3, 4 and bits 4..6 select size bytes 1, 2, 3, both
/// little-endian; size 0 means 65536) and insert opcodes (1..127 literal byte
/// counts). The source size must equal base.len(), copies must stay inside
/// the base, the output must land exactly on the target size, and opcode 0
/// is rejected. Returns the reconstructed target buffer. Complexity:
/// O(delta + target).
pub fn git2_delta_apply(base: &Vec[UInt8], delta: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let r1 = _varint7_read(delta, 0);
  if !r1.is_ok {
    return _err_bytes(r1.error);
  }
  let v1: _Varint = r1.value;
  let src_size = v1.value;
  if src_size != base.len() {
    return _err_bytes(_at("git2: delta source size mismatch", 0));
  }
  let r2 = _varint7_read(delta, v1.next);
  if !r2.is_ok {
    return _err_bytes(r2.error);
  }
  let v2: _Varint = r2.value;
  let tgt_size = v2.value;
  var pos = v2.next;
  var out = Vec[UInt8].new();
  let n = delta.len();
  while pos < n {
    let op = _b(delta, pos);
    let op_pos = pos;
    pos = pos + 1;
    if op == 0 {
      return _err_bytes(_at("git2: reserved delta opcode", op_pos));
    }
    if op >= 128 {
      var offset = 0;
      var size = 0;
      var mult = 1;
      if op % 2 == 1 {
        if pos >= n {
          return _err_bytes(_at("git2: truncated delta copy", pos));
        }
        offset = offset + _b(delta, pos) * mult;
        pos = pos + 1;
      }
      mult = 256;
      if (op / 2) % 2 == 1 {
        if pos >= n {
          return _err_bytes(_at("git2: truncated delta copy", pos));
        }
        offset = offset + _b(delta, pos) * mult;
        pos = pos + 1;
      }
      mult = 65536;
      if (op / 4) % 2 == 1 {
        if pos >= n {
          return _err_bytes(_at("git2: truncated delta copy", pos));
        }
        offset = offset + _b(delta, pos) * mult;
        pos = pos + 1;
      }
      mult = 16777216;
      if (op / 8) % 2 == 1 {
        if pos >= n {
          return _err_bytes(_at("git2: truncated delta copy", pos));
        }
        offset = offset + _b(delta, pos) * mult;
        pos = pos + 1;
      }
      mult = 1;
      if (op / 16) % 2 == 1 {
        if pos >= n {
          return _err_bytes(_at("git2: truncated delta copy", pos));
        }
        size = size + _b(delta, pos) * mult;
        pos = pos + 1;
      }
      mult = 256;
      if (op / 32) % 2 == 1 {
        if pos >= n {
          return _err_bytes(_at("git2: truncated delta copy", pos));
        }
        size = size + _b(delta, pos) * mult;
        pos = pos + 1;
      }
      mult = 65536;
      if (op / 64) % 2 == 1 {
        if pos >= n {
          return _err_bytes(_at("git2: truncated delta copy", pos));
        }
        size = size + _b(delta, pos) * mult;
        pos = pos + 1;
      }
      if size == 0 { size = 65536; }
      if offset > base.len() || size > base.len() - offset {
        return _err_bytes(_at("git2: delta copy out of range", op_pos));
      }
      _append_range(&mut out, base, offset, offset + size);
      if out.len() > tgt_size {
        return _err_bytes(_at("git2: delta output exceeds target size", op_pos));
      }
    } else {
      if pos + op > n {
        return _err_bytes(_at("git2: truncated delta insert", pos));
      }
      _append_range(&mut out, delta, pos, pos + op);
      pos = pos + op;
      if out.len() > tgt_size {
        return _err_bytes(_at("git2: delta output exceeds target size", op_pos));
      }
    }
  }
  if out.len() != tgt_size {
    return _err_bytes(_at("git2: delta target size mismatch", 0));
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Pack files
// --------------------------------------------------

/// Parse the fixed 12-byte pack header: "PACK", a big-endian version (2 or 3)
/// and the big-endian object count. The 20-byte trailer is NOT checked here
/// (git2_pack_walk validates it). Complexity: O(1).
pub fn git2_pack_header(data: &Vec[UInt8]) -> Result[GitPackHeader, Str] {
  if data.len() < 12 {
    return _err_phead(_at("git2: truncated pack header", 0));
  }
  if _b(data, 0) != 80 || _b(data, 1) != 65 || _b(data, 2) != 67 || _b(data, 3) != 75 {
    return _err_phead(_at("git2: bad pack magic", 0));
  }
  let version = _be32(data, 4);
  if version != 2 && version != 3 {
    return _err_phead(_at("git2: unsupported pack version", 4));
  }
  let count = _be32(data, 8);
  return _ok_phead(GitPackHeader{
    version: version;
    object_count: count;
    header_size: 12;
  });
}

/// Parse one pack entry header at byte `pos`. The first byte carries the
/// 4-bit size low group and the 3-bit type (1 COMMIT, 2 TREE, 3 BLOB, 4 TAG,
/// 6 OFS_DELTA, 7 REF_DELTA; 0 and 5 are rejected); bits 4..6 of every
/// following byte extend the size in big-endian 7-bit groups (at most 8
/// continuation groups, so sizes above 2^60 - 1 are rejected as oversized).
/// OFS_DELTA then carries the Git negative-offset varint (groups of 7 bits
/// with the +1 per group rule; distance 0 and bases before offset 12 are
/// rejected) and REF_DELTA a raw `id_size`-byte base id. `header_size` and
/// `data_offset` locate the zlib stream that follows. Complexity: O(offset
/// digits).
pub fn git2_pack_entry_header(data: &Vec[UInt8], pos: Int, id_size: Int) -> Result[GitPackEntryHeader, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_pentry(_at("git2: truncated pack entry", pos));
  }
  if id_size != 20 && id_size != 32 {
    return _err_pentry(_at("git2: bad id size", pos));
  }
  let first = _b(data, pos);
  let etype = (first / 16) % 8;
  if etype == 0 || etype == 5 {
    return _err_pentry(_at("git2: invalid pack entry type", pos));
  }
  var size = first % 16;
  var mult = 16;
  var cont = first / 128;
  var p = pos + 1;
  var groups = 0;
  while cont == 1 {
    if p >= n {
      return _err_pentry(_at("git2: truncated pack entry header", pos));
    }
    groups = groups + 1;
    if groups > 8 {
      return _err_pentry(_at("git2: oversized pack entry size", pos));
    }
    let b = _b(data, p);
    size = size + (b % 128) * mult;
    mult = mult * 128;
    cont = b / 128;
    p = p + 1;
  }
  if etype == 6 {
    if p >= n {
      return _err_pentry(_at("git2: truncated ofs delta", p));
    }
    var b = _b(data, p);
    var distance = b % 128;
    var ogroups = 0;
    p = p + 1;
    while b / 128 == 1 {
      ogroups = ogroups + 1;
      if ogroups > 8 {
        return _err_pentry(_at("git2: oversized ofs delta offset", pos));
      }
      if p >= n {
        return _err_pentry(_at("git2: truncated ofs delta", p));
      }
      b = _b(data, p);
      distance = (distance + 1) * 128 + (b % 128);
      p = p + 1;
    }
    if distance < 1 {
      return _err_pentry(_at("git2: invalid ofs delta distance", pos));
    }
    if distance > pos - 12 {
      return _err_pentry(_at("git2: ofs delta base out of range", pos));
    }
    return _ok_pentry(GitPackEntryHeader{
      entry_type: etype;
      size: size;
      header_size: p - pos;
      data_offset: p;
      base_offset: pos - distance;
      base_distance: distance;
      base_id: Vec[UInt8].new();
    });
  }
  if etype == 7 {
    if p + id_size > n {
      return _err_pentry(_at("git2: truncated ref delta id", p));
    }
    var bid = Vec[UInt8].new();
    _append_range(&mut bid, data, p, p + id_size);
    return _ok_pentry(GitPackEntryHeader{
      entry_type: etype;
      size: size;
      header_size: p + id_size - pos;
      data_offset: p + id_size;
      base_offset: -1;
      base_distance: -1;
      base_id: bid;
    });
  }
  return _ok_pentry(GitPackEntryHeader{
    entry_type: etype;
    size: size;
    header_size: p - pos;
    data_offset: p;
    base_offset: -1;
    base_distance: -1;
    base_id: Vec[UInt8].new();
  });
}

// Append one entry to a walked pack; every parallel vector receives exactly
// one entry and the id trailer is padded to id_size bytes.
fn _pack_push(eh: &GitPackEntryHeader, pack: &mut GitPack, off: Int, data_off: Int, end: Int, out_size: Int, flat_off: Int, id_size: Int) {
  pack.entry_type.push(eh.entry_type);
  pack.entry_offset.push(off);
  pack.entry_header_size.push(eh.header_size);
  pack.entry_data_offset.push(data_off);
  pack.entry_end.push(end);
  pack.entry_size.push(eh.size);
  pack.entry_out_size.push(out_size);
  pack.entry_base_offset.push(eh.base_offset);
  pack.entry_base_distance.push(eh.base_distance);
  let have_id = eh.base_id.len() == id_size;
  var i = 0;
  while i < id_size {
    if have_id {
      let b: UInt8 = eh.base_id[i];
      pack.entry_base_id.push(b);
    } else {
      pack.entry_base_id.push(0 as UInt8);
    }
    i = i + 1;
  }
  pack.entry_data_off.push(flat_off);
}

/// Walk a whole pack file: validate the header, then parse, inflate (with
/// Adler verification) and record every entry in order, requiring exactly
/// `object_count` entries followed by the raw 20-byte trailer. Each
/// decompressed entry size must equal the declared size. The trailer
/// checksum is preserved but not verified (SHA-1 is caller-side).
/// Complexity: O(pack length + decompressed length). Errors carry byte
/// offsets.
pub fn git2_pack_walk(data: &Vec[UInt8], id_size: Int) -> Result[GitPack, Str] {
  if id_size != 20 && id_size != 32 {
    return _err_pack(_at("git2: bad id size", 0));
  }
  let hr = git2_pack_header(data);
  if !hr.is_ok {
    return _err_pack(hr.error);
  }
  let h: GitPackHeader = hr.value;
  let n = data.len();
  if n < 32 {
    return _err_pack(_at("git2: truncated pack", n));
  }
  let limit = n - 20;
  if h.object_count > limit {
    return _err_pack(_at("git2: pack object count exceeds file size", 8));
  }
  var pack = GitPack{
    version: h.version;
    object_count: h.object_count;
    entry_type: Vec[Int].new();
    entry_offset: Vec[Int].new();
    entry_header_size: Vec[Int].new();
    entry_data_offset: Vec[Int].new();
    entry_end: Vec[Int].new();
    entry_size: Vec[Int].new();
    entry_out_size: Vec[Int].new();
    entry_base_offset: Vec[Int].new();
    entry_base_distance: Vec[Int].new();
    entry_base_id: Vec[UInt8].new();
    entry_data: Vec[UInt8].new();
    entry_data_off: Vec[Int].new();
    checksum: Vec[UInt8].new();
  };
  var pos = 12;
  var i = 0;
  while i < h.object_count {
    if pos >= limit {
      return _err_pack(_at("git2: truncated pack entry", pos));
    }
    let er = git2_pack_entry_header(data, pos, id_size);
    if !er.is_ok {
      return _err_pack(er.error);
    }
    let eh: GitPackEntryHeader = er.value;
    if eh.data_offset >= limit {
      return _err_pack(_at("git2: truncated pack entry", pos));
    }
    var entry_out = Vec[UInt8].new();
    let zr = _zlib_inflate_at(data, eh.data_offset, &mut entry_out);
    if !zr.is_ok {
      return _err_pack(zr.error);
    }
    let end: Int = zr.value;
    if end > limit {
      return _err_pack(_at("git2: entry overruns pack trailer", pos));
    }
    let actual = entry_out.len();
    if actual != eh.size {
      return _err_pack(_at("git2: pack entry size mismatch", pos));
    }
    let flat_off = pack.entry_data.len();
    _pack_push(&eh, &mut pack, pos, eh.data_offset, end, actual, flat_off, id_size);
    _append_all(&mut pack.entry_data, &entry_out);
    pos = end;
    i = i + 1;
  }
  if pos != limit {
    return _err_pack(_at("git2: pack length does not match object count", pos));
  }
  _append_range(&mut pack.checksum, data, limit, n);
  return _ok_pack(pack);
}

/// Number of walked entries. Complexity: O(1).
pub fn git2_pack_count(p: &GitPack) -> Int {
  return p.entry_type.len();
}

/// Type code of pack entry i. Err("git2: index out of range") when out of
/// range. Complexity: O(1).
pub fn git2_pack_entry_type(p: &GitPack, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= p.entry_type.len() {
    return _err_int("git2: index out of range");
  }
  let v: Int = p.entry_type[i];
  return _ok_int(v);
}

/// Header offset of pack entry i. Err("git2: index out of range") when out
/// of range. Complexity: O(1).
pub fn git2_pack_entry_offset(p: &GitPack, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= p.entry_offset.len() {
    return _err_int("git2: index out of range");
  }
  let v: Int = p.entry_offset[i];
  return _ok_int(v);
}

/// Declared size of pack entry i. Err("git2: index out of range") when out
/// of range. Complexity: O(1).
pub fn git2_pack_entry_size(p: &GitPack, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= p.entry_size.len() {
    return _err_int("git2: index out of range");
  }
  let v: Int = p.entry_size[i];
  return _ok_int(v);
}

/// Index of the pack entry whose header starts at `off`, or -1. Complexity:
/// O(entries).
pub fn git2_pack_entry_by_offset(p: &GitPack, off: Int) -> Int {
  let n: Int = p.entry_offset.len();
  var i = 0;
  while i < n {
    let v: Int = p.entry_offset[i];
    if v == off { return i; }
    i = i + 1;
  }
  return -1;
}

// Copy entry i's decompressed payload out of the flat pack buffer.
fn _pack_entry_bytes_ok(p: &GitPack, i: Int) -> Result[Vec[UInt8], Str] {
  let off: Int = p.entry_data_off[i];
  let len: Int = p.entry_out_size[i];
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    let b: UInt8 = p.entry_data[off + k];
    out.push(b);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Decompressed payload of pack entry i (the raw delta instruction stream
/// for OFS_DELTA/REF_DELTA entries). Err("git2: index out of range") when out
/// of range. Complexity: O(entry size).
pub fn git2_pack_payload(p: &GitPack, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= p.entry_type.len() {
    return _err_bytes("git2: index out of range");
  }
  return _pack_entry_bytes_ok(p, i);
}

// Recursively resolve an entry to its full object bytes: base entries return
// their payload, OFS_DELTA entries apply their delta to the resolved base.
fn _pack_resolve(p: &GitPack, i: Int, depth: Int) -> Result[Vec[UInt8], Str] {
  if depth > 64 {
    return _err_bytes(_at("git2: delta chain too deep", i));
  }
  let t: Int = p.entry_type[i];
  if t == 1 || t == 2 || t == 3 || t == 4 {
    return _pack_entry_bytes_ok(p, i);
  }
  if t == 7 {
    let eo: Int = p.entry_offset[i];
    return _err_bytes(_at("git2: ref delta needs external base", eo));
  }
  if t != 6 {
    return _err_bytes(_at("git2: unknown entry type", i));
  }
  let base_off: Int = p.entry_base_offset[i];
  let base_i = git2_pack_entry_by_offset(p, base_off);
  if base_i < 0 {
    return _err_bytes(_at("git2: ofs delta base not found", base_off));
  }
  let br = _pack_resolve(p, base_i, depth + 1);
  if !br.is_ok {
    return _err_bytes(br.error);
  }
  let base: Vec[UInt8] = br.value;
  let dr = _pack_entry_bytes_ok(p, i);
  if !dr.is_ok {
    return _err_bytes(dr.error);
  }
  let delta: Vec[UInt8] = dr.value;
  let ar = git2_delta_apply(&base, &delta);
  if !ar.is_ok {
    return _err_bytes(ar.error);
  }
  let v: Vec[UInt8] = ar.value;
  return _ok_bytes(v);
}

/// Fully resolve pack entry i to its object bytes. Plain entries return
/// their payload; OFS_DELTA chains are followed (up to 64 deep) and their
/// deltas applied. REF_DELTA entries cannot be resolved from the pack alone
/// (the base id must be looked up through the pack index) and return
/// "git2: ref delta needs external base at <base offset>". Complexity:
/// O(chain length * entry size).
pub fn git2_pack_resolve(p: &GitPack, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= p.entry_type.len() {
    return _err_bytes("git2: index out of range");
  }
  return _pack_resolve(p, i, 0);
}

// --------------------------------------------------
//  Pack index v2
// --------------------------------------------------

// Comparison of object index i's id (inside idx) with a probe id: -1, 0 or 1.
fn _idx_id_cmp(idx: &GitIndex, i: Int, probe: &Vec[UInt8], size: Int) -> Int {
  let sz: Int = idx.id_size;
  var k = 0;
  while k < size {
    let a: UInt8 = idx.id[i * sz + k];
    let x = (a as Int) & 0xFF;
    let y = (probe[k] as Int) & 0xFF;
    if x < y { return -1; }
    if x > y { return 1; }
    k = k + 1;
  }
  return 0;
}

/// Parse a version-2 pack index. Layout: magic 0xFF744F63, version 2, a
/// 256-entry big-endian fanout table (monotonic; fanout[255] == object
/// count), `count` sorted raw ids of `id_size` bytes (20 SHA-1, 32 SHA-256),
/// `count` big-endian CRC-32 values, `count` big-endian 4-byte offsets (an
/// offset with bit 31 set selects the matching entry of the 64-bit offset
/// table that follows), then the raw 20-byte pack checksum and the raw
/// 20-byte idx checksum (neither is verified). The 64-bit table size is
/// derived from the highest referenced slot; every slot must be referenced
/// exactly once and no 64-bit value may have bit 63 set (that would overflow
/// a signed Int). The buffer must end exactly after the idx checksum.
/// Complexity: O(count).
pub fn git2_idx_parse(data: &Vec[UInt8], id_size: Int) -> Result[GitIndex, Str] {
  if id_size != 20 && id_size != 32 {
    return _err_pidx(_at("git2: bad id size", 0));
  }
  let n = data.len();
  if n < 8 {
    return _err_pidx(_at("git2: truncated idx", 0));
  }
  if _b(data, 0) != 255 || _b(data, 1) != 116 || _b(data, 2) != 79 || _b(data, 3) != 99 {
    return _err_pidx(_at("git2: bad idx magic", 0));
  }
  let version = _be32(data, 4);
  if version != 2 {
    return _err_pidx(_at("git2: unsupported idx version", 4));
  }
  if n < 1032 {
    return _err_pidx(_at("git2: truncated idx fanout", n));
  }
  var fanout = Vec[Int].new();
  var prev = 0;
  var b = 0;
  while b < 256 {
    let v = _be32(data, 8 + b * 4);
    if v < prev {
      return _err_pidx(_at("git2: idx fanout not monotonic", 8 + b * 4));
    }
    fanout.push(v);
    prev = v;
    b = b + 1;
  }
  let count = prev;
  let per = id_size + 8;
  let need = 1032 + count * per + 40;
  if need > n {
    return _err_pidx(_at("git2: truncated idx tables", n));
  }
  var id_off = 1032;
  var i = 0;
  while i < count {
    if i > 0 {
      let c = _id_range_cmp(data, id_off, id_off - id_size, id_size);
      if c <= 0 {
        return _err_pidx(_at("git2: idx ids not sorted", id_off));
      }
    }
    let fb = _b(data, id_off);
    let hi_ok: Int = fanout[fb];
    if i >= hi_ok {
      return _err_pidx(_at("git2: idx fanout mismatch", 8 + fb * 4));
    }
    if fb > 0 {
      let lo_ok: Int = fanout[fb - 1];
      if i < lo_ok {
        return _err_pidx(_at("git2: idx fanout mismatch", 8 + fb * 4));
      }
    }
    id_off = id_off + id_size;
    i = i + 1;
  }
  let crc_off = id_off;
  let off_off = crc_off + count * 4;
  var idx = GitIndex{
    version: version;
    count: count;
    id_size: id_size;
    fanout: fanout;
    id: Vec[UInt8].new();
    crc: Vec[Int].new();
    raw_offset: Vec[Int].new();
    large_index: Vec[Int].new();
    large_offset: Vec[Int].new();
    offset: Vec[Int].new();
    pack_checksum: Vec[UInt8].new();
    idx_checksum: Vec[UInt8].new();
  };
  _append_range(&mut idx.id, data, 1032, crc_off);
  i = 0;
  while i < count {
    idx.crc.push(_be32(data, crc_off + i * 4));
    i = i + 1;
  }
  var max_large = -1;
  i = 0;
  while i < count {
    let raw = _be32(data, off_off + i * 4);
    idx.raw_offset.push(raw);
    if raw >= 2147483648 {
      let li = raw - 2147483648;
      idx.large_index.push(li);
      if li > max_large { max_large = li; }
    } else {
      idx.large_index.push(-1);
    }
    i = i + 1;
  }
  let large_count = max_large + 1;
  var seen = _zeros_int(large_count);
  i = 0;
  while i < count {
    let li: Int = idx.large_index[i];
    if li >= 0 {
      if li >= large_count {
        return _err_pidx(_at("git2: idx large offset index out of range", off_off + i * 4));
      }
      let s: Int = seen[li];
      if s != 0 {
        return _err_pidx(_at("git2: idx duplicate large offset index", off_off + i * 4));
      }
      seen[li] = 1;
    }
    i = i + 1;
  }
  let lpos = off_off + count * 4;
  if lpos + large_count * 8 + 40 > n {
    return _err_pidx(_at("git2: truncated idx large offsets", lpos));
  }
  i = 0;
  while i < large_count {
    if seen[i] == 0 {
      return _err_pidx(_at("git2: idx unused large offset slot", lpos + i * 8));
    }
    let hi32 = _be32(data, lpos + i * 8);
    let lo32 = _be32(data, lpos + i * 8 + 4);
    if hi32 >= 2147483648 {
      return _err_pidx(_at("git2: idx large offset out of range", lpos + i * 8));
    }
    idx.large_offset.push(hi32 * 4294967296 + lo32);
    i = i + 1;
  }
  i = 0;
  while i < count {
    let li: Int = idx.large_index[i];
    if li >= 0 {
      let lv: Int = idx.large_offset[li];
      idx.offset.push(lv);
    } else {
      let rv: Int = idx.raw_offset[i];
      idx.offset.push(rv);
    }
    i = i + 1;
  }
  let pcs = lpos + large_count * 8;
  if pcs + 40 != n {
    return _err_pidx(_at("git2: trailing bytes in idx", pcs + 40));
  }
  _append_range(&mut idx.pack_checksum, data, pcs, pcs + 20);
  _append_range(&mut idx.idx_checksum, data, pcs + 20, pcs + 40);
  return _ok_pidx(idx);
}

/// Number of objects in the index. Complexity: O(1).
pub fn git2_idx_count(idx: &GitIndex) -> Int {
  return idx.count;
}

/// Raw id size of the index in bytes (20 or 32). Complexity: O(1).
pub fn git2_idx_id_size(idx: &GitIndex) -> Int {
  return idx.id_size;
}

/// Cumulative fanout value for bucket `b` (0..255): the number of ids whose
/// first byte is <= b. Err("git2: index out of range") when b is out of
/// range. Complexity: O(1).
pub fn git2_idx_fanout(idx: &GitIndex, b: Int) -> Result[Int, Str] {
  if b < 0 || b > 255 {
    return _err_int("git2: index out of range");
  }
  let v: Int = idx.fanout[b];
  return _ok_int(v);
}

/// Resolved (possibly 64-bit) pack offset of object i. Err("git2: index out
/// of range") when out of range. Complexity: O(1).
pub fn git2_idx_offset(idx: &GitIndex, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= idx.count {
    return _err_int("git2: index out of range");
  }
  let v: Int = idx.offset[i];
  return _ok_int(v);
}

/// Stored CRC-32 of object i. Err("git2: index out of range") when out of
/// range. Complexity: O(1).
pub fn git2_idx_crc(idx: &GitIndex, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= idx.count {
    return _err_int("git2: index out of range");
  }
  let v: Int = idx.crc[i];
  return _ok_int(v);
}

/// Byte k (0 .. id_size-1) of object i's raw id. Err("git2: index out of
/// range") when i or k is out of range. Complexity: O(1).
pub fn git2_idx_id_byte(idx: &GitIndex, i: Int, k: Int) -> Result[Int, Str] {
  if i < 0 || i >= idx.count {
    return _err_int("git2: index out of range");
  }
  if k < 0 || k >= idx.id_size {
    return _err_int("git2: index out of range");
  }
  let sz: Int = idx.id_size;
  let b: UInt8 = idx.id[i * sz + k];
  return _ok_int((b as Int) & 0xFF);
}

/// Binary search for a raw object id. The search is bounded by the fanout
/// bucket of the id's first byte. Returns the object index, or -1 when the
/// id, the size or the index itself does not match. Complexity:
/// O(id_size * log count).
pub fn git2_idx_lookup(idx: &GitIndex, id: &Vec[UInt8], id_size: Int) -> Int {
  let count: Int = idx.count;
  if count == 0 { return -1; }
  let sz: Int = idx.id_size;
  if id_size != sz { return -1; }
  if id.len() != id_size { return -1; }
  let b0 = (id[0] as Int) & 0xFF;
  var lo = 0;
  if b0 > 0 {
    let f: Int = idx.fanout[b0 - 1];
    lo = f;
  }
  let hi: Int = idx.fanout[b0];
  var lo2 = lo;
  var hi2 = hi;
  while lo2 < hi2 {
    let mid = (lo2 + hi2) / 2;
    let c = _idx_id_cmp(idx, mid, id, id_size);
    if c == 0 { return mid; }
    if c < 0 {
      lo2 = mid + 1;
    } else {
      hi2 = mid;
    }
  }
  return -1;
}

/// Verify the stored CRC-32 of object i: parse the pack entry header at the
/// recorded offset, inflate its zlib stream to find the entry span and
/// compare the CRC-32 of the raw entry bytes [offset, end) with the stored
/// value. Err(m) when the offset or the pack entry is malformed; Ok(true) or
/// Ok(false) otherwise. Complexity: O(entry size).
pub fn git2_idx_verify_crc(idx: &GitIndex, pack: &Vec[UInt8], i: Int) -> Result[Bool, Str] {
  let orr = git2_idx_offset(idx, i);
  if !orr.is_ok {
    return _err_bool(orr.error);
  }
  let off: Int = orr.value;
  let sz: Int = idx.id_size;
  let er = git2_pack_entry_header(pack, off, sz);
  if !er.is_ok {
    return _err_bool(er.error);
  }
  let h: GitPackEntryHeader = er.value;
  var scratch = Vec[UInt8].new();
  let zr = _zlib_inflate_at(pack, h.data_offset, &mut scratch);
  if !zr.is_ok {
    return _err_bool(zr.error);
  }
  let end: Int = zr.value;
  let cr = git2_idx_crc(idx, i);
  if !cr.is_ok {
    return _err_bool(cr.error);
  }
  let stored: Int = cr.value;
  let computed = _crc32_range(pack, off, end);
  return _ok_bool(computed == stored);
}






