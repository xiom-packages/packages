// XIOM -- xiom.badger: BadgerDB (dgraph-io/badger) file-format structure parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: a read-only STRUCTURE parser for BadgerDB on-disk formats. Callers
// pass the whole file (or a block) as a byte vector; every parsed value is a
// scalar field or an offset/size pair (a span) into that buffer. Nothing is
// mmapped, nothing is written, no storage-engine behaviour (no transactions,
// no memtable, no compaction) is implemented, and no compression format is
// decoded.
//
// Implemented layers, all little-endian as specified by the port brief:
//   * value log entry: a 20-byte header (keyLen u32 LE, valLen u32 LE,
//     expiresAt u64 LE, meta byte, userMeta byte, 2 reserved bytes that must
//     be zero) followed by the key and value bytes; a meta bit table
//     (DELETE 0x01, VALUE_POINTER 0x02, TRANSACTION 0x04, FIN_TXN 0x08,
//     BIT_TXN 0x10, MERGE_ENTRY 0x20) and a multi-entry walk with consumed
//     counts. A 1 MiB sanity cap applies to each key length, each value
//     length and each whole entry; a declared length above the cap is
//     rejected before any span arithmetic.
//   * key structure: the user key followed by an 8-byte version timestamp
//     u64 LE whose bit 0 is the delete tag; version/delete accessors.
//   * SST table: a 16-byte file header (magic, version, block size, checksum
//     type, reserved); data blocks whose entries are LEB128 shared-prefix
//     length, LEB128 key-diff length, LEB128 value length, key diff bytes and
//     value bytes, followed by a 4-byte CRC32C block trailer; a block index
//     (block offset/size + separator key, with its own CRC32C); a bloom
//     filter block (bit count, hash count, bit array, CRC32C) with a
//     double-hash membership helper; and a 16-byte table footer (index
//     handle + CRC32C).
//   * manifest: a 20-byte header (magic, version, creation time, reserved)
//     and a file list of fixed 40-byte entries (id, checksum, size, flags,
//     key-range min/max version) with a trailing CRC32C and consumed counts.
//   * CRC32C (Castagnoli, reflected polynomial 0x82F63B78, init/final
//     0xFFFFFFFF) implemented locally, without the LevelDB rotation mask.
//
// Upstream deviations (verified against dgraph-io/badger sources):
//   * v1.6.2 encodes the value-log header as 18 fixed bytes, big-endian; the
//     v2 line encodes meta/userMeta first and the three lengths as uvarints.
//     This module implements the 20-byte little-endian fixed layout of the
//     port brief (18 meaningful bytes + 2 reserved) and never claims to
//     parse upstream files byte-for-byte.
//   * upstream appends MaxUint64-version big-endian to the key and keeps the
//     delete marker in the vlog meta byte; this module implements the
//     brief's little-endian version suffix with the delete tag in bit 0.
//   * the SST layout follows the port brief (a LevelDB-style table); the
//     upstream v2 table footer is checksumLen u32 + checksum + indexLen u32
//     + index, which is NOT what this parser reads.
// See SPEC.md for the byte-level tables, the error catalog and the exact
// verified subset.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType]; parsed
//     tables are flat parallel Vec fields and every push is mirrored.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int] element reads are bound to typed locals.
//   * 64-bit fields use the overflow-safe bolt/leveldb shape: the low seven
//     bytes accumulate with a `place` factor and the top byte is applied
//     separately, so the raw 64-bit pattern is exact (bit 63 set decodes as
//     a negative Int and is rejected by the version fields; see SPEC.md).
//   * bit tests use division and modulo, never shifts; `&` appears only in
//     the copied CRC32C step and in u32 masks, as in the green sibling
//     packages.
//   * error messages carry byte offsets and file ids as decimal text.

module xiom.badger

use xiom.convert.int;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// Value log entry header size in bytes (brief layout).
pub const BADGER_VLOG_HEADER_SIZE: Int = 20;

// Sanity cap, in bytes, for one key length, one value length and one whole
// value log entry (20 + key + value).
pub const BADGER_VLOG_ENTRY_CAP: Int = 1048576;

// Value log meta bits (brief table).
pub const BADGER_META_DELETE: Int = 1;
pub const BADGER_META_VALUE_POINTER: Int = 2;
pub const BADGER_META_TRANSACTION: Int = 4;
pub const BADGER_META_FIN_TXN: Int = 8;
pub const BADGER_META_BIT_TXN: Int = 16;
pub const BADGER_META_MERGE_ENTRY: Int = 32;

// All six defined meta bits set; a meta byte above this value has undefined
// bits (not rejected by the parser, reported by badger_meta_known).
pub const BADGER_META_ALL: Int = 63;

// Key version tag size: 8-byte u64 LE with bit 0 as the delete tag.
pub const BADGER_KEY_TAG_SIZE: Int = 8;

// SST file header (16 bytes).
pub const BADGER_SST_MAGIC: Int = 1380402242;
pub const BADGER_SST_VERSION: Int = 1;
pub const BADGER_SST_HEADER_SIZE: Int = 16;
pub const BADGER_SST_CHECKSUM_NONE: Int = 0;
pub const BADGER_SST_CHECKSUM_CRC32C: Int = 1;
pub const BADGER_SST_MIN_BLOCK_SIZE: Int = 1;
pub const BADGER_SST_MAX_BLOCK_SIZE: Int = 8388608;

// SST block trailer (4-byte CRC32C) and table footer (16 bytes).
pub const BADGER_SST_BLOCK_TRAILER_SIZE: Int = 4;
pub const BADGER_SST_FOOTER_SIZE: Int = 16;

// Sanity caps for SST structures.
pub const BADGER_SST_MAX_KEY_LEN: Int = 1048576;
pub const BADGER_SST_MAX_VALUE_LEN: Int = 1048576;
pub const BADGER_SST_MAX_INDEX_ENTRIES: Int = 100000;

// Bloom filter block limits.
pub const BADGER_BLOOM_MAX_BITS: Int = 8388608;
pub const BADGER_BLOOM_MAX_HASHES: Int = 64;

// Manifest constants.
pub const BADGER_MANIFEST_MAGIC: Int = 1296516162;
pub const BADGER_MANIFEST_VERSION: Int = 1;
pub const BADGER_MANIFEST_HEADER_SIZE: Int = 20;
pub const BADGER_MANIFEST_ENTRY_SIZE: Int = 40;
pub const BADGER_MANIFEST_MAX_FILES: Int = 100000;

// Manifest file-list flag bits.
pub const BADGER_TABLE_FLAG_DELETED: Int = 1;
pub const BADGER_TABLE_FLAG_KEY_RANGE: Int = 2;
pub const BADGER_TABLE_FLAG_KNOWN: Int = 3;

// badger_vlog_field selectors.
pub const BADGER_VLOG_FIELD_OFFSET: Int = 0;
pub const BADGER_VLOG_FIELD_KEY_OFFSET: Int = 1;
pub const BADGER_VLOG_FIELD_KEY_SIZE: Int = 2;
pub const BADGER_VLOG_FIELD_VALUE_OFFSET: Int = 3;
pub const BADGER_VLOG_FIELD_VALUE_SIZE: Int = 4;
pub const BADGER_VLOG_FIELD_META: Int = 5;
pub const BADGER_VLOG_FIELD_USER_META: Int = 6;
pub const BADGER_VLOG_FIELD_EXPIRES_AT: Int = 7;
pub const BADGER_VLOG_FIELD_COUNT: Int = 8;

// badger_manifest_file_field selectors.
pub const BADGER_FILE_FIELD_ID: Int = 0;
pub const BADGER_FILE_FIELD_CHECKSUM: Int = 1;
pub const BADGER_FILE_FIELD_SIZE: Int = 2;
pub const BADGER_FILE_FIELD_FLAGS: Int = 3;
pub const BADGER_FILE_FIELD_MIN_VERSION: Int = 4;
pub const BADGER_FILE_FIELD_MAX_VERSION: Int = 5;
pub const BADGER_FILE_FIELD_OFFSET: Int = 6;
pub const BADGER_FILE_FIELD_COUNT: Int = 7;

// The module version.
pub const BADGER_MODULE_VERSION: Str = "0.1.0";

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A decoded LEB128 varint plus the number of bytes it consumed.
///
/// `value` is in [0, 2^32) for the SST block-entry reader (at most five
/// bytes, the fifth with payload <= 15).
pub type BadgerVarint = {
  value: Int;
  size: Int;
}

/// A decoded versioned key: user key span plus the 8-byte version tag.
///
/// `tagged` is the raw little-endian u64 of the trailing 8 bytes; `version`
/// is `tagged / 2` (the delete tag removed) and `deleted` is bit 0 of
/// `tagged`. A tag with bit 63 set is rejected as out of Int range.
pub type BadgerKey = {
  user_offset: Int;
  user_size: Int;
  tagged: Int;
  version: Int;
  deleted: Bool;
}

/// One parsed value log entry header.
///
/// `expires_at` is the raw two's-complement u64 pattern of the 8-byte LE
/// field (0 = no expiry); `meta` is the meta bit byte and `user_meta` the
/// caller's user byte. The header is 20 bytes and the key starts right after
/// it.
pub type BadgerVlogHeader = {
  key_len: Int;
  val_len: Int;
  expires_at: Int;
  meta: Int;
  user_meta: Int;
}

/// A whole value log walk, in parallel vectors.
///
/// Entry i occupies [offsets[i], offsets[i] + entry_bytes) in the source
/// buffer; `key_offsets[i]`/`key_sizes[i]` locate the key and
/// `value_offsets[i]`/`value_sizes[i]` the value; `metas[i]`/`user_metas[i]`
/// are the header bytes and `expires[i]` the raw expiry pattern. The vectors
/// are always pushed together and never drift. `total_bytes` is the number of
/// bytes consumed from the walk start to the end of the last entry.
pub type BadgerVlogWalk = {
  count: Int;
  offsets: Vec[Int];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  metas: Vec[Int];
  user_metas: Vec[Int];
  expires: Vec[Int];
  total_bytes: Int;
}

/// A parsed SST file header (16 bytes at offset 0).
///
/// `magic` is BADGER_SST_MAGIC (the four bytes "BDGR"), `version` is
/// BADGER_SST_VERSION, `block_size` the target data-block size and
/// `checksum_type` 0 (none) or 1 (CRC32C).
pub type BadgerSstHeader = {
  magic: Int;
  version: Int;
  block_size: Int;
  checksum_type: Int;
}

/// One decoded SST data-block entry.
///
/// Layout: LEB128 shared-prefix length, LEB128 key-diff length, LEB128 value
/// length, the key-diff bytes, the value bytes. `key` is the fully
/// reconstructed key (shared prefix + diff); `value_offset` is the offset of
/// the value inside the block body; `entry_bytes` is the total consumed byte
/// count.
pub type BadgerSstEntry = {
  shared_len: Int;
  key_len: Int;
  val_len: Int;
  key_offset: Int;
  value_offset: Int;
  entry_bytes: Int;
  key: Vec[UInt8];
}

/// A whole SST data block walked entry by entry, in parallel vectors.
///
/// Keys are in `key_data`/`key_offsets`/`key_sizes`; `shared_lens[i]` is the
/// stored shared-prefix length; `value_offsets[i]`/`value_sizes[i]` locate the
/// value inside the block body; `entry_offsets[i]` is where entry i starts.
pub type BadgerSstEntries = {
  count: Int;
  key_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  shared_lens: Vec[Int];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  entry_offsets: Vec[Int];
}

/// The 4-byte SST block trailer: the raw CRC32C (Castagnoli, no LevelDB
/// mask) of the block body as u32 LE.
pub type BadgerSstBlockTrailer = {
  crc: Int;
}

/// A parsed SST block index (count, block handles, separator keys, CRC32C).
///
/// Entry i describes the data block at [offsets[i], offsets[i] + sizes[i]);
/// `key_offsets[i]`/`key_sizes[i]` slice `key_data` for its separator key.
/// `entries_end` is the offset where the entry region stops (the CRC32C
/// trailer follows); `crc` is the stored u32.
pub type BadgerSstIndex = {
  count: Int;
  offsets: Vec[Int];
  sizes: Vec[Int];
  key_data: Vec[UInt8];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  entries_end: Int;
  crc: Int;
}

/// A parsed 16-byte SST table footer.
///
/// `index_offset` (u64 LE), `index_size` (u32 LE) locate the block index;
/// `crc` is the stored u32 over the first 12 footer bytes.
pub type BadgerSstFooter = {
  index_offset: Int;
  index_size: Int;
  crc: Int;
}

/// A parsed bloom filter block.
///
/// `nbits` is the bit-array length, `nhashes` the probe count,
/// `bits_offset`/`bits_size` locate the bit array in the source buffer and
/// `crc` is the stored u32 over the nbits/hashes/bits bytes.
pub type BadgerBloom = {
  nbits: Int;
  nhashes: Int;
  bits_offset: Int;
  bits_size: Int;
  crc: Int;
}

/// The two probe hashes of one key, derived from domain-separated FNV-1a-32.
///
/// `h1` uses domain byte 1, `h2` domain byte 2; `h2` is forced non-zero so
/// the double-hash sequence h1 + i*h2 mod nbits has full period 1.
pub type BadgerBloomHashPair = {
  h1: Int;
  h2: Int;
}

/// A parsed manifest header (20 bytes at offset 0).
///
/// `creation` is the raw u64 creation-time pattern (unix seconds, 0 when
/// unused); `reserved` is the reserved u32 and must be zero.
pub type BadgerManifestHeader = {
  magic: Int;
  version: Int;
  creation: Int;
  reserved: Int;
}

/// One parsed manifest file-list entry (40 bytes).
///
/// `id` is the table file id, `checksum` its stored u32, `size` its byte
/// size, `flags` the file flags, and `min_version`/`max_version` the raw
/// key-range version bounds. `offset` is where the entry starts in the
/// caller's buffer and `consumed` is always 40.
pub type BadgerManifestEntry = {
  id: Int;
  checksum: Int;
  size: Int;
  flags: Int;
  min_version: Int;
  max_version: Int;
  offset: Int;
  consumed: Int;
}

/// A whole manifest file list, in parallel vectors.
///
/// Entry i is described by the six parallel vectors at index i; entry
/// offsets are `offsets[i]` and `entry_offsets[i]` (identical, the second
/// kept for symmetry with the walk types). `crc` is the stored u32 over the
/// count and all entries; `total_bytes` is count*4 + count*40 + 4.
pub type BadgerManifestFiles = {
  count: Int;
  ids: Vec[Int];
  checksums: Vec[Int];
  sizes: Vec[Int];
  flags: Vec[Int];
  min_versions: Vec[Int];
  max_versions: Vec[Int];
  offsets: Vec[Int];
  entry_offsets: Vec[Int];
  crc: Int;
  total_bytes: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] { return Ok(v); }
// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] { return Err(m); }
// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] { return Ok(v); }
// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] { return Err(m); }
// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
// Ok(v) for Result[BadgerVarint, Int] (the Int is a reader status code).
fn _ok_vv(v: BadgerVarint) -> Result[BadgerVarint, Int] { return Ok(v); }
// Err(c) for Result[BadgerVarint, Int].
fn _err_vc(c: Int) -> Result[BadgerVarint, Int] { return Err(c); }
// Ok(v) for Result[BadgerKey, Str].
fn _ok_key(v: BadgerKey) -> Result[BadgerKey, Str] { return Ok(v); }
// Err(m) for Result[BadgerKey, Str].
fn _err_key(m: Str) -> Result[BadgerKey, Str] { return Err(m); }
// Ok(v) for Result[BadgerVlogHeader, Str].
fn _ok_vh(v: BadgerVlogHeader) -> Result[BadgerVlogHeader, Str] { return Ok(v); }
// Err(m) for Result[BadgerVlogHeader, Str].
fn _err_vh(m: Str) -> Result[BadgerVlogHeader, Str] { return Err(m); }
// Ok(v) for Result[BadgerVlogWalk, Str].
fn _ok_vwalk(v: BadgerVlogWalk) -> Result[BadgerVlogWalk, Str] { return Ok(v); }
// Err(m) for Result[BadgerVlogWalk, Str].
fn _err_vwalk(m: Str) -> Result[BadgerVlogWalk, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstHeader, Str].
fn _ok_ssth(v: BadgerSstHeader) -> Result[BadgerSstHeader, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstHeader, Str].
fn _err_ssth(m: Str) -> Result[BadgerSstHeader, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstEntry, Str].
fn _ok_sse(v: BadgerSstEntry) -> Result[BadgerSstEntry, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstEntry, Str].
fn _err_sse(m: Str) -> Result[BadgerSstEntry, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstEntries, Str].
fn _ok_sse_list(v: BadgerSstEntries) -> Result[BadgerSstEntries, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstEntries, Str].
fn _err_sse_list(m: Str) -> Result[BadgerSstEntries, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstBlockTrailer, Str].
fn _ok_str_trailer(v: BadgerSstBlockTrailer) -> Result[BadgerSstBlockTrailer, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstBlockTrailer, Str].
fn _err_str_trailer(m: Str) -> Result[BadgerSstBlockTrailer, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstIndex, Str].
fn _ok_idx(v: BadgerSstIndex) -> Result[BadgerSstIndex, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstIndex, Str].
fn _err_idx(m: Str) -> Result[BadgerSstIndex, Str] { return Err(m); }
// Ok(v) for Result[BadgerSstFooter, Str].
fn _ok_ft(v: BadgerSstFooter) -> Result[BadgerSstFooter, Str] { return Ok(v); }
// Err(m) for Result[BadgerSstFooter, Str].
fn _err_ft(m: Str) -> Result[BadgerSstFooter, Str] { return Err(m); }
// Ok(v) for Result[BadgerBloom, Str].
fn _ok_bloom(v: BadgerBloom) -> Result[BadgerBloom, Str] { return Ok(v); }
// Err(m) for Result[BadgerBloom, Str].
fn _err_bloom(m: Str) -> Result[BadgerBloom, Str] { return Err(m); }
// Ok(v) for Result[BadgerBloomHashPair, Str].
fn _ok_bhp(v: BadgerBloomHashPair) -> Result[BadgerBloomHashPair, Str] { return Ok(v); }
// Err(m) for Result[BadgerBloomHashPair, Str].
fn _err_bhp(m: Str) -> Result[BadgerBloomHashPair, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestHeader, Str].
fn _ok_mh(v: BadgerManifestHeader) -> Result[BadgerManifestHeader, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestHeader, Str].
fn _err_mh(m: Str) -> Result[BadgerManifestHeader, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestEntry, Str].
fn _ok_me(v: BadgerManifestEntry) -> Result[BadgerManifestEntry, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestEntry, Str].
fn _err_me(m: Str) -> Result[BadgerManifestEntry, Str] { return Err(m); }
// Ok(v) for Result[BadgerManifestFiles, Str].
fn _ok_mf(v: BadgerManifestFiles) -> Result[BadgerManifestFiles, Str] { return Ok(v); }
// Err(m) for Result[BadgerManifestFiles, Str].
fn _err_mf(m: Str) -> Result[BadgerManifestFiles, Str] { return Err(m); }

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// "badger: <msg> at <off>" -- structural errors carry their byte offset.
fn _at(msg: Str, off: Int) -> Str {
  return "badger: " + msg + " at " + int_to_base(off, 10);
}

// Byte at `pos`, widened to 0..255; the caller guarantees the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Raw little-endian field of `size` (1, 2, 4 or 8) bytes at `off`.
//
// For size 8 the raw two's-complement 64-bit pattern is returned: the low
// seven bytes accumulate with a `place` factor and the top byte is applied
// separately, so no intermediate overflows and bit 63 set decodes as a
// negative Int. The caller guarantees off + size <= data.len().
fn _rdu(data: &Vec[UInt8], off: Int, size: Int) -> Int {
  var nlow = size;
  if size == 8 {
    nlow = 7;
  }
  var low: Int = 0;
  var place: Int = 1;
  var i = 0;
  while i < nlow {
    let b = _byte(data, off + i);
    low = low + b * place;
    place = place * 256;
    i = i + 1;
  }
  if size == 8 {
    let top = _byte(data, off + 7);
    if top < 128 {
      return low + top * place;
    }
    let t = top - 128;
    let hi = low + t * place;
    return hi + (0 - 9223372036854775807 - 1);
  }
  return low;
}

// Copy [start, start + size) of `data` into a fresh Vec; callers guarantee
// the bounds.
fn _copy_range(data: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    let b: UInt8 = data[start + i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Append all bytes of `src` to `dst`.
fn _append(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

// Three-way byte-wise comparison of two byte vectors (shorter first on a
// common prefix). Returns -1, 0 or 1.
fn _cmp_bytes(a: &Vec[UInt8], aoff: Int, asize: Int, b: &Vec[UInt8], boff: Int, bsize: Int) -> Int {
  var n = asize;
  if bsize < n {
    n = bsize;
  }
  var i = 0;
  while i < n {
    let av = _byte(a, aoff + i);
    let bv = _byte(b, boff + i);
    if av < bv {
      return -1;
    }
    if av > bv {
      return 1;
    }
    i = i + 1;
  }
  if asize < bsize {
    return -1;
  }
  if asize > bsize {
    return 1;
  }
  return 0;
}

// 2^k for small non-negative k, computed by repeated doubling (no shifts).
fn _pow2(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 2;
    i = i + 1;
  }
  return p;
}

// True when bit `bit_value` (one of the BADGER_META_* constants) is set in
// `v`; implemented with division and modulo, never shifts.
fn _bit_set(v: Int, bit_value: Int) -> Bool {
  if bit_value <= 0 {
    return false;
  }
  let q = v / bit_value;
  let r = q % 2;
  if r == 1 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  CRC32C (Castagnoli), local implementation
// --------------------------------------------------

// One reflected CRC32C step for byte `b`: xor into the register, then eight
// right shifts with the reversed polynomial 0x82F63B78 (2197175160) fed back
// on every set low bit. The register stays in [0, 2^32).
fn _crc32c_step(crc_in: Int, b: Int) -> Int {
  var crc = crc_in ^ b;
  var k = 0;
  while k < 8 {
    let lsb = crc % 2;
    crc = crc / 2;
    if lsb == 1 {
      crc = crc ^ 2197175160;
    }
    k = k + 1;
  }
  return crc;
}

/// Raw CRC32C (Castagnoli, reflected polynomial 0x82F63B78, init 0xFFFFFFFF,
/// final xor 0xFFFFFFFF) over [start, start + size) of `data`.
///
/// Returns a u32 as an Int, or -1 when `start`/`size` are negative or the
/// range falls outside `data`. No LevelDB rotation mask is applied.
/// Complexity: O(size).
pub fn badger_crc32c(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  if start < 0 { return -1; }
  if size < 0 { return -1; }
  if start + size > data.len() { return -1; }
  var crc = 4294967295;
  var i = 0;
  while i < size {
    crc = _crc32c_step(crc, _byte(data, start + i));
    i = i + 1;
  }
  return (crc ^ 4294967295) & 4294967295;
}

// --------------------------------------------------
//  LEB128 varint (SST block entries)
// --------------------------------------------------

// Shared base-128 u32 reader. `limit` is an exclusive byte bound (must be
// <= data.len()); callers guarantee pos >= 0. Err codes: 1 truncated,
// 2 overflow.
fn _varint_core(data: &Vec[UInt8], pos: Int, limit: Int) -> Result[BadgerVarint, Int] {
  var value: Int = 0;
  var mult: Int = 1;
  var i = 0;
  while i < 5 {
    if pos + i >= limit { return _err_vc(1); }
    let b = _byte(data, pos + i);
    let cont = b / 128;
    let payload = b % 128;
    if i == 4 {
      if cont == 1 { return _err_vc(2); }
      if payload > 15 { return _err_vc(2); }
      return _ok_vv(BadgerVarint{ value: value + payload * mult; size: 5; });
    }
    value = value + payload * mult;
    if cont == 0 {
      return _ok_vv(BadgerVarint{ value: value; size: i + 1; });
    }
    mult = mult * 128;
    i = i + 1;
  }
  return _err_vc(1);
}

// Turn a _varint_core status code into "<label>: truncated at <pos>" or
// "<label>: overflow at <pos>".
fn _vmsg(label: Str, code: Int, pos: Int) -> Str {
  if code == 1 { return _at(label + ": truncated", pos); }
  if code == 2 { return _at(label + ": overflow", pos); }
  return _at(label + ": bad input", pos);
}

// --------------------------------------------------
//  Value log meta bits
// --------------------------------------------------

/// Name of a single meta bit value: "DELETE" (1), "VALUE_POINTER" (2),
/// "TRANSACTION" (4), "FIN_TXN" (8), "BIT_TXN" (16), "MERGE_ENTRY" (32), or
/// "" for anything else. Complexity: O(1).
pub fn badger_meta_bit_name(bit_value: Int) -> Str {
  if bit_value == BADGER_META_DELETE { return "DELETE"; }
  if bit_value == BADGER_META_VALUE_POINTER { return "VALUE_POINTER"; }
  if bit_value == BADGER_META_TRANSACTION { return "TRANSACTION"; }
  if bit_value == BADGER_META_FIN_TXN { return "FIN_TXN"; }
  if bit_value == BADGER_META_BIT_TXN { return "BIT_TXN"; }
  if bit_value == BADGER_META_MERGE_ENTRY { return "MERGE_ENTRY"; }
  return "";
}

/// True when the meta byte has `bit_value` set; false for non-positive bit
/// values. Complexity: O(1).
pub fn badger_meta_has(meta: Int, bit_value: Int) -> Bool {
  return _bit_set(meta, bit_value);
}

/// True when every set bit of `meta` is one of the six defined bits (i.e.
/// meta is in [0, 63]). Complexity: O(1).
pub fn badger_meta_known(meta: Int) -> Bool {
  if meta < 0 { return false; }
  if meta > BADGER_META_ALL { return false; }
  return true;
}

/// A "|"-joined list of the defined meta bit names set in `meta`, in bit
/// order; "" when no defined bit is set. Complexity: O(1).
pub fn badger_meta_names(meta: Int) -> Str {
  var out = "";
  var first = true;
  if _bit_set(meta, BADGER_META_DELETE) {
    out = "DELETE";
    first = false;
  }
  if _bit_set(meta, BADGER_META_VALUE_POINTER) {
    if first {
      out = "VALUE_POINTER";
      first = false;
    } else {
      out = out + "|VALUE_POINTER";
    }
  }
  if _bit_set(meta, BADGER_META_TRANSACTION) {
    if first {
      out = "TRANSACTION";
      first = false;
    } else {
      out = out + "|TRANSACTION";
    }
  }
  if _bit_set(meta, BADGER_META_FIN_TXN) {
    if first {
      out = "FIN_TXN";
      first = false;
    } else {
      out = out + "|FIN_TXN";
    }
  }
  if _bit_set(meta, BADGER_META_BIT_TXN) {
    if first {
      out = "BIT_TXN";
      first = false;
    } else {
      out = out + "|BIT_TXN";
    }
  }
  if _bit_set(meta, BADGER_META_MERGE_ENTRY) {
    if first {
      out = "MERGE_ENTRY";
      first = false;
    } else {
      out = out + "|MERGE_ENTRY";
    }
  }
  return out;
}

// --------------------------------------------------
//  Value log entries
// --------------------------------------------------

/// Parse the 20-byte value log entry header at `off`.
///
/// Layout: keyLen u32 LE, valLen u32 LE, expiresAt u64 LE, meta byte,
/// userMeta byte, 2 reserved bytes that must be zero. A key or value length
/// above BADGER_VLOG_ENTRY_CAP (1 MiB) is rejected.
///
/// Errors: "badger: vlog header out of bounds at <off>", "badger: vlog
/// header truncated at <off>", "badger: vlog key length exceeds cap at
/// <off>", "badger: vlog value length exceeds cap at <off + 4>", "badger:
/// vlog header reserved bytes nonzero at <off + 18>". Complexity: O(1).
pub fn badger_parse_vlog_header(data: &Vec[UInt8], off: Int) -> Result[BadgerVlogHeader, Str] {
  if off < 0 {
    return _err_vh(_at("vlog header out of bounds", 0));
  }
  if off > data.len() || BADGER_VLOG_HEADER_SIZE > data.len() - off {
    return _err_vh(_at("vlog header truncated", off));
  }
  let key_len = _rdu(data, off, 4);
  let val_len = _rdu(data, off + 4, 4);
  if key_len > BADGER_VLOG_ENTRY_CAP {
    return _err_vh(_at("vlog key length exceeds cap", off));
  }
  if val_len > BADGER_VLOG_ENTRY_CAP {
    return _err_vh(_at("vlog value length exceeds cap", off + 4));
  }
  let b18 = _byte(data, off + 18);
  let b19 = _byte(data, off + 19);
  if b18 != 0 || b19 != 0 {
    return _err_vh(_at("vlog header reserved bytes nonzero", off + 18));
  }
  return _ok_vh(BadgerVlogHeader{
    key_len: key_len;
    val_len: val_len;
    expires_at: _rdu(data, off + 8, 8);
    meta: _byte(data, off + 16);
    user_meta: _byte(data, off + 17);
  });
}

/// Total byte size of the entry described by `h`: 20 + keyLen + valLen.
/// Complexity: O(1).
pub fn badger_vlog_entry_total(h: &BadgerVlogHeader) -> Int {
  let k: Int = h.key_len;
  let v: Int = h.val_len;
  return BADGER_VLOG_HEADER_SIZE + k + v;
}

/// Walk consecutive value log entries over [off, limit).
///
/// Stops exactly at `limit`; a partial header (fewer than 20 bytes left) is
/// an error, so a walk never silently drops trailing bytes. Every entry must
/// fit inside `limit`, its total size must stay within
/// BADGER_VLOG_ENTRY_CAP (1 MiB), and at most `max_entries` entries are
/// accepted (pass a positive bound).
///
/// Errors: "badger: vlog walk start out of bounds at 0", "badger: vlog walk
/// limit out of bounds at <limit>", "badger: vlog walk limit before start at
/// <limit>", "badger: vlog walk max entries must be positive at <off>",
/// "badger: vlog walk trailing bytes at <pos>", "badger: vlog entry
/// truncated at <pos>", "badger: vlog entry exceeds cap at <pos>", "badger:
/// vlog walk exceeds max entries at <pos>", plus any header-parse error.
/// Complexity: O(bytes walked).
pub fn badger_vlog_walk(data: &Vec[UInt8], off: Int, limit: Int, max_entries: Int) -> Result[BadgerVlogWalk, Str] {
  if off < 0 {
    return _err_vwalk(_at("vlog walk start out of bounds", 0));
  }
  if limit > data.len() {
    return _err_vwalk(_at("vlog walk limit out of bounds", limit));
  }
  if limit < off {
    return _err_vwalk(_at("vlog walk limit before start", limit));
  }
  if max_entries <= 0 {
    return _err_vwalk(_at("vlog walk max entries must be positive", off));
  }
  var offsets = Vec[Int].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var value_offsets = Vec[Int].new();
  var value_sizes = Vec[Int].new();
  var metas = Vec[Int].new();
  var user_metas = Vec[Int].new();
  var expires = Vec[Int].new();
  var pos = off;
  var total: Int = 0;
  while pos < limit {
    if limit - pos < BADGER_VLOG_HEADER_SIZE {
      return _err_vwalk(_at("vlog walk trailing bytes", pos));
    }
    let hr = badger_parse_vlog_header(data, pos);
    if !hr.is_ok {
      return _err_vwalk(hr.error);
    }
    let h = hr.value;
    let klen: Int = h.key_len;
    let vlen: Int = h.val_len;
    let eb: Int = BADGER_VLOG_HEADER_SIZE + klen + vlen;
    if eb > BADGER_VLOG_ENTRY_CAP {
      return _err_vwalk(_at("vlog entry exceeds cap", pos));
    }
    if eb > limit - pos {
      return _err_vwalk(_at("vlog entry truncated", pos));
    }
    if offsets.len() >= max_entries {
      return _err_vwalk(_at("vlog walk exceeds max entries", pos));
    }
    offsets.push(pos);
    key_offsets.push(pos + BADGER_VLOG_HEADER_SIZE);
    key_sizes.push(klen);
    value_offsets.push(pos + BADGER_VLOG_HEADER_SIZE + klen);
    value_sizes.push(vlen);
    metas.push(h.meta);
    user_metas.push(h.user_meta);
    expires.push(h.expires_at);
    total = total + eb;
    pos = pos + eb;
  }
  return _ok_vwalk(BadgerVlogWalk{
    count: offsets.len();
    offsets: offsets;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    value_offsets: value_offsets;
    value_sizes: value_sizes;
    metas: metas;
    user_metas: user_metas;
    expires: expires;
    total_bytes: total;
  });
}

/// Number of entries in a value log walk. Complexity: O(1).
pub fn badger_vlog_count(w: &BadgerVlogWalk) -> Int {
  return w.count;
}

/// Field `field` (one of the BADGER_VLOG_FIELD_* selectors) of entry `i`, or
/// Err("badger: vlog field index out of range at <i>") when `i` is outside
/// [0, count) or the selector is unknown.
/// Complexity: O(1).
pub fn badger_vlog_field(w: &BadgerVlogWalk, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= w.count {
    return _err_int(_at("vlog field index out of range", i));
  }
  if field == BADGER_VLOG_FIELD_OFFSET {
    let v: Int = w.offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_KEY_OFFSET {
    let v: Int = w.key_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_KEY_SIZE {
    let v: Int = w.key_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_VALUE_OFFSET {
    let v: Int = w.value_offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_VALUE_SIZE {
    let v: Int = w.value_sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_META {
    let v: Int = w.metas[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_USER_META {
    let v: Int = w.user_metas[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_EXPIRES_AT {
    let v: Int = w.expires[i];
    return _ok_int(v);
  }
  if field == BADGER_VLOG_FIELD_COUNT {
    return _ok_int(w.count);
  }
  return _err_int(_at("vlog field index out of range", i));
}

/// Key bytes of walk entry `i` copied out of `data`, or an empty Vec when `i`
/// is out of range. Complexity: O(key length).
pub fn badger_vlog_key_bytes(data: &Vec[UInt8], w: &BadgerVlogWalk, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= w.count { return Vec[UInt8].new(); }
  let ko: Int = w.key_offsets[i];
  let ks: Int = w.key_sizes[i];
  return _copy_range(data, ko, ks);
}

/// Value bytes of walk entry `i` copied out of `data`, or an empty Vec when
/// `i` is out of range. Complexity: O(value length).
pub fn badger_vlog_value_bytes(data: &Vec[UInt8], w: &BadgerVlogWalk, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= w.count { return Vec[UInt8].new(); }
  let vo: Int = w.value_offsets[i];
  let vs: Int = w.value_sizes[i];
  return _copy_range(data, vo, vs);
}

// --------------------------------------------------
//  Versioned keys
// --------------------------------------------------

/// Decode a versioned key spanning `size` bytes at `off`.
///
/// Layout: user key bytes followed by an 8-byte version timestamp u64 LE
/// whose bit 0 is the delete tag. `version` is the tag with the delete bit
/// cleared, divided by two; `tagged` is the raw u64 pattern. A tag with bit
/// 63 set is rejected (raw pattern would be negative).
///
/// Errors: "badger: key shorter than version tag at <off>", "badger: key
/// span out of bounds at <off>", "badger: key version exceeds Int range at
/// <off>". Complexity: O(1).
pub fn badger_key_decode(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerKey, Str] {
  if off < 0 {
    return _err_key(_at("key span out of bounds", 0));
  }
  if size < BADGER_KEY_TAG_SIZE {
    return _err_key(_at("key shorter than version tag", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_key(_at("key span out of bounds", off));
  }
  let tag_off = off + size - BADGER_KEY_TAG_SIZE;
  let tagged = _rdu(data, tag_off, 8);
  if tagged < 0 {
    return _err_key(_at("key version exceeds Int range", tag_off));
  }
  let low = tagged % 2;
  var deleted = false;
  if low == 1 {
    deleted = true;
  }
  let version = tagged / 2;
  return _ok_key(BadgerKey{
    user_offset: off;
    user_size: size - BADGER_KEY_TAG_SIZE;
    tagged: tagged;
    version: version;
    deleted: deleted;
  });
}

/// Version timestamp of a decoded key (the delete tag removed).
/// Complexity: O(1).
pub fn badger_key_version(k: &BadgerKey) -> Int {
  return k.version;
}

/// True when the decoded key carries the delete tag (bit 0 of the trailing
/// u64). Complexity: O(1).
pub fn badger_key_deleted(k: &BadgerKey) -> Bool {
  return k.deleted;
}

/// Raw 8-byte little-endian version tag of a decoded key, including the
/// delete bit. Complexity: O(1).
pub fn badger_key_tagged(k: &BadgerKey) -> Int {
  return k.tagged;
}

/// Size in bytes of the user key part (the decoded size minus 8).
/// Complexity: O(1).
pub fn badger_key_user_size(k: &BadgerKey) -> Int {
  return k.user_size;
}

/// User key bytes of a decoded key copied out of `data`.
/// Complexity: O(user key length).
pub fn badger_key_user_bytes(data: &Vec[UInt8], k: &BadgerKey) -> Vec[UInt8] {
  let uo: Int = k.user_offset;
  let us: Int = k.user_size;
  return _copy_range(data, uo, us);
}

// --------------------------------------------------
//  SST table header
// --------------------------------------------------

/// True when the 4 bytes at `data[pos]` are the little-endian SST magic
/// BADGER_SST_MAGIC (the ASCII bytes "BDGR"). Returns false when out of
/// range. Complexity: O(1).
pub fn badger_sst_magic_ok(data: &Vec[UInt8], pos: Int) -> Bool {
  if pos < 0 { return false; }
  if pos + 4 > data.len() { return false; }
  let m = _rdu(data, pos, 4);
  if m == BADGER_SST_MAGIC { return true; }
  return false;
}

/// Parse the 16-byte SST file header at offset 0.
///
/// Layout: magic u32 LE ("BDGR"), version u32 LE (1), block size u32 LE,
/// checksum type byte (0 none, 1 CRC32C), 3 reserved bytes that must be
/// zero.
///
/// Errors: "badger: sst header truncated at 0", "badger: sst bad magic at
/// 0", "badger: sst unsupported version at 4", "badger: sst block size out
/// of range at 8", "badger: sst unknown checksum type at 12", "badger: sst
/// reserved bytes nonzero at 13". Complexity: O(1).
pub fn badger_parse_sst_header(data: &Vec[UInt8]) -> Result[BadgerSstHeader, Str] {
  if data.len() < BADGER_SST_HEADER_SIZE {
    return _err_ssth(_at("sst header truncated", 0));
  }
  let magic = _rdu(data, 0, 4);
  if magic != BADGER_SST_MAGIC {
    return _err_ssth(_at("sst bad magic", 0));
  }
  let version = _rdu(data, 4, 4);
  if version != BADGER_SST_VERSION {
    return _err_ssth(_at("sst unsupported version", 4));
  }
  let block_size = _rdu(data, 8, 4);
  if block_size < BADGER_SST_MIN_BLOCK_SIZE {
    return _err_ssth(_at("sst block size out of range", 8));
  }
  if block_size > BADGER_SST_MAX_BLOCK_SIZE {
    return _err_ssth(_at("sst block size out of range", 8));
  }
  let ct = _byte(data, 12);
  if ct != BADGER_SST_CHECKSUM_NONE && ct != BADGER_SST_CHECKSUM_CRC32C {
    return _err_ssth(_at("sst unknown checksum type", 12));
  }
  var i = 13;
  while i < 16 {
    if _byte(data, i) != 0 {
      return _err_ssth(_at("sst reserved bytes nonzero", 13));
    }
    i = i + 1;
  }
  return _ok_ssth(BadgerSstHeader{
    magic: magic;
    version: version;
    block_size: block_size;
    checksum_type: ct;
  });
}

// --------------------------------------------------
//  SST data-block entries
// --------------------------------------------------

/// Parse one SST data-block entry at `pos` inside [pos, limit).
///
/// Layout: LEB128 shared-prefix length, LEB128 key-diff length, LEB128 value
/// length, the key-diff bytes, the value bytes. The key is reconstructed
/// from `prev_key` (pass an empty Vec at a block start; a shared length
/// beyond prev_key is an error). Key and value lengths above
/// BADGER_SST_MAX_KEY_LEN / BADGER_SST_MAX_VALUE_LEN are rejected.
///
/// Errors: "badger: sst block entry truncated at <pos>", "badger: sst block
/// entry varint overflow at <pos>", "badger: sst block entry shared beyond
/// previous key at <pos>", "badger: sst block entry key length exceeds cap
/// at <pos>", "badger: sst block entry value length exceeds cap at <pos>",
/// "badger: sst block entry key overrun at <pos>", "badger: sst block entry
/// value overrun at <pos>". Complexity: O(entry bytes).
pub fn badger_parse_sst_block_entry(body: &Vec[UInt8], pos: Int, limit: Int, prev_key: &Vec[UInt8]) -> Result[BadgerSstEntry, Str] {
  if pos < 0 {
    return _err_sse(_at("sst block entry truncated", 0));
  }
  var lim = limit;
  if lim > body.len() {
    lim = body.len();
  }
  if pos >= lim {
    return _err_sse(_at("sst block entry truncated", pos));
  }
  let r1 = _varint_core(body, pos, lim);
  if !r1.is_ok {
    let code: Int = r1.error;
    return _err_sse(_vmsg("sst block entry", code, pos));
  }
  let v1 = r1.value;
  let shared: Int = v1.value;
  let n1: Int = v1.size;
  let p2 = pos + n1;
  let r2 = _varint_core(body, p2, lim);
  if !r2.is_ok {
    let code: Int = r2.error;
    return _err_sse(_vmsg("sst block entry", code, p2));
  }
  let v2 = r2.value;
  let klen: Int = v2.value;
  let n2: Int = v2.size;
  let p3 = p2 + n2;
  let r3 = _varint_core(body, p3, lim);
  if !r3.is_ok {
    let code: Int = r3.error;
    return _err_sse(_vmsg("sst block entry", code, p3));
  }
  let v3 = r3.value;
  let vlen: Int = v3.value;
  let n3: Int = v3.size;
  if shared > prev_key.len() {
    return _err_sse(_at("sst block entry shared beyond previous key", pos));
  }
  if klen > BADGER_SST_MAX_KEY_LEN {
    return _err_sse(_at("sst block entry key length exceeds cap", pos));
  }
  if vlen > BADGER_SST_MAX_VALUE_LEN {
    return _err_sse(_at("sst block entry value length exceeds cap", pos));
  }
  let hdr = n1 + n2 + n3;
  if hdr > lim - pos {
    return _err_sse(_at("sst block entry key overrun", pos));
  }
  let key_start = pos + hdr;
  if key_start > lim || klen > lim - key_start {
    return _err_sse(_at("sst block entry key overrun", pos));
  }
  let value_start = key_start + klen;
  if value_start > lim || vlen > lim - value_start {
    return _err_sse(_at("sst block entry value overrun", pos));
  }
  var key = Vec[UInt8].new();
  var i = 0;
  while i < shared {
    let b: UInt8 = prev_key[i];
    key.push(b);
    i = i + 1;
  }
  i = 0;
  while i < klen {
    let b: UInt8 = body[key_start + i];
    key.push(b);
    i = i + 1;
  }
  return _ok_sse(BadgerSstEntry{
    shared_len: shared;
    key_len: klen;
    val_len: vlen;
    key_offset: key_start;
    value_offset: value_start;
    entry_bytes: hdr + klen + vlen;
    key: key;
  });
}

/// Walk every entry of an SST data block body.
///
/// `limit` is the exclusive end of the entry region (normally the block body
/// length; the 4-byte trailer is excluded). The entries must end exactly at
/// `limit`; the three LEB128 lengths mean every entry consumes at least three
/// bytes, so a walk always makes progress.
///
/// Errors: any entry-parse error plus "badger: sst block limit out of bounds
/// at 0". Complexity: O(block length).
pub fn badger_sst_block_entries(body: &Vec[UInt8], limit: Int) -> Result[BadgerSstEntries, Str] {
  if limit < 0 {
    return _err_sse_list(_at("sst block limit out of bounds", 0));
  }
  if limit > body.len() {
    return _err_sse_list(_at("sst block limit out of bounds", 0));
  }
  var key_data = Vec[UInt8].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var shared_lens = Vec[Int].new();
  var value_offsets = Vec[Int].new();
  var value_sizes = Vec[Int].new();
  var entry_offsets = Vec[Int].new();
  var prev = Vec[UInt8].new();
  var pos = 0;
  while pos < limit {
    let er = badger_parse_sst_block_entry(body, pos, limit, &prev);
    if !er.is_ok {
      return _err_sse_list(er.error);
    }
    let e = er.value;
    let eshared: Int = e.shared_len;
    let evl: Int = e.val_len;
    let evoff: Int = e.value_offset;
    let ebytes: Int = e.entry_bytes;
    let ekey: Vec[UInt8] = e.key;
    entry_offsets.push(pos);
    shared_lens.push(eshared);
    key_offsets.push(key_data.len());
    key_sizes.push(ekey.len());
    var ki = 0;
    while ki < ekey.len() {
      let kb: UInt8 = ekey[ki];
      key_data.push(kb);
      ki = ki + 1;
    }
    value_offsets.push(evoff);
    value_sizes.push(evl);
    prev = Vec[UInt8].new();
    _append(&mut prev, &ekey);
    pos = pos + ebytes;
  }
  return _ok_sse_list(BadgerSstEntries{
    count: entry_offsets.len();
    key_data: key_data;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    shared_lens: shared_lens;
    value_offsets: value_offsets;
    value_sizes: value_sizes;
    entry_offsets: entry_offsets;
  });
}

/// Number of entries in a walked SST data block. Complexity: O(1).
pub fn badger_sst_block_count(e: &BadgerSstEntries) -> Int {
  return e.count;
}

/// Reconstructed key of entry `i`, or an empty Vec when out of range.
/// Complexity: O(key length).
pub fn badger_sst_block_key(e: &BadgerSstEntries, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= e.count { return Vec[UInt8].new(); }
  let kd: Vec[UInt8] = e.key_data;
  let ko: Int = e.key_offsets[i];
  let ks: Int = e.key_sizes[i];
  return _copy_range(&kd, ko, ks);
}

/// Stored shared-prefix length of entry `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn badger_sst_block_shared(e: &BadgerSstEntries, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= e.count { return -1; }
  let v: Int = e.shared_lens[i];
  return v;
}

/// Value bytes of entry `i` taken from the original block body, or an empty
/// Vec when out of range. Complexity: O(value length).
pub fn badger_sst_block_value(body: &Vec[UInt8], e: &BadgerSstEntries, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= e.count { return Vec[UInt8].new(); }
  let vo: Int = e.value_offsets[i];
  let vs: Int = e.value_sizes[i];
  return _copy_range(body, vo, vs);
}

/// Byte offset of entry `i` inside the block body, or -1 when out of range.
/// Complexity: O(1).
pub fn badger_sst_block_entry_offset(e: &BadgerSstEntries, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= e.count { return -1; }
  let v: Int = e.entry_offsets[i];
  return v;
}

// --------------------------------------------------
//  SST block trailer
// --------------------------------------------------

/// Parse the 4-byte SST block trailer (raw CRC32C u32 LE) at `trailer[pos]`.
///
/// Errors: "badger: sst block trailer truncated at <pos>". Complexity: O(1).
pub fn badger_parse_sst_block_trailer(trailer: &Vec[UInt8], pos: Int) -> Result[BadgerSstBlockTrailer, Str] {
  if pos < 0 {
    return _err_str_trailer(_at("sst block trailer truncated", 0));
  }
  if pos > trailer.len() || BADGER_SST_BLOCK_TRAILER_SIZE > trailer.len() - pos {
    return _err_str_trailer(_at("sst block trailer truncated", pos));
  }
  return _ok_str_trailer(BadgerSstBlockTrailer{ crc: _rdu(trailer, pos, 4) });
}

/// True when `crc` equals the raw CRC32C of [start, start + size) of `body`.
/// A crc of -1 (invalid stored value) is never accepted.
/// Complexity: O(size).
pub fn badger_sst_block_trailer_ok(body: &Vec[UInt8], start: Int, size: Int, crc: Int) -> Bool {
  if crc < 0 { return false; }
  let actual = badger_crc32c(body, start, size);
  if actual < 0 { return false; }
  if actual == crc { return true; }
  return false;
}

// --------------------------------------------------
//  SST block index
// --------------------------------------------------

/// Parse an SST block index spanning `size` bytes at `off`.
///
/// Layout: count u32 LE, then `count` entries of block offset u64 LE, block
/// size u32 LE, key length u32 LE, key bytes; then a trailing CRC32C u32 LE
/// over everything before it. `size` must match exactly.
///
/// Errors: "badger: sst index truncated at <off>", "badger: sst index count
/// exceeds cap at <off>", "badger: sst index entry overruns at <pos>",
/// "badger: sst index block offset exceeds Int range at <pos>", "badger: sst
/// index key length exceeds cap at <pos>", "badger: sst index length
/// mismatch at <off>", "badger: sst index checksum mismatch at
/// <off + size - 4>". Complexity: O(size).
pub fn badger_sst_index_parse(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerSstIndex, Str] {
  if off < 0 {
    return _err_idx(_at("sst index truncated", 0));
  }
  if size < 8 {
    return _err_idx(_at("sst index truncated", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_idx(_at("sst index truncated", off));
  }
  let end = off + size;
  let count = _rdu(data, off, 4);
  if count > BADGER_SST_MAX_INDEX_ENTRIES {
    return _err_idx(_at("sst index count exceeds cap", off));
  }
  var offsets = Vec[Int].new();
  var sizes = Vec[Int].new();
  var key_data = Vec[UInt8].new();
  var key_offsets = Vec[Int].new();
  var key_sizes = Vec[Int].new();
  var pos = off + 4;
  var i = 0;
  while i < count {
    if pos > end || 16 > end - pos {
      return _err_idx(_at("sst index entry overruns", pos));
    }
    let boff = _rdu(data, pos, 8);
    if boff < 0 {
      return _err_idx(_at("sst index block offset exceeds Int range", pos));
    }
    let bsize = _rdu(data, pos + 8, 4);
    let klen = _rdu(data, pos + 12, 4);
    if klen > BADGER_SST_MAX_KEY_LEN {
      return _err_idx(_at("sst index key length exceeds cap", pos));
    }
    let kstart = pos + 16;
    if kstart > end || klen > end - kstart {
      return _err_idx(_at("sst index entry overruns", pos));
    }
    key_offsets.push(key_data.len());
    key_sizes.push(klen);
    var ki = 0;
    while ki < klen {
      let kb: UInt8 = data[kstart + ki];
      key_data.push(kb);
      ki = ki + 1;
    }
    offsets.push(boff);
    sizes.push(bsize);
    pos = kstart + klen;
    i = i + 1;
  }
  if pos > end || 4 > end - pos {
    return _err_idx(_at("sst index length mismatch", off));
  }
  let crc_off = pos;
  if crc_off + 4 != end {
    return _err_idx(_at("sst index length mismatch", off));
  }
  let crc = _rdu(data, crc_off, 4);
  let actual = badger_crc32c(data, off, size - 4);
  if actual < 0 || actual != crc {
    return _err_idx(_at("sst index checksum mismatch", crc_off));
  }
  return _ok_idx(BadgerSstIndex{
    count: offsets.len();
    offsets: offsets;
    sizes: sizes;
    key_data: key_data;
    key_offsets: key_offsets;
    key_sizes: key_sizes;
    entries_end: crc_off;
    crc: crc;
  });
}

/// Number of entries in a parsed block index. Complexity: O(1).
pub fn badger_sst_index_count(ix: &BadgerSstIndex) -> Int {
  return ix.count;
}

/// Data-block offset of index entry `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn badger_sst_index_offset(ix: &BadgerSstIndex, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= ix.count { return -1; }
  let v: Int = ix.offsets[i];
  return v;
}

/// Data-block size of index entry `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn badger_sst_index_size(ix: &BadgerSstIndex, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= ix.count { return -1; }
  let v: Int = ix.sizes[i];
  return v;
}

/// Separator key of index entry `i`, or an empty Vec when out of range.
/// Complexity: O(key length).
pub fn badger_sst_index_key(ix: &BadgerSstIndex, i: Int) -> Vec[UInt8] {
  if i < 0 { return Vec[UInt8].new(); }
  if i >= ix.count { return Vec[UInt8].new(); }
  let kd: Vec[UInt8] = ix.key_data;
  let ko: Int = ix.key_offsets[i];
  let ks: Int = ix.key_sizes[i];
  return _copy_range(&kd, ko, ks);
}

/// Index of the first entry whose separator key is >= the key span
/// [key_off, key_off + key_size) of `data`, or -1 when every key is smaller
/// (or the span is out of bounds). The index keys are assumed sorted in
/// ascending byte order, as written by a table builder.
/// Complexity: O(count * key length).
pub fn badger_sst_index_lookup(data: &Vec[UInt8], ix: &BadgerSstIndex, key_off: Int, key_size: Int) -> Int {
  if key_off < 0 { return -1; }
  if key_size < 0 { return -1; }
  if key_off > data.len() || key_size > data.len() - key_off { return -1; }
  let kd: Vec[UInt8] = ix.key_data;
  var i = 0;
  while i < ix.count {
    let ko: Int = ix.key_offsets[i];
    let ks: Int = ix.key_sizes[i];
    let c = _cmp_bytes(&kd, ko, ks, data, key_off, key_size);
    if c >= 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  SST table footer
// --------------------------------------------------

/// Parse the 16-byte SST table footer stored at the end of `data`.
///
/// Layout: index offset u64 LE, index size u32 LE, CRC32C u32 LE over the
/// first 12 bytes. The index range must lie inside the file, after the
/// header and before the footer itself.
///
/// Errors: "badger: sst footer truncated at 0", "badger: sst footer
/// checksum mismatch at <base>", "badger: sst footer index offset exceeds
/// Int range at <base>", "badger: sst footer index handle out of range at
/// <base>". Complexity: O(1).
pub fn badger_sst_footer_parse(data: &Vec[UInt8]) -> Result[BadgerSstFooter, Str] {
  if data.len() < BADGER_SST_FOOTER_SIZE {
    return _err_ft(_at("sst footer truncated", 0));
  }
  let base = data.len() - BADGER_SST_FOOTER_SIZE;
  let crc = _rdu(data, base + 12, 4);
  let actual = badger_crc32c(data, base, 12);
  if actual < 0 || actual != crc {
    return _err_ft(_at("sst footer checksum mismatch", base));
  }
  let ioff = _rdu(data, base, 8);
  if ioff < 0 {
    return _err_ft(_at("sst footer index offset exceeds Int range", base));
  }
  let isize = _rdu(data, base + 8, 4);
  if ioff < BADGER_SST_HEADER_SIZE {
    return _err_ft(_at("sst footer index handle out of range", base));
  }
  if ioff > base || isize > base - ioff {
    return _err_ft(_at("sst footer index handle out of range", base));
  }
  return _ok_ft(BadgerSstFooter{
    index_offset: ioff;
    index_size: isize;
    crc: crc;
  });
}

/// True when the footer handle [index_offset, index_offset + index_size)
/// satisfies the same bounds as badger_sst_footer_parse against `file_size`.
/// Complexity: O(1).
pub fn badger_sst_footer_ok(f: &BadgerSstFooter, file_size: Int) -> Bool {
  let ioff: Int = f.index_offset;
  let isize: Int = f.index_size;
  if file_size < BADGER_SST_FOOTER_SIZE { return false; }
  let base = file_size - BADGER_SST_FOOTER_SIZE;
  if ioff < BADGER_SST_HEADER_SIZE { return false; }
  if ioff > base { return false; }
  if isize > base - ioff { return false; }
  return true;
}

// --------------------------------------------------
//  Bloom filter block
// --------------------------------------------------

// One FNV-1a-32 step: xor the low byte and multiply by the 32-bit FNV prime
// modulo 2^32. The xor is the arithmetic bit loop used by the green bolt
// package (bitwise operators on high-bit values are unreliable in v0.61.3).
fn _fnv32_step(h_in: Int, b: Int) -> Int {
  var low = h_in % 256;
  if low < 0 {
    low = low + 256;
  }
  var x = low;
  var y = b;
  var out = 0;
  var bit = 1;
  while bit <= 128 {
    let xb = x % 2;
    let yb = y % 2;
    if xb != yb {
      out = out + bit;
    }
    x = x / 2;
    y = y / 2;
    bit = bit * 2;
  }
  let hx = (h_in - low) + out;
  return (hx * 16777619) & 4294967295;
}

// Domain-separated FNV-1a-32: the domain byte is absorbed first, then the
// key bytes. Domain 0 is the plain FNV-1a-32 of the span.
fn _fnv32_domain(data: &Vec[UInt8], off: Int, size: Int, domain: Int) -> Int {
  var h = 2166136261;
  if domain != 0 {
    h = _fnv32_step(h, domain);
  }
  var i = 0;
  while i < size {
    h = _fnv32_step(h, _byte(data, off + i));
    i = i + 1;
  }
  return h;
}

/// Plain FNV-1a-32 (offset basis 2166136261, prime 16777619, mod 2^32) of the
/// `size` bytes at `off`.
///
/// Err("badger: hash span out of bounds at <off>") when the span leaves the
/// buffer. Complexity: O(size).
pub fn badger_fnv1a32(data: &Vec[UInt8], off: Int, size: Int) -> Result[Int, Str] {
  if off < 0 {
    return _err_int(_at("hash span out of bounds", 0));
  }
  if size < 0 {
    return _err_int(_at("hash span out of bounds", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_int(_at("hash span out of bounds", off));
  }
  return _ok_int(_fnv32_domain(data, off, size, 0));
}

/// The two bloom probe hashes of the key span at [off, off + size):
/// h1 = FNV-1a-32 with domain byte 1, h2 = FNV-1a-32 with domain byte 2,
/// forced non-zero by mapping 0 to 1 and 4294967295 to 1.
///
/// Err("badger: hash span out of bounds at <off>") when the span leaves the
/// buffer. Complexity: O(size).
pub fn badger_bloom_hash_pair(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerBloomHashPair, Str] {
  if off < 0 {
    return _err_bhp(_at("hash span out of bounds", 0));
  }
  if size < 0 {
    return _err_bhp(_at("hash span out of bounds", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_bhp(_at("hash span out of bounds", off));
  }
  let h1 = _fnv32_domain(data, off, size, 1);
  var h2 = _fnv32_domain(data, off, size, 2);
  if h2 == 0 {
    h2 = 1;
  }
  if h2 == 4294967295 {
    h2 = 1;
  }
  return _ok_bhp(BadgerBloomHashPair{ h1: h1; h2: h2; });
}

/// Parse a bloom filter block spanning `size` bytes at `off`.
///
/// Layout: bit count u32 LE, hash count u32 LE, ceil(nbits/8) bit-array
/// bytes, trailing CRC32C u32 LE over the preceding bytes. `nbits` must be
/// in [1, BADGER_BLOOM_MAX_BITS] and `nhashes` in [1,
/// BADGER_BLOOM_MAX_HASHES].
///
/// Errors: "badger: bloom truncated at <off>", "badger: bloom nbits zero at
/// <off>", "badger: bloom bit count exceeds cap at <off>", "badger: bloom
/// hash count out of range at <off + 4>", "badger: bloom bit array overrun
/// at <off>", "badger: bloom length mismatch at <off>", "badger: bloom
/// checksum mismatch at <off + 8 + bits_size>". Complexity: O(size).
pub fn badger_bloom_parse(data: &Vec[UInt8], off: Int, size: Int) -> Result[BadgerBloom, Str] {
  if off < 0 {
    return _err_bloom(_at("bloom truncated", 0));
  }
  if size < 8 {
    return _err_bloom(_at("bloom truncated", off));
  }
  if off > data.len() || size > data.len() - off {
    return _err_bloom(_at("bloom truncated", off));
  }
  let nbits = _rdu(data, off, 4);
  if nbits == 0 {
    return _err_bloom(_at("bloom nbits zero", off));
  }
  if nbits > BADGER_BLOOM_MAX_BITS {
    return _err_bloom(_at("bloom bit count exceeds cap", off));
  }
  let nhashes = _rdu(data, off + 4, 4);
  if nhashes == 0 || nhashes > BADGER_BLOOM_MAX_HASHES {
    return _err_bloom(_at("bloom hash count out of range", off + 4));
  }
  let q = nbits / 8;
  var bits_size = q;
  let r = nbits % 8;
  if r > 0 {
    bits_size = q + 1;
  }
  if 8 + bits_size > size {
    return _err_bloom(_at("bloom bit array overrun", off));
  }
  if 8 + bits_size + 4 != size {
    return _err_bloom(_at("bloom length mismatch", off));
  }
  let crc_off = off + 8 + bits_size;
  let crc = _rdu(data, crc_off, 4);
  let actual = badger_crc32c(data, off, 8 + bits_size);
  if actual < 0 || actual != crc {
    return _err_bloom(_at("bloom checksum mismatch", crc_off));
  }
  return _ok_bloom(BadgerBloom{
    nbits: nbits;
    nhashes: nhashes;
    bits_offset: off + 8;
    bits_size: bits_size;
    crc: crc;
  });
}

/// Bloom membership probe for the key span [key_off, key_off + key_size) of
/// `key_data`.
///
/// `bloom_data` is the buffer the bloom block was parsed from (the bit array
/// spans `bits_offset`/`bits_size` there); `key_data` is the buffer holding
/// the key. Double hashing: probe bit (h1 + i*h2) mod nbits for i in
/// [0, nhashes). False means "definitely absent"; true means "possibly
/// present" (the usual bloom contract). Err carries hash or bit-array bounds
/// failures. Complexity: O(nhashes).
pub fn badger_bloom_has(bloom_data: &Vec[UInt8], key_data: &Vec[UInt8], b: &BadgerBloom, key_off: Int, key_size: Int) -> Result[Bool, Str] {
  let hp = badger_bloom_hash_pair(key_data, key_off, key_size);
  if !hp.is_ok {
    return _err_bool(hp.error);
  }
  let pair = hp.value;
  let h1: Int = pair.h1;
  let h2: Int = pair.h2;
  let nbits: Int = b.nbits;
  let nhashes: Int = b.nhashes;
  let boff: Int = b.bits_offset;
  let bsize: Int = b.bits_size;
  if boff < 0 || bsize < 0 {
    return _err_bool(_at("bloom bits out of bounds", boff));
  }
  if boff > bloom_data.len() || bsize > bloom_data.len() - boff {
    return _err_bool(_at("bloom bits out of bounds", boff));
  }
  var i = 0;
  while i < nhashes {
    let idx = (h1 + i * h2) % nbits;
    let byte_index = idx / 8;
    let bit_index = idx % 8;
    if byte_index >= bsize {
      return _err_bool(_at("bloom bits out of bounds", boff));
    }
    let bv = _byte(bloom_data, boff + byte_index);
    let bit = _pow2(bit_index);
    let q = bv / bit;
    if q % 2 != 1 {
      return _ok_bool(false);
    }
    i = i + 1;
  }
  return _ok_bool(true);
}

// --------------------------------------------------
//  Manifest header
// --------------------------------------------------

/// Parse the 20-byte manifest header at offset 0.
///
/// Layout: magic u32 LE ("BDGM"), version u32 LE (1), creation time u64 LE
/// (raw pattern; 0 when unused), reserved u32 LE that must be zero.
///
/// Errors: "badger: manifest header truncated at 0", "badger: manifest bad
/// magic at 0", "badger: manifest unsupported version at 4", "badger:
/// manifest creation exceeds Int range at 8", "badger: manifest reserved
/// nonzero at 16". Complexity: O(1).
pub fn badger_manifest_header_parse(data: &Vec[UInt8]) -> Result[BadgerManifestHeader, Str] {
  if data.len() < BADGER_MANIFEST_HEADER_SIZE {
    return _err_mh(_at("manifest header truncated", 0));
  }
  let magic = _rdu(data, 0, 4);
  if magic != BADGER_MANIFEST_MAGIC {
    return _err_mh(_at("manifest bad magic", 0));
  }
  let version = _rdu(data, 4, 4);
  if version != BADGER_MANIFEST_VERSION {
    return _err_mh(_at("manifest unsupported version", 4));
  }
  let creation = _rdu(data, 8, 8);
  if creation < 0 {
    return _err_mh(_at("manifest creation exceeds Int range", 8));
  }
  let reserved = _rdu(data, 16, 4);
  if reserved != 0 {
    return _err_mh(_at("manifest reserved nonzero", 16));
  }
  return _ok_mh(BadgerManifestHeader{
    magic: magic;
    version: version;
    creation: creation;
    reserved: reserved;
  });
}

// --------------------------------------------------
//  Manifest file list
// --------------------------------------------------

/// Parse one 40-byte manifest file-list entry at `off`.
///
/// Layout: id u64 LE, checksum u32 LE, size u64 LE, flags u32 LE, min
/// version u64 LE, max version u64 LE. `consumed` in the result is always 40.
/// The known flag bits are BADGER_TABLE_FLAG_DELETED (0x01) and
/// BADGER_TABLE_FLAG_KEY_RANGE (0x02); any other bit is rejected. u64 fields
/// with bit 63 set are rejected as out of Int range.
///
/// Errors: "badger: manifest entry truncated at <off>", "badger: manifest
/// entry id exceeds Int range at <off>", "badger: manifest entry size
/// exceeds Int range at <off + 12>", "badger: manifest entry unknown flags
/// for file <id> at <off + 20>", "badger: manifest entry min version exceeds
/// Int range at <off + 24>", "badger: manifest entry max version exceeds Int
/// range at <off + 32>". Complexity: O(1).
pub fn badger_manifest_entry_parse(data: &Vec[UInt8], off: Int) -> Result[BadgerManifestEntry, Str] {
  if off < 0 {
    return _err_me(_at("manifest entry truncated", 0));
  }
  if off > data.len() || BADGER_MANIFEST_ENTRY_SIZE > data.len() - off {
    return _err_me(_at("manifest entry truncated", off));
  }
  let id = _rdu(data, off, 8);
  if id < 0 {
    return _err_me(_at("manifest entry id exceeds Int range", off));
  }
  let checksum = _rdu(data, off + 8, 4);
  let size = _rdu(data, off + 12, 8);
  if size < 0 {
    return _err_me(_at("manifest entry size exceeds Int range", off + 12));
  }
  let flags = _rdu(data, off + 20, 4);
  if flags > BADGER_TABLE_FLAG_KNOWN {
    return _err_me("badger: manifest entry unknown flags for file " + int_to_base(id, 10) + " at " + int_to_base(off + 20, 10));
  }
  let minv = _rdu(data, off + 24, 8);
  if minv < 0 {
    return _err_me(_at("manifest entry min version exceeds Int range", off + 24));
  }
  let maxv = _rdu(data, off + 32, 8);
  if maxv < 0 {
    return _err_me(_at("manifest entry max version exceeds Int range", off + 32));
  }
  return _ok_me(BadgerManifestEntry{
    id: id;
    checksum: checksum;
    size: size;
    flags: flags;
    min_version: minv;
    max_version: maxv;
    offset: off;
    consumed: BADGER_MANIFEST_ENTRY_SIZE;
  });
}

/// Name of a manifest file-list flag value: "DELETED" (1), "KEY_RANGE" (2),
/// "DELETED|KEY_RANGE" (3), "" otherwise. Complexity: O(1).
pub fn badger_table_flag_name(flags: Int) -> Str {
  if flags == BADGER_TABLE_FLAG_DELETED { return "DELETED"; }
  if flags == BADGER_TABLE_FLAG_KEY_RANGE { return "KEY_RANGE"; }
  if flags == BADGER_TABLE_FLAG_KNOWN { return "DELETED|KEY_RANGE"; }
  return "";
}

/// True when manifest entry `e` is marked deleted. Complexity: O(1).
pub fn badger_manifest_entry_deleted(e: &BadgerManifestEntry) -> Bool {
  let f: Int = e.flags;
  return _bit_set(f, BADGER_TABLE_FLAG_DELETED);
}

/// True when manifest entry `e` carries key-range version bounds.
/// Complexity: O(1).
pub fn badger_manifest_entry_has_range(e: &BadgerManifestEntry) -> Bool {
  let f: Int = e.flags;
  return _bit_set(f, BADGER_TABLE_FLAG_KEY_RANGE);
}

/// Parse a manifest file list at `off`.
///
/// Layout: count u32 LE, `count` 40-byte entries, trailing CRC32C u32 LE
/// over the count and all entries. `total_bytes` in the result is
/// 4 + count*40 + 4.
///
/// Errors: "badger: manifest file list truncated at <off>", "badger:
/// manifest file count exceeds cap at <off>", any entry-parse error, and
/// "badger: manifest file list checksum mismatch at <off + 4 + count*40>".
/// Complexity: O(count).
pub fn badger_manifest_files_parse(data: &Vec[UInt8], off: Int) -> Result[BadgerManifestFiles, Str] {
  if off < 0 {
    return _err_mf(_at("manifest file list truncated", 0));
  }
  if off > data.len() || 4 > data.len() - off {
    return _err_mf(_at("manifest file list truncated", off));
  }
  let count = _rdu(data, off, 4);
  if count > BADGER_MANIFEST_MAX_FILES {
    return _err_mf(_at("manifest file count exceeds cap", off));
  }
  let body = 4 + count * BADGER_MANIFEST_ENTRY_SIZE;
  if body > data.len() - off || 4 > data.len() - off - body {
    return _err_mf(_at("manifest file list truncated", off));
  }
  var ids = Vec[Int].new();
  var checksums = Vec[Int].new();
  var sizes = Vec[Int].new();
  var flags = Vec[Int].new();
  var min_versions = Vec[Int].new();
  var max_versions = Vec[Int].new();
  var offsets = Vec[Int].new();
  var entry_offsets = Vec[Int].new();
  var i = 0;
  while i < count {
    let eoff = off + 4 + i * BADGER_MANIFEST_ENTRY_SIZE;
    let er = badger_manifest_entry_parse(data, eoff);
    if !er.is_ok {
      return _err_mf(er.error);
    }
    let e = er.value;
    let eid: Int = e.id;
    let eck: Int = e.checksum;
    let esz: Int = e.size;
    let efl: Int = e.flags;
    let emin: Int = e.min_version;
    let emax: Int = e.max_version;
    ids.push(eid);
    checksums.push(eck);
    sizes.push(esz);
    flags.push(efl);
    min_versions.push(emin);
    max_versions.push(emax);
    offsets.push(eoff);
    entry_offsets.push(eoff);
    i = i + 1;
  }
  let crc_off = off + body;
  let crc = _rdu(data, crc_off, 4);
  let actual = badger_crc32c(data, off, body);
  if actual < 0 || actual != crc {
    return _err_mf(_at("manifest file list checksum mismatch", crc_off));
  }
  return _ok_mf(BadgerManifestFiles{
    count: count;
    ids: ids;
    checksums: checksums;
    sizes: sizes;
    flags: flags;
    min_versions: min_versions;
    max_versions: max_versions;
    offsets: offsets;
    entry_offsets: entry_offsets;
    crc: crc;
    total_bytes: body + 4;
  });
}

/// Number of files in a parsed manifest file list. Complexity: O(1).
pub fn badger_manifest_file_count(f: &BadgerManifestFiles) -> Int {
  return f.count;
}

/// Field `field` (one of the BADGER_FILE_FIELD_* selectors) of file `i`, or
/// Err("badger: manifest file index out of range at <i>") when `i` is
/// outside [0, count) or the selector is unknown. Complexity: O(1).
pub fn badger_manifest_file_field(f: &BadgerManifestFiles, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.count {
    return _err_int(_at("manifest file index out of range", i));
  }
  if field == BADGER_FILE_FIELD_ID {
    let v: Int = f.ids[i];
    return _ok_int(v);
  }
  if field == BADGER_FILE_FIELD_CHECKSUM {
    let v: Int = f.checksums[i];
    return _ok_int(v);
  }
  if field == BADGER_FILE_FIELD_SIZE {
    let v: Int = f.sizes[i];
    return _ok_int(v);
  }
  if field == BADGER_FILE_FIELD_FLAGS {
    let v: Int = f.flags[i];
    return _ok_int(v);
  }
  if field == BADGER_FILE_FIELD_MIN_VERSION {
    let v: Int = f.min_versions[i];
    return _ok_int(v);
  }
  if field == BADGER_FILE_FIELD_MAX_VERSION {
    let v: Int = f.max_versions[i];
    return _ok_int(v);
  }
  if field == BADGER_FILE_FIELD_OFFSET {
    let v: Int = f.offsets[i];
    return _ok_int(v);
  }
  if field == BADGER_FILE_FIELD_COUNT {
    return _ok_int(f.count);
  }
  return _err_int(_at("manifest file index out of range", i));
}

/// A short version marker for the module. Complexity: O(1).
pub fn badger_version() -> Str {
  return "0.1.0";
}
