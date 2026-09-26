// XIOM -- xiom.ext: ext2/3/4 superblock codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of an ext2/3/4 superblock
// codec. Scope: the 1024-byte superblock at byte offset 1024, its documented
// core fields, raw feature masks with a documented name table, and the
// documented ext4 extension fields read when s_rev_level >= 1. The parse
// buffer stays with the caller; the parsed ExtSuperblock is a plain value
// with no references into it.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - ext_superblock_parse requires at least 2048 bytes so the whole
//   superblock (offset 1024 .. 2048) is present, then validates the magic
//   0xEF53, the log block size (block size = 1024 << s_log_block_size,
//   documented cap 65536, so the stored value is 0..6), s_inode_size
//   (>= 128 and <= block size) and the documented non-zero counts, and
//   reads every core field. When s_rev_level >= 1 the ext4 extension
//   fields are present in the same block and are read too (has_ext true);
//   when it is 0 the extension region is ignored and reported as 0.
// - The uuid is exposed as 32 lowercase hex characters. s_volume_name and
//   s_last_mounted are read up to the first NUL byte (or the field end) and
//   trimmed of ASCII whitespace.
// - Feature masks are raw u32 values. ext_has_feature_* test them
//   arithmetically (division/modulo, never shifts) and ext_feature_*_name
//   maps documented single bits to kernel-style names ("" otherwise).
// - ext_superblock_build validates the same invariants and emits a
//   canonical 1024-byte superblock; extension fields are written exactly
//   when s_rev_level >= 1. ext_superblock_build_image prepends 1024 zero
//   bytes so the block lands at byte offset 1024.
//
// Non-goals: no inode, block-group, directory or extent parsing, no journal
// handling, no checksum computation, no device I/O; the decoded struct is a
// snapshot and is never written back to a device by this package.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * little-endian reads/packs are arithmetic (modulo/division): `& 0xFF`
//     on values with bit 31 set miscompiles, and feature bit tests divide
//     by powers of two instead of using shifts or masks.
//   * struct fields and Vec element reads are bound to typed locals before
//     being passed by reference; &struct.field / &result.value are never
//     passed directly to a &Vec parameter.

module xiom.ext

use xiom.string;
use xiom.encoding.hex;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// The superblock starts one 1024-byte block into the volume and is itself
// exactly 1024 bytes, so the complete prefix is at least 2048 bytes.
pub const EXT_SUPERBLOCK_OFFSET: Int = 1024;
pub const EXT_SUPERBLOCK_SIZE: Int = 1024;
pub const EXT_SUPERBLOCK_MIN_BUFFER: Int = 2048;

// s_magic value, 0xEF53.
pub const EXT_MAGIC: Int = 61267;

// Block size = 1024 << s_log_block_size; the documented cap is 65536
// (stored value 6).
pub const EXT_MIN_BLOCK_SIZE: Int = 1024;
pub const EXT_MAX_BLOCK_SIZE: Int = 65536;
pub const EXT_MAX_LOG_BLOCK_SIZE: Int = 6;

// s_inode_size documented floor.
pub const EXT_MIN_INODE_SIZE: Int = 128;

// Name-field widths in bytes.
pub const EXT_UUID_LEN: Int = 16;
pub const EXT_VOLUME_NAME_LEN: Int = 16;
pub const EXT_LAST_MOUNTED_LEN: Int = 64;

// s_feature_compat bits (documented name table).
pub const EXT_FEATURE_COMPAT_DIR_PREALLOC: Int = 1;
pub const EXT_FEATURE_COMPAT_IMAGIC_INODES: Int = 2;
pub const EXT_FEATURE_COMPAT_HAS_JOURNAL: Int = 4;
pub const EXT_FEATURE_COMPAT_EXT_ATTR: Int = 8;
pub const EXT_FEATURE_COMPAT_RESIZE_INODE: Int = 16;
pub const EXT_FEATURE_COMPAT_DIR_INDEX: Int = 32;
pub const EXT_FEATURE_COMPAT_SPARSE_SUPER2: Int = 512;
pub const EXT_FEATURE_COMPAT_FAST_COMMIT: Int = 1024;
pub const EXT_FEATURE_COMPAT_STABLE_INODES: Int = 2048;
pub const EXT_FEATURE_COMPAT_ORPHAN_FILE: Int = 4096;

// s_feature_incompat bits (documented name table).
pub const EXT_FEATURE_INCOMPAT_COMPRESSION: Int = 1;
pub const EXT_FEATURE_INCOMPAT_FILETYPE: Int = 2;
pub const EXT_FEATURE_INCOMPAT_RECOVER: Int = 4;
pub const EXT_FEATURE_INCOMPAT_JOURNAL_DEV: Int = 8;
pub const EXT_FEATURE_INCOMPAT_META_BG: Int = 16;
pub const EXT_FEATURE_INCOMPAT_EXTENTS: Int = 64;
pub const EXT_FEATURE_INCOMPAT_64BIT: Int = 128;
pub const EXT_FEATURE_INCOMPAT_MMP: Int = 256;
pub const EXT_FEATURE_INCOMPAT_FLEX_BG: Int = 512;
pub const EXT_FEATURE_INCOMPAT_EA_INODE: Int = 1024;
pub const EXT_FEATURE_INCOMPAT_DIRDATA: Int = 4096;
pub const EXT_FEATURE_INCOMPAT_CSUM_SEED: Int = 8192;
pub const EXT_FEATURE_INCOMPAT_LARGEDIR: Int = 16384;
pub const EXT_FEATURE_INCOMPAT_INLINE_DATA: Int = 32768;
pub const EXT_FEATURE_INCOMPAT_ENCRYPT: Int = 65536;
pub const EXT_FEATURE_INCOMPAT_CASEFOLD: Int = 131072;

// s_feature_ro_compat bits (documented name table).
pub const EXT_FEATURE_RO_COMPAT_SPARSE_SUPER: Int = 1;
pub const EXT_FEATURE_RO_COMPAT_LARGE_FILE: Int = 2;
pub const EXT_FEATURE_RO_COMPAT_BTREE_DIR: Int = 4;
pub const EXT_FEATURE_RO_COMPAT_HUGE_FILE: Int = 8;
pub const EXT_FEATURE_RO_COMPAT_GDT_CSUM: Int = 16;
pub const EXT_FEATURE_RO_COMPAT_DIR_NLINK: Int = 32;
pub const EXT_FEATURE_RO_COMPAT_EXTRA_ISIZE: Int = 64;
pub const EXT_FEATURE_RO_COMPAT_QUOTA: Int = 256;
pub const EXT_FEATURE_RO_COMPAT_BIGALLOC: Int = 512;
pub const EXT_FEATURE_RO_COMPAT_METADATA_CSUM: Int = 1024;
pub const EXT_FEATURE_RO_COMPAT_REPLICA: Int = 2048;
pub const EXT_FEATURE_RO_COMPAT_READONLY: Int = 4096;
pub const EXT_FEATURE_RO_COMPAT_PROJECT: Int = 8192;
pub const EXT_FEATURE_RO_COMPAT_VERITY: Int = 32768;
pub const EXT_FEATURE_RO_COMPAT_ORPHAN_PRESENT: Int = 65536;

// --------------------------------------------------
//  Parsed superblock
// --------------------------------------------------

/// A decoded ext2/3/4 superblock.
///
/// The scalar fields mirror the on-disk field of the same name, read raw
/// (unsigned little-endian); nothing is interpreted beyond the documented
/// validation. `uuid_hex` is the 16-byte s_uuid as 32 lowercase hex
/// characters, `volume_name`/`last_mounted` are the trimmed name fields,
/// and `has_ext` records whether the ext4 extension fields were read
/// (s_rev_level >= 1): the `*_hi` counts, `min_extra_isize`,
/// `want_extra_isize`, `flags`, `checksum_type` and `desc_size` are 0 when
/// it is false. Fields are implementation details; callers should go
/// through the free functions below.
pub type ExtSuperblock = {
  inodes_count: Int;
  blocks_count_lo: Int;
  r_blocks_count_lo: Int;
  free_blocks_count_lo: Int;
  free_inodes_count: Int;
  first_data_block: Int;
  log_block_size: Int;
  log_cluster_size: Int;
  blocks_per_group: Int;
  clusters_per_group: Int;
  inodes_per_group: Int;
  mtime: Int;
  wtime: Int;
  mnt_count: Int;
  max_mnt_count: Int;
  magic: Int;
  state: Int;
  errors: Int;
  minor_rev_level: Int;
  lastcheck: Int;
  checkinterval: Int;
  creator_os: Int;
  rev_level: Int;
  def_resuid: Int;
  def_resgid: Int;
  first_ino: Int;
  inode_size: Int;
  block_group_nr: Int;
  feature_compat: Int;
  feature_incompat: Int;
  feature_ro_compat: Int;
  uuid_hex: Str;
  volume_name: Str;
  last_mounted: Str;
  algo_bitmap: Int;
  blocks_count_hi: Int;
  r_blocks_count_hi: Int;
  free_blocks_count_hi: Int;
  min_extra_isize: Int;
  want_extra_isize: Int;
  flags: Int;
  checksum_type: Int;
  desc_size: Int;
  has_ext: Bool;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[ExtSuperblock, Str].
fn _ok_sb(v: ExtSuperblock) -> Result[ExtSuperblock, Str] {
  return Ok(v);
}

// Err(m) for Result[ExtSuperblock, Str].
fn _err_sb(m: Str) -> Result[ExtSuperblock, Str] {
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
//  Internal byte and arithmetic helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian u16 at `off` as an Int (0..65535).
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256;
}

// Little-endian u32 at `off` as an Int (0..4294967295).
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536 + _byte(data, off + 3) * 16777216;
}

// 2 to the power `k` (0 <= k <= 31); 1 when k <= 0.
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// True when bit `bit` (0..31) is set in the unsigned value `v`.
// Arithmetic only: `v` may have bit 31 set, where `&` miscompiles.
fn _bit_set(v: Int, bit: Int) -> Bool {
  if bit < 0 || bit > 31 {
    return false;
  }
  let p = _pow2(bit);
  return (v / p) % 2 == 1;
}

// True when every bit set in `mask` is set in `v`. A mask of 0 is
// vacuously true. Bits above 31 are ignored.
fn _mask_set(v: Int, mask: Int) -> Bool {
  var i = 0;
  while i < 32 {
    if _bit_set(mask, i) {
      if !_bit_set(v, i) {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// Byte `k` (0 = least significant) of the raw two's-complement bit pattern
// of `v`, as a value in 0..255. Arithmetic only for the same reason.
fn _low_byte(v: Int, k: Int) -> Int {
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
  return b;
}

// Append `v` as one byte.
fn _push_le8(out: &mut Vec[UInt8], v: Int) {
  out.push(_low_byte(v, 0) as UInt8);
}

// Append `v` as two little-endian bytes.
fn _push_le16(out: &mut Vec[UInt8], v: Int) {
  out.push(_low_byte(v, 0) as UInt8);
  out.push(_low_byte(v, 1) as UInt8);
}

// Append `v` as four little-endian bytes.
fn _push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push(_low_byte(v, 0) as UInt8);
  out.push(_low_byte(v, 1) as UInt8);
  out.push(_low_byte(v, 2) as UInt8);
  out.push(_low_byte(v, 3) as UInt8);
}

// Append `count` zero bytes.
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append a name field: the bytes of `s`, then NUL padding up to `width`.
// Callers validate s.len() <= width and that s holds no NUL byte.
fn _push_name(out: &mut Vec[UInt8], s: Str, width: Int) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  _push_zero(out, width - s.len());
}

// True when `s` contains a NUL byte (0x00).
fn _has_nul(s: Str) -> Bool {
  var i = 0;
  let n = s.len();
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Unsigned width checks for the builder.
fn _u8_ok(v: Int) -> Bool {
  if v < 0 { return false; }
  if v > 255 { return false; }
  return true;
}

fn _u16_ok(v: Int) -> Bool {
  if v < 0 { return false; }
  if v > 65535 { return false; }
  return true;
}

fn _u32_ok(v: Int) -> Bool {
  if v < 0 { return false; }
  if v > 4294967295 { return false; }
  return true;
}

// The 16 s_uuid bytes at `off` as a 32-character lowercase hex string.
fn _uuid_hex(data: &Vec[UInt8], off: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < EXT_UUID_LEN {
    bytes.push(data[off + i]);
    i = i + 1;
  }
  return hex.hex_encode(&bytes);
}

// A name field of `width` bytes at `off`: bytes up to the first NUL (or the
// field end), trimmed of ASCII whitespace. The NUL and everything after it
// is dropped, so the result never contains a NUL.
fn _field_name(data: &Vec[UInt8], off: Int, width: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < width && !done {
    let c: Int = _byte(data, off + i);
    if c == 0 {
      done = true;
    } else {
      bytes.push(c as UInt8);
    }
    i = i + 1;
  }
  let raw = Str::from_utf8(bytes);
  return string.str_trim(raw);
}

// Block size derived from s_log_block_size, or -1 when the stored value is
// outside the documented 0..6 range (only possible on a hand-built struct).
fn _block_size(log_value: Int) -> Int {
  if log_value < 0 || log_value > EXT_MAX_LOG_BLOCK_SIZE {
    return -1;
  }
  return EXT_MIN_BLOCK_SIZE * _pow2(log_value);
}

// --------------------------------------------------
//  Parse
// --------------------------------------------------

// Read and validate the superblock whose first byte is at `base`. The
// caller guarantees base + 1024 <= data.len().
fn _parse_at(data: &Vec[UInt8], base: Int) -> Result[ExtSuperblock, Str] {
  let magic = _le16(data, base + 56);
  if magic != EXT_MAGIC {
    return _err_sb("ext: bad magic");
  }
  let log_block_size = _le32(data, base + 24);
  if log_block_size < 0 || log_block_size > EXT_MAX_LOG_BLOCK_SIZE {
    return _err_sb("ext: bad log block size");
  }
  let block_size = _block_size(log_block_size);
  let inode_size = _le16(data, base + 88);
  if inode_size < EXT_MIN_INODE_SIZE {
    return _err_sb("ext: bad inode size");
  }
  if inode_size > block_size {
    return _err_sb("ext: bad inode size");
  }
  let inodes_count = _le32(data, base + 0);
  if inodes_count == 0 {
    return _err_sb("ext: bad inode count");
  }
  let rev_level = _le32(data, base + 76);
  var has_ext = false;
  var blocks_count_hi = 0;
  var r_blocks_count_hi = 0;
  var free_blocks_count_hi = 0;
  var min_extra_isize = 0;
  var want_extra_isize = 0;
  var flags = 0;
  var checksum_type = 0;
  var desc_size = 0;
  if rev_level >= 1 {
    has_ext = true;
    desc_size = _le16(data, base + 254);
    blocks_count_hi = _le32(data, base + 336);
    r_blocks_count_hi = _le32(data, base + 340);
    free_blocks_count_hi = _le32(data, base + 344);
    min_extra_isize = _le16(data, base + 348);
    want_extra_isize = _le16(data, base + 350);
    flags = _le32(data, base + 352);
    checksum_type = _byte(data, base + 373);
  }
  let blocks_count_lo = _le32(data, base + 4);
  let blocks_count = blocks_count_lo + blocks_count_hi * 4294967296;
  if blocks_count == 0 {
    return _err_sb("ext: bad block count");
  }
  let blocks_per_group = _le32(data, base + 32);
  if blocks_per_group == 0 {
    return _err_sb("ext: bad blocks per group");
  }
  let inodes_per_group = _le32(data, base + 40);
  if inodes_per_group == 0 {
    return _err_sb("ext: bad inodes per group");
  }
  let sb = ExtSuperblock{
    inodes_count: inodes_count;
    blocks_count_lo: blocks_count_lo;
    r_blocks_count_lo: _le32(data, base + 8);
    free_blocks_count_lo: _le32(data, base + 12);
    free_inodes_count: _le32(data, base + 16);
    first_data_block: _le32(data, base + 20);
    log_block_size: log_block_size;
    log_cluster_size: _le32(data, base + 28);
    blocks_per_group: blocks_per_group;
    clusters_per_group: _le32(data, base + 36);
    inodes_per_group: inodes_per_group;
    mtime: _le32(data, base + 44);
    wtime: _le32(data, base + 48);
    mnt_count: _le16(data, base + 52);
    max_mnt_count: _le16(data, base + 54);
    magic: magic;
    state: _le16(data, base + 58);
    errors: _le16(data, base + 60);
    minor_rev_level: _le16(data, base + 62);
    lastcheck: _le32(data, base + 64);
    checkinterval: _le32(data, base + 68);
    creator_os: _le32(data, base + 72);
    rev_level: rev_level;
    def_resuid: _le16(data, base + 80);
    def_resgid: _le16(data, base + 82);
    first_ino: _le32(data, base + 84);
    inode_size: inode_size;
    block_group_nr: _le16(data, base + 90);
    feature_compat: _le32(data, base + 92);
    feature_incompat: _le32(data, base + 96);
    feature_ro_compat: _le32(data, base + 100);
    uuid_hex: _uuid_hex(data, base + 104);
    volume_name: _field_name(data, base + 120, EXT_VOLUME_NAME_LEN);
    last_mounted: _field_name(data, base + 136, EXT_LAST_MOUNTED_LEN);
    algo_bitmap: _le32(data, base + 200);
    blocks_count_hi: blocks_count_hi;
    r_blocks_count_hi: r_blocks_count_hi;
    free_blocks_count_hi: free_blocks_count_hi;
    min_extra_isize: min_extra_isize;
    want_extra_isize: want_extra_isize;
    flags: flags;
    checksum_type: checksum_type;
    desc_size: desc_size;
    has_ext: has_ext;
  };
  return _ok_sb(sb);
}

/// Parse the ext2/3/4 superblock at byte offset 1024.
///
/// The buffer must hold the whole 1024-byte superblock, so at least 2048
/// bytes are required (Err("ext: truncated buffer") otherwise). Validation
/// order (first failure wins): magic 0xEF53 -> Err("ext: bad magic"); the
/// log block size in 0..6 -> Err("ext: bad log block size"); s_inode_size
/// >= 128 and <= block size -> Err("ext: bad inode size"); s_inodes_count
/// != 0 -> Err("ext: bad inode count"); the combined block count != 0 ->
/// Err("ext: bad block count"); s_blocks_per_group != 0 -> Err("ext: bad
/// blocks per group"); s_inodes_per_group != 0 -> Err("ext: bad inodes per
/// group"). When s_rev_level >= 1 the ext4 extension fields present in the
/// same block are read as well.
///
/// Params: data - a buffer holding at least the first 2048 bytes of the
/// volume, read only.
/// Returns: Ok(ExtSuperblock) with every documented field; the buffer is
/// not retained.
/// Error case: the "ext: " messages above; no partial superblock is
/// returned.
/// Complexity: O(1).
pub fn ext_superblock_parse(data: &Vec[UInt8]) -> Result[ExtSuperblock, Str] {
  if data.len() < EXT_SUPERBLOCK_MIN_BUFFER {
    return _err_sb("ext: truncated buffer");
  }
  return _parse_at(data, EXT_SUPERBLOCK_OFFSET);
}

// --------------------------------------------------
//  Accessors -- core fields
// --------------------------------------------------

/// s_inodes_count (u32). Total inode count. Complexity: O(1).
pub fn ext_inodes_count(sb: &ExtSuperblock) -> Int {
  return sb.inodes_count;
}

/// s_blocks_count_lo (u32). Low 32 bits of the block count.
/// Complexity: O(1).
pub fn ext_blocks_count_lo(sb: &ExtSuperblock) -> Int {
  return sb.blocks_count_lo;
}

/// s_r_blocks_count_lo (u32). Blocks reserved for the super user.
/// Complexity: O(1).
pub fn ext_r_blocks_count_lo(sb: &ExtSuperblock) -> Int {
  return sb.r_blocks_count_lo;
}

/// s_free_blocks_count_lo (u32). Free block count, low 32 bits.
/// Complexity: O(1).
pub fn ext_free_blocks_count_lo(sb: &ExtSuperblock) -> Int {
  return sb.free_blocks_count_lo;
}

/// s_free_inodes_count (u32). Free inode count. Complexity: O(1).
pub fn ext_free_inodes_count(sb: &ExtSuperblock) -> Int {
  return sb.free_inodes_count;
}

/// s_first_data_block (u32). First data block (0 for 1 KiB blocks, else 1).
/// Complexity: O(1).
pub fn ext_first_data_block(sb: &ExtSuperblock) -> Int {
  return sb.first_data_block;
}

/// s_log_block_size (u32). Block size is 1024 << this; 0..6.
/// Complexity: O(1).
pub fn ext_log_block_size(sb: &ExtSuperblock) -> Int {
  return sb.log_block_size;
}

/// Derived block size in bytes, 1024 << s_log_block_size; -1 when a
/// hand-built struct stores a value outside 0..6. Complexity: O(1).
pub fn ext_block_size(sb: &ExtSuperblock) -> Int {
  return _block_size(sb.log_block_size);
}

/// s_log_cluster_size (u32). Cluster size is 1024 << this (bigalloc).
/// Complexity: O(1).
pub fn ext_log_cluster_size(sb: &ExtSuperblock) -> Int {
  return sb.log_cluster_size;
}

/// s_blocks_per_group (u32). Blocks per block group.
/// Complexity: O(1).
pub fn ext_blocks_per_group(sb: &ExtSuperblock) -> Int {
  return sb.blocks_per_group;
}

/// s_clusters_per_group (u32). Clusters per block group.
/// Complexity: O(1).
pub fn ext_clusters_per_group(sb: &ExtSuperblock) -> Int {
  return sb.clusters_per_group;
}

/// s_inodes_per_group (u32). Inodes per block group.
/// Complexity: O(1).
pub fn ext_inodes_per_group(sb: &ExtSuperblock) -> Int {
  return sb.inodes_per_group;
}

/// s_mtime (u32). Last mount time, seconds since the Unix epoch.
/// Complexity: O(1).
pub fn ext_mtime(sb: &ExtSuperblock) -> Int {
  return sb.mtime;
}

/// s_wtime (u32). Last write time, seconds since the Unix epoch.
/// Complexity: O(1).
pub fn ext_wtime(sb: &ExtSuperblock) -> Int {
  return sb.wtime;
}

/// s_mnt_count (u16). Mount count since the last check.
/// Complexity: O(1).
pub fn ext_mnt_count(sb: &ExtSuperblock) -> Int {
  return sb.mnt_count;
}

/// s_max_mnt_count (u16). Mount count allowed before a check.
/// Complexity: O(1).
pub fn ext_max_mnt_count(sb: &ExtSuperblock) -> Int {
  return sb.max_mnt_count;
}

/// s_magic (u16). 0xEF53 on a valid superblock. Complexity: O(1).
pub fn ext_magic(sb: &ExtSuperblock) -> Int {
  return sb.magic;
}

/// s_state (u16). Filesystem state flags, read raw. Complexity: O(1).
pub fn ext_state(sb: &ExtSuperblock) -> Int {
  return sb.state;
}

/// s_errors (u16). Error-behavior code, read raw. Complexity: O(1).
pub fn ext_errors(sb: &ExtSuperblock) -> Int {
  return sb.errors;
}

/// s_minor_rev_level (u16). Minor revision level. Complexity: O(1).
pub fn ext_minor_rev_level(sb: &ExtSuperblock) -> Int {
  return sb.minor_rev_level;
}

/// s_lastcheck (u32). Last check time, seconds since the Unix epoch.
/// Complexity: O(1).
pub fn ext_lastcheck(sb: &ExtSuperblock) -> Int {
  return sb.lastcheck;
}

/// s_checkinterval (u32). Maximum check interval in seconds.
/// Complexity: O(1).
pub fn ext_checkinterval(sb: &ExtSuperblock) -> Int {
  return sb.checkinterval;
}

/// s_creator_os (u32). Creating-OS code, read raw. Complexity: O(1).
pub fn ext_creator_os(sb: &ExtSuperblock) -> Int {
  return sb.creator_os;
}

/// s_rev_level (u32). 0 = original format, 1 = dynamic revision.
/// Complexity: O(1).
pub fn ext_rev_level(sb: &ExtSuperblock) -> Int {
  return sb.rev_level;
}

/// s_def_resuid (u16). Default UID for reserved blocks. Complexity: O(1).
pub fn ext_def_resuid(sb: &ExtSuperblock) -> Int {
  return sb.def_resuid;
}

/// s_def_resgid (u16). Default GID for reserved blocks. Complexity: O(1).
pub fn ext_def_resgid(sb: &ExtSuperblock) -> Int {
  return sb.def_resgid;
}

/// s_first_ino (u32). First non-reserved inode. Complexity: O(1).
pub fn ext_first_ino(sb: &ExtSuperblock) -> Int {
  return sb.first_ino;
}

/// s_inode_size (u16). Inode size in bytes (>= 128). Complexity: O(1).
pub fn ext_inode_size(sb: &ExtSuperblock) -> Int {
  return sb.inode_size;
}

/// s_block_group_nr (u16). Block group number of this superblock copy
/// (used by backups). Complexity: O(1).
pub fn ext_block_group_nr(sb: &ExtSuperblock) -> Int {
  return sb.block_group_nr;
}

/// s_feature_compat (u32) as a raw mask. Complexity: O(1).
pub fn ext_feature_compat(sb: &ExtSuperblock) -> Int {
  return sb.feature_compat;
}

/// s_feature_incompat (u32) as a raw mask. Complexity: O(1).
pub fn ext_feature_incompat(sb: &ExtSuperblock) -> Int {
  return sb.feature_incompat;
}

/// s_feature_ro_compat (u32) as a raw mask. Complexity: O(1).
pub fn ext_feature_ro_compat(sb: &ExtSuperblock) -> Int {
  return sb.feature_ro_compat;
}

/// s_uuid as 32 lowercase hex characters. Complexity: O(1).
pub fn ext_uuid_hex(sb: &ExtSuperblock) -> Str {
  return sb.uuid_hex;
}

/// s_volume_name, read up to the first NUL and trimmed; "" when empty.
/// Complexity: O(1).
pub fn ext_volume_name(sb: &ExtSuperblock) -> Str {
  return sb.volume_name;
}

/// s_last_mounted, read up to the first NUL and trimmed; "" when empty.
/// Complexity: O(1).
pub fn ext_last_mounted(sb: &ExtSuperblock) -> Str {
  return sb.last_mounted;
}

/// s_algo_bitmap (s_algorithm_usage_bitmap, u32), read raw.
/// Complexity: O(1).
pub fn ext_algo_bitmap(sb: &ExtSuperblock) -> Int {
  return sb.algo_bitmap;
}

// --------------------------------------------------
//  Accessors -- ext4 extension fields
// --------------------------------------------------

/// s_blocks_count_hi (u32); 0 when has_ext is false. Complexity: O(1).
pub fn ext_blocks_count_hi(sb: &ExtSuperblock) -> Int {
  return sb.blocks_count_hi;
}

/// s_r_blocks_count_hi (u32); 0 when has_ext is false. Complexity: O(1).
pub fn ext_r_blocks_count_hi(sb: &ExtSuperblock) -> Int {
  return sb.r_blocks_count_hi;
}

/// s_free_blocks_count_hi (u32); 0 when has_ext is false. Complexity: O(1).
pub fn ext_free_blocks_count_hi(sb: &ExtSuperblock) -> Int {
  return sb.free_blocks_count_hi;
}

/// s_min_extra_isize (u16); 0 when has_ext is false. Complexity: O(1).
pub fn ext_min_extra_isize(sb: &ExtSuperblock) -> Int {
  return sb.min_extra_isize;
}

/// s_want_extra_isize (u16); 0 when has_ext is false. Complexity: O(1).
pub fn ext_want_extra_isize(sb: &ExtSuperblock) -> Int {
  return sb.want_extra_isize;
}

/// s_flags (u32), read raw; 0 when has_ext is false. Complexity: O(1).
pub fn ext_flags(sb: &ExtSuperblock) -> Int {
  return sb.flags;
}

/// s_checksum_type (u8), read raw; 0 when has_ext is false.
/// Complexity: O(1).
pub fn ext_checksum_type(sb: &ExtSuperblock) -> Int {
  return sb.checksum_type;
}

/// s_desc_size (u16), read raw; 0 when has_ext is false. Complexity: O(1).
pub fn ext_desc_size(sb: &ExtSuperblock) -> Int {
  return sb.desc_size;
}

/// True when the ext4 extension fields were read (s_rev_level >= 1).
/// Complexity: O(1).
pub fn ext_has_ext_fields(sb: &ExtSuperblock) -> Bool {
  return sb.has_ext;
}

/// Derived 64-bit block count: blocks_count_lo + blocks_count_hi * 2^32.
/// Values with s_blocks_count_hi >= 2^31 exceed Int range and are not
/// representable (documented limitation). Complexity: O(1).
pub fn ext_blocks_count(sb: &ExtSuperblock) -> Int {
  return sb.blocks_count_lo + sb.blocks_count_hi * 4294967296;
}

/// Derived 64-bit reserved block count: r_blocks_count_lo + *_hi * 2^32.
/// Same representability limitation as ext_blocks_count. Complexity: O(1).
pub fn ext_r_blocks_count(sb: &ExtSuperblock) -> Int {
  return sb.r_blocks_count_lo + sb.r_blocks_count_hi * 4294967296;
}

/// Derived 64-bit free block count: free_blocks_count_lo + *_hi * 2^32.
/// Same representability limitation as ext_blocks_count. Complexity: O(1).
pub fn ext_free_blocks_count(sb: &ExtSuperblock) -> Int {
  return sb.free_blocks_count_lo + sb.free_blocks_count_hi * 4294967296;
}

// --------------------------------------------------
//  Feature-bit predicates and name table
// --------------------------------------------------

/// True when every bit set in `mask` is set in s_feature_compat.
/// A mask of 0 is vacuously true. Complexity: O(1).
pub fn ext_has_feature_compat(sb: &ExtSuperblock, mask: Int) -> Bool {
  let v: Int = sb.feature_compat;
  return _mask_set(v, mask);
}

/// True when every bit set in `mask` is set in s_feature_incompat.
/// A mask of 0 is vacuously true. Complexity: O(1).
pub fn ext_has_feature_incompat(sb: &ExtSuperblock, mask: Int) -> Bool {
  let v: Int = sb.feature_incompat;
  return _mask_set(v, mask);
}

/// True when every bit set in `mask` is set in s_feature_ro_compat.
/// A mask of 0 is vacuously true. Complexity: O(1).
pub fn ext_has_feature_ro_compat(sb: &ExtSuperblock, mask: Int) -> Bool {
  let v: Int = sb.feature_ro_compat;
  return _mask_set(v, mask);
}

/// Kernel-style name of one documented s_feature_compat bit; "" for 0, a
/// multi-bit mask or an undocumented bit. Complexity: O(1).
pub fn ext_feature_compat_name(mask: Int) -> Str {
  if mask == EXT_FEATURE_COMPAT_DIR_PREALLOC { return "COMPAT_DIR_PREALLOC"; }
  if mask == EXT_FEATURE_COMPAT_IMAGIC_INODES { return "COMPAT_IMAGIC_INODES"; }
  if mask == EXT_FEATURE_COMPAT_HAS_JOURNAL { return "COMPAT_HAS_JOURNAL"; }
  if mask == EXT_FEATURE_COMPAT_EXT_ATTR { return "COMPAT_EXT_ATTR"; }
  if mask == EXT_FEATURE_COMPAT_RESIZE_INODE { return "COMPAT_RESIZE_INODE"; }
  if mask == EXT_FEATURE_COMPAT_DIR_INDEX { return "COMPAT_DIR_INDEX"; }
  if mask == EXT_FEATURE_COMPAT_SPARSE_SUPER2 { return "COMPAT_SPARSE_SUPER2"; }
  if mask == EXT_FEATURE_COMPAT_FAST_COMMIT { return "COMPAT_FAST_COMMIT"; }
  if mask == EXT_FEATURE_COMPAT_STABLE_INODES { return "COMPAT_STABLE_INODES"; }
  if mask == EXT_FEATURE_COMPAT_ORPHAN_FILE { return "COMPAT_ORPHAN_FILE"; }
  return "";
}

/// Kernel-style name of one documented s_feature_incompat bit; "" for 0, a
/// multi-bit mask or an undocumented bit. Complexity: O(1).
pub fn ext_feature_incompat_name(mask: Int) -> Str {
  if mask == EXT_FEATURE_INCOMPAT_COMPRESSION { return "INCOMPAT_COMPRESSION"; }
  if mask == EXT_FEATURE_INCOMPAT_FILETYPE { return "INCOMPAT_FILETYPE"; }
  if mask == EXT_FEATURE_INCOMPAT_RECOVER { return "INCOMPAT_RECOVER"; }
  if mask == EXT_FEATURE_INCOMPAT_JOURNAL_DEV { return "INCOMPAT_JOURNAL_DEV"; }
  if mask == EXT_FEATURE_INCOMPAT_META_BG { return "INCOMPAT_META_BG"; }
  if mask == EXT_FEATURE_INCOMPAT_EXTENTS { return "INCOMPAT_EXTENTS"; }
  if mask == EXT_FEATURE_INCOMPAT_64BIT { return "INCOMPAT_64BIT"; }
  if mask == EXT_FEATURE_INCOMPAT_MMP { return "INCOMPAT_MMP"; }
  if mask == EXT_FEATURE_INCOMPAT_FLEX_BG { return "INCOMPAT_FLEX_BG"; }
  if mask == EXT_FEATURE_INCOMPAT_EA_INODE { return "INCOMPAT_EA_INODE"; }
  if mask == EXT_FEATURE_INCOMPAT_DIRDATA { return "INCOMPAT_DIRDATA"; }
  if mask == EXT_FEATURE_INCOMPAT_CSUM_SEED { return "INCOMPAT_CSUM_SEED"; }
  if mask == EXT_FEATURE_INCOMPAT_LARGEDIR { return "INCOMPAT_LARGEDIR"; }
  if mask == EXT_FEATURE_INCOMPAT_INLINE_DATA { return "INCOMPAT_INLINE_DATA"; }
  if mask == EXT_FEATURE_INCOMPAT_ENCRYPT { return "INCOMPAT_ENCRYPT"; }
  if mask == EXT_FEATURE_INCOMPAT_CASEFOLD { return "INCOMPAT_CASEFOLD"; }
  return "";
}

/// Kernel-style name of one documented s_feature_ro_compat bit; "" for 0, a
/// multi-bit mask or an undocumented bit. Complexity: O(1).
pub fn ext_feature_ro_compat_name(mask: Int) -> Str {
  if mask == EXT_FEATURE_RO_COMPAT_SPARSE_SUPER { return "RO_COMPAT_SPARSE_SUPER"; }
  if mask == EXT_FEATURE_RO_COMPAT_LARGE_FILE { return "RO_COMPAT_LARGE_FILE"; }
  if mask == EXT_FEATURE_RO_COMPAT_BTREE_DIR { return "RO_COMPAT_BTREE_DIR"; }
  if mask == EXT_FEATURE_RO_COMPAT_HUGE_FILE { return "RO_COMPAT_HUGE_FILE"; }
  if mask == EXT_FEATURE_RO_COMPAT_GDT_CSUM { return "RO_COMPAT_GDT_CSUM"; }
  if mask == EXT_FEATURE_RO_COMPAT_DIR_NLINK { return "RO_COMPAT_DIR_NLINK"; }
  if mask == EXT_FEATURE_RO_COMPAT_EXTRA_ISIZE { return "RO_COMPAT_EXTRA_ISIZE"; }
  if mask == EXT_FEATURE_RO_COMPAT_QUOTA { return "RO_COMPAT_QUOTA"; }
  if mask == EXT_FEATURE_RO_COMPAT_BIGALLOC { return "RO_COMPAT_BIGALLOC"; }
  if mask == EXT_FEATURE_RO_COMPAT_METADATA_CSUM { return "RO_COMPAT_METADATA_CSUM"; }
  if mask == EXT_FEATURE_RO_COMPAT_REPLICA { return "RO_COMPAT_REPLICA"; }
  if mask == EXT_FEATURE_RO_COMPAT_READONLY { return "RO_COMPAT_READONLY"; }
  if mask == EXT_FEATURE_RO_COMPAT_PROJECT { return "RO_COMPAT_PROJECT"; }
  if mask == EXT_FEATURE_RO_COMPAT_VERITY { return "RO_COMPAT_VERITY"; }
  if mask == EXT_FEATURE_RO_COMPAT_ORPHAN_PRESENT { return "RO_COMPAT_ORPHAN_PRESENT"; }
  return "";
}

// --------------------------------------------------
//  Build
// --------------------------------------------------

// The 16 uuid bytes described by sb.uuid_hex.
fn _uuid_bytes(sb: &ExtSuperblock) -> Result[Vec[UInt8], Str] {
  let s: Str = sb.uuid_hex;
  let r = hex.hex_decode(s);
  if !r.is_ok {
    return _err_bytes("ext: bad uuid");
  }
  let bytes: Vec[UInt8] = r.value;
  if bytes.len() != EXT_UUID_LEN {
    return _err_bytes("ext: bad uuid");
  }
  return _ok_bytes(bytes);
}

// Validate everything ext_superblock_build is about to write.
fn _validate_build(sb: &ExtSuperblock) -> Result[Unit, Str] {
  let magic: Int = sb.magic;
  if magic != EXT_MAGIC {
    return _err_unit("ext: bad magic");
  }
  let logb: Int = sb.log_block_size;
  if logb < 0 || logb > EXT_MAX_LOG_BLOCK_SIZE {
    return _err_unit("ext: bad log block size");
  }
  let block_size = _block_size(logb);
  let isize: Int = sb.inode_size;
  if isize < EXT_MIN_INODE_SIZE {
    return _err_unit("ext: bad inode size");
  }
  if isize > block_size {
    return _err_unit("ext: bad inode size");
  }
  let inodes_count: Int = sb.inodes_count;
  if inodes_count == 0 {
    return _err_unit("ext: bad inode count");
  }
  let rev: Int = sb.rev_level;
  var ext = false;
  if rev >= 1 {
    ext = true;
  }
  var bchi = 0;
  var rchi = 0;
  var fchi = 0;
  var minx = 0;
  var wantx = 0;
  var fl = 0;
  var ct = 0;
  var ds = 0;
  if ext {
    bchi = sb.blocks_count_hi;
    rchi = sb.r_blocks_count_hi;
    fchi = sb.free_blocks_count_hi;
    minx = sb.min_extra_isize;
    wantx = sb.want_extra_isize;
    fl = sb.flags;
    ct = sb.checksum_type;
    ds = sb.desc_size;
  }
  let blocks_count = sb.blocks_count_lo + bchi * 4294967296;
  if blocks_count == 0 {
    return _err_unit("ext: bad block count");
  }
  let bpg: Int = sb.blocks_per_group;
  if bpg == 0 {
    return _err_unit("ext: bad blocks per group");
  }
  let ipg: Int = sb.inodes_per_group;
  if ipg == 0 {
    return _err_unit("ext: bad inodes per group");
  }
  let ur = _uuid_bytes(sb);
  if !ur.is_ok {
    return _err_unit("ext: bad uuid");
  }
  let vol: Str = sb.volume_name;
  if vol.len() > EXT_VOLUME_NAME_LEN {
    return _err_unit("ext: bad volume name");
  }
  if _has_nul(vol) {
    return _err_unit("ext: bad volume name");
  }
  let lm: Str = sb.last_mounted;
  if lm.len() > EXT_LAST_MOUNTED_LEN {
    return _err_unit("ext: bad last mounted path");
  }
  if _has_nul(lm) {
    return _err_unit("ext: bad last mounted path");
  }
  if !_u32_ok(inodes_count) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.blocks_count_lo) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.r_blocks_count_lo) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.free_blocks_count_lo) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.free_inodes_count) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.first_data_block) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(logb) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.log_cluster_size) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(bpg) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.clusters_per_group) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(ipg) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.mtime) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.wtime) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.lastcheck) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.checkinterval) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.creator_os) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(rev) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.first_ino) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.feature_compat) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.feature_incompat) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.feature_ro_compat) {
    return _err_unit("ext: field out of range");
  }
  if !_u32_ok(sb.algo_bitmap) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.mnt_count) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.max_mnt_count) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.state) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.errors) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.minor_rev_level) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.def_resuid) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.def_resgid) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(isize) {
    return _err_unit("ext: field out of range");
  }
  if !_u16_ok(sb.block_group_nr) {
    return _err_unit("ext: field out of range");
  }
  if ext {
    if !_u32_ok(bchi) {
      return _err_unit("ext: field out of range");
    }
    if !_u32_ok(rchi) {
      return _err_unit("ext: field out of range");
    }
    if !_u32_ok(fchi) {
      return _err_unit("ext: field out of range");
    }
    if !_u16_ok(minx) {
      return _err_unit("ext: field out of range");
    }
    if !_u16_ok(wantx) {
      return _err_unit("ext: field out of range");
    }
    if !_u32_ok(fl) {
      return _err_unit("ext: field out of range");
    }
    if !_u8_ok(ct) {
      return _err_unit("ext: field out of range");
    }
    if !_u16_ok(ds) {
      return _err_unit("ext: field out of range");
    }
  }
  return _ok_unit();
}

// Emit the canonical 1024-byte block for an already-validated superblock.
// `ubytes` must be the 16 bytes described by sb.uuid_hex.
fn _emit_sb(sb: &ExtSuperblock, ubytes: &Vec[UInt8]) -> Vec[UInt8] {
  var ext = false;
  if sb.rev_level >= 1 {
    ext = true;
  }
  var desc_size = 0;
  var blocks_count_hi = 0;
  var r_blocks_count_hi = 0;
  var free_blocks_count_hi = 0;
  var min_extra_isize = 0;
  var want_extra_isize = 0;
  var flags = 0;
  var checksum_type = 0;
  if ext {
    desc_size = sb.desc_size;
    blocks_count_hi = sb.blocks_count_hi;
    r_blocks_count_hi = sb.r_blocks_count_hi;
    free_blocks_count_hi = sb.free_blocks_count_hi;
    min_extra_isize = sb.min_extra_isize;
    want_extra_isize = sb.want_extra_isize;
    flags = sb.flags;
    checksum_type = sb.checksum_type;
  }
  var out = Vec[UInt8].new();
  _push_le32(&mut out, sb.inodes_count);
  _push_le32(&mut out, sb.blocks_count_lo);
  _push_le32(&mut out, sb.r_blocks_count_lo);
  _push_le32(&mut out, sb.free_blocks_count_lo);
  _push_le32(&mut out, sb.free_inodes_count);
  _push_le32(&mut out, sb.first_data_block);
  _push_le32(&mut out, sb.log_block_size);
  _push_le32(&mut out, sb.log_cluster_size);
  _push_le32(&mut out, sb.blocks_per_group);
  _push_le32(&mut out, sb.clusters_per_group);
  _push_le32(&mut out, sb.inodes_per_group);
  _push_le32(&mut out, sb.mtime);
  _push_le32(&mut out, sb.wtime);
  _push_le16(&mut out, sb.mnt_count);
  _push_le16(&mut out, sb.max_mnt_count);
  _push_le16(&mut out, EXT_MAGIC);
  _push_le16(&mut out, sb.state);
  _push_le16(&mut out, sb.errors);
  _push_le16(&mut out, sb.minor_rev_level);
  _push_le32(&mut out, sb.lastcheck);
  _push_le32(&mut out, sb.checkinterval);
  _push_le32(&mut out, sb.creator_os);
  _push_le32(&mut out, sb.rev_level);
  _push_le16(&mut out, sb.def_resuid);
  _push_le16(&mut out, sb.def_resgid);
  _push_le32(&mut out, sb.first_ino);
  _push_le16(&mut out, sb.inode_size);
  _push_le16(&mut out, sb.block_group_nr);
  _push_le32(&mut out, sb.feature_compat);
  _push_le32(&mut out, sb.feature_incompat);
  _push_le32(&mut out, sb.feature_ro_compat);
  var k = 0;
  while k < EXT_UUID_LEN {
    out.push(ubytes[k]);
    k = k + 1;
  }
  _push_name(&mut out, sb.volume_name, EXT_VOLUME_NAME_LEN);
  _push_name(&mut out, sb.last_mounted, EXT_LAST_MOUNTED_LEN);
  _push_le32(&mut out, sb.algo_bitmap);
  _push_zero(&mut out, 50);
  _push_le16(&mut out, desc_size);
  _push_zero(&mut out, 80);
  _push_le32(&mut out, blocks_count_hi);
  _push_le32(&mut out, r_blocks_count_hi);
  _push_le32(&mut out, free_blocks_count_hi);
  _push_le16(&mut out, min_extra_isize);
  _push_le16(&mut out, want_extra_isize);
  _push_le32(&mut out, flags);
  _push_zero(&mut out, 17);
  _push_le8(&mut out, checksum_type);
  _push_zero(&mut out, 650);
  return out;
}

/// Build the canonical 1024-byte ext2/3/4 superblock block.
///
/// Every core field is written verbatim, s_magic as 0xEF53; the ext4
/// extension fields are written exactly when s_rev_level >= 1 (sb.has_ext
/// is ignored) and the reserved regions are zero. s_uuid must decode to
/// 16 bytes of hex and the name fields must fit their 16/64-byte widths
/// with no embedded NUL; every scalar must fit its on-disk unsigned width.
///
/// Params: sb - the field source, read only.
/// Returns: Ok(bytes) with exactly 1024 bytes; write them at byte offset
/// 1024 (or use ext_superblock_build_image for a ready-made 2048-byte
/// prefix).
/// Error case: Err("ext: bad magic"); Err("ext: bad log block size");
/// Err("ext: bad inode size"); Err("ext: bad inode count");
/// Err("ext: bad block count"); Err("ext: bad blocks per group");
/// Err("ext: bad inodes per group"); Err("ext: bad uuid");
/// Err("ext: bad volume name"); Err("ext: bad last mounted path");
/// Err("ext: field out of range"). Check order is the catalog order.
/// Nothing is emitted on Err.
/// Complexity: O(1).
pub fn ext_superblock_build(sb: &ExtSuperblock) -> Result[Vec[UInt8], Str] {
  let vr = _validate_build(sb);
  if !vr.is_ok {
    let msg: Str = vr.error;
    return _err_bytes(msg);
  }
  let ur = _uuid_bytes(sb);
  var ubytes = Vec[UInt8].new();
  if ur.is_ok {
    let b: Vec[UInt8] = ur.value;
    ubytes = b;
  }
  return _ok_bytes(_emit_sb(sb, &ubytes));
}

/// Build a 2048-byte volume prefix with the canonical superblock at byte
/// offset 1024: 1024 zero bytes followed by ext_superblock_build's block.
///
/// Params: sb - the field source, read only.
/// Returns: Ok(bytes) with exactly 2048 bytes, directly accepted by
/// ext_superblock_parse.
/// Error case: exactly the ext_superblock_build errors.
/// Complexity: O(1).
pub fn ext_superblock_build_image(sb: &ExtSuperblock) -> Result[Vec[UInt8], Str] {
  let br = ext_superblock_build(sb);
  if !br.is_ok {
    let msg: Str = br.error;
    return _err_bytes(msg);
  }
  let block: Vec[UInt8] = br.value;
  var out = Vec[UInt8].new();
  _push_zero(&mut out, EXT_SUPERBLOCK_OFFSET);
  var i = 0;
  while i < block.len() {
    out.push(block[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}
