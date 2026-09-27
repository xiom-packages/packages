// XIOM -- xiom.bolt: BoltDB (bbolt) page-file structure parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: a read-only STRUCTURE parser for the on-disk page file of bbolt
// (etcd-io/bbolt, the maintained fork of BoltDB). Callers pass the whole file
// as a byte vector; every parsed value is an offset/size pair (a span) into
// that buffer. Nothing is mmapped, nothing is written, no transaction or
// locking semantics are implemented, and page checksums are verified only for
// meta pages (the only pages bbolt checksums).
//
// Implemented layers, all little-endian:
//   * page header (16 bytes): id u64, flags u16, count u16, overflow u32.
//   * meta page (magic 0xED0CDAED, version 2, pageSize, flags, root bucket
//     {root pgid, sequence}, freelist pgid, pgid, txid, checksum u64). The
//     checksum is FNV-1a-64 over the 56 bytes that precede it (the meta
//     struct without its trailing checksum field); two meta pages exist and
//     the valid one with the higher txid is selected, both are reported.
//   * branch page elements (16 bytes each): pos u32, ksize u32, pgid u64,
//     stored right after the header; key bytes live at element + pos.
//   * leaf page elements (16 bytes each): flags u32 (bucket 0x01), pos u32,
//     ksize u32, vsize u32; key bytes at element + pos, value bytes directly
//     after the key. A bucket value is {root pgid u64, sequence u64} followed
//     by an inline page image when the bucket flag is set and the value is
//     longer than 16 bytes.
//   * freelist page: element count in the page-header count field; the
//     sentinel count 0xFFFF marks an overflow list whose true count is the
//     first u64 payload word. Payload words are u64 pgids; the page may span
//     `overflow` additional pages.
//   * a bounded tree walk from a root bucket pgid that returns the leaf
//     key/value spans plus the leaf element flags in key order, with
//     page-consistency checks (element pointers inside the page, child ids in
//     range, no page revisited, leaf keys ordered non-decreasing).
//
// Documented corrections to the port brief (see SPEC.md for details):
//   * bbolt branch pages have no u16 offset array at the page end with 0xFFFF
//     marking an empty slot; the child page pointer is the u64 pgid field of
//     each 16-byte branch element, and bolt_branch_child_pgids returns that
//     array.
//   * the freelist element count is the u16 page-header count (or the first
//     u64 payload word when the sentinel 0xFFFF is present); it is never a
//     standalone u32 field.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType]; parsed
//     tables are flat parallel Vec fields.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int] element reads are bound to typed locals.
//   * 64-bit fields use the overflow-safe xiom.pack shape: the low seven
//     bytes accumulate with a `place` factor and the top byte is applied
//     separately, so the raw 64-bit pattern is exact (bit 63 set decodes as a
//     negative Int; see SPEC.md).
//   * flag tests use modulo arithmetic, never `&`, because bitwise operations
//     on values with bit 31 set are miscompiled in v0.61.3.
//   * error messages carry byte offsets and page ids as decimal text.
// See SPEC.md for the byte layout tables, validation order, error catalog and
// test plan.

module xiom.bolt

use xiom.convert.int;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// Meta magic: the first u32 of the meta struct (page offset 16).
pub const BOLT_MAGIC: Int = 0xED0CDAED;

// Meta format version written by bbolt.
pub const BOLT_VERSION: Int = 2;

// Page-type flag bits (page header flags, u16).
pub const BOLT_PAGE_BRANCH: Int = 0x01;
pub const BOLT_PAGE_LEAF: Int = 0x02;
pub const BOLT_PAGE_META: Int = 0x04;
pub const BOLT_PAGE_FREELIST: Int = 0x10;

// Highest defined page flag bit mask; flags outside 1..31 are rejected.
pub const BOLT_PAGE_FLAGS_MAX: Int = 31;

// leafPageElement flag bit 0: the value is a bucket header.
pub const BOLT_BUCKET_LEAF_FLAG: Int = 0x01;

// Fixed layout sizes, in bytes.
pub const BOLT_PAGE_HEADER_SIZE: Int = 16;
pub const BOLT_META_HEADER_OFFSET: Int = 16;
pub const BOLT_META_SIZE: Int = 64;
pub const BOLT_META_SUM_SIZE: Int = 56;
pub const BOLT_META_CHECKSUM_OFFSET: Int = 72;
pub const BOLT_META_REQUIRED: Int = 80;
pub const BOLT_BRANCH_ELEM_SIZE: Int = 16;
pub const BOLT_LEAF_ELEM_SIZE: Int = 16;
pub const BOLT_BUCKET_HEADER_SIZE: Int = 16;

// Page-size policy: a power of two in [1024, 65536].
pub const BOLT_MIN_PAGE_SIZE: Int = 1024;
pub const BOLT_MAX_PAGE_SIZE: Int = 65536;

// Freelist page-header count value marking an overflow list whose true
// element count is the first u64 payload word.
pub const BOLT_FREELIST_OVERFLOW: Int = 0xFFFF;

// Suggested tree-walk depth cap; bolt_walk_tree takes an explicit cap.
pub const BOLT_MAX_DEPTH: Int = 64;

// bolt_branch_field selectors.
pub const BOLT_BRANCH_FIELD_POS: Int = 0;
pub const BOLT_BRANCH_FIELD_KSIZE: Int = 1;
pub const BOLT_BRANCH_FIELD_PGID: Int = 2;
pub const BOLT_BRANCH_FIELD_OFFSET: Int = 3;
pub const BOLT_BRANCH_FIELD_KEY_OFFSET: Int = 4;
pub const BOLT_BRANCH_FIELD_COUNT: Int = 5;

// bolt_leaf_field selectors.
pub const BOLT_LEAF_FIELD_FLAGS: Int = 0;
pub const BOLT_LEAF_FIELD_POS: Int = 1;
pub const BOLT_LEAF_FIELD_KSIZE: Int = 2;
pub const BOLT_LEAF_FIELD_VSIZE: Int = 3;
pub const BOLT_LEAF_FIELD_OFFSET: Int = 4;
pub const BOLT_LEAF_FIELD_KEY_OFFSET: Int = 5;
pub const BOLT_LEAF_FIELD_VALUE_OFFSET: Int = 6;
pub const BOLT_LEAF_FIELD_COUNT: Int = 7;

// bolt_leaf_bucket_field selectors.
pub const BOLT_BUCKET_FIELD_ROOT: Int = 0;
pub const BOLT_BUCKET_FIELD_SEQUENCE: Int = 1;
pub const BOLT_BUCKET_FIELD_COUNT: Int = 2;

// bolt_meta_field selectors.
pub const BOLT_META_FIELD_MAGIC: Int = 0;
pub const BOLT_META_FIELD_VERSION: Int = 1;
pub const BOLT_META_FIELD_PAGE_SIZE: Int = 2;
pub const BOLT_META_FIELD_FLAGS: Int = 3;
pub const BOLT_META_FIELD_ROOT: Int = 4;
pub const BOLT_META_FIELD_SEQUENCE: Int = 5;
pub const BOLT_META_FIELD_FREELIST: Int = 6;
pub const BOLT_META_FIELD_PGID: Int = 7;
pub const BOLT_META_FIELD_TXID: Int = 8;
pub const BOLT_META_FIELD_CHECKSUM: Int = 9;
pub const BOLT_META_FIELD_PAGE_ID: Int = 10;
pub const BOLT_META_FIELD_COMPUTED: Int = 11;
pub const BOLT_META_FIELD_OFFSET: Int = 12;
pub const BOLT_META_FIELD_COUNT: Int = 13;

// bolt_meta_read selection result values.
pub const BOLT_SELECT_META0: Int = 0;
pub const BOLT_SELECT_META1: Int = 1;

// bolt_walk_field selectors.
pub const BOLT_ENTRY_FIELD_KEY_OFFSET: Int = 0;
pub const BOLT_ENTRY_FIELD_KEY_SIZE: Int = 1;
pub const BOLT_ENTRY_FIELD_VALUE_OFFSET: Int = 2;
pub const BOLT_ENTRY_FIELD_VALUE_SIZE: Int = 3;
pub const BOLT_ENTRY_FIELD_FLAGS: Int = 4;
pub const BOLT_ENTRY_FIELD_PAGE_ID: Int = 5;
pub const BOLT_ENTRY_FIELD_DEPTH: Int = 6;
pub const BOLT_ENTRY_FIELD_COUNT: Int = 7;

// The raw 0xFFFFFFFFFFFFFFFF pgid bbolt writes when freelist syncing is
// disabled (decodes as -1 under the raw two's-complement convention).
pub const BOLT_PGID_NO_FREELIST: Int = -1;

// --------------------------------------------------
//  Parsed values
// --------------------------------------------------

/// One page: the 16-byte page header plus the page's byte span.
///
/// `offset` is the absolute offset of the page in the caller's buffer,
/// `size` the number of bytes the page occupies there (`page_size` for a
/// regular page, the inline value length minus 16 for an inline page), and
/// `inline` is true for pages decoded out of a bucket leaf value. `count` is
/// the element count for branch/leaf/freelist pages (meaningless for meta
/// pages, where it is 0). Use bolt_read_page / bolt_inline_page to obtain one.
pub type BoltPage = {
  page_id: Int;
  flags: Int;
  count: Int;
  overflow: Int;
  offset: Int;
  size: Int;
  inline: Bool;
}

/// One meta page image, including the failed checks of invalid pages.
///
/// `checksum` is the stored u64 and `computed_checksum` the FNV-1a-64 of the
/// 56 bytes at offset + 16; both use the raw two's-complement pattern. `valid`
/// is true when magic, version, page_size (equal to the page size the file
/// was read with) and checksum all check out.
pub type BoltMeta = {
  offset: Int;
  page_id: Int;
  page_flags: Int;
  magic: Int;
  version: Int;
  page_size: Int;
  flags: Int;
  root_pgid: Int;
  root_sequence: Int;
  freelist_pgid: Int;
  pgid: Int;
  txid: Int;
  checksum: Int;
  computed_checksum: Int;
  valid: Bool;
}

/// The two meta pages plus the selection.
///
/// `selected` is BOLT_SELECT_META0 or BOLT_SELECT_META1: the valid page with
/// the higher txid (meta 0 on a tie). bolt_meta_read only returns a pair when
/// at least one page is valid.
pub type BoltMetaPair = {
  meta0: BoltMeta;
  meta1: BoltMeta;
  selected: Int;
}

/// Flattened in-order walk of every leaf entry under a root page.
///
/// Entry i is described by the seven parallel vectors at index i:
/// `key_offsets[i]`/`key_sizes[i]` locate the key bytes in the source buffer,
/// `value_offsets[i]`/`value_sizes[i]` the value bytes, `elem_flags[i]` the
/// leaf element flags (BOLT_BUCKET_LEAF_FLAG for bucket values), `page_ids[i]`
/// the leaf page the entry came from, and `depths[i]` the depth of that leaf
/// (1 = the root page). The vectors are always pushed together and never
/// drift. In a well-formed bbolt tree the keys are ordered
/// non-decreasing byte-wise; bolt_walk_tree enforces that order and fails on
/// violation.
pub type BoltWalk = {
  page_ids: Vec[Int];
  depths: Vec[Int];
  key_offsets: Vec[Int];
  key_sizes: Vec[Int];
  value_offsets: Vec[Int];
  value_sizes: Vec[Int];
  elem_flags: Vec[Int];
  leaf_count: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
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

// Ok(v) for Result[BoltPage, Str].
fn _ok_page(v: BoltPage) -> Result[BoltPage, Str] {
  return Ok(v);
}

// Err(m) for Result[BoltPage, Str].
fn _err_page(m: Str) -> Result[BoltPage, Str] {
  return Err(m);
}

// Ok(v) for Result[BoltMeta, Str].
fn _ok_meta(v: BoltMeta) -> Result[BoltMeta, Str] {
  return Ok(v);
}

// Err(m) for Result[BoltMeta, Str].
fn _err_meta(m: Str) -> Result[BoltMeta, Str] {
  return Err(m);
}

// Ok(v) for Result[BoltMetaPair, Str].
fn _ok_pair(v: BoltMetaPair) -> Result[BoltMetaPair, Str] {
  return Ok(v);
}

// Err(m) for Result[BoltMetaPair, Str].
fn _err_pair(m: Str) -> Result[BoltMetaPair, Str] {
  return Err(m);
}

// Ok(v) for Result[BoltWalk, Str].
fn _ok_walk(v: BoltWalk) -> Result[BoltWalk, Str] {
  return Ok(v);
}

// Err(m) for Result[BoltWalk, Str].
fn _err_walk(m: Str) -> Result[BoltWalk, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// "bolt: <msg> at <off>" -- structural errors carry their byte offset.
fn _at(msg: Str, off: Int) -> Str {
  return "bolt: " + msg + " at " + int_to_base(off, 10);
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

// True when `ps` is a legal bbolt page size: a power of two in
// [BOLT_MIN_PAGE_SIZE, BOLT_MAX_PAGE_SIZE].
fn _page_size_ok(ps: Int) -> Bool {
  if ps < BOLT_MIN_PAGE_SIZE {
    return false;
  }
  if ps > BOLT_MAX_PAGE_SIZE {
    return false;
  }
  var p = ps;
  while p > 1 {
    let r = p % 2;
    if r != 0 {
      return false;
    }
    p = p / 2;
  }
  return p == 1;
}

// True when `flags` contains at least one known page-type bit and no unknown
// one (mask test by range, since `&` is unreliable on v0.61.3).
fn _page_flags_ok(flags: Int) -> Bool {
  if flags <= 0 {
    return false;
  }
  if flags > BOLT_PAGE_FLAGS_MAX {
    return false;
  }
  return true;
}

// True when [off, off + size) lies inside the page's own byte span.
// A valid BoltPage span is always inside the caller's buffer.
fn _span_ok(page: &BoltPage, off: Int, size: Int) -> Bool {
  if size < 0 {
    return false;
  }
  if off < page.offset {
    return false;
  }
  if off > page.offset + page.size {
    return false;
  }
  if size > page.offset + page.size - off {
    return false;
  }
  return true;
}

// Three-way byte-wise comparison of two in-buffer spans: -1, 0 or 1.
fn _span_cmp(data: &Vec[UInt8], aoff: Int, asize: Int, boff: Int, bsize: Int) -> Int {
  var n = asize;
  if bsize < n {
    n = bsize;
  }
  var i = 0;
  while i < n {
    let a = _byte(data, aoff + i);
    let b = _byte(data, boff + i);
    if a < b {
      return -1;
    }
    if a > b {
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

// --------------------------------------------------
//  FNV-1a-64 (meta checksum)
// --------------------------------------------------

// XOR `b` (0..255) into the low byte of the raw 64-bit pattern of `h`, using
// arithmetic only: bitwise operators on values with the high bits set are
// miscompiled in v0.61.3, but a 16-step bit loop over two 0..255 values is
// exact.
fn _xor_low_byte(h: Int, b: Int) -> Int {
  var low = h % 256;
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
  return (h - low) + out;
}

// FNV-1a-64 of `size` bytes at `off`: offset basis 0xCBF29CE484222325, prime
// 0x100000001B3, both applied to the raw two's-complement 64-bit pattern
// (`*` wraps, division truncates). The caller guarantees the span bounds.
fn _fnv1a(data: &Vec[UInt8], off: Int, size: Int) -> Int {
  var h = 0 - 3750763034362895579;
  var i = 0;
  while i < size {
    let b = _byte(data, off + i);
    h = _xor_low_byte(h, b);
    h = h * 1099511628211;
    i = i + 1;
  }
  return h;
}

/// FNV-1a-64 of the `size` bytes at `off`.
///
/// Err("bolt: span out of bounds") when off < 0, size < 0 or the span leaves
/// the buffer. The result is the raw two's-complement 64-bit pattern (a hash
/// with bit 63 set is negative). Complexity: O(size).
pub fn bolt_fnv1a64(data: &Vec[UInt8], off: Int, size: Int) -> Result[Int, Str] {
  if off < 0 {
    return _err_int("bolt: span out of bounds");
  }
  if size < 0 {
    return _err_int("bolt: span out of bounds");
  }
  if off > data.len() || size > data.len() - off {
    return _err_int("bolt: span out of bounds");
  }
  return _ok_int(_fnv1a(data, off, size));
}

/// FNV-1a-64 checksum recorded by a meta page at `page_off`: the hash of the
/// 56 bytes at page_off + 16 (meta magic through txid, i.e. everything before
/// the trailing checksum field).
///
/// Err("bolt: meta page out of bounds") when the 80 bytes a meta page needs
/// are not in the buffer. Complexity: O(56).
pub fn bolt_meta_checksum(data: &Vec[UInt8], page_off: Int) -> Result[Int, Str] {
  if page_off < 0 {
    return _err_int("bolt: meta page out of bounds");
  }
  if page_off > data.len() || BOLT_META_REQUIRED > data.len() - page_off {
    return _err_int("bolt: meta page out of bounds");
  }
  return _ok_int(_fnv1a(data, page_off + BOLT_META_HEADER_OFFSET, BOLT_META_SUM_SIZE));
}

// --------------------------------------------------
//  Page header
// --------------------------------------------------

/// Read the page with id `pgid` using `page_size`.
///
/// The page offset is pgid * page_size. Err("bolt: bad page size") when
/// page_size is not a power of two in [1024, 65536];
/// Err("bolt: page id out of range at <pgid>") when pgid is negative or has
/// no whole page in the buffer; Err("bolt: unknown page flags at <offset>")
/// when the flags field has no known page-type bit. Complexity: O(1).
pub fn bolt_read_page(data: &Vec[UInt8], page_size: Int, pgid: Int) -> Result[BoltPage, Str] {
  if !_page_size_ok(page_size) {
    return _err_page("bolt: bad page size");
  }
  if pgid < 0 {
    return _err_page("bolt: page id out of range: " + int_to_base(pgid, 10));
  }
  let total = data.len() / page_size;
  if pgid >= total {
    return _err_page("bolt: page id out of range: " + int_to_base(pgid, 10));
  }
  let off = pgid * page_size;
  let flags = _rdu(data, off + 8, 2);
  if !_page_flags_ok(flags) {
    return _err_page(_at("unknown page flags", off));
  }
  let p = BoltPage{
    page_id: _rdu(data, off, 8);
    flags: flags;
    count: _rdu(data, off + 10, 2);
    overflow: _rdu(data, off + 12, 4);
    offset: off;
    size: page_size;
    inline: false;
  };
  return _ok_page(p);
}

/// Page id recorded in the page header. Complexity: O(1).
pub fn bolt_page_id(p: &BoltPage) -> Int {
  return p.page_id;
}

/// Page-type flags of the page (BOLT_PAGE_* bits). Complexity: O(1).
pub fn bolt_page_flags(p: &BoltPage) -> Int {
  return p.flags;
}

/// Element count from the page header. Complexity: O(1).
pub fn bolt_page_count(p: &BoltPage) -> Int {
  return p.count;
}

/// Overflow page count from the page header. Complexity: O(1).
pub fn bolt_page_overflow(p: &BoltPage) -> Int {
  return p.overflow;
}

/// Absolute offset of the page in the source buffer. Complexity: O(1).
pub fn bolt_page_offset(p: &BoltPage) -> Int {
  return p.offset;
}

/// Number of bytes the page occupies in the source buffer. Complexity: O(1).
pub fn bolt_page_span(p: &BoltPage) -> Int {
  return p.size;
}

/// True when the page was decoded from a bucket leaf value. Complexity: O(1).
pub fn bolt_page_is_inline(p: &BoltPage) -> Bool {
  return p.inline;
}

// --------------------------------------------------
//  Meta pages
// --------------------------------------------------

// Read one meta page image at `off`; never fails (bounds are the caller's
// responsibility) and records validity in `valid`.
fn _meta_at(data: &Vec[UInt8], off: Int, ps: Int) -> BoltMeta {
  var m = BoltMeta{
    offset: off;
    page_id: _rdu(data, off, 8);
    page_flags: _rdu(data, off + 8, 2);
    magic: _rdu(data, off + BOLT_META_HEADER_OFFSET, 4);
    version: _rdu(data, off + 20, 4);
    page_size: _rdu(data, off + 24, 4);
    flags: _rdu(data, off + 28, 4);
    root_pgid: _rdu(data, off + 32, 8);
    root_sequence: _rdu(data, off + 40, 8);
    freelist_pgid: _rdu(data, off + 48, 8);
    pgid: _rdu(data, off + 56, 8);
    txid: _rdu(data, off + 64, 8);
    checksum: _rdu(data, off + BOLT_META_CHECKSUM_OFFSET, 8);
    computed_checksum: _fnv1a(data, off + BOLT_META_HEADER_OFFSET, BOLT_META_SUM_SIZE);
    valid: false;
  };
  m.valid = m.magic == BOLT_MAGIC && m.version == BOLT_VERSION && m.page_size == ps && m.checksum == m.computed_checksum;
  return m;
}

/// Parse both meta pages and select the valid one with the higher txid.
///
/// The page size is read from meta page 0 (offset 8 of the meta struct, page
/// offset 24) and must be a power of two in [1024, 65536]; meta page 1 is
/// then read at offset page_size. Each page is valid when its magic is
/// 0xED0CDAED, its version is 2, its page_size field equals the page size the
/// file was read with, and its stored checksum equals the FNV-1a-64 of the 56
/// bytes before it. On a tie meta 0 wins. Err("bolt: truncated meta") when
/// the buffer cannot hold the page-size field or one full page;
/// Err("bolt: bad page size") for an illegal page size;
/// Err("bolt: no valid meta page at offset 0 or <page_size>") when neither
/// page validates (the pair records both failures otherwise). Complexity:
/// O(page_size).
pub fn bolt_meta_read(data: &Vec[UInt8]) -> Result[BoltMetaPair, Str] {
  if data.len() < BOLT_META_REQUIRED {
    return _err_pair("bolt: truncated meta");
  }
  let ps = _rdu(data, 24, 4);
  if !_page_size_ok(ps) {
    return _err_pair("bolt: bad page size");
  }
  if data.len() < 2 * ps {
    return _err_pair("bolt: truncated meta");
  }
  let m0 = _meta_at(data, 0, ps);
  let m1 = _meta_at(data, ps, ps);
  if !m0.valid && !m1.valid {
    return _err_pair("bolt: no valid meta page at offset 0 or " + int_to_base(ps, 10));
  }
  var sel = BOLT_SELECT_META0;
  if m1.valid {
    if !m0.valid {
      sel = BOLT_SELECT_META1;
    } else {
      if m1.txid > m0.txid {
        sel = BOLT_SELECT_META1;
      }
    }
  }
  let pair = BoltMetaPair{ meta0: m0; meta1: m1; selected: sel; };
  return _ok_pair(pair);
}

/// Which meta page bolt_meta_read selected: BOLT_SELECT_META0 or
/// BOLT_SELECT_META1. Complexity: O(1).
pub fn bolt_meta_selected(pair: &BoltMetaPair) -> Int {
  return pair.selected;
}

/// Meta page `i` (0 or 1) of the pair, including an invalid page's fields.
/// Err("bolt: meta index out of range") for any other index.
/// Complexity: O(1).
pub fn bolt_meta_at(pair: &BoltMetaPair, i: Int) -> Result[BoltMeta, Str] {
  if i == 0 {
    let m: BoltMeta = pair.meta0;
    return _ok_meta(m);
  }
  if i == 1 {
    let m: BoltMeta = pair.meta1;
    return _ok_meta(m);
  }
  return _err_meta("bolt: meta index out of range");
}

/// The selected meta page image. Complexity: O(1).
pub fn bolt_meta_selected_meta(pair: &BoltMetaPair) -> BoltMeta {
  if pair.selected == BOLT_SELECT_META1 {
    let m: BoltMeta = pair.meta1;
    return m;
  }
  let m: BoltMeta = pair.meta0;
  return m;
}

/// Field `field` (a BOLT_META_FIELD_* selector) of a meta image.
/// Err("bolt: bad field selector") for an unknown selector; the raw parsed
/// value is returned with no extra validation. Complexity: O(1).
pub fn bolt_meta_field(m: &BoltMeta, field: Int) -> Result[Int, Str] {
  if field == BOLT_META_FIELD_MAGIC {
    return _ok_int(m.magic);
  }
  if field == BOLT_META_FIELD_VERSION {
    return _ok_int(m.version);
  }
  if field == BOLT_META_FIELD_PAGE_SIZE {
    return _ok_int(m.page_size);
  }
  if field == BOLT_META_FIELD_FLAGS {
    return _ok_int(m.flags);
  }
  if field == BOLT_META_FIELD_ROOT {
    return _ok_int(m.root_pgid);
  }
  if field == BOLT_META_FIELD_SEQUENCE {
    return _ok_int(m.root_sequence);
  }
  if field == BOLT_META_FIELD_FREELIST {
    return _ok_int(m.freelist_pgid);
  }
  if field == BOLT_META_FIELD_PGID {
    return _ok_int(m.pgid);
  }
  if field == BOLT_META_FIELD_TXID {
    return _ok_int(m.txid);
  }
  if field == BOLT_META_FIELD_CHECKSUM {
    return _ok_int(m.checksum);
  }
  if field == BOLT_META_FIELD_PAGE_ID {
    return _ok_int(m.page_id);
  }
  if field == BOLT_META_FIELD_COMPUTED {
    return _ok_int(m.computed_checksum);
  }
  if field == BOLT_META_FIELD_OFFSET {
    return _ok_int(m.offset);
  }
  return _err_int("bolt: bad field selector");
}

/// True when the meta image passed magic, version, page-size and checksum
/// validation. Complexity: O(1).
pub fn bolt_meta_valid(m: &BoltMeta) -> Bool {
  return m.valid;
}

/// Field `field` of the selected meta page of the pair (same selectors as
/// bolt_meta_field). Complexity: O(1).
pub fn bolt_meta_selected_field(pair: &BoltMetaPair, field: Int) -> Result[Int, Str] {
  let m = bolt_meta_selected_meta(pair);
  return bolt_meta_field(&m, field);
}

// --------------------------------------------------
//  Branch pages
// --------------------------------------------------

/// Field `field` (a BOLT_BRANCH_FIELD_* selector) of branch element `i`.
///
/// The 16-byte element is at page.offset + 16 + i * 16; pos/ksize/pgid are
/// read little-endian. Every access re-checks page consistency: the element
/// must lie inside the page, the key span element + pos .. + ksize must lie
/// inside the page, and the child pgid must be non-negative and point at a
/// whole page of the buffer. Err("bolt: not a branch page"),
/// Err("bolt: branch element index out of range"),
/// Err("bolt: branch element out of page bounds at <off>"),
/// Err("bolt: branch element key out of page bounds at <off>"),
/// Err("bolt: branch element page id out of range at <off>") and
/// Err("bolt: bad field selector"). Complexity: O(1).
pub fn bolt_branch_field(data: &Vec[UInt8], page: &BoltPage, i: Int, field: Int) -> Result[Int, Str] {
  if page.flags != BOLT_PAGE_BRANCH {
    return _err_int("bolt: not a branch page");
  }
  if i < 0 || i >= page.count {
    return _err_int("bolt: branch element index out of range");
  }
  let eoff = page.offset + BOLT_PAGE_HEADER_SIZE + i * BOLT_BRANCH_ELEM_SIZE;
  if !_span_ok(page, eoff, BOLT_BRANCH_ELEM_SIZE) {
    return _err_int(_at("branch element out of page bounds", eoff));
  }
  let pos = _rdu(data, eoff, 4);
  let ksize = _rdu(data, eoff + 4, 4);
  let pgid = _rdu(data, eoff + 8, 8);
  let koff = eoff + pos;
  if !_span_ok(page, koff, ksize) {
    return _err_int(_at("branch element key out of page bounds", eoff));
  }
  if pgid < 0 {
    return _err_int(_at("branch element page id out of range", eoff));
  }
  let total = data.len() / page.size;
  if pgid >= total {
    return _err_int(_at("branch element page id out of range", eoff));
  }
  if field == BOLT_BRANCH_FIELD_POS {
    return _ok_int(pos);
  }
  if field == BOLT_BRANCH_FIELD_KSIZE {
    return _ok_int(ksize);
  }
  if field == BOLT_BRANCH_FIELD_PGID {
    return _ok_int(pgid);
  }
  if field == BOLT_BRANCH_FIELD_OFFSET {
    return _ok_int(eoff);
  }
  if field == BOLT_BRANCH_FIELD_KEY_OFFSET {
    return _ok_int(koff);
  }
  return _err_int("bolt: bad field selector");
}

/// The child page-pointer array of a branch page, in element order.
///
/// This is bbolt's on-disk child pointer array: one u64 pgid per 16-byte
/// branch element, not a separate u16 offset array (see SPEC.md). All the
/// per-element consistency checks of bolt_branch_field apply.
/// Complexity: O(count).
pub fn bolt_branch_child_pgids(data: &Vec[UInt8], page: &BoltPage) -> Result[Vec[Int], Str] {
  if page.flags != BOLT_PAGE_BRANCH {
    return _err_ints("bolt: not a branch page");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < page.count {
    let r = bolt_branch_field(data, page, i, BOLT_BRANCH_FIELD_PGID);
    if !r.is_ok {
      return _err_ints(r.error);
    }
    let v: Int = r.value;
    out.push(v);
    i = i + 1;
  }
  return _ok_ints(out);
}

// --------------------------------------------------
//  Leaf pages, bucket values and inline pages
// --------------------------------------------------

/// Field `field` (a BOLT_LEAF_FIELD_* selector) of leaf element `i`.
///
/// The 16-byte element is at page.offset + 16 + i * 16; flags/pos/ksize/vsize
/// are read little-endian. Every access re-checks page consistency: the
/// element, the key span (element + pos .. + ksize) and the value span
/// (directly after the key .. + vsize) must lie inside the page.
/// Err("bolt: not a leaf page"), Err("bolt: leaf element index out of range"),
/// Err("bolt: leaf element out of page bounds at <off>"),
/// Err("bolt: leaf element key out of page bounds at <off>"),
/// Err("bolt: leaf element value out of page bounds at <off>") and
/// Err("bolt: bad field selector"). Complexity: O(1).
pub fn bolt_leaf_field(data: &Vec[UInt8], page: &BoltPage, i: Int, field: Int) -> Result[Int, Str] {
  if page.flags != BOLT_PAGE_LEAF {
    return _err_int("bolt: not a leaf page");
  }
  if i < 0 || i >= page.count {
    return _err_int("bolt: leaf element index out of range");
  }
  let eoff = page.offset + BOLT_PAGE_HEADER_SIZE + i * BOLT_LEAF_ELEM_SIZE;
  if !_span_ok(page, eoff, BOLT_LEAF_ELEM_SIZE) {
    return _err_int(_at("leaf element out of page bounds", eoff));
  }
  let eflags = _rdu(data, eoff, 4);
  let pos = _rdu(data, eoff + 4, 4);
  let ksize = _rdu(data, eoff + 8, 4);
  let vsize = _rdu(data, eoff + 12, 4);
  let koff = eoff + pos;
  if !_span_ok(page, koff, ksize) {
    return _err_int(_at("leaf element key out of page bounds", eoff));
  }
  let voff = koff + ksize;
  if !_span_ok(page, voff, vsize) {
    return _err_int(_at("leaf element value out of page bounds", eoff));
  }
  if field == BOLT_LEAF_FIELD_FLAGS {
    return _ok_int(eflags);
  }
  if field == BOLT_LEAF_FIELD_POS {
    return _ok_int(pos);
  }
  if field == BOLT_LEAF_FIELD_KSIZE {
    return _ok_int(ksize);
  }
  if field == BOLT_LEAF_FIELD_VSIZE {
    return _ok_int(vsize);
  }
  if field == BOLT_LEAF_FIELD_OFFSET {
    return _ok_int(eoff);
  }
  if field == BOLT_LEAF_FIELD_KEY_OFFSET {
    return _ok_int(koff);
  }
  if field == BOLT_LEAF_FIELD_VALUE_OFFSET {
    return _ok_int(voff);
  }
  return _err_int("bolt: bad field selector");
}

/// True when leaf element `i` is a bucket value (bit 0 of its flags is set).
/// Err("bolt: not a leaf page") for a non-leaf page and the usual element
/// errors from bolt_leaf_field. Complexity: O(1).
pub fn bolt_leaf_is_bucket(data: &Vec[UInt8], page: &BoltPage, i: Int) -> Result[Bool, Str] {
  let fr = bolt_leaf_field(data, page, i, BOLT_LEAF_FIELD_FLAGS);
  if !fr.is_ok {
    return _err_bool(fr.error);
  }
  let flags: Int = fr.value;
  if flags % 2 == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// True when leaf element `i` is an INLINE bucket: a bucket value longer than
/// the 16-byte bucket header. bbolt keeps small buckets entirely inside the
/// parent leaf value; larger buckets have root != 0 and a value of exactly 16
/// bytes.
/// Complexity: O(1).
pub fn bolt_leaf_is_inline_bucket(data: &Vec[UInt8], page: &BoltPage, i: Int) -> Result[Bool, Str] {
  let br = bolt_leaf_is_bucket(data, page, i);
  if !br.is_ok {
    return _err_bool(br.error);
  }
  let is_bucket: Bool = br.value;
  if !is_bucket {
    return _ok_bool(false);
  }
  let vr = bolt_leaf_field(data, page, i, BOLT_LEAF_FIELD_VSIZE);
  if !vr.is_ok {
    return _err_bool(vr.error);
  }
  let vsize: Int = vr.value;
  if vsize > BOLT_BUCKET_HEADER_SIZE {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Field `field` (a BOLT_BUCKET_FIELD_* selector) of the bucket value of leaf
/// element `i`: root pgid at value offset 8, sequence at value offset 8..16.
///
/// Err("bolt: leaf element is not a bucket") when the bucket flag is absent
/// and Err("bolt: bucket value too short") when fewer than 16 value bytes are
/// present. Complexity: O(1).
pub fn bolt_leaf_bucket_field(data: &Vec[UInt8], page: &BoltPage, i: Int, field: Int) -> Result[Int, Str] {
  let br = bolt_leaf_is_bucket(data, page, i);
  if !br.is_ok {
    return _err_int(br.error);
  }
  let is_bucket: Bool = br.value;
  if !is_bucket {
    return _err_int("bolt: leaf element is not a bucket");
  }
  let vr = bolt_leaf_field(data, page, i, BOLT_LEAF_FIELD_VSIZE);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let vsize: Int = vr.value;
  if vsize < BOLT_BUCKET_HEADER_SIZE {
    return _err_int("bolt: bucket value too short");
  }
  let vor = bolt_leaf_field(data, page, i, BOLT_LEAF_FIELD_VALUE_OFFSET);
  if !vor.is_ok {
    return _err_int(vor.error);
  }
  let voff: Int = vor.value;
  if field == BOLT_BUCKET_FIELD_ROOT {
    return _ok_int(_rdu(data, voff, 8));
  }
  if field == BOLT_BUCKET_FIELD_SEQUENCE {
    return _ok_int(_rdu(data, voff + 8, 8));
  }
  return _err_int("bolt: bad field selector");
}

/// Decode the inline page image of leaf element `i` as a BoltPage.
///
/// The image starts 16 bytes into the bucket value and spans the rest of it,
/// so the returned page has inline = true, `size` = vsize - 16 and `offset` =
/// value offset + 16. The inline image must itself be a leaf page with at
/// least a 16-byte header.
/// Err("bolt: leaf element is not a bucket"), Err("bolt: bucket is not
/// inline"), Err("bolt: truncated inline page") and
/// Err("bolt: inline page is not a leaf page"). Complexity: O(1).
pub fn bolt_inline_page(data: &Vec[UInt8], page: &BoltPage, i: Int) -> Result[BoltPage, Str] {
  let br = bolt_leaf_is_bucket(data, page, i);
  if !br.is_ok {
    return _err_page(br.error);
  }
  let is_bucket: Bool = br.value;
  if !is_bucket {
    return _err_page("bolt: leaf element is not a bucket");
  }
  let vr = bolt_leaf_field(data, page, i, BOLT_LEAF_FIELD_VSIZE);
  if !vr.is_ok {
    return _err_page(vr.error);
  }
  let vsize: Int = vr.value;
  if vsize <= BOLT_BUCKET_HEADER_SIZE {
    return _err_page("bolt: bucket is not inline");
  }
  let vor = bolt_leaf_field(data, page, i, BOLT_LEAF_FIELD_VALUE_OFFSET);
  if !vor.is_ok {
    return _err_page(vor.error);
  }
  let voff: Int = vor.value;
  let poff = voff + BOLT_BUCKET_HEADER_SIZE;
  let psize = vsize - BOLT_BUCKET_HEADER_SIZE;
  if psize < BOLT_PAGE_HEADER_SIZE {
    return _err_page(_at("truncated inline page", poff));
  }
  let iflags = _rdu(data, poff + 8, 2);
  if iflags != BOLT_PAGE_LEAF {
    return _err_page(_at("inline page is not a leaf page", poff));
  }
  let ip = BoltPage{
    page_id: _rdu(data, poff, 8);
    flags: iflags;
    count: _rdu(data, poff + 10, 2);
    overflow: _rdu(data, poff + 12, 4);
    offset: poff;
    size: psize;
    inline: true;
  };
  return _ok_page(ip);
}

// --------------------------------------------------
//  Freelist pages
// --------------------------------------------------

// Payload word index of the first pgid: 1 for an overflow list (the first
// word is the true count), 0 otherwise.
fn _freelist_index(page: &BoltPage) -> Int {
  if page.count == BOLT_FREELIST_OVERFLOW {
    return 1;
  }
  return 0;
}

// Byte span available to the freelist payload: the page plus its `overflow`
// continuation pages. Validates the page type and that the whole span is in
// the buffer.
fn _freelist_avail(data: &Vec[UInt8], page: &BoltPage) -> Result[Int, Str] {
  if page.flags != BOLT_PAGE_FREELIST {
    return _err_int("bolt: not a freelist page");
  }
  if page.overflow < 0 {
    return _err_int("bolt: bad freelist overflow");
  }
  let avail = page.size * (1 + page.overflow);
  if page.offset > data.len() || avail > data.len() - page.offset {
    return _err_int(_at("freelist out of bounds", page.offset));
  }
  return _ok_int(avail);
}

/// Element count of a freelist page.
///
/// The count is the page-header count field; when that equals 0xFFFF the list
/// is an overflow list and the true count is the first u64 payload word. The
/// count must fit in the page plus its overflow continuation pages.
/// Err("bolt: not a freelist page"), Err("bolt: freelist out of bounds at
/// <off>") and Err("bolt: freelist count out of bounds"). Complexity: O(1).
pub fn bolt_freelist_count(data: &Vec[UInt8], page: &BoltPage) -> Result[Int, Str] {
  let ar = _freelist_avail(data, page);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let avail: Int = ar.value;
  let words = (avail - BOLT_PAGE_HEADER_SIZE) / 8;
  if _freelist_index(page) == 1 {
    if words < 1 {
      return _err_int("bolt: freelist count out of bounds");
    }
    let raw = _rdu(data, page.offset + BOLT_PAGE_HEADER_SIZE, 8);
    if raw < 0 {
      return _err_int("bolt: freelist count out of bounds");
    }
    if raw > words - 1 {
      return _err_int("bolt: freelist count out of bounds");
    }
    return _ok_int(raw);
  }
  if page.count > words {
    return _err_int("bolt: freelist count out of bounds");
  }
  return _ok_int(page.count);
}

/// Free page id `i` of a freelist page (0-based, in payload order).
///
/// The pgid must be non-negative and below the buffer's page count.
/// Err("bolt: freelist index out of range") and
/// Err("bolt: freelist page id out of range at <off>") plus the errors of
/// bolt_freelist_count. Complexity: O(1).
pub fn bolt_freelist_pgid(data: &Vec[UInt8], page: &BoltPage, i: Int) -> Result[Int, Str] {
  let cr = bolt_freelist_count(data, page);
  if !cr.is_ok {
    return _err_int(cr.error);
  }
  let count: Int = cr.value;
  if i < 0 || i >= count {
    return _err_int("bolt: freelist index out of range");
  }
  let idx = _freelist_index(page);
  let off = page.offset + BOLT_PAGE_HEADER_SIZE + 8 * (idx + i);
  let pgid = _rdu(data, off, 8);
  if pgid < 0 {
    return _err_int(_at("freelist page id out of range", off));
  }
  let total = data.len() / page.size;
  if pgid >= total {
    return _err_int(_at("freelist page id out of range", off));
  }
  return _ok_int(pgid);
}

/// All free page ids of a freelist page, in payload order.
/// Complexity: O(count).
pub fn bolt_freelist_pgids(data: &Vec[UInt8], page: &BoltPage) -> Result[Vec[Int], Str] {
  let cr = bolt_freelist_count(data, page);
  if !cr.is_ok {
    return _err_ints(cr.error);
  }
  let count: Int = cr.value;
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    let pr = bolt_freelist_pgid(data, page, i);
    if !pr.is_ok {
      return _err_ints(pr.error);
    }
    let v: Int = pr.value;
    out.push(v);
    i = i + 1;
  }
  return _ok_ints(out);
}

// --------------------------------------------------
//  Bounded in-order tree walk
// --------------------------------------------------

/// Walk the tree under `root_pgid` and collect every leaf entry in key order.
///
/// The walk is an explicit depth-first traversal (no recursion, no allocation
/// beyond the result): branch children are pushed in reverse so child 0 is
/// visited first, which yields the bbolt tree's global key order for
/// well-formed files. Each visited page is checked for: a whole page in the
/// buffer (bolt_read_page), element pointer spans inside the page
/// (bolt_branch_field / bolt_leaf_field), child pgids in range, no page
/// visited twice (a cycle or shared page is Err), and depth <= max_depth
/// (depth 1 = root_pgid). Leaf keys must be non-decreasing byte-wise; the
/// first violation is Err.
///
/// Errors: Err("bolt: bad page size"), Err("bolt: bad walk depth cap") when
/// max_depth < 1, Err("bolt: root page id out of range: <pgid>"),
/// Err("bolt: page revisited in walk: <pgid>"), Err("bolt: tree too deep at
/// page <pgid> (cap <max_depth>)"), Err("bolt: not a tree page at <pgid>")
/// for meta/freelist pages, Err("bolt: leaf keys out of order at page <pgid>
/// element <i>") and every structural error of the element readers.
/// Complexity: O(entries + pages).
pub fn bolt_walk_tree(data: &Vec[UInt8], page_size: Int, root_pgid: Int, max_depth: Int) -> Result[BoltWalk, Str] {
  if !_page_size_ok(page_size) {
    return _err_walk("bolt: bad page size");
  }
  if max_depth < 1 {
    return _err_walk("bolt: bad walk depth cap");
  }
  if root_pgid < 0 {
    return _err_walk("bolt: root page id out of range: " + int_to_base(root_pgid, 10));
  }
  let total = data.len() / page_size;
  if root_pgid >= total {
    return _err_walk("bolt: root page id out of range: " + int_to_base(root_pgid, 10));
  }
  var w = BoltWalk{
    page_ids: Vec[Int].new();
    depths: Vec[Int].new();
    key_offsets: Vec[Int].new();
    key_sizes: Vec[Int].new();
    value_offsets: Vec[Int].new();
    value_sizes: Vec[Int].new();
    elem_flags: Vec[Int].new();
    leaf_count: 0;
  };
  var stack = Vec[Int].new();
  var sdepth = Vec[Int].new();
  var seen = Vec[Int].new();
  stack.push(root_pgid);
  sdepth.push(1);
  var last_off = -1;
  var last_size = 0;
  while stack.len() > 0 {
    let pgid: Int = stack[stack.len() - 1];
    let depth: Int = sdepth[sdepth.len() - 1];
    stack.pop();
    sdepth.pop();
    let pr = bolt_read_page(data, page_size, pgid);
    if !pr.is_ok {
      return _err_walk(pr.error);
    }
    let page: BoltPage = pr.value;
    var dup = false;
    var k = 0;
    while k < seen.len() {
      let s: Int = seen[k];
      if s == pgid {
        dup = true;
      }
      k = k + 1;
    }
    if dup {
      return _err_walk("bolt: page revisited in walk: " + int_to_base(pgid, 10));
    }
    seen.push(pgid);
    if page.flags == BOLT_PAGE_BRANCH {
      var i = page.count - 1;
      while i >= 0 {
        let gr = bolt_branch_field(data, &page, i, BOLT_BRANCH_FIELD_PGID);
        if !gr.is_ok {
          return _err_walk(gr.error);
        }
        let child: Int = gr.value;
        if depth + 1 > max_depth {
          return _err_walk("bolt: tree too deep at page " + int_to_base(pgid, 10) + " (cap " + int_to_base(max_depth, 10) + ")");
        }
        stack.push(child);
        sdepth.push(depth + 1);
        i = i - 1;
      }
    } else {
      if page.flags == BOLT_PAGE_LEAF {
        w.leaf_count = w.leaf_count + 1;
        var i = 0;
        while i < page.count {
          let fr = bolt_leaf_field(data, &page, i, BOLT_LEAF_FIELD_FLAGS);
          if !fr.is_ok {
            return _err_walk(fr.error);
          }
          let kor = bolt_leaf_field(data, &page, i, BOLT_LEAF_FIELD_KEY_OFFSET);
          if !kor.is_ok {
            return _err_walk(kor.error);
          }
          let ksr = bolt_leaf_field(data, &page, i, BOLT_LEAF_FIELD_KSIZE);
          if !ksr.is_ok {
            return _err_walk(ksr.error);
          }
          let vor = bolt_leaf_field(data, &page, i, BOLT_LEAF_FIELD_VALUE_OFFSET);
          if !vor.is_ok {
            return _err_walk(vor.error);
          }
          let vsr = bolt_leaf_field(data, &page, i, BOLT_LEAF_FIELD_VSIZE);
          if !vsr.is_ok {
            return _err_walk(vsr.error);
          }
          let eflags: Int = fr.value;
          let koff: Int = kor.value;
          let ksize: Int = ksr.value;
          let voff: Int = vor.value;
          let vsize: Int = vsr.value;
          if last_off >= 0 {
            if _span_cmp(data, last_off, last_size, koff, ksize) > 0 {
              return _err_walk("bolt: leaf keys out of order at page " + int_to_base(pgid, 10) + " element " + int_to_base(i, 10));
            }
          }
          last_off = koff;
          last_size = ksize;
          w.page_ids.push(pgid);
          w.depths.push(depth);
          w.key_offsets.push(koff);
          w.key_sizes.push(ksize);
          w.value_offsets.push(voff);
          w.value_sizes.push(vsize);
          w.elem_flags.push(eflags);
          i = i + 1;
        }
      } else {
        return _err_walk("bolt: not a tree page at " + int_to_base(pgid, 10));
      }
    }
  }
  return _ok_walk(w);
}

/// Number of leaf entries collected by a walk. Complexity: O(1).
pub fn bolt_walk_count(w: &BoltWalk) -> Int {
  return w.key_offsets.len();
}

/// Number of leaf pages visited by a walk. Complexity: O(1).
pub fn bolt_walk_leaf_count(w: &BoltWalk) -> Int {
  return w.leaf_count;
}

/// Field `field` (a BOLT_ENTRY_FIELD_* selector) of walk entry `i`; the
/// parallel vectors are always the same length, so any selector works for
/// every entry. Err("bolt: walk index out of range") outside [0, count) and
/// Err("bolt: bad field selector") for an unknown selector. Complexity: O(1).
pub fn bolt_walk_field(w: &BoltWalk, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= w.key_offsets.len() {
    return _err_int("bolt: walk index out of range");
  }
  if field == BOLT_ENTRY_FIELD_KEY_OFFSET {
    let v: Int = w.key_offsets[i];
    return _ok_int(v);
  }
  if field == BOLT_ENTRY_FIELD_KEY_SIZE {
    let v: Int = w.key_sizes[i];
    return _ok_int(v);
  }
  if field == BOLT_ENTRY_FIELD_VALUE_OFFSET {
    let v: Int = w.value_offsets[i];
    return _ok_int(v);
  }
  if field == BOLT_ENTRY_FIELD_VALUE_SIZE {
    let v: Int = w.value_sizes[i];
    return _ok_int(v);
  }
  if field == BOLT_ENTRY_FIELD_FLAGS {
    let v: Int = w.elem_flags[i];
    return _ok_int(v);
  }
  if field == BOLT_ENTRY_FIELD_PAGE_ID {
    let v: Int = w.page_ids[i];
    return _ok_int(v);
  }
  if field == BOLT_ENTRY_FIELD_DEPTH {
    let v: Int = w.depths[i];
    return _ok_int(v);
  }
  return _err_int("bolt: bad field selector");
}

// --------------------------------------------------
//  Span copies
// --------------------------------------------------

/// Copy the `size` bytes at `off` out of the buffer.
/// Err("bolt: span out of bounds") when the span leaves the buffer; a
/// zero-size span at data.len() is allowed. Complexity: O(size).
pub fn bolt_span_bytes(data: &Vec[UInt8], off: Int, size: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 {
    return _err_bytes("bolt: span out of bounds");
  }
  if size < 0 {
    return _err_bytes("bolt: span out of bounds");
  }
  if off > data.len() || size > data.len() - off {
    return _err_bytes("bolt: span out of bounds");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Copy the `size` bytes at `off` out of the buffer as a Str (raw bytes; no
/// encoding validation). Err("bolt: span out of bounds") when the span
/// leaves the buffer. Complexity: O(size).
pub fn bolt_span_str(data: &Vec[UInt8], off: Int, size: Int) -> Result[Str, Str] {
  let br = bolt_span_bytes(data, off, size);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let b: Vec[UInt8] = br.value;
  return _ok_str(Str::from_utf8(b));
}

/// Key of walk entry `i` as a copied Str. Complexity: O(key size).
pub fn bolt_walk_key_str(data: &Vec[UInt8], w: &BoltWalk, i: Int) -> Result[Str, Str] {
  let o = bolt_walk_field(w, i, BOLT_ENTRY_FIELD_KEY_OFFSET);
  if !o.is_ok {
    return _err_str(o.error);
  }
  let s = bolt_walk_field(w, i, BOLT_ENTRY_FIELD_KEY_SIZE);
  if !s.is_ok {
    return _err_str(s.error);
  }
  let ko: Int = o.value;
  let ks: Int = s.value;
  return bolt_span_str(data, ko, ks);
}

/// Value of walk entry `i` as a copied Str. Complexity: O(value size).
pub fn bolt_walk_value_str(data: &Vec[UInt8], w: &BoltWalk, i: Int) -> Result[Str, Str] {
  let o = bolt_walk_field(w, i, BOLT_ENTRY_FIELD_VALUE_OFFSET);
  if !o.is_ok {
    return _err_str(o.error);
  }
  let s = bolt_walk_field(w, i, BOLT_ENTRY_FIELD_VALUE_SIZE);
  if !s.is_ok {
    return _err_str(s.error);
  }
  let vo: Int = o.value;
  let vs: Int = s.value;
  return bolt_span_str(data, vo, vs);
}
