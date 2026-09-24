// XIOM -- xiom.pcap: classic PCAP capture file structure (parse only)
// Port task: greenfield pure-XIOM port (no FFI) of a classic PCAP reader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: classic libpcap capture files -- the 24-byte global header plus
// 16-byte packet records and their payload bytes -- in either byte order.
// pcap_parse detects the endianness from the magic and reads every field
// with it; packet payloads stay in the source buffer and are located by
// `offsets` (absolute index of the first payload byte) and `caplens`.
// pcapng is out of scope: its section header block starts with 0x0A0D0D0A,
// which is neither accepted magic.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * PcapFile (six scalar fields plus four Vec[Int] fields) is constructed
//     inside pcap_parse and crosses function boundaries only by reference
//     or through _ok_file, following the xiom.tar TarArchive precedent.
//   * Vec reads are bound to typed locals (`let caplen: Int = ...`) before
//     being used; no `==` is ever applied to a Str read from a Vec (BUG 17).
// See SPEC.md for the byte layout tables, endianness rules, error catalog
// and test plan.

module xiom.pcap

/// Parsed classic PCAP index. `magic` is the first four bytes read with the
/// detected endianness -- always 0xA1B2C3D4 (2712847316) for an accepted
/// file -- and `little_endian` records which byte order was detected. The
/// four Vec fields hold one entry per packet record, in file order:
/// capture timestamp seconds, captured (included) length, original length
/// on the wire, and the absolute offset of the first payload byte in the
/// source buffer. Timestamps are whole seconds only (microseconds are not
/// indexed).
pub type PcapFile = {
  magic: Int;
  little_endian: Bool;
  version_major: Int;
  version_minor: Int;
  snaplen: Int;
  linktype: Int;
  ts_secs: Vec[Int];
  caplens: Vec[Int];
  origlens: Vec[Int];
  offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[PcapFile, Str].
fn _ok_file(v: PcapFile) -> Result[PcapFile, Str] {
  return Ok(v);
}

// Err(m) for Result[PcapFile, Str].
fn _err_file(m: Str) -> Result[PcapFile, Str] {
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

// Unsigned 16-bit integer at [pos, pos+2) with the given byte order. The
// caller guarantees the two bytes are in bounds.
fn _u16(data: &Vec[UInt8], pos: Int, le: Bool) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  if le {
    return b0 + b1 * 256;
  }
  return b0 * 256 + b1;
}

// Unsigned 32-bit integer at [pos, pos+4) with the given byte order,
// returned in an Int (0..4294967295). The caller guarantees the four bytes
// are in bounds.
fn _u32(data: &Vec[UInt8], pos: Int, le: Bool) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  if le {
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
  }
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// True when the first four bytes are D4 C3 B2 A1: the classic magic
// 0xA1B2C3D4 stored little-endian, i.e. a little-endian capture file.
// The caller guarantees at least four bytes.
fn _magic_le(data: &Vec[UInt8]) -> Bool {
  if _byte(data, 0) != 212 { return false; }
  if _byte(data, 1) != 195 { return false; }
  if _byte(data, 2) != 178 { return false; }
  if _byte(data, 3) != 161 { return false; }
  return true;
}

// True when the first four bytes are A1 B2 C3 D4: the byte-swapped magic
// 0xD4C3B2A1 when read little-endian, i.e. a big-endian capture file.
// The caller guarantees at least four bytes.
fn _magic_be(data: &Vec[UInt8]) -> Bool {
  if _byte(data, 0) != 161 { return false; }
  if _byte(data, 1) != 178 { return false; }
  if _byte(data, 2) != 195 { return false; }
  if _byte(data, 3) != 212 { return false; }
  return true;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when `data` looks like a classic PCAP capture: at least the 24-byte
/// global header and either magic byte sequence, D4 C3 B2 A1 (little-endian
/// file, magic 0xA1B2C3D4) or A1 B2 C3 D4 (big-endian file, the byte-swapped
/// value 0xD4C3B2A1). Record bytes are not inspected. Complexity: O(1).
pub fn pcap_is_file(data: &Vec[UInt8]) -> Bool {
  if data.len() < 24 {
    return false;
  }
  if _magic_le(data) {
    return true;
  }
  return _magic_be(data);
}

/// Parse a classic PCAP capture.
///
/// The 24-byte global header is magic[4], version_major[2],
/// version_minor[2], thiszone[4], sigfigs[4], snaplen[4], network[4]; every
/// multi-byte field is read with the byte order detected from the magic.
/// thiszone and sigfigs are skipped (not part of the index).
///
/// Records follow at offset 24, each ts_sec[4], ts_usec[4], incl_len[4],
/// orig_len[4] plus `incl_len` payload bytes. `incl_len` is bounds-checked
/// against the remaining buffer; a record header is never read past the
/// end. A zero `incl_len` is a valid record (an empty packet).
///
/// Errors (all stable):
///   * `pcap: truncated header` -- fewer than 24 bytes;
///   * `pcap: bad magic` -- neither magic byte sequence;
///   * `pcap: truncated record` -- 1..15 trailing bytes, less than a
///     record header;
///   * `pcap: truncated packet` -- `incl_len` runs past the buffer end.
/// The whole call is Err on the first malformed record; no partial index is
/// returned. Complexity: O(records + total payload) time, O(records) space.
pub fn pcap_parse(data: &Vec[UInt8]) -> Result[PcapFile, Str] {
  if data.len() < 24 {
    return _err_file("pcap: truncated header");
  }
  var le = false;
  if _magic_le(data) {
    le = true;
  } elif !_magic_be(data) {
    return _err_file("pcap: bad magic");
  }
  let magic = _u32(data, 0, le);
  let version_major = _u16(data, 4, le);
  let version_minor = _u16(data, 6, le);
  let snaplen = _u32(data, 16, le);
  let linktype = _u32(data, 20, le);
  var ts_secs = Vec[Int].new();
  var caplens = Vec[Int].new();
  var origlens = Vec[Int].new();
  var offsets = Vec[Int].new();
  let n = data.len();
  var pos = 24;
  while pos < n {
    if n - pos < 16 {
      return _err_file("pcap: truncated record");
    }
    let incl: Int = _u32(data, pos + 8, le);
    let off = pos + 16;
    if incl < 0 || off + incl > n {
      return _err_file("pcap: truncated packet");
    }
    ts_secs.push(_u32(data, pos, le));
    caplens.push(incl);
    origlens.push(_u32(data, pos + 12, le));
    offsets.push(off);
    pos = off + incl;
  }
  let p = PcapFile{
    magic: magic;
    little_endian: le;
    version_major: version_major;
    version_minor: version_minor;
    snaplen: snaplen;
    linktype: linktype;
    ts_secs: ts_secs;
    caplens: caplens;
    origlens: origlens;
    offsets: offsets;
  };
  return _ok_file(p);
}

/// Number of packet records in the index. Complexity: O(1).
pub fn pcap_packet_count(p: &PcapFile) -> Int {
  return p.offsets.len();
}

/// Copy the captured bytes of packet `i` out of `data` (the buffer passed
/// to pcap_parse): `caplens[i]` bytes starting at `offsets[i]`. Err("pcap:
/// packet out of range") when `i` is negative or >= pcap_packet_count(p);
/// Err("pcap: truncated packet") when the recorded range does not fit in
/// `data` (for example when a shorter buffer is passed). A zero-length
/// record yields an empty Ok. Complexity: O(caplen).
pub fn pcap_packet(data: &Vec[UInt8], p: &PcapFile, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 {
    return _err_bytes("pcap: packet out of range");
  }
  if i >= p.offsets.len() {
    return _err_bytes("pcap: packet out of range");
  }
  let off: Int = p.offsets[i];
  let caplen: Int = p.caplens[i];
  if off < 0 || caplen < 0 {
    return _err_bytes("pcap: packet out of range");
  }
  if off + caplen > data.len() {
    return _err_bytes("pcap: truncated packet");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < caplen {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Captured (included) length of packet `i`; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pcap_caplen(p: &PcapFile, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= p.caplens.len() {
    return -1;
  }
  let caplen: Int = p.caplens[i];
  return caplen;
}

/// Original (on-the-wire) length of packet `i`; -1 when `i` is out of
/// range. `origlen >= caplen` when the capture was snaplen-truncated.
/// Complexity: O(1).
pub fn pcap_origlen(p: &PcapFile, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= p.origlens.len() {
    return -1;
  }
  let origlen: Int = p.origlens[i];
  return origlen;
}

/// Capture timestamp seconds of packet `i`; -1 when `i` is out of range.
/// The microsecond part is not indexed. Complexity: O(1).
pub fn pcap_ts_sec(p: &PcapFile, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= p.ts_secs.len() {
    return -1;
  }
  let ts_sec: Int = p.ts_secs[i];
  return ts_sec;
}

/// Link-layer type (the global header `network` field, e.g. 1 = Ethernet);
/// same for every packet in the file. Complexity: O(1).
pub fn pcap_linktype(p: &PcapFile) -> Int {
  return p.linktype;
}
