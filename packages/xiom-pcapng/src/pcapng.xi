// XIOM -- xiom.pcapng: PCAP Next Generation (pcapng) capture-file codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: parse (never write) the pcapng container layout. A pcapng file is a
// sequence of blocks, each with a 4-byte type, a 4-byte total length, a body
// and a trailing 4-byte copy of the total length that must match the leading
// copy. Section Header Blocks (SHB, type 0x0A0D0D0A) carry the byte-order
// magic 0x1A2B3C4D, so the section's byte order is detected from the first
// four body bytes and every multi-byte field of the section's blocks is read
// with it. This module indexes every block in file order (flat parallel Vecs:
// type, offsets, lengths) and parses the documented block types into pools:
// SHB, IDB (interface description), EPB (enhanced packet), SPB (simple
// packet), NRB (name resolution) and ISB (interface statistics). Blocks of
// unknown type are preserved with their raw body span. Options are parsed as
// TLV entries (u16 code, u16 length, value padded to a 4-byte boundary) for
// SHB/IDB/EPB/ISB; a code of 0 ends the option list.
//
// Non-goals: no packet dissection (packet bytes are opaque spans), no
// name-resolution client beyond NRB record field parsing, no compression, no
// section-length or timestamp-semantics validation, no writer.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; the index type is a plain value
//     with parallel Vec[Int] pools (no Vec[StructType] anywhere).
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * Vec reads are bound to typed locals before use; no `==` is applied to
//     a Str read from a Vec (BUG 17); error strings are literals.
//   * all lengths come from u32 fields and are validated against the buffer
//     before any span is recorded, so offsets + lengths cannot drift.
// See SPEC.md for the block layouts, validation policies, error catalog and
// test plan.

module xiom.pcapng

/// Parsed pcapng index. The first five vectors hold one entry per block, in
/// file order: block type, absolute offset of the block start, total length,
/// body length (total length - 12), and the section ordinal (0-based; the
/// first SHB starts section 0). The remaining pools are parallel vectors,
/// one entry per parsed item of that kind, in file order. No field is a
/// Vec[StructType]; use the free functions below instead of indexing pools
/// directly.
///
/// SHB pool: `shb_blocks` (block ordinal), `shb_orders` (1 little-endian,
/// 0 big-endian), `shb_majors`, `shb_minors`, `shb_section_lengths`
/// (-1 when the SHB declares 0xFFFFFFFFFFFFFFFF, i.e. "unspecified").
///
/// IDB pool: `idb_blocks`, `idb_sections`, `idb_linktypes`, `idb_snaplens`.
///
/// Packet pool (EPB and SPB, in file order): `pkt_blocks`, `pkt_kinds`
/// (0 = EPB, 1 = SPB), `pkt_sections`, `pkt_interfaces` (global interface
/// ordinal, -1 for SPB), `pkt_ts_highs`, `pkt_ts_lows`, `pkt_caplens`,
/// `pkt_origlens`, `pkt_data_offsets`.
///
/// NRB record pool: `rec_blocks`, `rec_types` (1 = IPv4, 2 = IPv6),
/// `rec_addr_offsets`, `rec_addr_lengths` (4 or 16), `rec_name_counts`.
/// Name pool: `name_records` (record ordinal), `name_offsets`,
/// `name_lengths`.
///
/// ISB pool: `isb_blocks`, `isb_interfaces`, `isb_ifrecv`, `isb_ifdrop`
/// (-1 when the option is absent).
///
/// Option pool (SHB/IDB/EPB/ISB options in file order): `opt_blocks`,
/// `opt_codes`, `opt_offsets`, `opt_lengths`. End-of-options markers are not
/// indexed.
pub type PcapngFile = {
  types: Vec[Int];
  offsets: Vec[Int];
  total_lengths: Vec[Int];
  body_lengths: Vec[Int];
  sections: Vec[Int];
  shb_blocks: Vec[Int];
  shb_orders: Vec[Int];
  shb_majors: Vec[Int];
  shb_minors: Vec[Int];
  shb_section_lengths: Vec[Int];
  idb_blocks: Vec[Int];
  idb_sections: Vec[Int];
  idb_linktypes: Vec[Int];
  idb_snaplens: Vec[Int];
  pkt_blocks: Vec[Int];
  pkt_kinds: Vec[Int];
  pkt_sections: Vec[Int];
  pkt_interfaces: Vec[Int];
  pkt_ts_highs: Vec[Int];
  pkt_ts_lows: Vec[Int];
  pkt_caplens: Vec[Int];
  pkt_origlens: Vec[Int];
  pkt_data_offsets: Vec[Int];
  rec_blocks: Vec[Int];
  rec_types: Vec[Int];
  rec_addr_offsets: Vec[Int];
  rec_addr_lengths: Vec[Int];
  rec_name_counts: Vec[Int];
  name_records: Vec[Int];
  name_offsets: Vec[Int];
  name_lengths: Vec[Int];
  isb_blocks: Vec[Int];
  isb_interfaces: Vec[Int];
  isb_ifrecv: Vec[Int];
  isb_ifdrop: Vec[Int];
  opt_blocks: Vec[Int];
  opt_codes: Vec[Int];
  opt_offsets: Vec[Int];
  opt_lengths: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[PcapngFile, Str].
fn _ok_file(v: PcapngFile) -> Result[PcapngFile, Str] {
  return Ok(v);
}

// Err(m) for Result[PcapngFile, Str].
fn _err_file(m: Str) -> Result[PcapngFile, Str] {
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
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit integer at [pos, pos+2) with the given byte order; the
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
// returned in an Int (0..4294967295); the caller guarantees the four bytes
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

// Unsigned 64-bit integer at [pos, pos+8) with the given byte order. The
// result is correct while the value fits the signed Int range, which holds
// for every length and counter this module validates against a buffer.
fn _u64(data: &Vec[UInt8], pos: Int, le: Bool) -> Int {
  let a = _u32(data, pos, le);
  let b = _u32(data, pos + 4, le);
  if le {
    return a + b * 4294967296;
  }
  return a * 4294967296 + b;
}

// `n` rounded up to the next multiple of 4 (n >= 0).
fn _pad4(n: Int) -> Int {
  let r = n % 4;
  if r == 0 {
    return n;
  }
  return n + (4 - r);
}

// True when the four bytes at `pos` are 10 13 13 10: the SHB type
// 0x0A0D0D0A. The sequence is a palindrome, so this test is valid whatever
// the byte order. The caller guarantees four bytes.
fn _is_shb(data: &Vec[UInt8], pos: Int) -> Bool {
  if _byte(data, pos) != 10 { return false; }
  if _byte(data, pos + 1) != 13 { return false; }
  if _byte(data, pos + 2) != 13 { return false; }
  if _byte(data, pos + 3) != 10 { return false; }
  return true;
}

// True when the four bytes at `pos` are 4D 3C 2B 1A: byte-order magic
// 0x1A2B3C4D stored little-endian, i.e. a little-endian section.
fn _bom_le(data: &Vec[UInt8], pos: Int) -> Bool {
  if _byte(data, pos) != 77 { return false; }
  if _byte(data, pos + 1) != 60 { return false; }
  if _byte(data, pos + 2) != 43 { return false; }
  if _byte(data, pos + 3) != 26 { return false; }
  return true;
}

// True when the four bytes at `pos` are 1A 2B 3C 4D: byte-order magic
// 0x1A2B3C4D stored big-endian, i.e. a big-endian section.
fn _bom_be(data: &Vec[UInt8], pos: Int) -> Bool {
  if _byte(data, pos) != 26 { return false; }
  if _byte(data, pos + 1) != 43 { return false; }
  if _byte(data, pos + 2) != 60 { return false; }
  if _byte(data, pos + 3) != 77 { return false; }
  return true;
}

// --------------------------------------------------
//  Internal parsing helpers
// --------------------------------------------------

// Copy `len` bytes at `off` out of `data`. Err("pcapng: span out of bounds")
// when the recorded span does not fit the passed buffer.
fn _copy_span(data: &Vec[UInt8], off: Int, len: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 || len < 0 {
    return _err_bytes("pcapng: span out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("pcapng: span out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// Parse the option region [start, start + region_len) of block `block` and
// append every option before the first code-0 end-of-options marker to the
// four option pools. The caller guarantees the region lies inside the block
// body; region_len is a multiple of 4 for every supported block type.
// Err("pcapng: option overruns block") when an option header declares a
// padded value that does not fit the remaining region.
fn _opt_scan(data: &Vec[UInt8], start: Int, region_len: Int, block: Int, le: Bool,
             opt_blocks: &mut Vec[Int], opt_codes: &mut Vec[Int],
             opt_offsets: &mut Vec[Int], opt_lengths: &mut Vec[Int]) -> Result[Unit, Str] {
  var pos = 0;
  while pos < region_len {
    let code = _u16(data, start + pos, le);
    let len = _u16(data, start + pos + 2, le);
    if code == 0 {
      return _ok_unit();
    }
    let padded = _pad4(len);
    if 4 + padded > region_len - pos {
      return _err_unit("pcapng: option overruns block");
    }
    opt_blocks.push(block);
    opt_codes.push(code);
    opt_offsets.push(start + pos + 4);
    opt_lengths.push(len);
    pos = pos + 4 + padded;
  }
  return _ok_unit();
}

// First option pool index whose block is `block` and code is `code`, or -1
// when absent. The caller has already validated the block ordinal.
fn _opt_find(blocks: &Vec[Int], codes: &Vec[Int], block: Int, code: Int) -> Int {
  var i = 0;
  while i < codes.len() {
    let b: Int = blocks[i];
    let c: Int = codes[i];
    if b == block && c == code {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Scan the DNS-name area [value_start + addr_len, value_start + value_len)
// of NRB record `record` and append every NUL-terminated name to the name
// pools. Runs of NUL bytes are padding and produce no entries; a non-empty
// name must be followed by a NUL. Err("pcapng: unterminated name") when a
// name reaches the end of the record value without a terminator.
fn _name_scan(data: &Vec[UInt8], value_start: Int, value_len: Int, addr_len: Int, record: Int,
              name_records: &mut Vec[Int], name_offsets: &mut Vec[Int],
              name_lengths: &mut Vec[Int]) -> Result[Unit, Str] {
  var pos = addr_len;
  while pos < value_len {
    while pos < value_len && _byte(data, value_start + pos) == 0 {
      pos = pos + 1;
    }
    if pos >= value_len {
      return _ok_unit();
    }
    var end = pos;
    while end < value_len && _byte(data, value_start + end) != 0 {
      end = end + 1;
    }
    if end >= value_len {
      return _err_unit("pcapng: unterminated name");
    }
    name_records.push(record);
    name_offsets.push(value_start + pos);
    name_lengths.push(end - pos);
    pos = end + 1;
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Public API: sniff and parse
// --------------------------------------------------

/// True when `data` starts with the SHB type bytes 10 13 13 10 and is long
/// enough for a complete minimal block (12 bytes). Only the first four bytes
/// and the length are inspected; malformed bodies are not detected here.
/// Complexity: O(1).
pub fn pcapng_is_file(data: &Vec[UInt8]) -> Bool {
  if data.len() < 12 {
    return false;
  }
  return _is_shb(data, 0);
}

/// Parse a pcapng file.
///
/// Blocks are walked from offset 0. The first block must be an SHB
/// (documented policy); every SHB establishes a new section, its byte order
/// (from the 0x1A2B3C4D magic) and the interface base for that section. The
/// leading and trailing total-length copies must be equal, the total length
/// must be >= 12 and a multiple of 4, and no block may run past the buffer;
/// otherwise the whole call is Err with one of the documented messages and
/// no partial index is returned.
///
/// Parsed per block type: SHB (version major must be 1; section length
/// 0xFFFFFFFFFFFFFFFF is reported as -1), IDB (linktype, snaplen, options),
/// EPB (interface, 64-bit timestamp, caplen/origlen, data span, options; a
/// packet may only reference an interface declared earlier in its section and
/// caplen must not exceed origlen), SPB (original length; the data region
/// must be exactly origlen padded to 4 bytes), NRB (IPv4/IPv6 records with
/// NUL-terminated names), ISB (interface, timestamp, ifrecv/ifdrop 64-bit
/// counters, options). Blocks of unknown type (including the obsolete Packet
/// Block type 2) are indexed with their raw body span and otherwise ignored.
///
/// Complexity: O(data.len()) time and O(blocks + records + names + options)
/// space.
pub fn pcapng_parse(data: &Vec[UInt8]) -> Result[PcapngFile, Str] {
  let n = data.len();
  var types = Vec[Int].new();
  var offsets = Vec[Int].new();
  var total_lengths = Vec[Int].new();
  var body_lengths = Vec[Int].new();
  var sections = Vec[Int].new();
  var shb_blocks = Vec[Int].new();
  var shb_orders = Vec[Int].new();
  var shb_majors = Vec[Int].new();
  var shb_minors = Vec[Int].new();
  var shb_section_lengths = Vec[Int].new();
  var idb_blocks = Vec[Int].new();
  var idb_sections = Vec[Int].new();
  var idb_linktypes = Vec[Int].new();
  var idb_snaplens = Vec[Int].new();
  var pkt_blocks = Vec[Int].new();
  var pkt_kinds = Vec[Int].new();
  var pkt_sections = Vec[Int].new();
  var pkt_interfaces = Vec[Int].new();
  var pkt_ts_highs = Vec[Int].new();
  var pkt_ts_lows = Vec[Int].new();
  var pkt_caplens = Vec[Int].new();
  var pkt_origlens = Vec[Int].new();
  var pkt_data_offsets = Vec[Int].new();
  var rec_blocks = Vec[Int].new();
  var rec_types = Vec[Int].new();
  var rec_addr_offsets = Vec[Int].new();
  var rec_addr_lengths = Vec[Int].new();
  var rec_name_counts = Vec[Int].new();
  var name_records = Vec[Int].new();
  var name_offsets = Vec[Int].new();
  var name_lengths = Vec[Int].new();
  var isb_blocks = Vec[Int].new();
  var isb_interfaces = Vec[Int].new();
  var isb_ifrecv = Vec[Int].new();
  var isb_ifdrop = Vec[Int].new();
  var opt_blocks = Vec[Int].new();
  var opt_codes = Vec[Int].new();
  var opt_offsets = Vec[Int].new();
  var opt_lengths = Vec[Int].new();
  var section = -1;
  var iface_base = 0;
  var le = true;
  var pos = 0;
  while pos < n {
    let remaining = n - pos;
    if remaining < 12 {
      return _err_file("pcapng: truncated block header");
    }
    let shb_here = _is_shb(data, pos);
    if !shb_here && section < 0 {
      return _err_file("pcapng: section header block must be first");
    }
    if shb_here {
      if _bom_le(data, pos + 8) {
        le = true;
      } elif _bom_be(data, pos + 8) {
        le = false;
      } else {
        return _err_file("pcapng: bad byte-order magic");
      }
    }
    var btype = 0;
    if shb_here {
      btype = 168627466;
    } else {
      btype = _u32(data, pos, le);
    }
    let total = _u32(data, pos + 4, le);
    if total < 12 || total % 4 != 0 {
      return _err_file("pcapng: bad block length");
    }
    if total > remaining {
      return _err_file("pcapng: truncated block");
    }
    let trailing = _u32(data, pos + total - 4, le);
    if trailing != total {
      return _err_file("pcapng: total length mismatch");
    }
    let bi = types.len();
    let body_start = pos + 8;
    let body_len = total - 12;
    if shb_here {
      section = section + 1;
      iface_base = idb_linktypes.len();
    }
    types.push(btype);
    offsets.push(pos);
    total_lengths.push(total);
    body_lengths.push(body_len);
    sections.push(section);
    if shb_here {
      if body_len < 16 {
        return _err_file("pcapng: truncated section header");
      }
      let major = _u16(data, body_start + 4, le);
      if major != 1 {
        return _err_file("pcapng: unsupported version");
      }
      let minor = _u16(data, body_start + 6, le);
      var sec_len = _u64(data, body_start + 8, le);
      if _u32(data, body_start + 8, le) == 4294967295 && _u32(data, body_start + 12, le) == 4294967295 {
        sec_len = -1;
      }
      var order_code = 0;
      if le {
        order_code = 1;
      }
      shb_blocks.push(bi);
      shb_orders.push(order_code);
      shb_majors.push(major);
      shb_minors.push(minor);
      shb_section_lengths.push(sec_len);
      let os_shb = _opt_scan(data, body_start + 16, body_len - 16, bi, le, &mut opt_blocks, &mut opt_codes, &mut opt_offsets, &mut opt_lengths);
      if !os_shb.is_ok {
        return _err_file(os_shb.error);
      }
    } elif btype == 1 {
      if body_len < 8 {
        return _err_file("pcapng: truncated interface description");
      }
      let linktype = _u16(data, body_start, le);
      let snaplen = _u32(data, body_start + 4, le);
      idb_blocks.push(bi);
      idb_sections.push(section);
      idb_linktypes.push(linktype);
      idb_snaplens.push(snaplen);
      let os_idb = _opt_scan(data, body_start + 8, body_len - 8, bi, le, &mut opt_blocks, &mut opt_codes, &mut opt_offsets, &mut opt_lengths);
      if !os_idb.is_ok {
        return _err_file(os_idb.error);
      }
    } elif btype == 6 {
      if body_len < 20 {
        return _err_file("pcapng: truncated enhanced packet");
      }
      let iface = _u32(data, body_start, le);
      let ts_high = _u32(data, body_start + 4, le);
      let ts_low = _u32(data, body_start + 8, le);
      let caplen = _u32(data, body_start + 12, le);
      let origlen = _u32(data, body_start + 16, le);
      if caplen > origlen {
        return _err_file("pcapng: captured length exceeds original");
      }
      let data_region = _pad4(caplen);
      if 20 + data_region > body_len {
        return _err_file("pcapng: truncated packet data");
      }
      if iface_base + iface >= idb_linktypes.len() {
        return _err_file("pcapng: packet interface out of range");
      }
      pkt_blocks.push(bi);
      pkt_kinds.push(0);
      pkt_sections.push(section);
      pkt_interfaces.push(iface_base + iface);
      pkt_ts_highs.push(ts_high);
      pkt_ts_lows.push(ts_low);
      pkt_caplens.push(caplen);
      pkt_origlens.push(origlen);
      pkt_data_offsets.push(body_start + 20);
      let os_epb = _opt_scan(data, body_start + 20 + data_region, body_len - 20 - data_region, bi, le, &mut opt_blocks, &mut opt_codes, &mut opt_offsets, &mut opt_lengths);
      if !os_epb.is_ok {
        return _err_file(os_epb.error);
      }
    } elif btype == 3 {
      if body_len < 4 {
        return _err_file("pcapng: truncated simple packet");
      }
      let origlen = _u32(data, body_start, le);
      let data_region = body_len - 4;
      let pad = _pad4(origlen) - origlen;
      if data_region < origlen {
        return _err_file("pcapng: truncated packet data");
      }
      if data_region > origlen + pad {
        return _err_file("pcapng: bad packet padding");
      }
      pkt_blocks.push(bi);
      pkt_kinds.push(1);
      pkt_sections.push(section);
      pkt_interfaces.push(-1);
      pkt_ts_highs.push(0);
      pkt_ts_lows.push(0);
      pkt_caplens.push(origlen);
      pkt_origlens.push(origlen);
      pkt_data_offsets.push(body_start + 4);
    } elif btype == 4 {
      var rpos = 0;
      while rpos < body_len {
        if body_len - rpos < 4 {
          return _err_file("pcapng: truncated name record");
        }
        let rtype = _u16(data, body_start + rpos, le);
        let vlen = _u16(data, body_start + rpos + 2, le);
        if rtype == 0 {
          rpos = body_len;
        } else {
          let vpad = _pad4(vlen);
          if 4 + vpad > body_len - rpos {
            return _err_file("pcapng: truncated name record");
          }
          if rtype == 1 || rtype == 2 {
            var addr_len = 16;
            if rtype == 1 {
              addr_len = 4;
            }
            if vlen < addr_len {
              return _err_file("pcapng: bad name record");
            }
            let record = rec_blocks.len();
            let ns_before = name_lengths.len();
            rec_blocks.push(bi);
            rec_types.push(rtype);
            rec_addr_offsets.push(body_start + rpos + 4);
            rec_addr_lengths.push(addr_len);
            let ns = _name_scan(data, body_start + rpos + 4, vlen, addr_len, record, &mut name_records, &mut name_offsets, &mut name_lengths);
            if !ns.is_ok {
              return _err_file(ns.error);
            }
            rec_name_counts.push(name_lengths.len() - ns_before);
          }
          rpos = rpos + 4 + vpad;
        }
      }
    } elif btype == 5 {
      if body_len < 12 {
        return _err_file("pcapng: truncated interface statistics");
      }
      let iface = _u32(data, body_start, le);
      if iface_base + iface >= idb_linktypes.len() {
        return _err_file("pcapng: packet interface out of range");
      }
      isb_blocks.push(bi);
      isb_interfaces.push(iface_base + iface);
      let os_isb = _opt_scan(data, body_start + 12, body_len - 12, bi, le, &mut opt_blocks, &mut opt_codes, &mut opt_offsets, &mut opt_lengths);
      if !os_isb.is_ok {
        return _err_file(os_isb.error);
      }
      var ifrecv = -1;
      let i6 = _opt_find(&opt_blocks, &opt_codes, bi, 6);
      if i6 >= 0 {
        let l6: Int = opt_lengths[i6];
        if l6 != 8 {
          return _err_file("pcapng: bad statistics counter");
        }
        let o6: Int = opt_offsets[i6];
        ifrecv = _u64(data, o6, le);
      }
      var ifdrop = -1;
      let i7 = _opt_find(&opt_blocks, &opt_codes, bi, 7);
      if i7 >= 0 {
        let l7: Int = opt_lengths[i7];
        if l7 != 8 {
          return _err_file("pcapng: bad statistics counter");
        }
        let o7: Int = opt_offsets[i7];
        ifdrop = _u64(data, o7, le);
      }
      isb_ifrecv.push(ifrecv);
      isb_ifdrop.push(ifdrop);
    }
    pos = pos + total;
  }
  if section < 0 {
    return _err_file("pcapng: section header block must be first");
  }
  let f = PcapngFile{
    types: types;
    offsets: offsets;
    total_lengths: total_lengths;
    body_lengths: body_lengths;
    sections: sections;
    shb_blocks: shb_blocks;
    shb_orders: shb_orders;
    shb_majors: shb_majors;
    shb_minors: shb_minors;
    shb_section_lengths: shb_section_lengths;
    idb_blocks: idb_blocks;
    idb_sections: idb_sections;
    idb_linktypes: idb_linktypes;
    idb_snaplens: idb_snaplens;
    pkt_blocks: pkt_blocks;
    pkt_kinds: pkt_kinds;
    pkt_sections: pkt_sections;
    pkt_interfaces: pkt_interfaces;
    pkt_ts_highs: pkt_ts_highs;
    pkt_ts_lows: pkt_ts_lows;
    pkt_caplens: pkt_caplens;
    pkt_origlens: pkt_origlens;
    pkt_data_offsets: pkt_data_offsets;
    rec_blocks: rec_blocks;
    rec_types: rec_types;
    rec_addr_offsets: rec_addr_offsets;
    rec_addr_lengths: rec_addr_lengths;
    rec_name_counts: rec_name_counts;
    name_records: name_records;
    name_offsets: name_offsets;
    name_lengths: name_lengths;
    isb_blocks: isb_blocks;
    isb_interfaces: isb_interfaces;
    isb_ifrecv: isb_ifrecv;
    isb_ifdrop: isb_ifdrop;
    opt_blocks: opt_blocks;
    opt_codes: opt_codes;
    opt_offsets: opt_offsets;
    opt_lengths: opt_lengths;
  };
  return _ok_file(f);
}

// --------------------------------------------------
//  Public API: block index
// --------------------------------------------------

/// Number of blocks in the index. Complexity: O(1).
pub fn pcapng_block_count(p: &PcapngFile) -> Int {
  return p.types.len();
}

/// Type of block `i` (0x0A0D0D0A = 168627466 for an SHB); -1 when `i` is out
/// of range. Complexity: O(1).
pub fn pcapng_block_type(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.types.len() {
    return -1;
  }
  let t: Int = p.types[i];
  return t;
}

/// Absolute offset of block `i` in the source buffer; -1 when out of range.
/// Complexity: O(1).
pub fn pcapng_block_offset(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.offsets.len() {
    return -1;
  }
  let o: Int = p.offsets[i];
  return o;
}

/// Absolute offset of block `i`'s body (block offset + 8); -1 out of range.
/// Complexity: O(1).
pub fn pcapng_block_body_offset(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.offsets.len() {
    return -1;
  }
  let o: Int = p.offsets[i];
  return o + 8;
}

/// Body length of block `i` (total length - 12); -1 out of range.
/// Complexity: O(1).
pub fn pcapng_block_body_length(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.body_lengths.len() {
    return -1;
  }
  let l: Int = p.body_lengths[i];
  return l;
}

/// Section ordinal of block `i` (0-based); -1 out of range.
/// Complexity: O(1).
pub fn pcapng_block_section(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.sections.len() {
    return -1;
  }
  let s: Int = p.sections[i];
  return s;
}

/// Copy the raw body bytes of block `i` (works for every block type,
/// including unknown ones). Err("pcapng: block out of range") when `i` is
/// out of range; Err("pcapng: span out of bounds") when the recorded span
/// does not fit `data`. Complexity: O(body length).
pub fn pcapng_block_body(data: &Vec[UInt8], p: &PcapngFile, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= p.offsets.len() {
    return _err_bytes("pcapng: block out of range");
  }
  let off: Int = p.offsets[i];
  let len: Int = p.body_lengths[i];
  return _copy_span(data, off + 8, len);
}

// --------------------------------------------------
//  Public API: sections (SHB)
// --------------------------------------------------

/// Number of sections (one per SHB). Complexity: O(1).
pub fn pcapng_section_count(p: &PcapngFile) -> Int {
  return p.shb_blocks.len();
}

/// Byte order of section `s`: 1 = little-endian, 0 = big-endian; -1 out of
/// range. Complexity: O(1).
pub fn pcapng_section_order(p: &PcapngFile, s: Int) -> Int {
  if s < 0 || s >= p.shb_orders.len() {
    return -1;
  }
  let o: Int = p.shb_orders[s];
  return o;
}

/// Major version of section `s` (always 1 for a parsed file, since any other
/// value is rejected); -1 out of range. Complexity: O(1).
pub fn pcapng_section_major(p: &PcapngFile, s: Int) -> Int {
  if s < 0 || s >= p.shb_majors.len() {
    return -1;
  }
  let v: Int = p.shb_majors[s];
  return v;
}

/// Minor version of section `s` (reported, not enforced); -1 out of range.
/// Complexity: O(1).
pub fn pcapng_section_minor(p: &PcapngFile, s: Int) -> Int {
  if s < 0 || s >= p.shb_minors.len() {
    return -1;
  }
  let v: Int = p.shb_minors[s];
  return v;
}

/// Declared section length of section `s` in bytes (excluding the SHB
/// itself); -1 when out of range or when the SHB declares the unspecified
/// value 0xFFFFFFFFFFFFFFFF. The value is reported, not validated.
/// Complexity: O(1).
pub fn pcapng_section_length(p: &PcapngFile, s: Int) -> Int {
  if s < 0 || s >= p.shb_section_lengths.len() {
    return -1;
  }
  let l: Int = p.shb_section_lengths[s];
  return l;
}

// --------------------------------------------------
//  Public API: interfaces (IDB)
// --------------------------------------------------

/// Number of interfaces described by IDBs across all sections.
/// Complexity: O(1).
pub fn pcapng_interface_count(p: &PcapngFile) -> Int {
  return p.idb_linktypes.len();
}

/// Link-layer type of interface `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_interface_linktype(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.idb_linktypes.len() {
    return -1;
  }
  let v: Int = p.idb_linktypes[i];
  return v;
}

/// Snapshot length of interface `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_interface_snaplen(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.idb_snaplens.len() {
    return -1;
  }
  let v: Int = p.idb_snaplens[i];
  return v;
}

/// Block ordinal of the IDB that declared interface `i`; -1 out of range.
/// Complexity: O(1).
pub fn pcapng_interface_block(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.idb_blocks.len() {
    return -1;
  }
  let v: Int = p.idb_blocks[i];
  return v;
}

/// Section ordinal of interface `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_interface_section(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.idb_sections.len() {
    return -1;
  }
  let v: Int = p.idb_sections[i];
  return v;
}

// --------------------------------------------------
//  Public API: packets (EPB and SPB)
// --------------------------------------------------

/// Number of packet records (EPB and SPB) across all sections.
/// Complexity: O(1).
pub fn pcapng_packet_count(p: &PcapngFile) -> Int {
  return p.pkt_blocks.len();
}

/// Kind of packet `i`: 0 = EPB, 1 = SPB; -1 out of range. Complexity: O(1).
pub fn pcapng_packet_kind(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_kinds.len() {
    return -1;
  }
  let v: Int = p.pkt_kinds[i];
  return v;
}

/// Block ordinal of packet `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_packet_block(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_blocks.len() {
    return -1;
  }
  let v: Int = p.pkt_blocks[i];
  return v;
}

/// Section ordinal of packet `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_packet_section(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_sections.len() {
    return -1;
  }
  let v: Int = p.pkt_sections[i];
  return v;
}

/// Global interface ordinal of packet `i` (section interface id + section
/// base); -1 when out of range or for an SPB, which names no interface.
/// Complexity: O(1).
pub fn pcapng_packet_interface(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_interfaces.len() {
    return -1;
  }
  let v: Int = p.pkt_interfaces[i];
  return v;
}

/// High 32 bits of packet `i`'s 64-bit timestamp; 0 for an SPB (no
/// timestamp field); -1 out of range. Complexity: O(1).
pub fn pcapng_packet_ts_high(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_ts_highs.len() {
    return -1;
  }
  let v: Int = p.pkt_ts_highs[i];
  return v;
}

/// Low 32 bits of packet `i`'s 64-bit timestamp; 0 for an SPB (no timestamp
/// field); -1 out of range. Complexity: O(1).
pub fn pcapng_packet_ts_low(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_ts_lows.len() {
    return -1;
  }
  let v: Int = p.pkt_ts_lows[i];
  return v;
}

/// Packet `i`'s timestamp as `high * 2^32 + low`; 0 for an SPB; -1 out of
/// range. Correct while the composed value fits the Int range.
/// Complexity: O(1).
pub fn pcapng_packet_timestamp(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_blocks.len() {
    return -1;
  }
  let hi: Int = p.pkt_ts_highs[i];
  let lo: Int = p.pkt_ts_lows[i];
  return hi * 4294967296 + lo;
}

/// Captured length of packet `i` (EPB caplen, or SPB origlen since SPB data
/// is untruncated); -1 out of range. Complexity: O(1).
pub fn pcapng_packet_caplen(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_caplens.len() {
    return -1;
  }
  let v: Int = p.pkt_caplens[i];
  return v;
}

/// Original on-the-wire length of packet `i`; -1 out of range.
/// Complexity: O(1).
pub fn pcapng_packet_origlen(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_origlens.len() {
    return -1;
  }
  let v: Int = p.pkt_origlens[i];
  return v;
}

/// Absolute offset of packet `i`'s captured data in the source buffer; -1
/// out of range. Complexity: O(1).
pub fn pcapng_packet_data_offset(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.pkt_data_offsets.len() {
    return -1;
  }
  let v: Int = p.pkt_data_offsets[i];
  return v;
}

/// Copy packet `i`'s captured data bytes out of the source buffer.
/// Err("pcapng: packet out of range") when `i` is out of range;
/// Err("pcapng: span out of bounds") when the recorded span does not fit
/// `data`. Complexity: O(caplen).
pub fn pcapng_packet_data(data: &Vec[UInt8], p: &PcapngFile, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= p.pkt_blocks.len() {
    return _err_bytes("pcapng: packet out of range");
  }
  let off: Int = p.pkt_data_offsets[i];
  let len: Int = p.pkt_caplens[i];
  return _copy_span(data, off, len);
}

// --------------------------------------------------
//  Public API: name resolution (NRB)
// --------------------------------------------------

/// Number of parsed NRB records (IPv4 and IPv6 only). Complexity: O(1).
pub fn pcapng_record_count(p: &PcapngFile) -> Int {
  return p.rec_blocks.len();
}

/// Type of record `r`: 1 = IPv4 address + names, 2 = IPv6 address + names;
/// -1 out of range. Complexity: O(1).
pub fn pcapng_record_type(p: &PcapngFile, r: Int) -> Int {
  if r < 0 || r >= p.rec_types.len() {
    return -1;
  }
  let v: Int = p.rec_types[r];
  return v;
}

/// Block ordinal of the NRB that carried record `r`; -1 out of range.
/// Complexity: O(1).
pub fn pcapng_record_block(p: &PcapngFile, r: Int) -> Int {
  if r < 0 || r >= p.rec_blocks.len() {
    return -1;
  }
  let v: Int = p.rec_blocks[r];
  return v;
}

/// Number of DNS names attached to record `r`; -1 out of range.
/// Complexity: O(1).
pub fn pcapng_record_name_count(p: &PcapngFile, r: Int) -> Int {
  if r < 0 || r >= p.rec_name_counts.len() {
    return -1;
  }
  let v: Int = p.rec_name_counts[r];
  return v;
}

/// Copy record `r`'s address bytes (4 for IPv4, 16 for IPv6). Err("pcapng:
/// record out of range") when `r` is out of range; Err("pcapng: span out of
/// bounds") when the recorded span does not fit `data`.
/// Complexity: O(address length).
pub fn pcapng_record_address(data: &Vec[UInt8], p: &PcapngFile, r: Int) -> Result[Vec[UInt8], Str] {
  if r < 0 || r >= p.rec_blocks.len() {
    return _err_bytes("pcapng: record out of range");
  }
  let off: Int = p.rec_addr_offsets[r];
  let len: Int = p.rec_addr_lengths[r];
  return _copy_span(data, off, len);
}

/// Number of parsed DNS names across all records. Complexity: O(1).
pub fn pcapng_name_count(p: &PcapngFile) -> Int {
  return p.name_offsets.len();
}

/// Record ordinal that DNS name `n` belongs to; -1 out of range.
/// Complexity: O(1).
pub fn pcapng_name_record(p: &PcapngFile, n: Int) -> Int {
  if n < 0 || n >= p.name_records.len() {
    return -1;
  }
  let v: Int = p.name_records[n];
  return v;
}

/// Absolute offset of DNS name `n` (without its NUL terminator) in the
/// source buffer; -1 out of range. Complexity: O(1).
pub fn pcapng_name_offset(p: &PcapngFile, n: Int) -> Int {
  if n < 0 || n >= p.name_offsets.len() {
    return -1;
  }
  let v: Int = p.name_offsets[n];
  return v;
}

/// Length in bytes of DNS name `n` (without its NUL terminator); -1 out of
/// range. Complexity: O(1).
pub fn pcapng_name_length(p: &PcapngFile, n: Int) -> Int {
  if n < 0 || n >= p.name_lengths.len() {
    return -1;
  }
  let v: Int = p.name_lengths[n];
  return v;
}

/// Copy DNS name `n`'s bytes (without the NUL terminator). Err("pcapng: name
/// out of range") when `n` is out of range; Err("pcapng: span out of
/// bounds") when the recorded span does not fit `data`.
/// Complexity: O(name length).
pub fn pcapng_name_bytes(data: &Vec[UInt8], p: &PcapngFile, n: Int) -> Result[Vec[UInt8], Str] {
  if n < 0 || n >= p.name_offsets.len() {
    return _err_bytes("pcapng: name out of range");
  }
  let off: Int = p.name_offsets[n];
  let len: Int = p.name_lengths[n];
  return _copy_span(data, off, len);
}

// --------------------------------------------------
//  Public API: interface statistics (ISB)
// --------------------------------------------------

/// Number of parsed interface statistics blocks. Complexity: O(1).
pub fn pcapng_isb_count(p: &PcapngFile) -> Int {
  return p.isb_blocks.len();
}

/// Global interface ordinal of ISB `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_isb_interface(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.isb_interfaces.len() {
    return -1;
  }
  let v: Int = p.isb_interfaces[i];
  return v;
}

/// Block ordinal of ISB `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_isb_block(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.isb_blocks.len() {
    return -1;
  }
  let v: Int = p.isb_blocks[i];
  return v;
}

/// `isb_ifrecv` 64-bit counter of ISB `i` (option code 6, packets received);
/// -1 when out of range or when the option is absent. Complexity: O(1).
pub fn pcapng_isb_ifrecv(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.isb_ifrecv.len() {
    return -1;
  }
  let v: Int = p.isb_ifrecv[i];
  return v;
}

/// `isb_ifdrop` 64-bit counter of ISB `i` (option code 7, packets dropped);
/// -1 when out of range or when the option is absent. Complexity: O(1).
pub fn pcapng_isb_ifdrop(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.isb_ifdrop.len() {
    return -1;
  }
  let v: Int = p.isb_ifdrop[i];
  return v;
}

// --------------------------------------------------
//  Public API: options
// --------------------------------------------------

/// Number of indexed options across SHB/IDB/EPB/ISB blocks (end-of-options
/// markers are not counted). Complexity: O(1).
pub fn pcapng_option_count(p: &PcapngFile) -> Int {
  return p.opt_codes.len();
}

/// Block ordinal that carries option `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_option_block(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.opt_blocks.len() {
    return -1;
  }
  let v: Int = p.opt_blocks[i];
  return v;
}

/// Code of option `i`; -1 out of range. Complexity: O(1).
pub fn pcapng_option_code(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.opt_codes.len() {
    return -1;
  }
  let v: Int = p.opt_codes[i];
  return v;
}

/// Absolute offset of option `i`'s value bytes in the source buffer; -1 out
/// of range. Complexity: O(1).
pub fn pcapng_option_offset(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.opt_offsets.len() {
    return -1;
  }
  let v: Int = p.opt_offsets[i];
  return v;
}

/// Value length of option `i` (without padding); -1 out of range.
/// Complexity: O(1).
pub fn pcapng_option_length(p: &PcapngFile, i: Int) -> Int {
  if i < 0 || i >= p.opt_lengths.len() {
    return -1;
  }
  let v: Int = p.opt_lengths[i];
  return v;
}

/// First option pool index of block `block` with code `code`, scanning the
/// pool in file order (first match wins); -1 when `block` is out of range or
/// no such indexed option exists. Complexity: O(options).
pub fn pcapng_option_find(p: &PcapngFile, block: Int, code: Int) -> Int {
  if block < 0 || block >= p.types.len() {
    return -1;
  }
  let blocks: Vec[Int] = p.opt_blocks;
  let codes: Vec[Int] = p.opt_codes;
  return _opt_find(&blocks, &codes, block, code);
}

/// Copy option `i`'s value bytes (without padding). Err("pcapng: option out
/// of range") when `i` is out of range; Err("pcapng: span out of bounds")
/// when the recorded span does not fit `data`. Complexity: O(value length).
pub fn pcapng_option_value(data: &Vec[UInt8], p: &PcapngFile, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= p.opt_offsets.len() {
    return _err_bytes("pcapng: option out of range");
  }
  let off: Int = p.opt_offsets[i];
  let len: Int = p.opt_lengths[i];
  return _copy_span(data, off, len);
}
