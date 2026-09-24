// XIOM -- xiom.ogg: Ogg page walk, page fields and the Ogg CRC-32 checksum
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.ogg placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structural parsing of the Ogg container page layer -- the 27-byte
// page header plus the segment (lacing) table -- and the Ogg CRC-32
// checksum. Codec payloads (Vorbis/Opus/Theora/...) are not interpreted.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * OggPages (six Vec fields) is constructed inside ogg_parse_pages and
//     crosses function boundaries only by reference or through _ok_pages.
//   * the module declares no `use` statements: it needs nothing from
//     xiom.std.
// See SPEC.md for the byte layout table, CRC parameters, error catalog and
// test plan.

module xiom.ogg

/// Parsed Ogg page index: one element per page, in stream order.
/// `offsets[i]` is the absolute byte offset of page `i` in the scanned
/// buffer; `sizes[i]` its total size (27 + segment count + sum of lacing
/// values); `flags[i]` the raw header-type byte; `granules[i]` the granule
/// position clamped to Int max (see SPEC.md); `serials[i]` and
/// `sequences[i]` the unsigned 32-bit bitstream serial and page sequence
/// fields. Payload bytes stay in the source buffer and are located with
/// `offsets`/`sizes`.
pub type OggPages = {
  offsets: Vec[Int];
  sizes: Vec[Int];
  flags: Vec[Int];
  granules: Vec[Int];
  serials: Vec[Int];
  sequences: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[OggPages, Str].
fn _ok_pages(v: OggPages) -> Result[OggPages, Str] {
  return Ok(v);
}

// Err(m) for Result[OggPages, Str].
fn _err_pages(m: Str) -> Result[OggPages, Str] {
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

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// True when the four bytes at `pos` are the ASCII capture "OggS"
// (0x4F 0x67 0x67 0x53, decimal 79 103 103 83).
fn _capture(data: &Vec[UInt8], pos: Int) -> Bool {
  if _byte(data, pos) != 79 { return false; }
  if _byte(data, pos + 1) != 103 { return false; }
  if _byte(data, pos + 2) != 103 { return false; }
  if _byte(data, pos + 3) != 83 { return false; }
  return true;
}

// Unsigned little-endian u32 at `pos`; callers guarantee the bounds.
fn _le_u32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + _byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// Little-endian 8-byte granule position at `pos`, clamped to Int max
// (9223372036854775807): any value with bit 63 set -- including the common
// 0xFFFFFFFFFFFFFFFF "-1" encoding of pages with no completed packet -- is
// reported as Int max. Callers guarantee the bounds.
fn _granule(data: &Vec[UInt8], pos: Int) -> Int {
  if _byte(data, pos + 7) >= 128 {
    return 9223372036854775807;
  }
  var v: Int = 0;
  var i = 7;
  while i >= 0 {
    v = v * 256 + _byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// --------------------------------------------------
//  Ogg CRC-32 (poly 0x04C11DB7, init 0, MSB-first, no reflection, no xorout)
// --------------------------------------------------

// One CRC step for byte `b`: xor into the top byte, then eight MSB-first
// shifts with the polynomial 0x04C11DB7 (79764919) fed back on overflow.
// The register never leaves 0..2^32-1, so the result is always a
// non-negative Int.
fn _crc_byte(crc_in: Int, b: Int) -> Int {
  var crc = crc_in ^ (b * 16777216);
  var k = 0;
  while k < 8 {
    if crc >= 2147483648 {
      crc = ((crc - 2147483648) * 2) ^ 79764919;
    } else {
      crc = crc * 2;
    }
    k = k + 1;
  }
  return crc;
}

// Ogg CRC over [start, start + size) of `data`. Relative byte indices in
// [zero_from, zero_to) are read as 0 (pass zero_from > zero_to to disable),
// which is how ogg_page_crc_ok treats the stored checksum field.
fn _crc_range(data: &Vec[UInt8], start: Int, size: Int, zero_from: Int, zero_to: Int) -> Int {
  var crc: Int = 0;
  var i = 0;
  while i < size {
    var b: Int = _byte(data, start + i);
    if i >= zero_from && i < zero_to {
      b = 0;
    }
    crc = _crc_byte(crc, b);
    i = i + 1;
  }
  return crc;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse the Ogg page structure of `data`.
///
/// Walks pages from offset 0. Each page is validated in this order: at
/// least 27 header bytes remain (Err("ogg: truncated page header") on the
/// first page, and on a later remainder that starts with "OggS" but is
/// shorter than a header; Err("ogg: trailing garbage") on any other short
/// remainder); the capture "OggS" (Err("ogg: bad capture pattern") on the
/// first page, Err("ogg: trailing garbage") afterwards); the version byte
/// is 0 (Err("ogg: unsupported version")); the segment table fits
/// (Err("ogg: truncated segment table")); the payload -- the sum of the
/// lacing values -- fits (Err("ogg: truncated page data")). The stored
/// checksum is NOT validated here; use ogg_page_crc_ok for that. An empty
/// buffer is Err("ogg: empty input").
///
/// Page size = 27 + segment count + sum(lacing values). Every page is
/// appended to the returned OggPages index in stream order: absolute byte
/// offset, total size, raw header-type flag, granule position (clamped to
/// Int max, see SPEC.md), unsigned serial and unsigned sequence number.
pub fn ogg_parse_pages(data: &Vec[UInt8]) -> Result[OggPages, Str] {
  let n = data.len();
  if n == 0 {
    return _err_pages("ogg: empty input");
  }
  var offsets = Vec[Int].new();
  var sizes = Vec[Int].new();
  var flags = Vec[Int].new();
  var granules = Vec[Int].new();
  var serials = Vec[Int].new();
  var sequences = Vec[Int].new();
  var pos = 0;
  while pos < n {
    if n - pos < 27 {
      if pos == 0 {
        return _err_pages("ogg: truncated page header");
      }
      if n - pos >= 4 && _capture(data, pos) {
        return _err_pages("ogg: truncated page header");
      }
      return _err_pages("ogg: trailing garbage");
    }
    if !_capture(data, pos) {
      if pos == 0 {
        return _err_pages("ogg: bad capture pattern");
      }
      return _err_pages("ogg: trailing garbage");
    }
    if _byte(data, pos + 4) != 0 {
      return _err_pages("ogg: unsupported version");
    }
    let nsegs = _byte(data, pos + 26);
    if nsegs > n - pos - 27 {
      return _err_pages("ogg: truncated segment table");
    }
    var body: Int = 0;
    var i = 0;
    while i < nsegs {
      body = body + _byte(data, pos + 27 + i);
      i = i + 1;
    }
    if body > n - pos - 27 - nsegs {
      return _err_pages("ogg: truncated page data");
    }
    let size = 27 + nsegs + body;
    offsets.push(pos);
    sizes.push(size);
    flags.push(_byte(data, pos + 5));
    granules.push(_granule(data, pos + 6));
    serials.push(_le_u32(data, pos + 14));
    sequences.push(_le_u32(data, pos + 18));
    pos = pos + size;
  }
  let pages = OggPages{
    offsets: offsets;
    sizes: sizes;
    flags: flags;
    granules: granules;
    serials: serials;
    sequences: sequences;
  };
  return _ok_pages(pages);
}

/// Number of parsed pages. Complexity: O(1).
pub fn ogg_page_count(p: &OggPages) -> Int {
  return p.offsets.len();
}

/// Absolute byte offset of page `i` in the scanned buffer; -1 when `i` is
/// negative or >= ogg_page_count(p). Complexity: O(1).
pub fn ogg_page_offset(p: &OggPages, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= p.offsets.len() {
    return -1;
  }
  let v: Int = p.offsets[i];
  return v;
}

/// Unsigned 32-bit bitstream serial of page `i`; -1 when `i` is negative or
/// >= ogg_page_count(p). Complexity: O(1).
pub fn ogg_page_serial(p: &OggPages, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= p.serials.len() {
    return -1;
  }
  let v: Int = p.serials[i];
  return v;
}

/// Ogg CRC-32 of a whole buffer: polynomial 0x04C11DB7, initial value 0,
/// MSB-first, no input/output reflection, no final xor. All 32-bit results
/// are returned as non-negative Int values, and ogg_crc32(empty) == 0.
/// Complexity: O(data.len()).
pub fn ogg_crc32(data: &Vec[UInt8]) -> Int {
  return _crc_range(data, 0, data.len(), 1, 0);
}

/// Verify the stored checksum of page `page_index` (0-based, in the order
/// ogg_parse_pages returns pages): the CRC-32 is recomputed over exactly
/// the page bytes with the 4 stored checksum bytes (page-relative offsets
/// 22..25) treated as zero and compared with the stored little-endian u32.
///
/// Ok(true) when the page checksum matches, Ok(false) when it does not.
/// Err carries the ogg_parse_pages error when the buffer is not a valid
/// page walk, and Err("ogg: page index out of range") when `page_index` is
/// negative or >= ogg_page_count(p). Complexity: O(page size).
pub fn ogg_page_crc_ok(data: &Vec[UInt8], page_index: Int) -> Result[Bool, Str] {
  let pr = ogg_parse_pages(data);
  if !pr.is_ok {
    return _err_bool(pr.error);
  }
  if page_index < 0 {
    return _err_bool("ogg: page index out of range");
  }
  let pages = pr.value;
  if page_index >= pages.offsets.len() {
    return _err_bool("ogg: page index out of range");
  }
  let off: Int = pages.offsets[page_index];
  let size: Int = pages.sizes[page_index];
  let stored: Int = _le_u32(data, off + 22);
  let computed = _crc_range(data, off, size, 22, 26);
  return _ok_bool(stored == computed);
}
