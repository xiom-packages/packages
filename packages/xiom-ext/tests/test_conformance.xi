// XIOM -- xiom.ext conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.ext superblock codec against the rules
// pinned in SPEC.md: the 1024-byte superblock at offset 1024, the documented
// core fields, the ext4 extension fields, feature masks/name table, the
// validation catalog and build/parse round trips.
//
// All fixtures are assembled byte by byte in this file (independent of
// src/ext.xi), so ext_superblock_parse is exercised against bytes the test
// controls rather than only against ext_superblock_build. Str comparisons go
// through xiom.string.compare's str_compare (BUG 17: `==` on Str values can
// lower to a pointer comparison); every Vec element read is widened with
// `& 0xFF` before entering Int arithmetic and bound to an explicitly typed
// local, and `&` arguments are always local bindings.

module ext_tests
use xiom.io; use xiom.test;
use xiom.ext;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/ext.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn zero_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    let v: Vec[UInt8] = r.value;
    return v;
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn slice_of(v: Vec[UInt8], start: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < count {
    out.push(v[start + i]);
    i = i + 1;
  }
  return out;
}

fn set_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_bytes(v: Vec[UInt8], pos: Int, b: Vec[UInt8]) -> Vec[UInt8] {
  var out = v;
  var i = 0;
  while i < b.len() {
    let bb: Int = (b[i] as Int) & 0xFF;
    out = set_byte(out, pos + i, bb);
    i = i + 1;
  }
  return out;
}

fn set_le16(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  let a = set_byte(v, pos, val % 256);
  return set_byte(a, pos + 1, (val / 256) % 256);
}

fn set_le32(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  let a = set_byte(v, pos, val % 256);
  let b = set_byte(a, pos + 1, (val / 256) % 256);
  let c = set_byte(b, pos + 2, (val / 65536) % 256);
  return set_byte(c, pos + 3, (val / 16777216) % 256);
}

// Write a whole `width`-byte name field: the bytes of `s`, then NULs. The
// remainder of the old field is cleared, so no stale byte leaks through.
fn set_field(v: Vec[UInt8], pos: Int, width: Int, s: Str) -> Vec[UInt8] {
  var out = v;
  var i = 0;
  while i < width {
    if i < s.len() {
      let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
      out = set_byte(out, pos + i, b);
    } else {
      out = set_byte(out, pos + i, 0);
    }
    i = i + 1;
  }
  return out;
}

fn tp2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

fn all_zero(v: Vec[UInt8], start: Int, count: Int) -> Bool {
  var i = 0;
  while i < count {
    let b: Int = (v[start + i] as Int) & 0xFF;
    if b != 0 { return false; }
    i = i + 1;
  }
  return true;
}

// Parse must fail with exactly `want`.
fn perr(d: Vec[UInt8], want: Str) -> Bool {
  let r = ext_superblock_parse(&d);
  if r.is_ok { return false; }
  let msg: Str = r.error;
  return streq(msg, want);
}

// Build must fail with exactly `want`.
fn berr(sb: ExtSuperblock, want: Str) -> Bool {
  let r = ext_superblock_build(&sb);
  if r.is_ok { return false; }
  let msg: Str = r.error;
  return streq(msg, want);
}

// The pinned hand-built ext2-style superblock (rev 0) in a 2048-byte
// buffer: byte offset 1024 + the on-disk field offset.
fn core_bytes() -> Vec[UInt8] {
  var v = zero_bytes(2048);
  v = set_le32(v, 1024, 1280);       // s_inodes_count
  v = set_le32(v, 1028, 32768);      // s_blocks_count_lo
  v = set_le32(v, 1032, 1638);       // s_r_blocks_count_lo
  v = set_le32(v, 1036, 30000);      // s_free_blocks_count_lo
  v = set_le32(v, 1040, 1000);       // s_free_inodes_count
  v = set_le32(v, 1044, 0);          // s_first_data_block
  v = set_le32(v, 1048, 1);          // s_log_block_size (2048 bytes)
  v = set_le32(v, 1052, 1);          // s_log_cluster_size
  v = set_le32(v, 1056, 8192);       // s_blocks_per_group
  v = set_le32(v, 1060, 8192);       // s_clusters_per_group
  v = set_le32(v, 1064, 512);        // s_inodes_per_group
  v = set_le32(v, 1068, 1700000000); // s_mtime
  v = set_le32(v, 1072, 1700000100); // s_wtime
  v = set_le16(v, 1076, 12);         // s_mnt_count
  v = set_le16(v, 1078, 30);         // s_max_mnt_count
  v = set_le16(v, 1080, 61267);      // s_magic 0xEF53
  v = set_le16(v, 1082, 1);          // s_state
  v = set_le16(v, 1084, 3);          // s_errors
  v = set_le16(v, 1086, 0);          // s_minor_rev_level
  v = set_le32(v, 1088, 1699000000); // s_lastcheck
  v = set_le32(v, 1092, 15552000);   // s_checkinterval
  v = set_le32(v, 1096, 0);          // s_creator_os
  v = set_le32(v, 1100, 0);          // s_rev_level
  v = set_le16(v, 1104, 1000);       // s_def_resuid
  v = set_le16(v, 1106, 1000);       // s_def_resgid
  v = set_le32(v, 1108, 11);         // s_first_ino
  v = set_le16(v, 1112, 128);        // s_inode_size
  v = set_le16(v, 1114, 0);          // s_block_group_nr
  v = set_le32(v, 1116, 60);         // s_feature_compat (4|8|16|32)
  v = set_le32(v, 1120, 66);         // s_feature_incompat (2|64)
  v = set_le32(v, 1124, 3);          // s_feature_ro_compat (1|2)
  v = set_bytes(v, 1128, hb("00112233445566778899aabbccddeeff"));
  v = set_bytes(v, 1144, bytes_of("testvol"));
  v = set_bytes(v, 1160, bytes_of("/mnt/test"));
  v = set_le32(v, 1224, 5);          // s_algo_bitmap
  return v;
}

// core_bytes plus rev_level 1 and the ext4 extension fields.
fn ext_bytes() -> Vec[UInt8] {
  var v = core_bytes();
  v = set_le32(v, 1100, 1);    // s_rev_level
  v = set_le16(v, 1278, 64);   // s_desc_size
  v = set_le32(v, 1360, 1);    // s_blocks_count_hi
  v = set_le32(v, 1364, 0);    // s_r_blocks_count_hi
  v = set_le32(v, 1368, 0);    // s_free_blocks_count_hi
  v = set_le16(v, 1372, 32);   // s_min_extra_isize
  v = set_le16(v, 1374, 32);   // s_want_extra_isize
  v = set_le32(v, 1376, 4);    // s_flags
  v = set_byte(v, 1397, 1);    // s_checksum_type
  return v;
}

// The same pinned values as core_bytes(), as a struct.
fn base_sb() -> ExtSuperblock {
  return ExtSuperblock{
    inodes_count: 1280;
    blocks_count_lo: 32768;
    r_blocks_count_lo: 1638;
    free_blocks_count_lo: 30000;
    free_inodes_count: 1000;
    first_data_block: 0;
    log_block_size: 1;
    log_cluster_size: 1;
    blocks_per_group: 8192;
    clusters_per_group: 8192;
    inodes_per_group: 512;
    mtime: 1700000000;
    wtime: 1700000100;
    mnt_count: 12;
    max_mnt_count: 30;
    magic: 61267;
    state: 1;
    errors: 3;
    minor_rev_level: 0;
    lastcheck: 1699000000;
    checkinterval: 15552000;
    creator_os: 0;
    rev_level: 0;
    def_resuid: 1000;
    def_resgid: 1000;
    first_ino: 11;
    inode_size: 128;
    block_group_nr: 0;
    feature_compat: 60;
    feature_incompat: 66;
    feature_ro_compat: 3;
    uuid_hex: "00112233445566778899aabbccddeeff";
    volume_name: "testvol";
    last_mounted: "/mnt/test";
    algo_bitmap: 5;
    blocks_count_hi: 0;
    r_blocks_count_hi: 0;
    free_blocks_count_hi: 0;
    min_extra_isize: 0;
    want_extra_isize: 0;
    flags: 0;
    checksum_type: 0;
    desc_size: 0;
    has_ext: false;
  };
}

// base_sb() with rev_level 1 and the ext4 fields of ext_bytes().
fn ext_sb() -> ExtSuperblock {
  var sb = base_sb();
  sb.rev_level = 1;
  sb.desc_size = 64;
  sb.blocks_count_hi = 1;
  sb.min_extra_isize = 32;
  sb.want_extra_isize = 32;
  sb.flags = 4;
  sb.checksum_type = 1;
  sb.has_ext = true;
  return sb;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = core_bytes();
  let r = ext_superblock_parse(&data);
  if !r.is_ok { return assert(false, "core fixture must parse"); }
  let sb: ExtSuperblock = r.value;
  var ok = ext_inodes_count(&sb) == 1280;
  if ext_blocks_count_lo(&sb) != 32768 { ok = false; }
  if ext_r_blocks_count_lo(&sb) != 1638 { ok = false; }
  if ext_free_blocks_count_lo(&sb) != 30000 { ok = false; }
  if ext_free_inodes_count(&sb) != 1000 { ok = false; }
  if ext_first_data_block(&sb) != 0 { ok = false; }
  if ext_log_block_size(&sb) != 1 { ok = false; }
  if ext_block_size(&sb) != 2048 { ok = false; }
  if ext_log_cluster_size(&sb) != 1 { ok = false; }
  if ext_blocks_per_group(&sb) != 8192 { ok = false; }
  if ext_clusters_per_group(&sb) != 8192 { ok = false; }
  if ext_inodes_per_group(&sb) != 512 { ok = false; }
  if ext_mtime(&sb) != 1700000000 { ok = false; }
  if ext_wtime(&sb) != 1700000100 { ok = false; }
  if ext_mnt_count(&sb) != 12 { ok = false; }
  if ext_max_mnt_count(&sb) != 30 { ok = false; }
  if ext_magic(&sb) != 61267 { ok = false; }
  if ext_state(&sb) != 1 { ok = false; }
  if ext_errors(&sb) != 3 { ok = false; }
  if ext_minor_rev_level(&sb) != 0 { ok = false; }
  if ext_lastcheck(&sb) != 1699000000 { ok = false; }
  if ext_checkinterval(&sb) != 15552000 { ok = false; }
  if ext_creator_os(&sb) != 0 { ok = false; }
  if ext_rev_level(&sb) != 0 { ok = false; }
  if ext_def_resuid(&sb) != 1000 { ok = false; }
  if ext_def_resgid(&sb) != 1000 { ok = false; }
  if ext_first_ino(&sb) != 11 { ok = false; }
  if ext_inode_size(&sb) != 128 { ok = false; }
  if ext_block_group_nr(&sb) != 0 { ok = false; }
  if ext_feature_compat(&sb) != 60 { ok = false; }
  if ext_feature_incompat(&sb) != 66 { ok = false; }
  if ext_feature_ro_compat(&sb) != 3 { ok = false; }
  if !streq(ext_uuid_hex(&sb), "00112233445566778899aabbccddeeff") { ok = false; }
  if !streq(ext_volume_name(&sb), "testvol") { ok = false; }
  if !streq(ext_last_mounted(&sb), "/mnt/test") { ok = false; }
  if ext_algo_bitmap(&sb) != 5 { ok = false; }
  if ext_has_ext_fields(&sb) { ok = false; }
  if ext_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_r_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_free_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_min_extra_isize(&sb) != 0 { ok = false; }
  if ext_want_extra_isize(&sb) != 0 { ok = false; }
  if ext_flags(&sb) != 0 { ok = false; }
  if ext_checksum_type(&sb) != 0 { ok = false; }
  if ext_desc_size(&sb) != 0 { ok = false; }
  return assert(ok, "hand-built core superblock: every pinned field and accessor");
}

fn t2() -> TestResult {
  let full = core_bytes();
  let short1 = prefix(full, 2047);
  var ok = perr(short1, "ext: truncated buffer");
  let tiny = prefix(full, 1024);
  if !perr(tiny, "ext: truncated buffer") { ok = false; }
  let empty = Vec[UInt8].new();
  if !perr(empty, "ext: truncated buffer") { ok = false; }
  // A superblock-shaped block at offset 0 is not a superblock: the parser
  // only reads at byte offset 1024.
  let zero = zero_bytes(2048);
  let at_zero = set_le16(zero, 56, 61267);
  if !perr(at_zero, "ext: bad magic") { ok = false; }
  let exact = ext_superblock_parse(&full);
  if !exact.is_ok { ok = false; }
  return assert(ok, "buffer >= 2048 required; the magic is read at offset 1024 only");
}

fn t3() -> TestResult {
  var d = core_bytes();
  let bad0 = set_le16(d, 1080, 0);
  var ok = perr(bad0, "ext: bad magic");
  let bad1 = set_le16(d, 1080, 61266);
  if !perr(bad1, "ext: bad magic") { ok = false; }
  let good = set_le16(d, 1080, 61267);
  if !ext_superblock_parse(&good).is_ok { ok = false; }
  d = set_le16(core_bytes(), 1080, 61267);
  if !ext_superblock_parse(&d).is_ok { ok = false; }
  return assert(ok, "s_magic must be exactly 0xEF53");
}

fn t4() -> TestResult {
  var ok = true;
  var log = 0;
  while log <= 6 {
    var d = core_bytes();
    d = set_le32(d, 1048, log);
    let r = ext_superblock_parse(&d);
    if !r.is_ok {
      ok = false;
    } else {
      let sb: ExtSuperblock = r.value;
      if ext_log_block_size(&sb) != log { ok = false; }
      if ext_block_size(&sb) != 1024 * tp2(log) { ok = false; }
    }
    log = log + 1;
  }
  let d7 = set_le32(core_bytes(), 1048, 7);
  if !perr(d7, "ext: bad log block size") { ok = false; }
  let d9 = set_le32(core_bytes(), 1048, 9);
  if !perr(d9, "ext: bad log block size") { ok = false; }
  return assert(ok, "log block size 0..6 maps to 1024..65536; 7 and 9 are rejected");
}

fn t5() -> TestResult {
  let d127 = set_le16(core_bytes(), 1112, 127);
  var ok = perr(d127, "ext: bad inode size");
  let d128 = set_le16(core_bytes(), 1112, 128);
  if !ext_superblock_parse(&d128).is_ok { ok = false; }
  let d256 = set_le16(core_bytes(), 1112, 256);
  if !ext_superblock_parse(&d256).is_ok { ok = false; }
  let d2048 = set_le16(core_bytes(), 1112, 2048);
  if !ext_superblock_parse(&d2048).is_ok { ok = false; }
  var dsmall = core_bytes();
  dsmall = set_le32(dsmall, 1048, 0);
  let db1024 = set_le16(dsmall, 1112, 1024);
  if !ext_superblock_parse(&db1024).is_ok { ok = false; }
  let db1025 = set_le16(dsmall, 1112, 1025);
  if !perr(db1025, "ext: bad inode size") { ok = false; }
  let db4096 = set_le16(dsmall, 1112, 4096);
  if !perr(db4096, "ext: bad inode size") { ok = false; }
  return assert(ok, "inode size >= 128 and <= block size is enforced");
}

fn t6() -> TestResult {
  var ok = perr(set_le32(core_bytes(), 1024, 0), "ext: bad inode count");
  if !perr(set_le32(core_bytes(), 1028, 0), "ext: bad block count") { ok = false; }
  if !perr(set_le32(core_bytes(), 1056, 0), "ext: bad blocks per group") { ok = false; }
  if !perr(set_le32(core_bytes(), 1064, 0), "ext: bad inodes per group") { ok = false; }
  // A zero low count with a nonzero high count is a valid 64-bit count.
  var d = ext_bytes();
  d = set_le32(d, 1028, 0);
  let r = ext_superblock_parse(&d);
  if !r.is_ok {
    ok = false;
  } else {
    let sb: ExtSuperblock = r.value;
    if ext_blocks_count(&sb) != 4294967296 { ok = false; }
  }
  return assert(ok, "documented counts must be non-zero; a 64-bit low zero is fine");
}

fn t7() -> TestResult {
  let data = core_bytes();
  let r = ext_superblock_parse(&data);
  if !r.is_ok { return assert(false, "core fixture must parse"); }
  let sb: ExtSuperblock = r.value;
  var ok = ext_has_feature_compat(&sb, 4);
  if !ext_has_feature_compat(&sb, 32) { ok = false; }
  if ext_has_feature_compat(&sb, 1) { ok = false; }
  if !ext_has_feature_compat(&sb, 36) { ok = false; }
  if ext_has_feature_compat(&sb, 5) { ok = false; }
  if !ext_has_feature_compat(&sb, 0) { ok = false; }
  if !ext_has_feature_incompat(&sb, 2) { ok = false; }
  if !ext_has_feature_incompat(&sb, 64) { ok = false; }
  if ext_has_feature_incompat(&sb, 128) { ok = false; }
  if !ext_has_feature_ro_compat(&sb, 1) { ok = false; }
  if !ext_has_feature_ro_compat(&sb, 2) { ok = false; }
  if ext_has_feature_ro_compat(&sb, 8) { ok = false; }
  if !ext_has_feature_ro_compat(&sb, 3) { ok = false; }
  return assert(ok, "feature predicates test every bit of the mask");
}

fn t8() -> TestResult {
  let data = ext_bytes();
  let r = ext_superblock_parse(&data);
  if !r.is_ok { return assert(false, "ext4 fixture must parse"); }
  let sb: ExtSuperblock = r.value;
  var ok = ext_rev_level(&sb) == 1;
  if !ext_has_ext_fields(&sb) { ok = false; }
  if ext_blocks_count_lo(&sb) != 32768 { ok = false; }
  if ext_blocks_count_hi(&sb) != 1 { ok = false; }
  if ext_blocks_count(&sb) != 4295000064 { ok = false; }
  if ext_r_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_free_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_min_extra_isize(&sb) != 32 { ok = false; }
  if ext_want_extra_isize(&sb) != 32 { ok = false; }
  if ext_flags(&sb) != 4 { ok = false; }
  if ext_checksum_type(&sb) != 1 { ok = false; }
  if ext_desc_size(&sb) != 64 { ok = false; }
  if !streq(ext_uuid_hex(&sb), "00112233445566778899aabbccddeeff") { ok = false; }
  return assert(ok, "rev >= 1 reads the documented ext4 extension fields");
}

fn t9() -> TestResult {
  // Same bytes as the ext4 fixture, but rev 0: the extension region is
  // ignored and reported as zero.
  var data = ext_bytes();
  data = set_le32(data, 1100, 0);
  let r = ext_superblock_parse(&data);
  if !r.is_ok { return assert(false, "rev-0 fixture must parse"); }
  let sb: ExtSuperblock = r.value;
  var ok = !ext_has_ext_fields(&sb);
  if ext_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_r_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_free_blocks_count_hi(&sb) != 0 { ok = false; }
  if ext_min_extra_isize(&sb) != 0 { ok = false; }
  if ext_want_extra_isize(&sb) != 0 { ok = false; }
  if ext_flags(&sb) != 0 { ok = false; }
  if ext_checksum_type(&sb) != 0 { ok = false; }
  if ext_desc_size(&sb) != 0 { ok = false; }
  if ext_blocks_count(&sb) != 32768 { ok = false; }
  return assert(ok, "s_rev_level 0 ignores the extension region");
}

fn t10() -> TestResult {
  var ok = streq(ext_feature_compat_name(1), "COMPAT_DIR_PREALLOC");
  if !streq(ext_feature_compat_name(4), "COMPAT_HAS_JOURNAL") { ok = false; }
  if !streq(ext_feature_compat_name(32), "COMPAT_DIR_INDEX") { ok = false; }
  if !streq(ext_feature_compat_name(4096), "COMPAT_ORPHAN_FILE") { ok = false; }
  if !streq(ext_feature_compat_name(0), "") { ok = false; }
  if !streq(ext_feature_compat_name(5), "") { ok = false; }
  if !streq(ext_feature_compat_name(256), "") { ok = false; }
  if !streq(ext_feature_incompat_name(1), "INCOMPAT_COMPRESSION") { ok = false; }
  if !streq(ext_feature_incompat_name(2), "INCOMPAT_FILETYPE") { ok = false; }
  if !streq(ext_feature_incompat_name(128), "INCOMPAT_64BIT") { ok = false; }
  if !streq(ext_feature_incompat_name(512), "INCOMPAT_FLEX_BG") { ok = false; }
  if !streq(ext_feature_incompat_name(8192), "INCOMPAT_CSUM_SEED") { ok = false; }
  if !streq(ext_feature_incompat_name(131072), "INCOMPAT_CASEFOLD") { ok = false; }
  if !streq(ext_feature_incompat_name(2 + 64), "") { ok = false; }
  if !streq(ext_feature_ro_compat_name(1), "RO_COMPAT_SPARSE_SUPER") { ok = false; }
  if !streq(ext_feature_ro_compat_name(1024), "RO_COMPAT_METADATA_CSUM") { ok = false; }
  if !streq(ext_feature_ro_compat_name(32768), "RO_COMPAT_VERITY") { ok = false; }
  if !streq(ext_feature_ro_compat_name(65536), "RO_COMPAT_ORPHAN_PRESENT") { ok = false; }
  if !streq(ext_feature_ro_compat_name(16384), "") { ok = false; }
  return assert(ok, "feature name table maps documented single bits and nothing else");
}

fn t11() -> TestResult {
  let br = ext_superblock_build(&base_sb());
  if !br.is_ok { return assert(false, "build must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = built.len() == 1024;
  let fixture = core_bytes();
  let block = slice_of(fixture, 1024, 1024);
  if !bytes_equal(built, block) { ok = false; }
  let m0: Int = (built[56] as Int) & 0xFF;
  let m1: Int = (built[57] as Int) & 0xFF;
  if m0 != 83 { ok = false; }
  if m1 != 239 { ok = false; }
  return assert(ok, "builder emits the canonical 1024-byte block, byte-identical to the fixture");
}

fn t12() -> TestResult {
  let ir = ext_superblock_build_image(&base_sb());
  if !ir.is_ok { return assert(false, "build_image must succeed"); }
  let image: Vec[UInt8] = ir.value;
  var ok = image.len() == 2048;
  if !all_zero(image, 0, 1024) { ok = false; }
  let br = ext_superblock_build(&base_sb());
  if !br.is_ok { ok = false; } else {
    let built: Vec[UInt8] = br.value;
    let block = slice_of(image, 1024, 1024);
    if !bytes_equal(block, built) { ok = false; }
  }
  let r = ext_superblock_parse(&image);
  if !r.is_ok { ok = false; } else {
    let sb: ExtSuperblock = r.value;
    if ext_magic(&sb) != 61267 { ok = false; }
    if !streq(ext_volume_name(&sb), "testvol") { ok = false; }
    if ext_inodes_count(&sb) != 1280 { ok = false; }
  }
  return assert(ok, "build_image puts the block at byte offset 1024 and parses back");
}

fn t13() -> TestResult {
  let br = ext_superblock_build(&ext_sb());
  if !br.is_ok { return assert(false, "ext4 build must succeed"); }
  let built: Vec[UInt8] = br.value;
  let fixture = ext_bytes();
  let block = slice_of(fixture, 1024, 1024);
  var ok = bytes_equal(built, block);
  let ir = ext_superblock_build_image(&ext_sb());
  if !ir.is_ok {
    ok = false;
  } else {
    let image: Vec[UInt8] = ir.value;
    let r = ext_superblock_parse(&image);
    if !r.is_ok {
      ok = false;
    } else {
      let sb: ExtSuperblock = r.value;
      if ext_rev_level(&sb) != 1 { ok = false; }
      if !ext_has_ext_fields(&sb) { ok = false; }
      if ext_blocks_count_hi(&sb) != 1 { ok = false; }
      if ext_blocks_count(&sb) != 4295000064 { ok = false; }
      if ext_desc_size(&sb) != 64 { ok = false; }
      if ext_min_extra_isize(&sb) != 32 { ok = false; }
      if ext_want_extra_isize(&sb) != 32 { ok = false; }
      if ext_flags(&sb) != 4 { ok = false; }
      if ext_checksum_type(&sb) != 1 { ok = false; }
      if !streq(ext_uuid_hex(&sb), "00112233445566778899aabbccddeeff") { ok = false; }
      if !streq(ext_last_mounted(&sb), "/mnt/test") { ok = false; }
    }
  }
  return assert(ok, "ext4 build round-trips through parse and matches the fixture");
}

fn t14() -> TestResult {
  var ok = berr(set_magic_zero(base_sb()), "ext: bad magic");
  if !berr(set_log7(base_sb()), "ext: bad log block size") { ok = false; }
  if !berr(set_inode_size(base_sb(), 64), "ext: bad inode size") { ok = false; }
  if !berr(set_inode_size(base_sb(), 4096), "ext: bad inode size") { ok = false; }
  if !berr(set_inodes_count(base_sb(), 0), "ext: bad inode count") { ok = false; }
  if !berr(set_blocks_count(base_sb(), 0), "ext: bad block count") { ok = false; }
  if !berr(set_blocks_per_group(base_sb(), 0), "ext: bad blocks per group") { ok = false; }
  if !berr(set_inodes_per_group(base_sb(), 0), "ext: bad inodes per group") { ok = false; }
  if !berr(set_uuid(base_sb(), "xyz"), "ext: bad uuid") { ok = false; }
  if !berr(set_uuid(base_sb(), "0011"), "ext: bad uuid") { ok = false; }
  if !berr(set_uuid(base_sb(), "00112233445566778899aabbccddeegg"), "ext: bad uuid") { ok = false; }
  if !berr(set_volume(base_sb(), "12345678901234567"), "ext: bad volume name") { ok = false; }
  if !berr(set_mounted(base_sb(), "12345678901234567890123456789012345678901234567890123456789012345"), "ext: bad last mounted path") { ok = false; }
  if !berr(set_mnt_count(base_sb(), 65536), "ext: field out of range") { ok = false; }
  if !berr(set_compat(base_sb(), -1), "ext: field out of range") { ok = false; }
  if !berr(set_inodes_count(base_sb(), 4294967296), "ext: field out of range") { ok = false; }
  if !berr(set_desc_size(ext_sb(), 70000), "ext: field out of range") { ok = false; }
  if !berr(set_checksum_type(ext_sb(), 256), "ext: field out of range") { ok = false; }
  return assert(ok, "builder rejects the documented invalid inputs with exact messages");
}

fn t15() -> TestResult {
  // A name field with no NUL keeps all 16 bytes.
  var full16 = core_bytes();
  full16 = set_field(full16, 1144, 16, "ABCDEFGHIJKLMNOP");
  var ok = perr_ok_name(full16, "ABCDEFGHIJKLMNOP");
  // Spaces around a NUL-padded name are trimmed.
  var padded = core_bytes();
  padded = set_field(padded, 1144, 16, "  pad  ");
  if !perr_ok_name(padded, "pad") { ok = false; }
  // last_mounted uses the same rule with a 64-byte field.
  var mounted = core_bytes();
  mounted = set_field(mounted, 1160, 64, "/mnt/x ");
  if !perr_ok_mounted(mounted, "/mnt/x") { ok = false; }
  // An all-NUL field reads as "".
  var empty = core_bytes();
  empty = set_field(empty, 1160, 64, "");
  if !perr_ok_mounted(empty, "") { ok = false; }
  return assert(ok, "name fields stop at the first NUL and are trimmed");
}

fn t16() -> TestResult {
  var d = core_bytes();
  d = set_bytes(d, 1128, hb("0102030405060708090a0b0c0d0e0f10"));
  let r1 = ext_superblock_parse(&d);
  var ok = r1.is_ok;
  if r1.is_ok {
    let sb1: ExtSuperblock = r1.value;
    if !streq(ext_uuid_hex(&sb1), "0102030405060708090a0b0c0d0e0f10") { ok = false; }
  }
  var e = core_bytes();
  e = set_bytes(e, 1128, hb("ffffffffffffffffffffffffffffffff"));
  let r2 = ext_superblock_parse(&e);
  if r2.is_ok {
    let sb2: ExtSuperblock = r2.value;
    if !streq(ext_uuid_hex(&sb2), "ffffffffffffffffffffffffffffffff") { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "s_uuid is 32 lowercase hex characters");
}

fn t17() -> TestResult {
  let data = ext_bytes();
  let r1 = ext_superblock_parse(&data);
  if !r1.is_ok { return assert(false, "fixture must parse"); }
  let sb1: ExtSuperblock = r1.value;
  let b1r = ext_superblock_build(&sb1);
  if !b1r.is_ok { return assert(false, "rebuild must succeed"); }
  let b1: Vec[UInt8] = b1r.value;
  let fixture = ext_bytes();
  let block = slice_of(fixture, 1024, 1024);
  var ok = bytes_equal(b1, block);
  let r2 = ext_superblock_parse(&data);
  if !r2.is_ok { ok = false; } else {
    let sb2: ExtSuperblock = r2.value;
    let b2r = ext_superblock_build(&sb2);
    if !b2r.is_ok { ok = false; } else {
      let b2: Vec[UInt8] = b2r.value;
      if !bytes_equal(b1, b2) { ok = false; }
    }
  }
  // A trimmed name survives parse -> build -> parse.
  var padded = core_bytes();
  padded = set_field(padded, 1144, 16, "  pad  ");
  let p1 = ext_superblock_parse(&padded);
  if !p1.is_ok { ok = false; } else {
    let s1: ExtSuperblock = p1.value;
    let pb = ext_superblock_build_image(&s1);
    if !pb.is_ok { ok = false; } else {
      let pbytes: Vec[UInt8] = pb.value;
      let p2 = ext_superblock_parse(&pbytes);
      if !p2.is_ok { ok = false; } else {
        let s2: ExtSuperblock = p2.value;
        if !streq(ext_volume_name(&s2), "pad") { ok = false; }
      }
    }
  }
  return assert(ok, "parse -> build reproduces the block and is stable on re-parse");
}

fn t18() -> TestResult {
  var sb = base_sb();
  var ok = ext_block_size(&sb) == 2048;
  sb.log_block_size = 0;
  if ext_block_size(&sb) != 1024 { ok = false; }
  sb.log_block_size = 6;
  if ext_block_size(&sb) != 65536 { ok = false; }
  sb.log_block_size = 7;
  if ext_block_size(&sb) != -1 { ok = false; }
  sb = base_sb();
  if ext_blocks_count(&sb) != 32768 { ok = false; }
  if ext_r_blocks_count(&sb) != 1638 { ok = false; }
  if ext_free_blocks_count(&sb) != 30000 { ok = false; }
  return assert(ok, "derived accessors: block size table and 64-bit count folds");
}

fn t19() -> TestResult {
  var d = ext_bytes();
  d = set_le32(d, 1364, 2);
  d = set_le32(d, 1368, 3);
  let r = ext_superblock_parse(&d);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let sb: ExtSuperblock = r.value;
  var ok = ext_r_blocks_count(&sb) == 1638 + 2 * 4294967296;
  if ext_free_blocks_count(&sb) != 30000 + 3 * 4294967296 { ok = false; }
  if ext_r_blocks_count_hi(&sb) != 2 { ok = false; }
  if ext_free_blocks_count_hi(&sb) != 3 { ok = false; }
  return assert(ok, "high count halves fold into the combined accessors");
}

fn t20() -> TestResult {
  // The builder writes extension fields exactly when rev_level >= 1:
  // garbage in a rev-0 struct is ignored ...
  var sb = base_sb();
  sb.blocks_count_hi = 12345;
  sb.desc_size = 999;
  sb.checksum_type = 7;
  let br = ext_superblock_build(&sb);
  if !br.is_ok { return assert(false, "rev-0 build must succeed"); }
  let b0: Vec[UInt8] = br.value;
  var ok = bytes_equal(b0, slice_of(core_bytes(), 1024, 1024));
  // ... and rev >= 1 writes them even when has_ext was not set by parse.
  var se = ext_sb();
  se.has_ext = false;
  let er = ext_superblock_build_image(&se);
  if !er.is_ok {
    ok = false;
  } else {
    let eb: Vec[UInt8] = er.value;
    let pr = ext_superblock_parse(&eb);
    if !pr.is_ok { ok = false; } else {
      let ps: ExtSuperblock = pr.value;
      if ext_blocks_count_hi(&ps) != 1 { ok = false; }
      if ext_desc_size(&ps) != 64 { ok = false; }
    }
  }
  return assert(ok, "extension fields are written exactly when rev_level >= 1");
}

// --------------------------------------------------
//  Typed setters for builder inputs (no direct field writes in tests)
// --------------------------------------------------

fn set_magic_zero(sb: ExtSuperblock) -> ExtSuperblock {
  var out = sb;
  out.magic = 0;
  return out;
}

fn set_log7(sb: ExtSuperblock) -> ExtSuperblock {
  var out = sb;
  out.log_block_size = 7;
  return out;
}

fn set_inode_size(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.inode_size = v;
  return out;
}

fn set_inodes_count(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.inodes_count = v;
  return out;
}

fn set_blocks_count(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.blocks_count_lo = v;
  return out;
}

fn set_blocks_per_group(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.blocks_per_group = v;
  return out;
}

fn set_inodes_per_group(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.inodes_per_group = v;
  return out;
}

fn set_uuid(sb: ExtSuperblock, v: Str) -> ExtSuperblock {
  var out = sb;
  out.uuid_hex = v;
  return out;
}

fn set_volume(sb: ExtSuperblock, v: Str) -> ExtSuperblock {
  var out = sb;
  out.volume_name = v;
  return out;
}

fn set_mounted(sb: ExtSuperblock, v: Str) -> ExtSuperblock {
  var out = sb;
  out.last_mounted = v;
  return out;
}

fn set_mnt_count(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.mnt_count = v;
  return out;
}

fn set_compat(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.feature_compat = v;
  return out;
}

fn set_desc_size(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.desc_size = v;
  return out;
}

fn set_checksum_type(sb: ExtSuperblock, v: Int) -> ExtSuperblock {
  var out = sb;
  out.checksum_type = v;
  return out;
}

// --------------------------------------------------
//  Small parse helpers used by t15
// --------------------------------------------------

fn perr_ok_name(d: Vec[UInt8], want: Str) -> Bool {
  let r = ext_superblock_parse(&d);
  if !r.is_ok { return false; }
  let sb: ExtSuperblock = r.value;
  return streq(ext_volume_name(&sb), want);
}

fn perr_ok_mounted(d: Vec[UInt8], want: Str) -> Bool {
  let r = ext_superblock_parse(&d);
  if !r.is_ok { return false; }
  let sb: ExtSuperblock = r.value;
  return streq(ext_last_mounted(&sb), want);
}

fn main() -> Int {
  io.println("=== xiom.ext conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.ext: all tests passed");
  } else {
    io.println("xiom.ext: tests failed");
  }
  return failed;
}
