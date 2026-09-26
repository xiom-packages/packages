// XIOM -- xiom.uboot: U-Boot legacy image header codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a U-Boot *legacy* image
// header codec. Scope: the fixed 64-byte `image_header_t` (`ih_` prefix),
// its two CRC-32 fields (stored raw, verified by explicit helpers), the
// documented id name tables, a canonical builder and the data span that
// follows the header. FIT images (`d00dfeed`), payload decompression and
// multi-image (IH_TYPE_MULTI) semantics are documented non-goals.
// See SPEC.md for the byte layout, validation order, error catalog, CRC
// policy and test plan.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - `uboot_parse_header` decodes and validates a 64-byte header from a
//   buffer of at least 64 bytes and does not look at the payload;
//   `uboot_parse` additionally requires the declared data size to fit
//   (`data_size <= data.len() - 64`). Both return the same flat
//   `UbootHeader` scalar struct (no vectors, no Vec of structs).
// - All fields are big-endian: seven 32-bit words then four id bytes then
//   the 32-byte name. The builder always writes the fixed magic.
// - The name field is NUL-padded printable ASCII: parsing takes bytes up to
//   the first 0x00 (or the whole 32 bytes when no NUL is present) and every
//   byte before the terminator must be 0x20..0x7E; bytes after the first NUL
//   are ignored. A 32-character name fills the field with no terminator.
// - The id tables are partial and documented (section 4 of SPEC.md): ids
//   outside the table are passed through unchanged and their name accessors
//   report "unknown"; nothing is rejected for an unknown id.
// - CRC-32 values are stored raw by the parsers; a mismatch is never
//   reported there. Callers verify with `uboot_header_crc_ok` /
//   `uboot_data_crc_ok`, or compute spans with `uboot_crc32_range`.
//   The header CRC is the standard CRC-32 of the 64 header bytes with the
//   4 `ih_hcrc` bytes treated as zero (the U-Boot rule: the field is not
//   part of its own computation). The data CRC covers `ih_size` bytes
//   starting at offset 64.
// - `uboot_build` emits the canonical image: fixed magic, the caller's
//   timestamp/addresses/ids/name, the size derived from the payload and both
//   CRCs recomputed. The input header's magic, hcrc, dcrc and size fields
//   are ignored.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the leaf helpers below
//     (constructing Result payloads in larger functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * big-endian words are accumulated arithmetically (`v = v * 256 + byte`)
//     and emitted by an arithmetic byte extractor, so 32-bit values with bit
//     31 set (e.g. 0x80008000 load addresses) never touch a sign bit.
//   * CRC-32 is a local, table-free, bitwise implementation of the standard
//     reflected polynomial (0xEDB88320). Every intermediate register stays
//     in 0..2^32-1 (positive in a signed 64-bit Int), so the only bitwise
//     operations are `>> 1` and `& 1` on values whose bit 63 is clear; no
//     sign-bit-set value is masked or shifted.
//   * Str values read from struct fields are bound to typed locals; the
//     module performs no `==` on Str values at all (Str length checks use
//     `.len()`), and the tests use xiom.string.compare.str_compare.
//   * nested helpers receive the existing `&mut` reference (gpt/tar/aiff
//     precedent); only top-level builders take `&mut` locals.

module xiom.uboot

use xiom.string;

const _UBOOT_HEADER_BYTES: Int = 64;
const _UBOOT_NAME_BYTES: Int = 32;
const _UBOOT_MAGIC: Int = 654645590;
const _UBOOT_FIT_MAGIC: Int = 3490578157;
const _UBOOT_U32_MAX: Int = 4294967295;
const _UBOOT_ID_MAX: Int = 255;
const _UBOOT_PRINT_MIN: Int = 32;
const _UBOOT_PRINT_MAX: Int = 126;

/// Parsed U-Boot legacy image header. All fields are stored raw as parsed;
/// `magic` is always the legacy magic after a successful parse, `size` is the
/// declared data size in bytes, `hcrc`/`dcrc` are the stored CRC-32 values
/// (never verified by the parsers) and `name` is the decoded NUL-trimmed
/// printable name. Fields are implementation details; callers should go
/// through the free functions below.
pub type UbootHeader = {
  magic: Int;
  hcrc: Int;
  time: Int;
  size: Int;
  load: Int;
  ep: Int;
  dcrc: Int;
  os: Int;
  arch: Int;
  image_type: Int;
  comp: Int;
  name: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[UbootHeader, Str].
fn _ok_header(v: UbootHeader) -> Result[UbootHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[UbootHeader, Str].
fn _err_header(m: Str) -> Result[UbootHeader, Str] {
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

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte).
// Arithmetic only: this form is exact for every 32-bit unsigned value and
// avoids masking a value with bit 31 set.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
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

// Big-endian UInt32 at `off` as an Int (0..2^32-1); callers guarantee the
// bounds.
fn _be32(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    v = v * 256 + _byte(data, off + i);
    i = i + 1;
  }
  return v;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Overwrite the `size` bytes at `pos` with the big-endian image of `v`.
// Callers guarantee 0 <= pos and pos + size <= out.len().
fn _set_be(out: &mut Vec[UInt8], pos: Int, v: Int, size: Int) {
  var i = 0;
  while i < size {
    out[pos + i] = _be_byte(v, size - 1 - i);
    i = i + 1;
  }
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
//  Internal name helpers
// --------------------------------------------------

// "" when the 32 name bytes at 32..64 form a legal name, else the documented
// error. Scanning stops at the first NUL; every byte before the terminator
// (or all 32 when there is none) must be printable ASCII (0x20..0x7E).
fn _name_err(data: &Vec[UInt8]) -> Str {
  var i = _UBOOT_HEADER_BYTES - _UBOOT_NAME_BYTES;
  while i < _UBOOT_HEADER_BYTES {
    let b: Int = _byte(data, i);
    if b == 0 { return ""; }
    if b < _UBOOT_PRINT_MIN { return "uboot: bad image name"; }
    if b > _UBOOT_PRINT_MAX { return "uboot: bad image name"; }
    i = i + 1;
  }
  return "";
}

// The 32 name bytes at 32..64 decoded to a Str: bytes up to the first NUL
// (or all 32 when there is none). Callers guarantee `_name_err` is "".
fn _name_at(data: &Vec[UInt8]) -> Str {
  var bytes = Vec[UInt8].new();
  var i = _UBOOT_HEADER_BYTES - _UBOOT_NAME_BYTES;
  var done = false;
  while i < _UBOOT_HEADER_BYTES && !done {
    let b: Int = _byte(data, i);
    if b == 0 {
      done = true;
    } else {
      bytes.push(b as UInt8);
    }
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// True when `s` can be written to the 32-byte name field: every byte is
// printable ASCII and the string is at most 32 characters. A 32-character
// name fills the field completely (no NUL terminator).
fn _name_ok(s: Str) -> Bool {
  if s.len() > _UBOOT_NAME_BYTES { return false; }
  var i = 0;
  while i < s.len() {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c < _UBOOT_PRINT_MIN { return false; }
    if c > _UBOOT_PRINT_MAX { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Internal CRC-32 helpers
// --------------------------------------------------

// Standard CRC-32 (IEEE 802.3 / zlib / PKZIP): reflected polynomial
// 0xEDB88320, init 0xFFFFFFFF, reflected input and output, final xor
// 0xFFFFFFFF. Table-free and bitwise; every intermediate register stays in
// 0..2^32-1, so `>> 1` and `& 1` never touch a sign bit. Every byte whose
// position falls in [zero_from, zero_to) is fed as zero instead of its
// stored value, which implements the U-Boot rule that the `ih_hcrc` field is
// not part of its own computation. The caller guarantees 0 <= start and
// start + count <= data.len().
fn _crc32_span(data: &Vec[UInt8], start: Int, count: Int, zero_from: Int, zero_to: Int) -> Int {
  var crc = 4294967295;
  var i = 0;
  while i < count {
    var b: Int = 0;
    let pos: Int = start + i;
    if pos < zero_from || pos >= zero_to {
      b = _byte(data, pos);
    }
    var reg = crc ^ b;
    var j = 0;
    while j < 8 {
      if (reg & 1) == 1 {
        reg = (reg >> 1) ^ 3988292384;
      } else {
        reg = reg >> 1;
      }
      j = j + 1;
    }
    crc = reg;
    i = i + 1;
  }
  return crc ^ 4294967295;
}

// Standard CRC-32 of the `count` bytes at `start` (no zeroing).
fn _crc32_range(data: &Vec[UInt8], start: Int, count: Int) -> Int {
  return _crc32_span(data, start, count, start, start);
}

// Standard CRC-32 of the 64 header bytes at offset 0 with the 4 `ih_hcrc`
// bytes (offset 4..7) treated as zero.
fn _crc32_header(data: &Vec[UInt8]) -> Int {
  return _crc32_span(data, 0, _UBOOT_HEADER_BYTES, 4, 8);
}

// Overwrite the 4 data-CRC bytes at `pos` with the standard CRC-32 of the
// `count` bytes at `start` (no zeroing). A single helper computes and
// patches, so the mutable reference is never held across two borrows of the
// same buffer.
fn _seal_crc(out: &mut Vec[UInt8], pos: Int, start: Int, count: Int) {
  let v: Int = _crc32_range(out, start, count);
  _set_be(out, pos, v, 4);
}

// Overwrite the 4 `ih_hcrc` bytes at offset 4 with the standard CRC-32 of
// the first 64 header bytes, zeroing the CRC field itself.
fn _seal_header_crc(out: &mut Vec[UInt8]) {
  let v: Int = _crc32_header(out);
  _set_be(out, 4, v, 4);
}

// --------------------------------------------------
//  Internal id name tables (partial, see SPEC.md section 4)
// --------------------------------------------------

// OS id name; ids outside the documented table are passed through and
// reported as "unknown".
fn _os_name(id: Int) -> Str {
  if id == 0 { return "invalid"; }
  if id == 1 { return "openbsd"; }
  if id == 3 { return "freebsd"; }
  if id == 5 { return "linux"; }
  if id == 6 { return "vxworks"; }
  return "unknown";
}

// Architecture id name; ids outside the documented table are "unknown".
fn _arch_name(id: Int) -> Str {
  if id == 2 { return "arm"; }
  if id == 3 { return "i386"; }
  if id == 5 { return "mips"; }
  if id == 6 { return "mips64"; }
  if id == 7 { return "ppc"; }
  if id == 22 { return "aarch64"; }
  return "unknown";
}

// Image type id name; ids outside the documented table are "unknown".
fn _image_type_name(id: Int) -> Str {
  if id == 1 { return "standalone"; }
  if id == 2 { return "kernel"; }
  if id == 3 { return "ramdisk"; }
  if id == 4 { return "multi"; }
  if id == 5 { return "firmware"; }
  if id == 6 { return "script"; }
  if id == 8 { return "filesystem"; }
  if id == 14 { return "kernel-noload"; }
  return "unknown";
}

// Compression id name; ids outside the documented table are "unknown".
fn _comp_name(id: Int) -> Str {
  if id == 0 { return "none"; }
  if id == 1 { return "gzip"; }
  if id == 2 { return "bzip2"; }
  if id == 3 { return "lzma"; }
  if id == 5 { return "lzo"; }
  if id == 6 { return "lz4"; }
  if id == 9 { return "zstd"; }
  return "unknown";
}

// --------------------------------------------------
//  Public API -- shape and magic
// --------------------------------------------------

/// Size of the legacy image header in bytes: always 64.
/// Complexity: O(1).
pub fn uboot_header_size() -> Int {
  return _UBOOT_HEADER_BYTES;
}

/// Offset of the image data: always the 64 bytes of the header (the legacy
/// header has no alignment or offset field).
/// Complexity: O(1).
pub fn uboot_data_offset() -> Int {
  return _UBOOT_HEADER_BYTES;
}

/// True when `data` starts with the flattened image tree (FIT) magic
/// `d00dfeed`. FIT images are a documented non-goal: the parser rejects them
/// with "uboot: FIT image not supported". False for a buffer shorter than
/// 4 bytes or any other prefix.
/// Complexity: O(1).
pub fn uboot_is_fit(data: &Vec[UInt8]) -> Bool {
  if data.len() < 4 { return false; }
  return _be32(data, 0) == _UBOOT_FIT_MAGIC;
}

// --------------------------------------------------
//  Public API -- parsing
// --------------------------------------------------

/// Parse the 64-byte legacy header from a buffer that holds at least the
/// header. The payload is not inspected: `data` may be exactly 64 bytes even
/// when `ih_size` is nonzero (use `uboot_data_bytes` to copy a payload, or
/// `uboot_parse` for the strict full-image check).
///
/// Validation order (first failure wins): a buffer shorter than 64 bytes ->
/// Err("uboot: truncated header"); a `d00dfeed` prefix ->
/// Err("uboot: FIT image not supported"); any other prefix than the legacy
/// magic `27051956` -> Err("uboot: bad magic"); a name byte outside
/// printable ASCII before the NUL -> Err("uboot: bad image name").
///
/// Both CRC fields are copied raw and never verified here. Ids are accepted
/// as any byte value and passed through.
///
/// Params: data - image buffer, read only (at least 64 bytes).
/// Returns: Ok(UbootHeader).
/// Complexity: O(1).
pub fn uboot_parse_header(data: &Vec[UInt8]) -> Result[UbootHeader, Str] {
  if data.len() < _UBOOT_HEADER_BYTES { return _err_header("uboot: truncated header"); }
  let magic: Int = _be32(data, 0);
  if magic != _UBOOT_MAGIC {
    if magic == _UBOOT_FIT_MAGIC { return _err_header("uboot: FIT image not supported"); }
    return _err_header("uboot: bad magic");
  }
  let hcrc: Int = _be32(data, 4);
  let time: Int = _be32(data, 8);
  let size: Int = _be32(data, 12);
  let load: Int = _be32(data, 16);
  let ep: Int = _be32(data, 20);
  let dcrc: Int = _be32(data, 24);
  let os: Int = _byte(data, 28);
  let arch: Int = _byte(data, 29);
  let image_type: Int = _byte(data, 30);
  let comp: Int = _byte(data, 31);
  let ne: Str = _name_err(data);
  if ne.len() > 0 { return _err_header(ne); }
  let nm: Str = _name_at(data);
  let h = UbootHeader{
    magic: magic;
    hcrc: hcrc;
    time: time;
    size: size;
    load: load;
    ep: ep;
    dcrc: dcrc;
    os: os;
    arch: arch;
    image_type: image_type;
    comp: comp;
    name: nm;
  };
  return _ok_header(h);
}

/// Parse a legacy header from a full image buffer and require the declared
/// data size to fit: `ih_size <= data.len() - 64`.
///
/// Validation order (first failure wins): buffer shorter than 64 bytes ->
/// Err("uboot: truncated header"); `d00dfeed` prefix ->
/// Err("uboot: FIT image not supported"); any other prefix than the legacy
/// magic -> Err("uboot: bad magic"); declared size larger than the bytes
/// after the header -> Err("uboot: truncated data"); a name byte outside
/// printable ASCII before the NUL -> Err("uboot: bad image name").
///
/// Bytes after `64 + ih_size` are ignored, so a longer buffer is accepted.
/// CRCs are copied raw and never verified here (see the `_crc_ok` helpers).
///
/// Params: data - image buffer, read only (header plus payload).
/// Returns: Ok(UbootHeader).
/// Complexity: O(1).
pub fn uboot_parse(data: &Vec[UInt8]) -> Result[UbootHeader, Str] {
  if data.len() < _UBOOT_HEADER_BYTES { return _err_header("uboot: truncated header"); }
  let magic: Int = _be32(data, 0);
  if magic != _UBOOT_MAGIC {
    if magic == _UBOOT_FIT_MAGIC { return _err_header("uboot: FIT image not supported"); }
    return _err_header("uboot: bad magic");
  }
  let size: Int = _be32(data, 12);
  if size > data.len() - _UBOOT_HEADER_BYTES { return _err_header("uboot: truncated data"); }
  return uboot_parse_header(data);
}

// --------------------------------------------------
//  Public API -- header accessors
// --------------------------------------------------

/// Header magic field; always the legacy magic after a successful parse.
/// Complexity: O(1).
pub fn uboot_magic(h: &UbootHeader) -> Int {
  return h.magic;
}

/// Image creation timestamp field (raw 32-bit seconds, no epoch policy).
/// Complexity: O(1).
pub fn uboot_timestamp(h: &UbootHeader) -> Int {
  return h.time;
}

/// Declared image data size in bytes (`ih_size`). Complexity: O(1).
pub fn uboot_data_size(h: &UbootHeader) -> Int {
  return h.size;
}

/// Data load address field (raw 32-bit value). Complexity: O(1).
pub fn uboot_load_addr(h: &UbootHeader) -> Int {
  return h.load;
}

/// Entry point address field (raw 32-bit value). Complexity: O(1).
pub fn uboot_entry_point(h: &UbootHeader) -> Int {
  return h.ep;
}

/// Stored header CRC-32, raw. Complexity: O(1).
pub fn uboot_header_crc(h: &UbootHeader) -> Int {
  return h.hcrc;
}

/// Stored data CRC-32, raw. Complexity: O(1).
pub fn uboot_data_crc(h: &UbootHeader) -> Int {
  return h.dcrc;
}

/// Operating system id byte (0..255). Complexity: O(1).
pub fn uboot_os(h: &UbootHeader) -> Int {
  return h.os;
}

/// Documented name of the operating system id (section 4 of SPEC.md):
/// 0 invalid, 1 openbsd, 3 freebsd, 5 linux, 6 vxworks; every other id is
/// passed through and reported as "unknown".
/// Complexity: O(1).
pub fn uboot_os_name(h: &UbootHeader) -> Str {
  return _os_name(h.os);
}

/// CPU architecture id byte (0..255). Complexity: O(1).
pub fn uboot_arch(h: &UbootHeader) -> Int {
  return h.arch;
}

/// Documented name of the architecture id: 2 arm, 3 i386, 5 mips, 6 mips64,
/// 7 ppc, 22 aarch64; every other id is "unknown".
/// Complexity: O(1).
pub fn uboot_arch_name(h: &UbootHeader) -> Str {
  return _arch_name(h.arch);
}

/// Image type id byte (0..255). Complexity: O(1).
pub fn uboot_image_type(h: &UbootHeader) -> Int {
  return h.image_type;
}

/// Documented name of the image type id: 1 standalone, 2 kernel, 3 ramdisk,
/// 4 multi, 5 firmware, 6 script, 8 filesystem, 14 kernel-noload; every
/// other id is "unknown".
/// Complexity: O(1).
pub fn uboot_image_type_name(h: &UbootHeader) -> Str {
  return _image_type_name(h.image_type);
}

/// Compression id byte (0..255). Complexity: O(1).
pub fn uboot_compression(h: &UbootHeader) -> Int {
  return h.comp;
}

/// Documented name of the compression id: 0 none, 1 gzip, 2 bzip2, 3 lzma,
/// 5 lzo, 6 lz4, 9 zstd; every other id is "unknown".
/// Complexity: O(1).
pub fn uboot_compression_name(h: &UbootHeader) -> Str {
  return _comp_name(h.comp);
}

/// Decoded image name: the name-field bytes up to the first NUL (or all 32
/// when there is none). Never contains a non-printable byte after a
/// successful parse. Complexity: O(1).
pub fn uboot_name(h: &UbootHeader) -> Str {
  let s: Str = h.name;
  return s;
}

/// End offset of the data span: `64 + ih_size` (independent of the buffer).
/// Complexity: O(1).
pub fn uboot_data_end(h: &UbootHeader) -> Int {
  return _UBOOT_HEADER_BYTES + h.size;
}

/// Copy the image data span out of `data`.
///
/// Err("uboot: truncated data") when `ih_size` is negative (only possible on
/// a hand-built header) or when `64 + ih_size` does not fit in `data`.
/// Params: data - image buffer, read only; h - the parsed header.
/// Complexity: O(ih_size).
pub fn uboot_data_bytes(data: &Vec[UInt8], h: &UbootHeader) -> Result[Vec[UInt8], Str] {
  if h.size < 0 { return _err_bytes("uboot: truncated data"); }
  if data.len() < _UBOOT_HEADER_BYTES { return _err_bytes("uboot: truncated data"); }
  if h.size > data.len() - _UBOOT_HEADER_BYTES { return _err_bytes("uboot: truncated data"); }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < h.size {
    out.push(data[_UBOOT_HEADER_BYTES + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Public API -- CRC-32 helpers
// --------------------------------------------------

/// Standard CRC-32 of the whole buffer (reflected polynomial 0xEDB88320,
/// init 0xFFFFFFFF, final xor 0xFFFFFFFF; the check value for "123456789"
/// is 3421780262 and the empty buffer is 0). Complexity: O(data.len()).
pub fn uboot_crc32(data: &Vec[UInt8]) -> Int {
  return _crc32_range(data, 0, data.len());
}

/// Standard CRC-32 of the `count` bytes at `start`; -1 when `start` is
/// negative, `count` is negative, or the span does not fit in `data`.
/// Complexity: O(count).
pub fn uboot_crc32_range(data: &Vec[UInt8], start: Int, count: Int) -> Int {
  if start < 0 || count < 0 { return -1; }
  if start > data.len() { return -1; }
  if count > data.len() - start { return -1; }
  return _crc32_range(data, start, count);
}

/// True when the 64 header bytes at offset 0 still match the stored
/// `ih_hcrc`. The stored field is treated as zero while the CRC is
/// recomputed (the U-Boot rule: the field is not part of its own
/// computation). `uboot_parse` never computes this; call it explicitly.
/// False when `data` is shorter than 64 bytes. Complexity: O(1).
pub fn uboot_header_crc_ok(data: &Vec[UInt8], h: &UbootHeader) -> Bool {
  if data.len() < _UBOOT_HEADER_BYTES { return false; }
  return _crc32_header(data) == h.hcrc;
}

/// True when the `ih_size` bytes at offset 64 still match the stored
/// `ih_dcrc`. False when `ih_size` is negative or the span does not fit in
/// `data` (a header-only buffer therefore fails whenever `ih_size > 0`).
/// `uboot_parse` never computes this; call it explicitly.
/// Complexity: O(ih_size).
pub fn uboot_data_crc_ok(data: &Vec[UInt8], h: &UbootHeader) -> Bool {
  if h.size < 0 { return false; }
  if data.len() < _UBOOT_HEADER_BYTES { return false; }
  if h.size > data.len() - _UBOOT_HEADER_BYTES { return false; }
  return _crc32_range(data, _UBOOT_HEADER_BYTES, h.size) == h.dcrc;
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

/// Build a canonical legacy image from `h` and a payload.
///
/// Written layout, in order: the fixed magic `27051956`; a zero `ih_hcrc`
/// placeholder; `time`, the size derived from `payload.len()`, `load` and
/// `ep` from `h`; a zero `ih_dcrc` placeholder; the four id bytes from `h`;
/// the name bytes followed by NUL padding to 32 bytes; then the payload
/// bytes verbatim. The data CRC is the standard CRC-32 of the payload and is
/// patched at offset 24; the header CRC is the standard CRC-32 of the 64
/// header bytes with the `ih_hcrc` field still zero and is patched at offset
/// 4. The header's own `magic`, `hcrc`, `dcrc` and `size` fields are
/// ignored (the image is canonical), the payload is never compressed.
///
/// Err("uboot: bad timestamp") when `time` is outside 0..2^32-1;
/// Err("uboot: bad address") when `load` or `ep` is outside 0..2^32-1;
/// Err("uboot: bad id") when any id byte is outside 0..255;
/// Err("uboot: bad image name") when the name is longer than 32 characters
/// or contains a byte outside printable ASCII; Err("uboot: data too large")
/// when the payload does not fit the 32-bit size field.
///
/// Params: h - timestamp/addresses/ids/name source, read only; payload -
/// image data, read only (may be empty).
/// Returns: Ok(bytes) of length 64 + payload.len().
/// Complexity: O(payload.len()).
pub fn uboot_build(h: &UbootHeader, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if h.time < 0 { return _err_bytes("uboot: bad timestamp"); }
  if h.time > _UBOOT_U32_MAX { return _err_bytes("uboot: bad timestamp"); }
  if h.load < 0 { return _err_bytes("uboot: bad address"); }
  if h.load > _UBOOT_U32_MAX { return _err_bytes("uboot: bad address"); }
  if h.ep < 0 { return _err_bytes("uboot: bad address"); }
  if h.ep > _UBOOT_U32_MAX { return _err_bytes("uboot: bad address"); }
  if h.os < 0 || h.os > _UBOOT_ID_MAX { return _err_bytes("uboot: bad id"); }
  if h.arch < 0 || h.arch > _UBOOT_ID_MAX { return _err_bytes("uboot: bad id"); }
  if h.image_type < 0 || h.image_type > _UBOOT_ID_MAX { return _err_bytes("uboot: bad id"); }
  if h.comp < 0 || h.comp > _UBOOT_ID_MAX { return _err_bytes("uboot: bad id"); }
  if payload.len() > _UBOOT_U32_MAX { return _err_bytes("uboot: data too large"); }
  if !_name_ok(h.name) { return _err_bytes("uboot: bad image name"); }
  var out = Vec[UInt8].new();
  _push_be(&mut out, _UBOOT_MAGIC, 4);
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, h.time, 4);
  _push_be(&mut out, payload.len(), 4);
  _push_be(&mut out, h.load, 4);
  _push_be(&mut out, h.ep, 4);
  _push_be(&mut out, 0, 4);
  out.push(h.os as UInt8);
  out.push(h.arch as UInt8);
  out.push(h.image_type as UInt8);
  out.push(h.comp as UInt8);
  var i = 0;
  while i < h.name.len() {
    out.push(string.byte_at(h.name, i));
    i = i + 1;
  }
  _push_zero(&mut out, _UBOOT_NAME_BYTES - h.name.len());
  _push_bytes(&mut out, payload);
  _seal_crc(&mut out, 24, _UBOOT_HEADER_BYTES, payload.len());
  _seal_header_crc(&mut out);
  return _ok_bytes(out);
}
