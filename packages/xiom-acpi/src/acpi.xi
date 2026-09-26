// XIOM -- xiom.acpi: ACPI table-layer codec (RSDP, SDT header, RSDT/XSDT chains)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.acpi placeholder.
//
// ACPI's table layer is little-endian: the RSDP ("RSD PTR ", revision 0/2),
// the 36-byte System Description Table (SDT) header shared by every table,
// and the RSDT (u32 entries) / XSDT (u64 entries) arrays that chain the
// tables together. This module:
//   * parses and validates an RSDP (`acpi_rsdp_parse`), checking the
//     signature, the base checksum, the revision and (revision 2) the length
//     and the extended checksum;
//   * walks an RSDT/XSDT chain over a caller-supplied buffer
//     (`acpi_walk_rsdt`, `acpi_walk_xsdt`, `acpi_tables_from_rsdp`),
//     resolving every nonzero entry to a validated span: 4-byte alignment,
//     36-byte header inside the buffer, printable signature, length >= 36,
//     length inside the buffer and a valid table checksum;
//   * stores the chain as flat parallel vectors (no Vec[StructType]) and
//     exposes count/offset/length/revision/signature/OEM-ID accessors plus
//     first-match signature lookup;
//   * builds canonical tables, RSDT/XSDT arrays and RSDPs
//     (`acpi_build_table`, `acpi_build_rsdt`, `acpi_build_xsdt`,
//     `acpi_build_rsdp`), computing every checksum.
//
// Documented policies:
//   * zero entries (address 0) in an RSDT/XSDT are skipped; they neither
//     add a table nor terminate the walk, which always runs to the end of
//     the entry area;
//   * table addresses must be 4-byte aligned (checked for the root and for
//     every entry);
//   * duplicate signatures are tolerated: the chain stores every resolved
//     table in walk order and `acpi_find_table` returns the first match;
//   * u64 values above 2^63-1 are held as the same signed two's-complement
//     Int bit pattern (the xiom.msgpack convention); such an XSDT entry is
//     negative and is therefore reported as an out-of-range address;
//   * text fields written by the builders are printable ASCII, space-padded
//     to their field width, and the builders reject anything longer or
//     non-printable.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * all little-endian extraction/packing is arithmetic (modulo/division)
//     because `& 0xFF` on operands with bit 31 set miscompiles in this
//     compiler; this form is exact for negative two's-complement values.
//   * every byte read from a Vec[UInt8] is widened with `(b as Int) & 0xFF`
//     before entering Int arithmetic.
//   * every push on one parallel vector is mirrored on all its siblings.
//   * Str values coming out of a Vec are never compared with `==` (BUG 17
//     discipline); signature and text fields are compared byte by byte.

module xiom.acpi

use xiom.string;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Smallest valid RSDP length (revision 0).
pub const ACPI_RSDP_MIN_LEN: Int = 20;
/// Length of a revision 2 RSDP.
pub const ACPI_RSDP_REV2_LEN: Int = 36;
/// Length of every SDT header.
pub const ACPI_SDT_HEADER_LEN: Int = 36;
/// Packed signature of the RSDT ("RSDT" as a big-endian u32).
pub const ACPI_RSDT_SIG: Int = 1381188692;
/// Packed signature of the XSDT ("XSDT" as a big-endian u32).
pub const ACPI_XSDT_SIG: Int = 1481851988;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed Root System Description Pointer. `oem_id` holds the six raw OEMID
/// bytes; `length` is 20 for revision 0 and the stored length field for
/// revision 2; `xsdt_address` is 0 for revision 0.
pub type AcpiRsdp = {
  revision: Int;
  length: Int;
  rsdt_address: Int;
  xsdt_address: Int;
  oem_id: Vec[UInt8];
}

/// Flat RSDT/XSDT walk result: one entry per resolved table, in walk order.
/// The parallel vectors always have equal lengths; `table_offsets` are
/// absolute offsets into the walked buffer, `table_sigs` are packed
/// signatures and `table_lengths`/`table_revisions` copy the header fields.
/// Fields are implementation details; callers should go through the free
/// functions below.
pub type AcpiTableSet = {
  table_offsets: Vec[Int];
  table_lengths: Vec[Int];
  table_revisions: Vec[Int];
  table_sigs: Vec[Int];
}

// Internal descriptor for one resolved table.
type AcpiTableDesc = {
  offset: Int;
  length: Int;
  revision: Int;
  sig: Int;
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[AcpiRsdp, Str].
fn _ok_rsdp(v: AcpiRsdp) -> Result[AcpiRsdp, Str] {
  return Ok(v);
}

// Err(m) for Result[AcpiRsdp, Str].
fn _err_rsdp(m: Str) -> Result[AcpiRsdp, Str] {
  return Err(m);
}

// Ok(v) for Result[AcpiTableSet, Str].
fn _ok_set(v: AcpiTableSet) -> Result[AcpiTableSet, Str] {
  return Ok(v);
}

// Err(m) for Result[AcpiTableSet, Str].
fn _err_set(m: Str) -> Result[AcpiTableSet, Str] {
  return Err(m);
}

// Ok(v) for Result[AcpiTableDesc, Str].
fn _ok_desc(v: AcpiTableDesc) -> Result[AcpiTableDesc, Str] {
  return Ok(v);
}

// Err(m) for Result[AcpiTableDesc, Str].
fn _err_desc(m: Str) -> Result[AcpiTableDesc, Str] {
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
  let b: UInt8 = data[pos];
  return (b as Int) & 0xFF;
}

// Unsigned little-endian Int of the `size` bytes at `pos` (1..8 bytes;
// 8-byte values above 2^63-1 wrap to the same two's-complement bit
// pattern). The caller guarantees pos + size <= data.len().
fn _read_le(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var shift: Int = 1;
  var i = 0;
  while i < size {
    v = v + _byte(data, pos + i) * shift;
    shift = shift * 256;
    i = i + 1;
  }
  return v;
}

// Byte `shift_bytes` above the least significant byte of `v` (0 = LSB).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3, and this form is exact for negative two's-complement values.
fn _byte_of(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in little-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_of(v, i));
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

// Sum of data[offset, offset + length) modulo 256, or -1 when the range
// does not fit the buffer.
fn _sum8(data: &Vec[UInt8], offset: Int, length: Int) -> Int {
  if offset < 0 || length < 0 {
    return -1;
  }
  if offset > data.len() - length {
    return -1;
  }
  var s: Int = 0;
  var i = 0;
  while i < length {
    s = s + _byte(data, offset + i);
    i = i + 1;
  }
  return s % 256;
}

// True when `b` (0..255) is a printable ASCII byte (0x20..0x7e).
fn _b_printable(b: Int) -> Bool {
  return b >= 32 && b <= 126;
}

// True when data[offset, offset + length) exists and is all printable
// ASCII.
fn _range_printable(data: &Vec[UInt8], offset: Int, length: Int) -> Bool {
  if offset < 0 || length < 0 {
    return false;
  }
  if offset > data.len() - length {
    return false;
  }
  var i = 0;
  while i < length {
    if !_b_printable(_byte(data, offset + i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the bytes at `offset` equal the bytes of `s`.
fn _range_eq_str(data: &Vec[UInt8], offset: Int, s: Str) -> Bool {
  let n = s.len();
  if offset < 0 || n < 0 {
    return false;
  }
  if offset > data.len() - n {
    return false;
  }
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if _byte(data, offset + i) != ((b as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Packed big-endian signature of the four bytes at `offset`.
fn _sig_packed(data: &Vec[UInt8], offset: Int) -> Int {
  return _byte(data, offset) * 16777216 + _byte(data, offset + 1) * 65536 + _byte(data, offset + 2) * 256 + _byte(data, offset + 3);
}

// Copy data[offset, offset + length) into a fresh vector; the caller has
// already proven the range fits.
fn _copy_range(data: &Vec[UInt8], offset: Int, length: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < length {
    out.push(data[offset + i]);
    i = i + 1;
  }
  return out;
}

// ------------------------------------------------------------------
//  Validation helpers shared by the parser and the chain walker
// ------------------------------------------------------------------

// True when `s` fits `width` and every byte is printable ASCII.
fn _text_ok(s: Str, width: Int) -> Bool {
  let n = s.len();
  if n > width {
    return false;
  }
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if !_b_printable((b as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly four printable ASCII characters.
fn _sig_text_ok(s: Str) -> Bool {
  if s.len() != 4 {
    return false;
  }
  return _text_ok(s, 4);
}

// First text-field error for a table builder, or "" when all are valid.
fn _table_text_err(sig: Str, oem_id: Str, oem_table_id: Str, creator_id: Str) -> Str {
  if !_sig_text_ok(sig) {
    return "acpi: bad signature text";
  }
  if !_text_ok(oem_id, 6) {
    return "acpi: bad oem id text";
  }
  if !_text_ok(oem_table_id, 8) {
    return "acpi: bad oem table id text";
  }
  if !_text_ok(creator_id, 4) {
    return "acpi: bad creator id text";
  }
  return "";
}

// Append `s` and then spaces up to `width` bytes. The caller has already
// validated that s.len() <= width and that every byte is printable.
fn _push_text_field(out: &mut Vec[UInt8], s: Str, width: Int) {
  var i = 0;
  let n = s.len();
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  while i < width {
    out.push(32 as UInt8);
    i = i + 1;
  }
}

// Resolve a candidate table address inside `data`: alignment 4, 36-byte
// header inside the buffer, printable signature, length >= 36 inside the
// buffer, checksum over the declared length. Returns the descriptor used
// by the walkers.
fn _resolve_table(data: &Vec[UInt8], addr: Int) -> Result[AcpiTableDesc, Str] {
  if addr < 0 {
    return _err_desc("acpi: table address out of range");
  }
  if addr % 4 != 0 {
    return _err_desc("acpi: table address not aligned");
  }
  if addr > data.len() - ACPI_SDT_HEADER_LEN {
    return _err_desc("acpi: table header out of range");
  }
  if !_range_printable(data, addr, 4) {
    return _err_desc("acpi: table signature not printable");
  }
  let length: Int = _read_le(data, addr + 4, 4);
  if length < ACPI_SDT_HEADER_LEN || length > data.len() - addr {
    return _err_desc("acpi: table length out of range");
  }
  if _sum8(data, addr, length) != 0 {
    return _err_desc("acpi: bad table checksum");
  }
  let rev: Int = _byte(data, addr + 8);
  let sig: Int = _sig_packed(data, addr);
  return _ok_desc(AcpiTableDesc{ offset: addr; length: length; revision: rev; sig: sig; });
}

// --------------------------------------------------
//  RSDP and table-chain entry points
// --------------------------------------------------

/// Parse and validate a Root System Description Pointer at offset 0 of
/// `data`.
///
/// Validation order: buffer length (>= 20), signature `"RSD PTR "`, base
/// checksum (bytes 0..20 sum to 0 mod 256), revision (0 or 2), OEMID
/// printability, and for revision 2 the stored length (>= 36, inside the
/// buffer) and the extended checksum (bytes 20..length sum to 0 mod 256).
/// The returned `oem_id` is a copy of the six raw OEMID bytes.
///
/// Errors: `acpi: buffer too short`, `acpi: bad rsdp signature`,
/// `acpi: bad rsdp checksum`, `acpi: unsupported rsdp revision`,
/// `acpi: rsdp oem id not printable`, `acpi: bad rsdp length`,
/// `acpi: bad rsdp extended checksum`.
/// Complexity: O(1) plus O(length) for the extended checksum.
pub fn acpi_rsdp_parse(data: &Vec[UInt8]) -> Result[AcpiRsdp, Str] {
  if data.len() < ACPI_RSDP_MIN_LEN {
    return _err_rsdp("acpi: buffer too short");
  }
  if !_range_eq_str(data, 0, "RSD PTR ") {
    return _err_rsdp("acpi: bad rsdp signature");
  }
  if _sum8(data, 0, ACPI_RSDP_MIN_LEN) != 0 {
    return _err_rsdp("acpi: bad rsdp checksum");
  }
  let revision: Int = _byte(data, 15);
  if revision != 0 && revision != 2 {
    return _err_rsdp("acpi: unsupported rsdp revision");
  }
  if !_range_printable(data, 9, 6) {
    return _err_rsdp("acpi: rsdp oem id not printable");
  }
  let rsdt: Int = _read_le(data, 16, 4);
  var oem = Vec[UInt8].new();
  var k = 0;
  while k < 6 {
    oem.push(data[9 + k]);
    k = k + 1;
  }
  if revision == 0 {
    return _ok_rsdp(AcpiRsdp{
      revision: 0;
      length: ACPI_RSDP_MIN_LEN;
      rsdt_address: rsdt;
      xsdt_address: 0;
      oem_id: oem;
    });
  }
  if data.len() < ACPI_RSDP_REV2_LEN {
    return _err_rsdp("acpi: bad rsdp length");
  }
  let length: Int = _read_le(data, 20, 4);
  if length < ACPI_RSDP_REV2_LEN || length > data.len() {
    return _err_rsdp("acpi: bad rsdp length");
  }
  if _sum8(data, 20, length - 20) != 0 {
    return _err_rsdp("acpi: bad rsdp extended checksum");
  }
  let xsdt: Int = _read_le(data, 24, 8);
  return _ok_rsdp(AcpiRsdp{
    revision: 2;
    length: length;
    rsdt_address: rsdt;
    xsdt_address: xsdt;
    oem_id: oem;
  });
}

/// RSDP revision (`0` or `2`).
/// Complexity: O(1).
pub fn acpi_rsdp_revision(r: &AcpiRsdp) -> Int {
  return r.revision;
}

/// RSDP length: 20 for revision 0, the stored length field for revision 2.
/// Complexity: O(1).
pub fn acpi_rsdp_length(r: &AcpiRsdp) -> Int {
  return r.length;
}

/// RSDT address (u32) from the RSDP.
/// Complexity: O(1).
pub fn acpi_rsdp_rsdt_address(r: &AcpiRsdp) -> Int {
  return r.rsdt_address;
}

/// XSDT address (u64, bit pattern) from the RSDP; 0 for revision 0.
/// Complexity: O(1).
pub fn acpi_rsdp_xsdt_address(r: &AcpiRsdp) -> Int {
  return r.xsdt_address;
}

/// Copy of the six raw RSDP OEMID bytes.
/// Complexity: O(1).
pub fn acpi_rsdp_oem_id(r: &AcpiRsdp) -> Vec[UInt8] {
  let v: Vec[UInt8] = r.oem_id;
  return v;
}

/// Walk an RSDT rooted at `offset`: the root must be a valid table with the
/// "RSDT" signature and an entry area whose length is a multiple of 4.
/// Every nonzero u32 entry is resolved to a validated table; zero entries
/// are skipped and the walk continues (documented zero-entry policy).
///
/// Errors: the `_resolve_table` catalog for the root and every entry
/// (`acpi: table address out of range`, `acpi: table address not aligned`,
/// `acpi: table header out of range`, `acpi: table signature not
/// printable`, `acpi: table length out of range`, `acpi: bad table
/// checksum`), plus `acpi: bad root signature` and
/// `acpi: rsdt length misaligned`.
/// Complexity: O(root length + entries).
pub fn acpi_walk_rsdt(data: &Vec[UInt8], offset: Int) -> Result[AcpiTableSet, Str] {
  return _walk_index(data, offset, 4, ACPI_RSDT_SIG, "acpi: rsdt length misaligned");
}

/// Walk an XSDT rooted at `offset`: the root must be a valid table with the
/// "XSDT" signature and an entry area whose length is a multiple of 8.
/// Every nonzero u64 entry is resolved to a validated table; zero entries
/// are skipped and the walk continues (documented zero-entry policy).
/// An entry above 2^63-1 is negative and reported as out of range.
///
/// Errors: the `_resolve_table` catalog for the root and every entry, plus
/// `acpi: bad root signature` and `acpi: xsdt length misaligned`.
/// Complexity: O(root length + entries).
pub fn acpi_walk_xsdt(data: &Vec[UInt8], offset: Int) -> Result[AcpiTableSet, Str] {
  return _walk_index(data, offset, 8, ACPI_XSDT_SIG, "acpi: xsdt length misaligned");
}

/// Walk the table chain selected by a parsed RSDP: revision 2 with a
/// nonzero XSDT address uses `acpi_walk_xsdt`, otherwise (including a
/// revision 2 RSDP with XSDT address 0) `acpi_walk_rsdt` on the RSDT
/// address.
///
/// Err("acpi: no table root") when the selected address is zero, plus
/// every walker error.
/// Complexity: O(root length + entries).
pub fn acpi_tables_from_rsdp(data: &Vec[UInt8], r: &AcpiRsdp) -> Result[AcpiTableSet, Str] {
  let rev: Int = r.revision;
  let xsdt: Int = r.xsdt_address;
  if rev == 2 && xsdt > 0 {
    return acpi_walk_xsdt(data, xsdt);
  }
  let rsdt: Int = r.rsdt_address;
  if rsdt <= 0 {
    return _err_set("acpi: no table root");
  }
  return acpi_walk_rsdt(data, rsdt);
}

// Shared RSDT/XSDT walk: resolve the root, check its signature, split the
// entry area and resolve every nonzero entry, mirroring all four parallel
// vectors on each push.
fn _walk_index(data: &Vec[UInt8], offset: Int, entry_size: Int, want_sig: Int, misaligned_err: Str) -> Result[AcpiTableSet, Str] {
  let rr = _resolve_table(data, offset);
  if !rr.is_ok {
    return _err_set(rr.error);
  }
  let root: AcpiTableDesc = rr.value;
  let rsig: Int = root.sig;
  if rsig != want_sig {
    return _err_set("acpi: bad root signature");
  }
  let root_len: Int = root.length;
  let area: Int = root_len - ACPI_SDT_HEADER_LEN;
  if area % entry_size != 0 {
    return _err_set(misaligned_err);
  }
  let count: Int = area / entry_size;
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  var revisions = Vec[Int].new();
  var sigs = Vec[Int].new();
  var i = 0;
  while i < count {
    let epos: Int = offset + ACPI_SDT_HEADER_LEN + i * entry_size;
    let addr: Int = _read_le(data, epos, entry_size);
    if addr != 0 {
      let er = _resolve_table(data, addr);
      if !er.is_ok {
        return _err_set(er.error);
      }
      let d: AcpiTableDesc = er.value;
      let dof: Int = d.offset;
      let dln: Int = d.length;
      let drv: Int = d.revision;
      let dsg: Int = d.sig;
      offsets.push(dof);
      lengths.push(dln);
      revisions.push(drv);
      sigs.push(dsg);
    }
    i = i + 1;
  }
  return _ok_set(AcpiTableSet{
    table_offsets: offsets;
    table_lengths: lengths;
    table_revisions: revisions;
    table_sigs: sigs;
  });
}

// --------------------------------------------------
//  Checksum helpers
// --------------------------------------------------

/// Sum of data[offset, offset + length) modulo 256, or -1 when the range
/// does not fit the buffer.
/// Complexity: O(length).
pub fn acpi_sum8(data: &Vec[UInt8], offset: Int, length: Int) -> Int {
  return _sum8(data, offset, length);
}

/// True when data[offset, offset + length) exists and its bytes sum to 0
/// modulo 256, i.e. the range carries a valid ACPI checksum byte. This is
/// the verify helper used for the RSDP base checksum, the RSDP extended
/// checksum and every SDT header checksum.
/// Complexity: O(length).
pub fn acpi_checksum_valid(data: &Vec[UInt8], offset: Int, length: Int) -> Bool {
  return _sum8(data, offset, length) == 0;
}

/// True when data[offset, offset + length) exists and every byte is
/// printable ASCII (0x20..0x7e).
/// Complexity: O(length).
pub fn acpi_range_printable(data: &Vec[UInt8], offset: Int, length: Int) -> Bool {
  return _range_printable(data, offset, length);
}

/// Packed big-endian u32 of a four-character printable signature
/// ("FACP" is 1178682192), or -1 when `s` is not exactly four printable
/// ASCII characters. Printable signatures never set bit 31.
/// Complexity: O(1).
pub fn acpi_signature_value(s: Str) -> Int {
  if s.len() != 4 {
    return -1;
  }
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    let b: UInt8 = string.byte_at(s, i);
    let bv: Int = (b as Int) & 0xFF;
    if !_b_printable(bv) {
      return -1;
    }
    v = v * 256 + bv;
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Table-chain accessors
// --------------------------------------------------

/// Number of resolved tables in the chain.
/// Complexity: O(1).
pub fn acpi_table_count(t: &AcpiTableSet) -> Int {
  return t.table_offsets.len();
}

/// Absolute buffer offset of table `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn acpi_table_offset(t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_offsets.len() {
    return -1;
  }
  let v: Int = t.table_offsets[i];
  return v;
}

/// Declared length of table `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn acpi_table_length(t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_lengths.len() {
    return -1;
  }
  let v: Int = t.table_lengths[i];
  return v;
}

/// Header revision of table `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn acpi_table_revision(t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_revisions.len() {
    return -1;
  }
  let v: Int = t.table_revisions[i];
  return v;
}

/// Packed signature of table `i`, or -1 when out of range. Compare against
/// `acpi_signature_value("FACP")` or use `acpi_find_table`.
/// Complexity: O(1).
pub fn acpi_table_signature(t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_sigs.len() {
    return -1;
  }
  let v: Int = t.table_sigs[i];
  return v;
}

/// First table index whose packed signature equals `sig`, or -1 when `sig`
/// is not a four-character printable signature or no table matches.
/// Duplicate signatures are tolerated: the first match in walk order wins.
/// Complexity: O(tables).
pub fn acpi_find_table(t: &AcpiTableSet, sig: Str) -> Int {
  let want: Int = acpi_signature_value(sig);
  if want < 0 {
    return -1;
  }
  var i = 0;
  while i < t.table_sigs.len() {
    let s: Int = t.table_sigs[i];
    if s == want {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Copy `field_len` bytes starting `field_off` bytes into the header of
// table `i`. Err("acpi: index out of range") for a bad index,
// Err("acpi: table span out of bounds") when the recorded span does not
// fit `data`.
fn _table_field(data: &Vec[UInt8], t: &AcpiTableSet, i: Int, field_off: Int, field_len: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= t.table_offsets.len() {
    return _err_bytes("acpi: index out of range");
  }
  let off: Int = t.table_offsets[i];
  if off < 0 || field_off < 0 || field_len < 0 {
    return _err_bytes("acpi: table span out of bounds");
  }
  if field_off > data.len() - off - field_len {
    return _err_bytes("acpi: table span out of bounds");
  }
  return _ok_bytes(_copy_range(data, off + field_off, field_len));
}

/// Copy of the four signature bytes of table `i`.
/// Errors: `acpi: index out of range`, `acpi: table span out of bounds`.
/// Complexity: O(1).
pub fn acpi_table_signature_bytes(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str] {
  return _table_field(data, t, i, 0, 4);
}

/// Copy of the six OEMID bytes of table `i` (header offset 10).
/// Errors: `acpi: index out of range`, `acpi: table span out of bounds`.
/// Complexity: O(1).
pub fn acpi_table_oem_id(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str] {
  return _table_field(data, t, i, 10, 6);
}

/// Copy of the eight OEM table ID bytes of table `i` (header offset 16).
/// Errors: `acpi: index out of range`, `acpi: table span out of bounds`.
/// Complexity: O(1).
pub fn acpi_table_oem_table_id(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str] {
  return _table_field(data, t, i, 16, 8);
}

/// Copy of the four creator ID bytes of table `i` (header offset 28).
/// Errors: `acpi: index out of range`, `acpi: table span out of bounds`.
/// Complexity: O(1).
pub fn acpi_table_creator_id(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str] {
  return _table_field(data, t, i, 28, 4);
}

/// OEM revision (u32, header offset 24) of table `i`, or -1 when the index
/// is out of range or the span does not fit `data`.
/// Complexity: O(1).
pub fn acpi_table_oem_revision(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_offsets.len() {
    return -1;
  }
  let off: Int = t.table_offsets[i];
  if off < 0 || off > data.len() - 28 {
    return -1;
  }
  return _read_le(data, off + 24, 4);
}

/// Creator revision (u32, header offset 32) of table `i`, or -1 when the
/// index is out of range or the span does not fit `data`.
/// Complexity: O(1).
pub fn acpi_table_creator_revision(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_offsets.len() {
    return -1;
  }
  let off: Int = t.table_offsets[i];
  if off < 0 || off > data.len() - 32 {
    return -1;
  }
  return _read_le(data, off + 32, 4);
}

/// Absolute offset of the body of table `i` (header offset 36), or -1 when
/// the index is out of range or the recorded span does not fit `data`.
/// Complexity: O(1).
pub fn acpi_table_body_offset(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_offsets.len() {
    return -1;
  }
  let off: Int = t.table_offsets[i];
  let len: Int = t.table_lengths[i];
  if off < 0 || len < ACPI_SDT_HEADER_LEN {
    return -1;
  }
  if off > data.len() - len {
    return -1;
  }
  return off + ACPI_SDT_HEADER_LEN;
}

/// Declared body length of table `i` (length - 36), or -1 when the index
/// is out of range or the stored length is below 36.
/// Complexity: O(1).
pub fn acpi_table_body_length(t: &AcpiTableSet, i: Int) -> Int {
  if i < 0 || i >= t.table_lengths.len() {
    return -1;
  }
  let len: Int = t.table_lengths[i];
  if len < ACPI_SDT_HEADER_LEN {
    return -1;
  }
  return len - ACPI_SDT_HEADER_LEN;
}

/// True when the recorded offset/length span of table `i` fits `data`.
/// Complexity: O(1).
pub fn acpi_table_span_ok(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Bool {
  if i < 0 || i >= t.table_offsets.len() {
    return false;
  }
  let off: Int = t.table_offsets[i];
  let len: Int = t.table_lengths[i];
  if off < 0 || len < ACPI_SDT_HEADER_LEN {
    return false;
  }
  return off <= data.len() - len;
}

/// Copy of the body bytes of table `i` (everything after the 36-byte
/// header).
/// Errors: `acpi: index out of range`, `acpi: table span out of bounds`.
/// Complexity: O(body length).
pub fn acpi_table_body(data: &Vec[UInt8], t: &AcpiTableSet, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= t.table_offsets.len() {
    return _err_bytes("acpi: index out of range");
  }
  let off: Int = t.table_offsets[i];
  let len: Int = t.table_lengths[i];
  if off < 0 || len < ACPI_SDT_HEADER_LEN {
    return _err_bytes("acpi: table span out of bounds");
  }
  if off > data.len() - len {
    return _err_bytes("acpi: table span out of bounds");
  }
  return _ok_bytes(_copy_range(data, off + ACPI_SDT_HEADER_LEN, len - ACPI_SDT_HEADER_LEN));
}

// --------------------------------------------------
//  Builders (canonical output)
// --------------------------------------------------

/// Build a canonical SDT: 36-byte header plus `body` verbatim.
///
/// `sig` must be exactly four printable ASCII characters; `oem_id`
/// (max 6), `oem_table_id` (max 8) and `creator_id` (max 4) must be
/// printable ASCII and are space-padded to their field width; `revision`
/// must be 0..255; the OEM and creator revisions must be 0..4294967295.
/// The length field is 36 + body.len(), and the header checksum is
/// computed so that every byte of the table sums to 0 modulo 256.
///
/// Errors: `acpi: bad signature text`, `acpi: bad oem id text`,
/// `acpi: bad oem table id text`, `acpi: bad creator id text`,
/// `acpi: bad revision`, `acpi: bad oem revision`,
/// `acpi: bad creator revision`, `acpi: table too large`.
/// Complexity: O(body length).
pub fn acpi_build_table(sig: Str, revision: Int, oem_id: Str, oem_table_id: Str, oem_revision: Int, creator_id: Str, creator_revision: Int, body: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let te = _table_text_err(sig, oem_id, oem_table_id, creator_id);
  if te.len() > 0 {
    return _err_bytes(te);
  }
  if revision < 0 || revision > 255 {
    return _err_bytes("acpi: bad revision");
  }
  if oem_revision < 0 || oem_revision > 4294967295 {
    return _err_bytes("acpi: bad oem revision");
  }
  if creator_revision < 0 || creator_revision > 4294967295 {
    return _err_bytes("acpi: bad creator revision");
  }
  let blen: Int = body.len();
  if blen > 4294967259 {
    return _err_bytes("acpi: table too large");
  }
  var tmp = Vec[UInt8].new();
  _push_text_field(&mut tmp, sig, 4);
  _push_le(&mut tmp, ACPI_SDT_HEADER_LEN + blen, 4);
  tmp.push(revision as UInt8);
  tmp.push(0 as UInt8);
  _push_text_field(&mut tmp, oem_id, 6);
  _push_text_field(&mut tmp, oem_table_id, 8);
  _push_le(&mut tmp, oem_revision, 4);
  _push_text_field(&mut tmp, creator_id, 4);
  _push_le(&mut tmp, creator_revision, 4);
  _push_bytes(&mut tmp, body);
  let sum: Int = _sum8(&tmp, 0, tmp.len());
  let checksum: Int = (256 - sum) % 256;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < tmp.len() {
    if i == 9 {
      out.push(checksum as UInt8);
    } else {
      let b: UInt8 = tmp[i];
      out.push(b);
    }
    i = i + 1;
  }
  return _ok_bytes(out);
}

// Build an RSDT/XSDT body of little-endian entries and delegate the header
// to acpi_build_table. Index tables are emitted with revision 1 and OEM
// revision 1.
fn _build_index_table(sig: Str, entry_size: Int, entries: &Vec[Int], oem_id: Str, oem_table_id: Str, creator_id: Str, creator_revision: Int) -> Result[Vec[UInt8], Str] {
  let te = _table_text_err(sig, oem_id, oem_table_id, creator_id);
  if te.len() > 0 {
    return _err_bytes(te);
  }
  var body = Vec[UInt8].new();
  var i = 0;
  while i < entries.len() {
    let e: Int = entries[i];
    if e < 0 {
      return _err_bytes("acpi: entry address out of range");
    }
    if entry_size == 4 && e > 4294967295 {
      return _err_bytes("acpi: entry address out of range");
    }
    _push_le(&mut body, e, entry_size);
    i = i + 1;
  }
  return acpi_build_table(sig, 1, oem_id, oem_table_id, 1, creator_id, creator_revision, &body);
}

/// Build a canonical RSDT (signature "RSDT", revision 1, OEM revision 1)
/// whose body is the u32 little-endian `entries` in caller order.
///
/// Errors: the text errors of `acpi_build_table` plus
/// `acpi: entry address out of range` when an entry is negative or above
/// 4294967295. Text errors are reported before entry errors.
/// Complexity: O(entries).
pub fn acpi_build_rsdt(entries: &Vec[Int], oem_id: Str, oem_table_id: Str, creator_id: Str, creator_revision: Int) -> Result[Vec[UInt8], Str] {
  return _build_index_table("RSDT", 4, entries, oem_id, oem_table_id, creator_id, creator_revision);
}

/// Build a canonical XSDT (signature "XSDT", revision 1, OEM revision 1)
/// whose body is the u64 little-endian `entries` in caller order.
///
/// Errors: the text errors of `acpi_build_table` plus
/// `acpi: entry address out of range` when an entry is negative. Text
/// errors are reported before entry errors.
/// Complexity: O(entries).
pub fn acpi_build_xsdt(entries: &Vec[Int], oem_id: Str, oem_table_id: Str, creator_id: Str, creator_revision: Int) -> Result[Vec[UInt8], Str] {
  return _build_index_table("XSDT", 8, entries, oem_id, oem_table_id, creator_id, creator_revision);
}

/// Build a canonical RSDP: revision 0 (20 bytes) or revision 2 (36 bytes,
/// length field 36). `rsdt_address` is a u32; `xsdt_address` is a u64 and
/// must be 0 for revision 0. `oem_id` (max 6) must be printable ASCII and
/// is space-padded. Both checksums are computed (revision 2 adds the
/// extended checksum over bytes 20..36).
///
/// Errors: `acpi: rsdp revision must be 0 or 2`, `acpi: bad oem id text`,
/// `acpi: rsdp address out of range` (negative address, or an RSDT address
/// above 4294967295), `acpi: rsdp revision 0 has no xsdt`.
/// Complexity: O(1).
pub fn acpi_build_rsdp(revision: Int, rsdt_address: Int, xsdt_address: Int, oem_id: Str) -> Result[Vec[UInt8], Str] {
  if revision != 0 && revision != 2 {
    return _err_bytes("acpi: rsdp revision must be 0 or 2");
  }
  if !_text_ok(oem_id, 6) {
    return _err_bytes("acpi: bad oem id text");
  }
  if rsdt_address < 0 || rsdt_address > 4294967295 {
    return _err_bytes("acpi: rsdp address out of range");
  }
  if xsdt_address < 0 {
    return _err_bytes("acpi: rsdp address out of range");
  }
  if revision == 0 && xsdt_address != 0 {
    return _err_bytes("acpi: rsdp revision 0 has no xsdt");
  }
  var tmp = Vec[UInt8].new();
  _push_text_field(&mut tmp, "RSD PTR ", 8);
  tmp.push(0 as UInt8);
  _push_text_field(&mut tmp, oem_id, 6);
  tmp.push(revision as UInt8);
  _push_le(&mut tmp, rsdt_address, 4);
  if revision == 2 {
    _push_le(&mut tmp, ACPI_RSDP_REV2_LEN, 4);
    _push_le(&mut tmp, xsdt_address, 8);
    tmp.push(0 as UInt8);
    tmp.push(0 as UInt8);
    tmp.push(0 as UInt8);
    tmp.push(0 as UInt8);
  }
  let base_sum: Int = _sum8(&tmp, 0, ACPI_RSDP_MIN_LEN);
  let base_ck: Int = (256 - base_sum) % 256;
  var ext_ck: Int = 0;
  if revision == 2 {
    let ext_sum: Int = _sum8(&tmp, ACPI_RSDP_MIN_LEN, 16);
    ext_ck = (256 - ext_sum) % 256;
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < tmp.len() {
    if i == 8 {
      out.push(base_ck as UInt8);
    } else if i == 32 {
      out.push(ext_ck as UInt8);
    } else {
      let b: UInt8 = tmp[i];
      out.push(b);
    }
    i = i + 1;
  }
  return _ok_bytes(out);
}
