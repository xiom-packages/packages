// XIOM -- xiom.smbios: SMBIOS/DMI entry-point and structure-table codec
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.smbios placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) codec for the documented SMBIOS/DMI subset: the
// 32-bit entry point (anchor "_SM_", checksum, length 0x1F, major/minor,
// max structure size, entry revision, intermediate "_DMI_" anchor plus
// its checksum, structure table length/address, structure count and BCD
// revision), the 64-bit entry point (anchor "_SM3_", checksum, length
// 0x18, major/minor, docrev, entry revision, table maximum size and a
// 64-bit table address) with a documented preference rule, and the
// structure table stream (type, length, handle, formatted area, and a
// double-NUL-terminated string set).
//
// Documented structure types with field accessors: 0 BIOS Information,
// 1 System Information (including the 16 raw UUID bytes), 2 Baseboard,
// 3 Chassis (chassis type byte plus a documented name table), 4 Processor,
// 16 Physical Memory Array (capacity) and 17 Memory Device
// (size/speed/type/manufacturer string index). Type 127 ends the walk.
// Every other type is preserved with its raw formatted span and string
// spans; nothing outside the documented subset is decoded.
//
// Documented non-goals: no vendor/OEM extension decoding, no DMI-to-sysfs
// mapping, no memory-device type table, no UUID string formatting and no
// address-to-offset translation (the table address is used as an offset
// into the buffer handed to smbios_parse).
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing struct payloads such as Result[SmbiosTable, Str]
//     directly in other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(b as Int) & 0xFF`; all little-endian extraction/packing is
//     arithmetic (multiplication/division or modulo), which is exact for
//     values with bit 31 set, where bitwise operations on such values
//     miscompile in this compiler.
//   * every Vec[Int] and Vec[Str] element read is bound to a typed local.
//   * strings are decoded with xiom.encoding.utf8_decode; the string
//     builder's to_str path is avoided because its length contract
//     aborts on a 0x00 byte and SMBIOS string sets are NUL-separated by
//     construction.
//   * every push on one parallel vector is mirrored on all its siblings;
//     the accessors re-derive and bound-check every span they use.

module xiom.smbios

use xiom.string;
use xiom.encoding;

/// Entry-point variant constant: the 32-bit "_SM_" entry point.
pub const SMBIOS_ENTRY_32: Int = 0;
/// Entry-point variant constant: the 64-bit "_SM3_" entry point.
pub const SMBIOS_ENTRY_64: Int = 1;

/// Structure type: BIOS Information.
pub const SMBIOS_TYPE_BIOS: Int = 0;
/// Structure type: System Information.
pub const SMBIOS_TYPE_SYSTEM: Int = 1;
/// Structure type: Baseboard (module) Information.
pub const SMBIOS_TYPE_BASEBOARD: Int = 2;
/// Structure type: System Enclosure or Chassis.
pub const SMBIOS_TYPE_CHASSIS: Int = 3;
/// Structure type: Processor Information.
pub const SMBIOS_TYPE_PROCESSOR: Int = 4;
/// Structure type: Physical Memory Array.
pub const SMBIOS_TYPE_MEMORY_ARRAY: Int = 16;
/// Structure type: Memory Device.
pub const SMBIOS_TYPE_MEMORY_DEVICE: Int = 17;
/// Structure type: End-of-Table. Terminates the structure walk.
pub const SMBIOS_TYPE_END_OF_TABLE: Int = 127;

/// Decoded entry point. `kind` is SMBIOS_ENTRY_32 or SMBIOS_ENTRY_64.
/// Fields not carried by a variant are 0: `docrev` and `count`/`bcd_rev`
/// are 32-bit only for `count`/`bcd_rev` and 64-bit only for `docrev`,
/// while `major`/`minor`/`revision`/`max_size`/`table_addr` exist in both
/// (`max_size` is the 32-bit max structure size or the 64-bit structure
/// table maximum size; `table_addr` is a u32 or u64 value). A table
/// address with bit 63 set is held as the same signed two's-complement
/// Int bit pattern. Fields are implementation details; callers should go
/// through the free functions below.
pub type SmbiosEntry = {
  kind: Int;
  major: Int;
  minor: Int;
  docrev: Int;
  revision: Int;
  max_size: Int;
  table_len: Int;
  table_addr: Int;
  count: Int;
  bcd_rev: Int;
}

/// Flat structure-table store. One entry per structure, in table order:
/// `types`/`lengths`/`handles` hold the 1-byte type, the 1-byte formatted
/// length (>= 4) and the little-endian 16-bit handle; `starts` is the
/// absolute offset of the structure in the buffer the store was parsed
/// from; `str_first`/`str_count` locate structure i's strings as a
/// contiguous range of the flat `str_struct`/`str_off`/`str_len` vectors
/// (so every parallel vector push is mirrored). Strings are 1-indexed;
/// `smbios_string_count` gives the number of strings. Fields are
/// implementation details; callers should go through the free functions
/// below.
pub type SmbiosTable = {
  types: Vec[Int];
  lengths: Vec[Int];
  handles: Vec[Int];
  starts: Vec[Int];
  str_first: Vec[Int];
  str_count: Vec[Int];
  str_struct: Vec[Int];
  str_off: Vec[Int];
  str_len: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[SmbiosEntry, Str].
fn _ok_entry(v: SmbiosEntry) -> Result[SmbiosEntry, Str] {
  return Ok(v);
}

// Err(m) for Result[SmbiosEntry, Str].
fn _err_entry(m: Str) -> Result[SmbiosEntry, Str] {
  return Err(m);
}

// Ok(v) for Result[SmbiosTable, Str].
fn _ok_table(v: SmbiosTable) -> Result[SmbiosTable, Str] {
  return Ok(v);
}

// Err(m) for Result[SmbiosTable, Str].
fn _err_table(m: Str) -> Result[SmbiosTable, Str] {
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
  var mult: Int = 1;
  var i = 0;
  while i < size {
    v = v + _byte(data, pos + i) * mult;
    mult = mult * 256;
    i = i + 1;
  }
  return v;
}

// Append the low `size` bytes of `v` in little-endian order. Arithmetic
// only, exact for negative two's-complement values.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var q = v;
  var i = 0;
  while i < size {
    var b = q % 256;
    if b < 0 { b = b + 256; }
    out.push(b as UInt8);
    q = (q - b) / 256;
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

// Append the bytes of `s` (upper bound 0x7F per byte; anchors only).
fn _push_ascii(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < string.str_len(s) {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// The byte that makes `data[off, off+len)` sum to 0 modulo 256. Only
// called with a sum in 0..255.
fn _checksum_byte(s: Int) -> Int {
  if s <= 0 {
    return 0;
  }
  return 256 - s;
}

// --------------------------------------------------
//  Entry-point checksums
// --------------------------------------------------

/// Sum of `data[off, off + len)` modulo 256, or -1 when the span is
/// invalid (negative `off`/`len`, or past the end of `data`). This is the
/// helper behind the four checksum predicates and the builders.
/// Complexity: O(len).
pub fn smbios_checksum8(data: &Vec[UInt8], off: Int, len: Int) -> Int {
  if off < 0 || len < 0 || off + len > data.len() {
    return -1;
  }
  var s = 0;
  var i = 0;
  while i < len {
    s = s + _byte(data, off + i);
    if s >= 256 {
      s = s - 256;
    }
    i = i + 1;
  }
  return s;
}

/// True when `data` starts with a 32-bit entry point whose 31 bytes sum
/// to 0 modulo 256. False when the buffer is shorter than 31 bytes.
/// Complexity: O(1).
pub fn smbios_entry32_checksum_ok(data: &Vec[UInt8]) -> Bool {
  return smbios_checksum8(data, 0, 31) == 0;
}

/// True when the intermediate entry point area of `data` (bytes
/// 16..31: the "_DMI_" anchor, its checksum, table length/address,
/// structure count and BCD revision) sums to 0 modulo 256. False when
/// the buffer is shorter than 31 bytes.
/// Complexity: O(1).
pub fn smbios_entry32_intermediate_checksum_ok(data: &Vec[UInt8]) -> Bool {
  return smbios_checksum8(data, 16, 15) == 0;
}

/// True when `data` starts with a 64-bit entry point whose 24 bytes sum
/// to 0 modulo 256. False when the buffer is shorter than 24 bytes.
/// Complexity: O(1).
pub fn smbios_entry64_checksum_ok(data: &Vec[UInt8]) -> Bool {
  return smbios_checksum8(data, 0, 24) == 0;
}

/// True when the preferred entry point of `data` (see smbios_entry_parse)
/// passes its own entry-point checksum. The 32-bit intermediate checksum
/// is separate (smbios_entry32_intermediate_checksum_ok). False when no
/// entry point parses.
/// Complexity: O(data.len()/16).
pub fn smbios_entry_checksum_ok(data: &Vec[UInt8]) -> Bool {
  let er = smbios_entry_parse(data);
  if !er.is_ok {
    return false;
  }
  let e: SmbiosEntry = er.value;
  if e.kind == SMBIOS_ENTRY_64 {
    return smbios_entry64_checksum_ok(data);
  }
  return smbios_entry32_checksum_ok(data);
}

// --------------------------------------------------
//  Entry-point parsing
// --------------------------------------------------

// Is the 4-byte "_SM_" anchor at `off`?
fn _anchor32(data: &Vec[UInt8], off: Int) -> Bool {
  if off < 0 || off + 4 > data.len() {
    return false;
  }
  if _byte(data, off) != 95 { return false; }
  if _byte(data, off + 1) != 83 { return false; }
  if _byte(data, off + 2) != 77 { return false; }
  return _byte(data, off + 3) == 95;
}

// Is the 5-byte "_SM3_" anchor at `off`?
fn _anchor64(data: &Vec[UInt8], off: Int) -> Bool {
  if off < 0 || off + 5 > data.len() {
    return false;
  }
  if _byte(data, off) != 95 { return false; }
  if _byte(data, off + 1) != 83 { return false; }
  if _byte(data, off + 2) != 77 { return false; }
  if _byte(data, off + 3) != 51 { return false; }
  return _byte(data, off + 4) == 95;
}

// Is the 5-byte intermediate "_DMI_" anchor at `off`?
fn _anchor_dmi(data: &Vec[UInt8], off: Int) -> Bool {
  if off < 0 || off + 5 > data.len() {
    return false;
  }
  if _byte(data, off) != 95 { return false; }
  if _byte(data, off + 1) != 68 { return false; }
  if _byte(data, off + 2) != 77 { return false; }
  if _byte(data, off + 3) != 73 { return false; }
  return _byte(data, off + 4) == 95;
}

// An all-zero entry point; fields are overwritten by the parser.
fn _entry_new() -> SmbiosEntry {
  return SmbiosEntry{
    kind: 0;
    major: 0;
    minor: 0;
    docrev: 0;
    revision: 0;
    max_size: 0;
    table_len: 0;
    table_addr: 0;
    count: 0;
    bcd_rev: 0;
  };
}

// Parse and validate the 31-byte "_SM_" entry point at `off`.
fn _entry32_at(data: &Vec[UInt8], off: Int) -> Result[SmbiosEntry, Str] {
  if off < 0 || off + 31 > data.len() {
    return _err_entry("smbios: 32-bit entry point too short");
  }
  if !_anchor32(data, off) {
    return _err_entry("smbios: bad 32-bit signature");
  }
  if _byte(data, off + 5) != 31 {
    return _err_entry("smbios: bad 32-bit entry length");
  }
  if smbios_checksum8(data, off, 31) != 0 {
    return _err_entry("smbios: bad 32-bit checksum");
  }
  if !_anchor_dmi(data, off + 16) {
    return _err_entry("smbios: bad intermediate anchor");
  }
  if smbios_checksum8(data, off + 16, 15) != 0 {
    return _err_entry("smbios: bad intermediate checksum");
  }
  var e = _entry_new();
  e.kind = SMBIOS_ENTRY_32;
  e.major = _byte(data, off + 6);
  e.minor = _byte(data, off + 7);
  e.max_size = _read_le(data, off + 8, 2);
  e.revision = _byte(data, off + 10);
  e.table_len = _read_le(data, off + 22, 2);
  e.table_addr = _read_le(data, off + 24, 4);
  e.count = _read_le(data, off + 28, 2);
  e.bcd_rev = _byte(data, off + 30);
  return _ok_entry(e);
}

// Parse and validate the 24-byte "_SM3_" entry point at `off`.
fn _entry64_at(data: &Vec[UInt8], off: Int) -> Result[SmbiosEntry, Str] {
  if off < 0 || off + 24 > data.len() {
    return _err_entry("smbios: 64-bit entry point too short");
  }
  if !_anchor64(data, off) {
    return _err_entry("smbios: bad 64-bit signature");
  }
  if _byte(data, off + 6) != 24 {
    return _err_entry("smbios: bad 64-bit entry length");
  }
  if smbios_checksum8(data, off, 24) != 0 {
    return _err_entry("smbios: bad 64-bit checksum");
  }
  var e = _entry_new();
  e.kind = SMBIOS_ENTRY_64;
  e.major = _byte(data, off + 7);
  e.minor = _byte(data, off + 8);
  e.docrev = _byte(data, off + 9);
  e.revision = _byte(data, off + 10);
  e.max_size = _read_le(data, off + 12, 4);
  e.table_addr = _read_le(data, off + 16, 8);
  return _ok_entry(e);
}

/// Parse the 32-bit entry point at offset 0 of `data`. Requires the
/// "_SM_" anchor, the 0x1F length byte, both checksums (entry point and
/// intermediate) and the "_DMI_" anchor. Err messages: `smbios: 32-bit
/// entry point too short`, `bad 32-bit signature`, `bad 32-bit entry
/// length`, `bad 32-bit checksum`, `bad intermediate anchor`, `bad
/// intermediate checksum`.
/// Complexity: O(1).
pub fn smbios_entry32_parse(data: &Vec[UInt8]) -> Result[SmbiosEntry, Str] {
  return _entry32_at(data, 0);
}

/// Parse the 64-bit entry point at offset 0 of `data`. Requires the
/// "_SM3_" anchor, the 0x18 length byte and the entry-point checksum.
/// Err messages: `smbios: 64-bit entry point too short`, `bad 64-bit
/// signature`, `bad 64-bit entry length`, `bad 64-bit checksum`.
/// Complexity: O(1).
pub fn smbios_entry64_parse(data: &Vec[UInt8]) -> Result[SmbiosEntry, Str] {
  return _entry64_at(data, 0);
}

/// Parse the preferred entry point of `data`, scanning 16-byte-aligned
/// offsets. **Preference rule:** the first aligned "_SM3_" anchor wins;
/// when it is present the 64-bit entry point is authoritative and its
/// errors propagate even if a valid "_SM_" follows. Only when no "_SM3_"
/// anchor exists is the first aligned "_SM_" anchor parsed. Neither
/// anchor yields Err("smbios: no entry point").
/// Complexity: O(data.len()/16).
pub fn smbios_entry_parse(data: &Vec[UInt8]) -> Result[SmbiosEntry, Str] {
  var off = 0;
  while off + 5 <= data.len() {
    if _anchor64(data, off) {
      return _entry64_at(data, off);
    }
    off = off + 16;
  }
  off = 0;
  while off + 4 <= data.len() {
    if _anchor32(data, off) {
      return _entry32_at(data, off);
    }
    off = off + 16;
  }
  return _err_entry("smbios: no entry point");
}

/// Number of entry-point anchors in `data`: every 16-byte-aligned offset
/// holding an "_SM3_" or "_SM_" anchor counts once. A normal image has 1
/// or 2.
/// Complexity: O(data.len()/16).
pub fn smbios_entry_points(data: &Vec[UInt8]) -> Int {
  var n = 0;
  var off = 0;
  while off + 4 <= data.len() {
    if off + 5 <= data.len() && _anchor64(data, off) {
      n = n + 1;
    } elif _anchor32(data, off) {
      n = n + 1;
    }
    off = off + 16;
  }
  return n;
}

// --------------------------------------------------
//  Entry-point accessors
// --------------------------------------------------

/// Entry-point variant: SMBIOS_ENTRY_32 or SMBIOS_ENTRY_64.
pub fn smbios_entry_kind(e: &SmbiosEntry) -> Int {
  return e.kind;
}

/// Major version of the entry point.
pub fn smbios_entry_major(e: &SmbiosEntry) -> Int {
  return e.major;
}

/// Minor version of the entry point.
pub fn smbios_entry_minor(e: &SmbiosEntry) -> Int {
  return e.minor;
}

/// Documentation revision (64-bit entry point only; 0 for "_SM_").
pub fn smbios_entry_docrev(e: &SmbiosEntry) -> Int {
  return e.docrev;
}

/// Entry point revision byte (both variants; 0 for the canonical built
/// entry points).
pub fn smbios_entry_revision(e: &SmbiosEntry) -> Int {
  return e.revision;
}

/// Max structure size ("_SM_") or structure table maximum size ("_SM3_").
pub fn smbios_entry_max_size(e: &SmbiosEntry) -> Int {
  return e.max_size;
}

/// Declared structure table length ("_SM_" only; 0 for "_SM3_").
pub fn smbios_entry_table_len(e: &SmbiosEntry) -> Int {
  return e.table_len;
}

/// Structure table address: a u32 for "_SM_", a u64 for "_SM3_" (values
/// with bit 63 set keep the same two's-complement Int bit pattern). It
/// is used as an offset into the buffer given to smbios_parse.
pub fn smbios_entry_table_addr(e: &SmbiosEntry) -> Int {
  return e.table_addr;
}

/// Declared number of structures ("_SM_" only; 0 for "_SM3_", and 0 also
/// means "unknown" on a parsed 32-bit entry point).
pub fn smbios_entry_count(e: &SmbiosEntry) -> Int {
  return e.count;
}

/// BCD revision byte ("_SM_" only; 0 for "_SM3_").
pub fn smbios_entry_bcd(e: &SmbiosEntry) -> Int {
  return e.bcd_rev;
}

// --------------------------------------------------
//  Structure-table parsing
// --------------------------------------------------

// An empty structure-table store.
fn _table_new() -> SmbiosTable {
  return SmbiosTable{
    types: Vec[Int].new();
    lengths: Vec[Int].new();
    handles: Vec[Int].new();
    starts: Vec[Int].new();
    str_first: Vec[Int].new();
    str_count: Vec[Int].new();
    str_struct: Vec[Int].new();
    str_off: Vec[Int].new();
    str_len: Vec[Int].new();
  };
}

// Walk the structure stream in data[start, end). Each structure is a
// 4-byte header, the formatted area, then a string set ending at the
// first pair of consecutive 0x00 bytes (an empty set is that pair
// alone). Stops after a type 127 structure. When `expect` > 0 the
// number of parsed structures must equal it.
fn _table_parse(data: &Vec[UInt8], start: Int, end: Int, expect: Int) -> Result[SmbiosTable, Str] {
  var t = _table_new();
  var pos = start;
  var stopped = false;
  while pos < end && !stopped {
    if pos + 4 > end {
      return _err_table("smbios: truncated structure");
    }
    let stype = _byte(data, pos);
    let length = _byte(data, pos + 1);
    if length < 4 {
      return _err_table("smbios: invalid structure length");
    }
    if pos + length > end {
      return _err_table("smbios: truncated structure");
    }
    let handle = _read_le(data, pos + 2, 2);
    let idx = t.types.len();
    var j = 0;
    while j < idx {
      let h: Int = t.handles[j];
      if h == handle {
        return _err_table("smbios: duplicate handle");
      }
      j = j + 1;
    }
    // Find the double-NUL that ends the string set.
    let sstart = pos + length;
    var pair = sstart;
    var found = false;
    while pair + 1 < end && !found {
      if _byte(data, pair) == 0 && _byte(data, pair + 1) == 0 {
        found = true;
      } else {
        pair = pair + 1;
      }
    }
    if !found {
      return _err_table("smbios: unterminated string set");
    }
    // Enumerate the strings before the pair; the NUL at `pair` is the
    // last string's terminator.
    let first = t.str_struct.len();
    var p = sstart;
    while p < pair {
      var nul = p;
      while _byte(data, nul) != 0 {
        nul = nul + 1;
      }
      t.str_struct.push(idx);
      t.str_off.push(p);
      t.str_len.push(nul - p);
      p = nul + 1;
    }
    let scount = t.str_struct.len() - first;
    t.types.push(stype);
    t.lengths.push(length);
    t.handles.push(handle);
    t.starts.push(pos);
    t.str_first.push(first);
    t.str_count.push(scount);
    if stype == SMBIOS_TYPE_END_OF_TABLE {
      stopped = true;
    }
    pos = pair + 2;
  }
  if expect > 0 && t.types.len() != expect {
    return _err_table("smbios: structure count mismatch");
  }
  return _ok_table(t);
}

/// Parse and validate a structure table held in `table` (offsets in the
/// returned store are relative to `table`).
///
/// Every structure must have a length of at least 4, a formatted area
/// inside the table and a string set terminated by a double NUL; handles
/// must be unique (documented policy: any repeated handle is an error).
/// A type 127 structure ends the walk (following bytes are ignored);
/// a table without one is accepted. Err messages: `smbios: truncated
/// structure`, `invalid structure length`, `unterminated string set`,
/// `duplicate handle`.
/// Complexity: O(table.len() + structures^2).
pub fn smbios_table_parse(table: &Vec[UInt8]) -> Result[SmbiosTable, Str] {
  return _table_parse(table, 0, table.len(), -1);
}

/// Parse a whole image: locate the preferred entry point in `data` (see
/// smbios_entry_parse), then parse the structure table it points at.
///
/// The entry point's `table_addr` is interpreted as an offset into
/// `data`. For 32-bit entry points the table spans
/// `[table_addr, table_addr + table_len)` and must fit the buffer; a
/// declared structure count above 0 must match the structures parsed (0
/// means "unknown" and skips the check). For 64-bit entry points the
/// table spans `[table_addr, end)` where `end` is the buffer end, or
/// `table_addr + max_size` when that is smaller and non-zero.
/// Err: any entry-point error, `smbios: table out of buffer`, plus every
/// smbios_table_parse error. Offsets in the returned store are absolute
/// in `data`.
/// Complexity: O(data.len() + structures^2).
pub fn smbios_parse(data: &Vec[UInt8]) -> Result[SmbiosTable, Str] {
  let er = smbios_entry_parse(data);
  if !er.is_ok {
    return _err_table(er.error);
  }
  let e: SmbiosEntry = er.value;
  let addr: Int = e.table_addr;
  if addr < 0 || addr > data.len() {
    return _err_table("smbios: table out of buffer");
  }
  if e.kind == SMBIOS_ENTRY_32 {
    let tlen: Int = e.table_len;
    if tlen < 0 || addr + tlen > data.len() {
      return _err_table("smbios: table out of buffer");
    }
    return _table_parse(data, addr, addr + tlen, e.count);
  }
  var tend = data.len();
  let msize: Int = e.max_size;
  if msize > 0 && addr + msize < tend {
    tend = addr + msize;
  }
  if addr >= tend {
    return _err_table("smbios: table out of buffer");
  }
  return _table_parse(data, addr, tend, -1);
}

// --------------------------------------------------
//  Structure accessors
// --------------------------------------------------

/// Number of structures in the store (the type 127 structure counts).
/// Complexity: O(1).
pub fn smbios_count(t: &SmbiosTable) -> Int {
  return t.types.len();
}

/// Structure type of structure `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn smbios_type(t: &SmbiosTable, i: Int) -> Int {
  if i < 0 || i >= t.types.len() {
    return -1;
  }
  let v: Int = t.types[i];
  return v;
}

/// Declared formatted length (header included, >= 4) of structure `i`,
/// or -1 when out of range.
/// Complexity: O(1).
pub fn smbios_length(t: &SmbiosTable, i: Int) -> Int {
  if i < 0 || i >= t.lengths.len() {
    return -1;
  }
  let v: Int = t.lengths[i];
  return v;
}

/// Little-endian 16-bit handle of structure `i`, or -1 when out of
/// range.
/// Complexity: O(1).
pub fn smbios_handle(t: &SmbiosTable, i: Int) -> Int {
  if i < 0 || i >= t.handles.len() {
    return -1;
  }
  let v: Int = t.handles[i];
  return v;
}

/// Absolute offset of structure `i` in the buffer it was parsed from,
/// or -1 when out of range.
/// Complexity: O(1).
pub fn smbios_struct_start(t: &SmbiosTable, i: Int) -> Int {
  if i < 0 || i >= t.starts.len() {
    return -1;
  }
  let v: Int = t.starts[i];
  return v;
}

/// Length of the formatted area (`length - 4`) of structure `i`, or -1
/// when out of range.
/// Complexity: O(1).
pub fn smbios_formatted_len(t: &SmbiosTable, i: Int) -> Int {
  if i < 0 || i >= t.lengths.len() {
    return -1;
  }
  let v: Int = t.lengths[i];
  return v - 4;
}

/// Index of the first structure whose type is `stype`, or -1 when absent
/// (also for a negative `stype`).
/// Complexity: O(structures).
pub fn smbios_find_type(t: &SmbiosTable, stype: Int) -> Int {
  var i = 0;
  while i < t.types.len() {
    let v: Int = t.types[i];
    if v == stype {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Copy the raw formatted area (header excluded, strings excluded) of
/// structure `i` out of `data`. Err("smbios: structure index out of
/// range") for a bad index, Err("smbios: structure out of bounds") when
/// the recorded span does not fit `data`.
/// Complexity: O(length).
pub fn smbios_formatted(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= t.types.len() {
    return _err_bytes("smbios: structure index out of range");
  }
  let len: Int = t.lengths[i];
  let base: Int = t.starts[i];
  if base < 0 || len < 4 || base + len > data.len() {
    return _err_bytes("smbios: structure out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 4;
  while k < len {
    out.push(data[base + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  String accessors
// --------------------------------------------------

/// Number of strings in structure `i`'s string set, or -1 when `i` is
/// out of range. SMBIOS strings are 1-indexed; index 0 means "no string
/// provided".
/// Complexity: O(1).
pub fn smbios_string_count(t: &SmbiosTable, i: Int) -> Int {
  if i < 0 || i >= t.str_count.len() {
    return -1;
  }
  let v: Int = t.str_count[i];
  return v;
}

/// Copy the raw bytes of string `s` (1-indexed) of structure `i`.
///
/// `s == 0` yields Ok(empty) — index 0 is the documented "no string".
/// Err("smbios: structure index out of range"), Err("smbios: string
/// index out of range") for bad indices, and Err("smbios: string out of
/// bounds") when the recorded span does not fit `data`.
/// Complexity: O(string length).
pub fn smbios_string_bytes(data: &Vec[UInt8], t: &SmbiosTable, i: Int, s: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= t.types.len() {
    return _err_bytes("smbios: structure index out of range");
  }
  let sc: Int = smbios_string_count(t, i);
  if s < 0 || s > sc {
    return _err_bytes("smbios: string index out of range");
  }
  if s == 0 {
    return _ok_bytes(Vec[UInt8].new());
  }
  let k: Int = t.str_first[i] + s - 1;
  if k < 0 || k >= t.str_struct.len() {
    return _err_bytes("smbios: string out of bounds");
  }
  let own: Int = t.str_struct[k];
  if own != i {
    return _err_bytes("smbios: string out of bounds");
  }
  let off: Int = t.str_off[k];
  let len: Int = t.str_len[k];
  if off < 0 || len < 0 || off + len > data.len() {
    return _err_bytes("smbios: string out of bounds");
  }
  var out = Vec[UInt8].new();
  var j = 0;
  while j < len {
    out.push(data[off + j]);
    j = j + 1;
  }
  return _ok_bytes(out);
}

/// Decode string `s` (1-indexed) of structure `i` as UTF-8 text.
///
/// `s == 0` yields Ok("") — index 0 is the documented "no string".
/// Err("smbios: structure index out of range"), Err("smbios: string
/// index out of range"), Err("smbios: string out of bounds") and
/// Err("smbios: invalid string bytes") when the stored bytes are not
/// valid UTF-8 (raw bytes stay available through smbios_string_bytes).
/// Complexity: O(string length).
pub fn smbios_string(data: &Vec[UInt8], t: &SmbiosTable, i: Int, s: Int) -> Result[Str, Str] {
  let br = smbios_string_bytes(data, t, i, s);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  if bytes.len() == 0 {
    return _ok_str("");
  }
  let dr = encoding.utf8_decode(&bytes);
  if !dr.is_ok {
    return _err_str("smbios: invalid string bytes");
  }
  let st: Str = dr.value;
  return _ok_str(st);
}

// --------------------------------------------------
//  Documented field accessors
// --------------------------------------------------

// Value of the `size`-byte little-endian field at formatted offset `off`
// of structure `i` when its type is `want` and the field fits the
// formatted area; -1 otherwise (wrong index, wrong type, field absent or
// span outside `data`).
fn _field(data: &Vec[UInt8], t: &SmbiosTable, i: Int, want: Int, off: Int, size: Int) -> Int {
  if i < 0 || i >= t.types.len() {
    return -1;
  }
  let ty: Int = t.types[i];
  if ty != want {
    return -1;
  }
  let len: Int = t.lengths[i];
  if off < 4 || off + size > len {
    return -1;
  }
  let base: Int = t.starts[i];
  if base < 0 || base + len > data.len() {
    return -1;
  }
  return _read_le(data, base + off, size);
}

/// BIOS Information (type 0) vendor string index (offset 04h), or -1
/// when absent. Index 0 means "no string".
pub fn smbios_bios_vendor(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BIOS, 4, 1);
}

/// BIOS Information (type 0) BIOS version string index (offset 05h), or
/// -1 when absent.
pub fn smbios_bios_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BIOS, 5, 1);
}

/// BIOS Information (type 0) release date string index (offset 08h), or
/// -1 when absent.
pub fn smbios_bios_release_date(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BIOS, 8, 1);
}

/// BIOS Information (type 0) ROM size byte (offset 09h), passed through
/// raw: no 64 KiB/MiB scaling is applied. -1 when absent.
pub fn smbios_bios_rom_size(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BIOS, 9, 1);
}

/// System Information (type 1) manufacturer string index (offset 04h),
/// or -1 when absent.
pub fn smbios_system_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_SYSTEM, 4, 1);
}

/// System Information (type 1) product name string index (offset 05h),
/// or -1 when absent.
pub fn smbios_system_product(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_SYSTEM, 5, 1);
}

/// System Information (type 1) version string index (offset 06h), or -1
/// when absent.
pub fn smbios_system_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_SYSTEM, 6, 1);
}

/// System Information (type 1) serial number string index (offset 07h),
/// or -1 when absent.
pub fn smbios_system_serial(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_SYSTEM, 7, 1);
}

/// System Information (type 1) UUID: the 16 raw bytes at offset 08h, in
/// on-wire order.
///
/// Byte-order note: SMBIOS 2.6+ stores the first three UUID fields
/// (time_low u32, time_mid u16, time_hi_and_version u16) in little-endian
/// and the remaining 8 bytes as-is; this function does not reorder or
/// reformat anything. Err("smbios: structure index out of range") for a
/// bad index and Err("smbios: uuid out of range") when structure `i` is
/// not a System Information structure carrying a full 16-byte UUID.
/// Complexity: O(1).
pub fn smbios_uuid(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= t.types.len() {
    return _err_bytes("smbios: structure index out of range");
  }
  let ty: Int = t.types[i];
  if ty != SMBIOS_TYPE_SYSTEM {
    return _err_bytes("smbios: uuid out of range");
  }
  let len: Int = t.lengths[i];
  if 8 + 16 > len {
    return _err_bytes("smbios: uuid out of range");
  }
  let base: Int = t.starts[i];
  if base < 0 || base + len > data.len() {
    return _err_bytes("smbios: uuid out of range");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < 16 {
    out.push(data[base + 8 + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Baseboard (type 2) manufacturer string index (offset 04h), or -1 when
/// absent.
pub fn smbios_baseboard_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BASEBOARD, 4, 1);
}

/// Baseboard (type 2) product string index (offset 05h), or -1 when
/// absent.
pub fn smbios_baseboard_product(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BASEBOARD, 5, 1);
}

/// Baseboard (type 2) version string index (offset 06h), or -1 when
/// absent.
pub fn smbios_baseboard_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BASEBOARD, 6, 1);
}

/// Baseboard (type 2) serial number string index (offset 07h), or -1
/// when absent.
pub fn smbios_baseboard_serial(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BASEBOARD, 7, 1);
}

/// Baseboard (type 2) asset tag string index (offset 08h), or -1 when
/// absent.
pub fn smbios_baseboard_asset_tag(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_BASEBOARD, 8, 1);
}

/// Chassis (type 3) manufacturer string index (offset 04h), or -1 when
/// absent.
pub fn smbios_chassis_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_CHASSIS, 4, 1);
}

/// Chassis (type 3) raw type byte (offset 05h), or -1 when absent. Bit 7
/// is the chassis lock flag; use smbios_chassis_type_name for the
/// documented name of the low bits.
pub fn smbios_chassis_type(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_CHASSIS, 5, 1);
}

/// Chassis (type 3) version string index (offset 06h), or -1 when
/// absent.
pub fn smbios_chassis_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_CHASSIS, 6, 1);
}

/// Chassis (type 3) serial number string index (offset 07h), or -1 when
/// absent.
pub fn smbios_chassis_serial(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_CHASSIS, 7, 1);
}

/// Chassis (type 3) asset tag string index (offset 08h), or -1 when
/// absent.
pub fn smbios_chassis_asset_tag(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_CHASSIS, 8, 1);
}

/// Documented name of a chassis type byte (see the SMBIOS chassis type
/// table). Bit 7 (the lock flag) is stripped first, so 0x85 means the
/// locked form of type 5. Values outside 1..0x24 yield "Unknown".
/// Complexity: O(1).
pub fn smbios_chassis_type_name(chassis_type: Int) -> Str {
  var v = chassis_type;
  if v >= 128 {
    v = v - 128;
  }
  if v == 1 { return "Other"; }
  if v == 2 { return "Unknown"; }
  if v == 3 { return "Desktop"; }
  if v == 4 { return "Low Profile Desktop"; }
  if v == 5 { return "Pizza Box"; }
  if v == 6 { return "Mini Tower"; }
  if v == 7 { return "Tower"; }
  if v == 8 { return "Portable"; }
  if v == 9 { return "Laptop"; }
  if v == 10 { return "Notebook"; }
  if v == 11 { return "Hand Held"; }
  if v == 12 { return "Docking Station"; }
  if v == 13 { return "All in One"; }
  if v == 14 { return "Sub Notebook"; }
  if v == 15 { return "Space-saving"; }
  if v == 16 { return "Lunch Box"; }
  if v == 17 { return "Main Server Chassis"; }
  if v == 18 { return "Expansion Chassis"; }
  if v == 19 { return "Sub Chassis"; }
  if v == 20 { return "Bus Expansion Chassis"; }
  if v == 21 { return "Peripheral Chassis"; }
  if v == 22 { return "RAID Chassis"; }
  if v == 23 { return "Rack Mount Chassis"; }
  if v == 24 { return "Sealed-case PC"; }
  if v == 25 { return "Multi-system"; }
  if v == 26 { return "CompactPCI"; }
  if v == 27 { return "AdvancedTCA"; }
  if v == 28 { return "Blade"; }
  if v == 29 { return "Blade Enclosure"; }
  if v == 30 { return "Tablet"; }
  if v == 31 { return "Convertible"; }
  if v == 32 { return "Detachable"; }
  if v == 33 { return "IoT Gateway"; }
  if v == 34 { return "Embedded PC"; }
  if v == 35 { return "Mini PC"; }
  if v == 36 { return "Stick PC"; }
  return "Unknown";
}

/// Processor (type 4) socket designation string index (offset 04h), or
/// -1 when absent.
pub fn smbios_processor_socket(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_PROCESSOR, 4, 1);
}

/// Processor (type 4) processor family byte (offset 06h), passed through
/// raw (the SMBIOS family table is not decoded). -1 when absent.
pub fn smbios_processor_family(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_PROCESSOR, 6, 1);
}

/// Processor (type 4) processor version string index (offset 10h), or -1
/// when absent.
pub fn smbios_processor_version(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_PROCESSOR, 16, 1);
}

/// Physical Memory Array (type 16) maximum capacity in KiB (32-bit
/// little-endian field at offset 07h), passed through raw.
///
/// Documented values: 0x80000000 means "unknown"; the 64-bit extended
/// capacity field is not read. -1 when absent.
pub fn smbios_memory_array_capacity(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_MEMORY_ARRAY, 7, 4);
}

/// Memory Device (type 17) size in MiB (16-bit little-endian field at
/// offset 0Ch), passed through raw.
///
/// Documented values: 0 means "not installed", 0xFFFF means "unknown",
/// 0x7FFF means "see the extended size field" (not decoded here). -1
/// when absent.
pub fn smbios_memory_device_size(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_MEMORY_DEVICE, 12, 2);
}

/// Memory Device (type 17) memory type byte (offset 12h), passed through
/// raw (the SMBIOS memory type table is not decoded). -1 when absent.
pub fn smbios_memory_device_type(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_MEMORY_DEVICE, 18, 1);
}

/// Memory Device (type 17) speed in MT/s (16-bit little-endian field at
/// offset 15h), passed through raw. -1 when absent.
pub fn smbios_memory_device_speed(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_MEMORY_DEVICE, 21, 2);
}

/// Memory Device (type 17) manufacturer string index (offset 17h), or
/// -1 when absent.
pub fn smbios_memory_device_manufacturer(data: &Vec[UInt8], t: &SmbiosTable, i: Int) -> Int {
  return _field(data, t, i, SMBIOS_TYPE_MEMORY_DEVICE, 23, 1);
}

// --------------------------------------------------
//  Canonical builders
// --------------------------------------------------

/// Build the canonical 31-byte 32-bit "_SM_" entry point.
///
/// Layout: anchor, computed checksum, length 0x1F, major, minor, max
/// structure size (u16), entry point revision 0, five zero formatted
/// bytes, the "_DMI_" anchor (offset 0x10), its computed checksum
/// (offset 0x15), structure table length (u16 at 0x16), structure table
/// address (u32 at 0x18), structure count (u16 at 0x1C) and BCD revision
/// (offset 0x1E). Both checksums are computed with smbios_checksum8 so
/// each 0x1F-byte block and the 15-byte intermediate block sum to 0.
///
/// Err messages: `smbios: major version out of range`, `minor version
/// out of range`, `max structure size out of range`, `table address out
/// of range` (above 0xFFFFFFFF), `table length out of range`, `structure
/// count out of range`, `bcd revision out of range`.
/// Complexity: O(1).
pub fn smbios_entry32_build(major: Int, minor: Int, max_size: Int, table_addr: Int, table_len: Int, count: Int, bcd_rev: Int) -> Result[Vec[UInt8], Str] {
  if major < 0 || major > 255 {
    return _err_bytes("smbios: major version out of range");
  }
  if minor < 0 || minor > 255 {
    return _err_bytes("smbios: minor version out of range");
  }
  if max_size < 0 || max_size > 65535 {
    return _err_bytes("smbios: max structure size out of range");
  }
  if table_addr < 0 || table_addr > 4294967295 {
    return _err_bytes("smbios: table address out of range");
  }
  if table_len < 0 || table_len > 65535 {
    return _err_bytes("smbios: table length out of range");
  }
  if count < 0 || count > 65535 {
    return _err_bytes("smbios: structure count out of range");
  }
  if bcd_rev < 0 || bcd_rev > 255 {
    return _err_bytes("smbios: bcd revision out of range");
  }
  var out = Vec[UInt8].new();
  _push_ascii(&mut out, "_SM_");
  out.push(0 as UInt8);
  out.push(31 as UInt8);
  out.push(major as UInt8);
  out.push(minor as UInt8);
  _push_le(&mut out, max_size, 2);
  out.push(0 as UInt8);
  var z = 0;
  while z < 5 {
    out.push(0 as UInt8);
    z = z + 1;
  }
  _push_ascii(&mut out, "_DMI_");
  out.push(0 as UInt8);
  _push_le(&mut out, table_len, 2);
  _push_le(&mut out, table_addr, 4);
  _push_le(&mut out, count, 2);
  out.push(bcd_rev as UInt8);
  // Intermediate checksum first: its byte counts toward the entry-point
  // checksum, which is sealed last.
  let si: Int = smbios_checksum8(&out, 16, 15);
  out[21] = _checksum_byte(si) as UInt8;
  let s32: Int = smbios_checksum8(&out, 0, 31);
  out[4] = _checksum_byte(s32) as UInt8;
  return _ok_bytes(out);
}

/// Build the canonical 24-byte 64-bit "_SM3_" entry point.
///
/// Layout: anchor, computed checksum, length 0x18, major, minor, docrev,
/// entry point revision, one reserved zero byte, structure table maximum
/// size (u32 at 0x0C) and structure table address (u64 at 0x10). The
/// checksum is computed with smbios_checksum8 so the 0x18 bytes sum to 0.
///
/// Err messages: `smbios: major version out of range`, `minor version
/// out of range`, `docrev out of range`, `entry revision out of range`,
/// `max structure size out of range` (above 0xFFFFFFFF), `table address
/// out of range` (negative; the u64 bit pattern must fit a positive
/// Int).
/// Complexity: O(1).
pub fn smbios_entry64_build(major: Int, minor: Int, docrev: Int, revision: Int, max_size: Int, table_addr: Int) -> Result[Vec[UInt8], Str] {
  if major < 0 || major > 255 {
    return _err_bytes("smbios: major version out of range");
  }
  if minor < 0 || minor > 255 {
    return _err_bytes("smbios: minor version out of range");
  }
  if docrev < 0 || docrev > 255 {
    return _err_bytes("smbios: docrev out of range");
  }
  if revision < 0 || revision > 255 {
    return _err_bytes("smbios: entry revision out of range");
  }
  if max_size < 0 || max_size > 4294967295 {
    return _err_bytes("smbios: max structure size out of range");
  }
  if table_addr < 0 {
    return _err_bytes("smbios: table address out of range");
  }
  var out = Vec[UInt8].new();
  _push_ascii(&mut out, "_SM3_");
  out.push(0 as UInt8);
  out.push(24 as UInt8);
  out.push(major as UInt8);
  out.push(minor as UInt8);
  out.push(docrev as UInt8);
  out.push(revision as UInt8);
  out.push(0 as UInt8);
  _push_le(&mut out, max_size, 4);
  _push_le(&mut out, table_addr, 8);
  let s64: Int = smbios_checksum8(&out, 0, 24);
  out[5] = _checksum_byte(s64) as UInt8;
  return _ok_bytes(out);
}

/// Build one canonical structure: type, 1-byte length (`4 +
/// formatted.len()`), little-endian handle, the formatted bytes verbatim,
/// then the string set — every string NUL-terminated and the set closed
/// by an extra NUL (a zero-string set is the documented two-NUL pair
/// `00 00`).
///
/// Strings are emitted as their UTF-8 bytes. Validation is atomic
/// (nothing is written on Err) and reports: `smbios: structure type out
/// of range`, `smbios: handle out of range`, `smbios: formatted area too
/// long` (more than 251 bytes), `smbios: empty string`, `smbios: string
/// contains NUL`.
/// Complexity: O(formatted + string bytes).
pub fn smbios_struct_build(stype: Int, handle: Int, formatted: &Vec[UInt8], strings: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  if stype < 0 || stype > 255 {
    return _err_bytes("smbios: structure type out of range");
  }
  if handle < 0 || handle > 65535 {
    return _err_bytes("smbios: handle out of range");
  }
  let flen: Int = formatted.len();
  if flen > 251 {
    return _err_bytes("smbios: formatted area too long");
  }
  let ns: Int = strings.len();
  var i = 0;
  while i < ns {
    let s: Str = strings[i];
    if string.str_len(s) == 0 {
      return _err_bytes("smbios: empty string");
    }
    var k = 0;
    while k < string.str_len(s) {
      let b: UInt8 = string.byte_at(s, k);
      if ((b as Int) & 0xFF) == 0 {
        return _err_bytes("smbios: string contains NUL");
      }
      k = k + 1;
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  out.push(stype as UInt8);
  out.push((4 + flen) as UInt8);
  _push_le(&mut out, handle, 2);
  _push_bytes(&mut out, formatted);
  i = 0;
  while i < ns {
    let s2: Str = strings[i];
    _push_ascii(&mut out, s2);
    out.push(0 as UInt8);
    i = i + 1;
  }
  out.push(0 as UInt8);
  if ns == 0 {
    out.push(0 as UInt8);
  }
  return _ok_bytes(out);
}

/// Build a canonical 32-bit image: the 31-byte "_SM_" entry point at
/// offset 0 (padded with zeros to 32), then `table` verbatim at offset
/// 32. The entry point reports `table_addr` 32, `table_len` =
/// `table.len()`, the number of structures found by smbios_table_parse
/// and `max_size` 0. `table` must parse (any smbios_table_parse error is
/// returned as is); `table.len()` must fit a u16.
///
/// The result parses back with smbios_parse and yields the same
/// structures.
/// Complexity: O(table bytes).
pub fn smbios_image_build32(table: &Vec[UInt8], major: Int, minor: Int, bcd_rev: Int) -> Result[Vec[UInt8], Str] {
  let tr = smbios_table_parse(table);
  if !tr.is_ok {
    return _err_bytes(tr.error);
  }
  let t: SmbiosTable = tr.value;
  let count: Int = t.types.len();
  let er = smbios_entry32_build(major, minor, 0, 32, table.len(), count, bcd_rev);
  if !er.is_ok {
    return _err_bytes(er.error);
  }
  let ep: Vec[UInt8] = er.value;
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, &ep);
  while out.len() < 32 {
    out.push(0 as UInt8);
  }
  _push_bytes(&mut out, table);
  return _ok_bytes(out);
}
