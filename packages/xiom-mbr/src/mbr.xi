// XIOM -- xiom.mbr: Master Boot Record (MBR) codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a Master Boot Record
// codec. Scope: the canonical 512-byte MBR sector -- the raw boot code span,
// the four 16-byte primary partition entries and the 0x55AA boot signature.
// Extended partitions (EBR chains), GPT (sibling xiom.gpt), boot code
// semantics and filesystem detection are documented non-goals in SPEC.md.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - `mbr_parse` validates the sector length, the 0x55AA signature, the four
//   boot flags and the documented type/LBA consistency policy (a type byte
//   of 0x00 implies zero LBA fields), then returns an `Mbr` of flat parallel
//   vectors: one element per entry slot for the boot flags, the packed raw
//   CHS triples (start and end), the type codes, the LBA starts and the LBA
//   sector counts. No Vec of structs is used.
// - The boot code span (bytes 0x000..0x1B7 inclusive, 440 bytes) and the six
//   bytes at 0x1B8..0x1BD (optional 4-byte disk signature plus two reserved
//   bytes) are preserved raw and never interpreted.
// - A CHS triple is stored as its raw 24-bit value
//   head * 65536 + byte2 * 256 + byte3 and decoded on demand: head (u8),
//   sector (the low 6 bits of byte2) and cylinder (the high 2 bits of byte2
//   plus byte3, 10 bits total). Zero CHS is tolerated as long as the LBA
//   fields are set.
// - LBA ranges are checked against a disk size only by `mbr_parse_sized`;
//   `mbr_parse` never assumes a disk size.
// - `mbr_build` writes a canonical 512-byte sector: the caller's boot code
//   and disk-area bytes, the provided entries zero-filled to four slots and
//   a recomputed 0x55AA signature.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the leaf helpers below.
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * Str values are never compared with `==`; the module maps type codes to
//     string literals and performs no string equality at all.
//   * no bitwise operator ever sees a sign-bit-set value: CHS decoding uses
//     division and modulo on small non-negative Ints only.
//   * all `&`/`&mut` arguments are local bindings, never struct fields or
//     call results.

module xiom.mbr

const _MBR_SECTOR_BYTES: Int = 512;
const _MBR_BOOT_BYTES: Int = 440;
const _MBR_DISK_AREA_BYTES: Int = 6;
const _MBR_ENTRIES_OFF: Int = 446;
const _MBR_ENTRY_BYTES: Int = 16;
const _MBR_ENTRY_SLOTS: Int = 4;
const _MBR_SIG_OFF: Int = 510;
const _MBR_SIG_A: Int = 85;
const _MBR_SIG_B: Int = 170;
const _MBR_SIG_VALUE: Int = 43605;
const _MBR_FLAG_INACTIVE: Int = 0;
const _MBR_FLAG_ACTIVE: Int = 128;
const _MBR_TYPE_UNUSED: Int = 0;
const _MBR_TYPE_BYTE_MAX: Int = 255;
const _MBR_CHS_MAX: Int = 16777215;
const _MBR_U32_MAX: Int = 4294967295;

/// Parsed Master Boot Record.
///
/// The two leading fields are the raw preserved spans: `boot_code` holds the
/// 440 bytes at 0x000..0x1B7 and `disk_area` the six bytes at
/// 0x1B8..0x1BD (optional disk signature plus reserved). The remaining six
/// vectors are the flat parallel entry columns, one element per entry slot
/// in table order: `boot_flags` (0x00 or 0x80), `start_chs` and `end_chs`
/// (packed raw 24-bit triples), `types` (raw type bytes), `lba_starts` and
/// `lba_counts` (LE32 values). A parsed table has exactly four elements in
/// every entry vector; unused slots are kept (type 0x00). Fields are
/// implementation details; callers should go through the free functions
/// below.
pub type Mbr = {
  boot_code: Vec[UInt8];
  disk_area: Vec[UInt8];
  boot_flags: Vec[Int];
  start_chs: Vec[Int];
  types: Vec[Int];
  end_chs: Vec[Int];
  lba_starts: Vec[Int];
  lba_counts: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Mbr, Str].
fn _ok_table(v: Mbr) -> Result[Mbr, Str] {
  return Ok(v);
}

// Err(m) for Result[Mbr, Str].
fn _err_table(m: Str) -> Result[Mbr, Str] {
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

// Little-endian UInt16 at `off` as an Int (0..65535).
fn _le16(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256;
}

// Little-endian UInt32 at `off` as an Int (0..2^32-1).
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536 + _byte(data, off + 3) * 16777216;
}

// Byte number `k` of `v` (0 = least significant). Arithmetic only: this is
// exact for negative two's-complement values too (gpt/bson precedent), so a
// hand-built value that slipped past a cheap guard cannot corrupt a write.
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

// Append `v` (0..2^32-1) as four little-endian bytes.
fn _push_le32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Append a packed raw CHS triple: byte 1 (head), byte 2 (sector in the low
// 6 bits, cylinder high bits above), byte 3 (cylinder low byte). Callers
// guarantee 0 <= p <= 0xFFFFFF.
fn _push_chs(out: &mut Vec[UInt8], p: Int) {
  out.push(_byte_at(p, 2));
  out.push(_byte_at(p, 1));
  out.push(_byte_at(p, 0));
}

// Append `count` zero bytes.
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Internal CHS helpers
// --------------------------------------------------

// Packed raw triple at `off` (3 bytes); callers guarantee the bounds.
fn _chs_at(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) * 65536 + _byte(data, off + 1) * 256 + _byte(data, off + 2);
}

// Head byte of a packed raw triple (u8).
fn _chs_head(p: Int) -> Int {
  return p / 65536;
}

// Second CHS byte of a packed raw triple (raw, 0..255).
fn _chs_sec_byte(p: Int) -> Int {
  return (p / 256) % 256;
}

// Decoded sector (low 6 bits of the second CHS byte, 0..63).
fn _chs_sector(p: Int) -> Int {
  return _chs_sec_byte(p) % 64;
}

// Decoded cylinder (high 2 bits of the second CHS byte plus the third byte,
// 0..1023).
fn _chs_cylinder(p: Int) -> Int {
  return (_chs_sec_byte(p) / 64) * 256 + p % 256;
}

// --------------------------------------------------
//  Internal signature and vector helpers
// --------------------------------------------------

// True when the two signature bytes are 0x55 at 0x1FE and 0xAA at 0x1FF;
// the caller guarantees a 512-byte buffer.
fn _sig_ok(data: &Vec[UInt8]) -> Bool {
  if _byte(data, _MBR_SIG_OFF) != _MBR_SIG_A { return false; }
  if _byte(data, _MBR_SIG_OFF + 1) != _MBR_SIG_B { return false; }
  return true;
}

// True when the six parallel entry vectors all have the same length.
fn _vecs_equal(m: &Mbr) -> Bool {
  let n = m.boot_flags.len();
  if m.start_chs.len() != n { return false; }
  if m.types.len() != n { return false; }
  if m.end_chs.len() != n { return false; }
  if m.lba_starts.len() != n { return false; }
  if m.lba_counts.len() != n { return false; }
  return true;
}

// Minimum length of the six parallel entry vectors (the safe maximum for
// indexing a hand-built table).
fn _vecs_min(m: &Mbr) -> Int {
  var n = m.boot_flags.len();
  if m.start_chs.len() < n { n = m.start_chs.len(); }
  if m.types.len() < n { n = m.types.len(); }
  if m.end_chs.len() < n { n = m.end_chs.len(); }
  if m.lba_starts.len() < n { n = m.lba_starts.len(); }
  if m.lba_counts.len() < n { n = m.lba_counts.len(); }
  return n;
}

// --------------------------------------------------
//  Public API -- parsing
// --------------------------------------------------

/// Parse a Master Boot Record from at least its first 512 bytes.
///
/// Validation order (first failure wins): a buffer shorter than 512 bytes is
/// Err("mbr: truncated sector"); bytes 0x1FE..0x1FF must be the 0x55 0xAA
/// signature -> Err("mbr: bad signature"); every one of the four boot flags
/// must be 0x00 or 0x80 -> Err("mbr: bad boot flag"); every entry with type
/// byte 0x00 must have zero LBA fields (the documented type 0 policy;
/// CHS is not constrained) -> Err("mbr: unused entry not zero").
///
/// The boot code span [0x000, 0x1B8) and the six disk-area bytes
/// [0x1B8, 0x1BE) are copied raw. CHS triples are never cross-checked
/// against the LBA fields, so zero CHS is tolerated whenever the LBA fields
/// are set (LBA-only partitions are common). No disk size is assumed: LBA
/// ranges are only bounded by `mbr_parse_sized`.
///
/// Params: data - the sector bytes, read only (bytes after 511 are ignored).
/// Returns: Ok(Mbr) with four elements in every entry vector.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(512).
pub fn mbr_parse(data: &Vec[UInt8]) -> Result[Mbr, Str] {
  if data.len() < _MBR_SECTOR_BYTES { return _err_table("mbr: truncated sector"); }
  if !_sig_ok(data) { return _err_table("mbr: bad signature"); }
  var boot_code = Vec[UInt8].new();
  var disk_area = Vec[UInt8].new();
  var i = 0;
  while i < _MBR_BOOT_BYTES {
    boot_code.push(data[i]);
    i = i + 1;
  }
  i = 0;
  while i < _MBR_DISK_AREA_BYTES {
    disk_area.push(data[_MBR_BOOT_BYTES + i]);
    i = i + 1;
  }
  var boot_flags = Vec[Int].new();
  var start_chs = Vec[Int].new();
  var types = Vec[Int].new();
  var end_chs = Vec[Int].new();
  var lba_starts = Vec[Int].new();
  var lba_counts = Vec[Int].new();
  var e = 0;
  while e < _MBR_ENTRY_SLOTS {
    let off: Int = _MBR_ENTRIES_OFF + e * _MBR_ENTRY_BYTES;
    let flag: Int = _byte(data, off);
    if flag != _MBR_FLAG_INACTIVE {
      if flag != _MBR_FLAG_ACTIVE { return _err_table("mbr: bad boot flag"); }
    }
    let ty: Int = _byte(data, off + 4);
    let ls: Int = _le32(data, off + 8);
    let lc: Int = _le32(data, off + 12);
    if ty == _MBR_TYPE_UNUSED {
      if ls != 0 { return _err_table("mbr: unused entry not zero"); }
      if lc != 0 { return _err_table("mbr: unused entry not zero"); }
    }
    boot_flags.push(flag);
    start_chs.push(_chs_at(data, off + 1));
    types.push(ty);
    end_chs.push(_chs_at(data, off + 5));
    lba_starts.push(ls);
    lba_counts.push(lc);
    e = e + 1;
  }
  let table = Mbr{
    boot_code: boot_code;
    disk_area: disk_area;
    boot_flags: boot_flags;
    start_chs: start_chs;
    types: types;
    end_chs: end_chs;
    lba_starts: lba_starts;
    lba_counts: lba_counts;
  };
  return _ok_table(table);
}

/// Parse a Master Boot Record and additionally bound every in-use entry by a
/// disk size (documented opt-in policy: `mbr_parse` never assumes one).
///
/// Validation is `mbr_parse` followed by: `total_sectors <= 0` ->
/// Err("mbr: bad disk size"); for every entry with a non-zero type code,
/// `lba_start + lba_count <= total_sectors` -> Err("mbr: entry beyond
/// disk"). Unused entries (type 0x00) have zero LBA fields by the parse
/// policy and impose no bound. An entry with `lba_count == 0` is a
/// zero-length extent and passes exactly when `lba_start <= total_sectors`.
///
/// Params: data - the sector bytes, read only; total_sectors - the disk
/// size in 512-byte sectors (1..2^32-1 for a real disk; larger values are
/// accepted and simply never fail the bound).
/// Returns: Ok(Mbr) identical to `mbr_parse`.
/// Error case: the `mbr_parse` errors plus "mbr: bad disk size" and
/// "mbr: entry beyond disk".
/// Complexity: O(512).
pub fn mbr_parse_sized(data: &Vec[UInt8], total_sectors: Int) -> Result[Mbr, Str] {
  let pr = mbr_parse(data);
  if !pr.is_ok {
    let msg: Str = pr.error;
    return _err_table(msg);
  }
  if total_sectors <= 0 { return _err_table("mbr: bad disk size"); }
  let m: Mbr = pr.value;
  var i = 0;
  let n: Int = mbr_entry_count(&m);
  while i < n {
    if mbr_entry_in_use(&m, i) {
      let s: Int = mbr_entry_lba_start(&m, i);
      let c: Int = mbr_entry_lba_count(&m, i);
      if s + c > total_sectors { return _err_table("mbr: entry beyond disk"); }
    }
    i = i + 1;
  }
  return _ok_table(m);
}

/// The two bytes at 0x1FE..0x1FF read as a little-endian UInt16, or -1 when
/// `data` is shorter than 512 bytes. The canonical MBR byte sequence
/// 0x55 0xAA therefore reads back as 0xAA55 = 43605; `mbr_signature_ok` is
/// the normative byte check. Complexity: O(1).
pub fn mbr_signature(data: &Vec[UInt8]) -> Int {
  if data.len() < _MBR_SECTOR_BYTES { return -1; }
  return _le16(data, _MBR_SIG_OFF);
}

/// True when `data` holds at least 512 bytes and the two signature bytes are
/// exactly 0x55 at 0x1FE and 0xAA at 0x1FF (the documented MBR signature).
/// This is the byte-order-exact check; compare with `mbr_signature` only if
/// you need the raw numeric value. Complexity: O(1).
pub fn mbr_signature_ok(data: &Vec[UInt8]) -> Bool {
  return mbr_signature(data) == _MBR_SIG_VALUE;
}

/// The 440 raw boot code bytes (0x000..0x1B7 inclusive) of `m`. The span is
/// preserved verbatim by `mbr_parse` and written back verbatim by
/// `mbr_build`. Complexity: O(440).
pub fn mbr_boot_code_span(m: &Mbr) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let src: Vec[UInt8] = m.boot_code;
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

/// The six raw bytes at 0x1B8..0x1BD of `m`: the optional 4-byte disk
/// signature followed by two reserved bytes. The codec preserves the bytes
/// but never interprets them (the disk signature is not exposed as a
/// number). Complexity: O(6).
pub fn mbr_disk_area_span(m: &Mbr) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let src: Vec[UInt8] = m.disk_area;
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

/// Safe entry count: the minimum length of the six parallel entry vectors,
/// so a hand-built table with drifted vectors reports the indexing maximum.
/// A parsed table reports 4. Complexity: O(1).
pub fn mbr_entry_count(m: &Mbr) -> Int {
  return _vecs_min(m);
}

// --------------------------------------------------
//  Public API -- type names
// --------------------------------------------------

/// Documented partial name table for a partition type byte: 0x00 "unused",
/// 0x07 "NTFS/exFAT", 0x0B "FAT32 (CHS)", 0x0C "FAT32 (LBA)",
/// 0x82 "Linux swap", 0x83 "Linux", 0x8E "Linux LVM", 0xEE "GPT protective",
/// 0xEF "EFI system". Any other value in 0..255 is "unknown" (unknown types
/// pass through untouched: `mbr_entry_type` still reports the raw byte).
/// Values outside 0..255 return "". Complexity: O(1).
pub fn mbr_type_name(code: Int) -> Str {
  if code == 0 { return "unused"; }
  if code == 7 { return "NTFS/exFAT"; }
  if code == 11 { return "FAT32 (CHS)"; }
  if code == 12 { return "FAT32 (LBA)"; }
  if code == 130 { return "Linux swap"; }
  if code == 131 { return "Linux"; }
  if code == 142 { return "Linux LVM"; }
  if code == 238 { return "GPT protective"; }
  if code == 239 { return "EFI system"; }
  if code < 0 { return ""; }
  if code > _MBR_TYPE_BYTE_MAX { return ""; }
  return "unknown";
}

// --------------------------------------------------
//  Public API -- entry accessors
// --------------------------------------------------

/// Raw boot flag byte of entry `i` (0x00 inactive, 0x80 active); -1 when `i`
/// is negative or out of range. Complexity: O(1).
pub fn mbr_entry_boot_flag(m: &Mbr, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= m.boot_flags.len() { return -1; }
  let v: Int = m.boot_flags[i];
  return v;
}

/// True when entry `i` is marked bootable (boot flag 0x80); false when `i`
/// is negative, out of range or the flag is 0x00. Complexity: O(1).
pub fn mbr_entry_bootable(m: &Mbr, i: Int) -> Bool {
  let f: Int = mbr_entry_boot_flag(m, i);
  return f == _MBR_FLAG_ACTIVE;
}

/// Raw partition type byte of entry `i`; -1 when `i` is negative or out of
/// range. Type 0x00 marks an unused slot. Complexity: O(1).
pub fn mbr_entry_type(m: &Mbr, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= m.types.len() { return -1; }
  let v: Int = m.types[i];
  return v;
}

/// Documented name of entry `i`'s type byte (see `mbr_type_name`); "" when
/// `i` is negative or out of range. Complexity: O(1).
pub fn mbr_entry_type_name(m: &Mbr, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= m.types.len() { return ""; }
  let ty: Int = m.types[i];
  return mbr_type_name(ty);
}

/// Packed raw start CHS triple of entry `i` (head * 65536 + byte2 * 256 +
/// byte3); -1 when `i` is negative or out of range. Complexity: O(1).
pub fn mbr_entry_start_chs(m: &Mbr, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= m.start_chs.len() { return -1; }
  let v: Int = m.start_chs[i];
  return v;
}

/// Decoded start head (u8, 0..255) of entry `i`; -1 when `i` is negative,
/// out of range or the stored triple is negative (hand-built drift).
/// Complexity: O(1).
pub fn mbr_entry_start_chs_head(m: &Mbr, i: Int) -> Int {
  let p: Int = mbr_entry_start_chs(m, i);
  if p < 0 { return -1; }
  return _chs_head(p);
}

/// Decoded start sector (low 6 bits, 0..63) of entry `i`; -1 when `i` is
/// negative, out of range or the stored triple is negative. Complexity:
/// O(1).
pub fn mbr_entry_start_chs_sector(m: &Mbr, i: Int) -> Int {
  let p: Int = mbr_entry_start_chs(m, i);
  if p < 0 { return -1; }
  return _chs_sector(p);
}

/// Decoded start cylinder (10 bits, 0..1023) of entry `i`; -1 when `i` is
/// negative, out of range or the stored triple is negative. Complexity:
/// O(1).
pub fn mbr_entry_start_chs_cylinder(m: &Mbr, i: Int) -> Int {
  let p: Int = mbr_entry_start_chs(m, i);
  if p < 0 { return -1; }
  return _chs_cylinder(p);
}

/// Packed raw end CHS triple of entry `i`; -1 when `i` is negative or out
/// of range. Complexity: O(1).
pub fn mbr_entry_end_chs(m: &Mbr, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= m.end_chs.len() { return -1; }
  let v: Int = m.end_chs[i];
  return v;
}

/// Decoded end head (u8, 0..255) of entry `i`; -1 when `i` is negative, out
/// of range or the stored triple is negative. Complexity: O(1).
pub fn mbr_entry_end_chs_head(m: &Mbr, i: Int) -> Int {
  let p: Int = mbr_entry_end_chs(m, i);
  if p < 0 { return -1; }
  return _chs_head(p);
}

/// Decoded end sector (low 6 bits, 0..63) of entry `i`; -1 when `i` is
/// negative, out of range or the stored triple is negative. Complexity:
/// O(1).
pub fn mbr_entry_end_chs_sector(m: &Mbr, i: Int) -> Int {
  let p: Int = mbr_entry_end_chs(m, i);
  if p < 0 { return -1; }
  return _chs_sector(p);
}

/// Decoded end cylinder (10 bits, 0..1023) of entry `i`; -1 when `i` is
/// negative, out of range or the stored triple is negative. Complexity:
/// O(1).
pub fn mbr_entry_end_chs_cylinder(m: &Mbr, i: Int) -> Int {
  let p: Int = mbr_entry_end_chs(m, i);
  if p < 0 { return -1; }
  return _chs_cylinder(p);
}

/// First LBA of entry `i` (LE32, 0..2^32-1); -1 when `i` is negative or out
/// of range. Complexity: O(1).
pub fn mbr_entry_lba_start(m: &Mbr, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= m.lba_starts.len() { return -1; }
  let v: Int = m.lba_starts[i];
  return v;
}

/// Sector count of entry `i` (LE32, 0..2^32-1); -1 when `i` is negative or
/// out of range. Complexity: O(1).
pub fn mbr_entry_lba_count(m: &Mbr, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= m.lba_counts.len() { return -1; }
  let v: Int = m.lba_counts[i];
  return v;
}

/// True when entry `i` is in use, i.e. its type byte is not 0x00; false
/// when `i` is negative or out of range. The predicate deliberately ignores
/// the LBA fields: the type 0 policy already pins them to zero for a parsed
/// table. Complexity: O(1).
pub fn mbr_entry_in_use(m: &Mbr, i: Int) -> Bool {
  let ty: Int = mbr_entry_type(m, i);
  if ty <= 0 { return false; }
  return true;
}

// --------------------------------------------------
//  Public API -- overlap detection
// --------------------------------------------------

/// Documented pairwise overlap check: true when entries `a` and `b` are
/// both in use (type != 0), both have a non-zero sector count and their
/// half-open extents [lba_start, lba_start + lba_count) intersect. False
/// when `a == b`, when either index is negative or out of range, when
/// either entry is unused and when either count is zero (a zero-length
/// extent covers nothing). Complexity: O(1).
pub fn mbr_entries_overlap(m: &Mbr, a: Int, b: Int) -> Bool {
  if a < 0 { return false; }
  if b < 0 { return false; }
  if a == b { return false; }
  if !mbr_entry_in_use(m, a) { return false; }
  if !mbr_entry_in_use(m, b) { return false; }
  let ca: Int = mbr_entry_lba_count(m, a);
  let cb: Int = mbr_entry_lba_count(m, b);
  if ca <= 0 { return false; }
  if cb <= 0 { return false; }
  let sa: Int = mbr_entry_lba_start(m, a);
  let sb: Int = mbr_entry_lba_start(m, b);
  if sa < sb + cb {
    if sb < sa + ca { return true; }
  }
  return false;
}

/// True when any two distinct in-use entries of `m` overlap: all six pairs
/// (0,1) (0,2) (0,3) (1,2) (1,3) (2,3) within `mbr_entry_count` are checked
/// with `mbr_entries_overlap`. A Linux + unused-entry table reports false;
/// adjacency (end == next start) is not an overlap. Both sums stay below
/// 2^33, so no overflow is possible on 64-bit Int. Complexity: O(1) (at
/// most six pairs).
pub fn mbr_has_overlap(m: &Mbr) -> Bool {
  var i = 0;
  let n: Int = mbr_entry_count(m);
  while i < n {
    var j = i + 1;
    while j < n {
      if mbr_entries_overlap(m, i, j) { return true; }
      j = j + 1;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

/// Build a canonical 512-byte MBR sector.
///
/// Validation order (first failure wins): `boot_code` must be exactly 440
/// bytes -> Err("mbr: bad boot code"); `disk_area` must be exactly 6 bytes
/// -> Err("mbr: bad disk area"); the six entry vectors must have equal
/// lengths -> Err("mbr: entry vector mismatch"); the common length must be
/// at most 4 -> Err("mbr: bad entry count"); per entry, in order: boot flag
/// 0x00/0x80 -> Err("mbr: bad boot flag"); type byte 0..255 ->
/// Err("mbr: bad entry type"); type 0x00 with a non-zero LBA start or count
/// -> Err("mbr: unused entry not zero"); both CHS triples in 0..0xFFFFFF ->
/// Err("mbr: bad CHS"); both LBA fields in 0..2^32-1 -> Err("mbr: bad LBA").
///
/// Layout: `boot_code` (440 bytes) + `disk_area` (6 bytes) + four 16-byte
/// entry slots. The first `n` slots come from the vectors (n is their
/// common length, 0..4) and the remaining slots are written as all-zero
/// unused entries; the two signature bytes 0x55 0xAA are always recomputed.
/// The result is always exactly 512 bytes.
///
/// Params: m - the entry and raw-span source, read only.
/// Returns: Ok(bytes) of length 512.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(512).
pub fn mbr_build(m: &Mbr) -> Result[Vec[UInt8], Str] {
  let bc: Vec[UInt8] = m.boot_code;
  if bc.len() != _MBR_BOOT_BYTES { return _err_bytes("mbr: bad boot code"); }
  let da: Vec[UInt8] = m.disk_area;
  if da.len() != _MBR_DISK_AREA_BYTES { return _err_bytes("mbr: bad disk area"); }
  if !_vecs_equal(m) { return _err_bytes("mbr: entry vector mismatch"); }
  let n: Int = _vecs_min(m);
  if n > _MBR_ENTRY_SLOTS { return _err_bytes("mbr: bad entry count"); }
  var i = 0;
  while i < n {
    let flag: Int = m.boot_flags[i];
    if flag != _MBR_FLAG_INACTIVE {
      if flag != _MBR_FLAG_ACTIVE { return _err_bytes("mbr: bad boot flag"); }
    }
    let ty: Int = m.types[i];
    if ty < 0 { return _err_bytes("mbr: bad entry type"); }
    if ty > _MBR_TYPE_BYTE_MAX { return _err_bytes("mbr: bad entry type"); }
    let ls: Int = m.lba_starts[i];
    let lc: Int = m.lba_counts[i];
    if ty == _MBR_TYPE_UNUSED {
      if ls != 0 { return _err_bytes("mbr: unused entry not zero"); }
      if lc != 0 { return _err_bytes("mbr: unused entry not zero"); }
    }
    let sc: Int = m.start_chs[i];
    if sc < 0 { return _err_bytes("mbr: bad CHS"); }
    if sc > _MBR_CHS_MAX { return _err_bytes("mbr: bad CHS"); }
    let ec: Int = m.end_chs[i];
    if ec < 0 { return _err_bytes("mbr: bad CHS"); }
    if ec > _MBR_CHS_MAX { return _err_bytes("mbr: bad CHS"); }
    if ls < 0 { return _err_bytes("mbr: bad LBA"); }
    if ls > _MBR_U32_MAX { return _err_bytes("mbr: bad LBA"); }
    if lc < 0 { return _err_bytes("mbr: bad LBA"); }
    if lc > _MBR_U32_MAX { return _err_bytes("mbr: bad LBA"); }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, &bc);
  _push_bytes(&mut out, &da);
  i = 0;
  while i < _MBR_ENTRY_SLOTS {
    if i < n {
      out.push(m.boot_flags[i] as UInt8);
      _push_chs(&mut out, m.start_chs[i]);
      out.push(m.types[i] as UInt8);
      _push_chs(&mut out, m.end_chs[i]);
      _push_le32(&mut out, m.lba_starts[i]);
      _push_le32(&mut out, m.lba_counts[i]);
    } else {
      _push_zero(&mut out, _MBR_ENTRY_BYTES);
    }
    i = i + 1;
  }
  out.push(_MBR_SIG_A as UInt8);
  out.push(_MBR_SIG_B as UInt8);
  return _ok_bytes(out);
}
