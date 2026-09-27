// XIOM -- xiom.zigbee: IEEE 802.15.4 MAC / ZigBee NWK / APS structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI), dependency-free structure codec for the ZigBee
// protocol stack. It parses, byte for byte, the structure of:
//
//   * IEEE 802.15.4 MAC frames -- frame control, sequence number, addressing
//     fields (short 16-bit and extended 64-bit, little-endian), the
//     auxiliary security header as an opaque span when the security bit is
//     set, beacon payload (superframe spec, GTS descriptors, pending
//     addresses), MAC command frames (command identifier table) and the
//     trailing 2-byte FCS (located, never verified).
//   * ZigBee NWK headers -- frame control, 16-bit destination/source,
//     radius, sequence, optional IEEE addresses, multicast control, source
//     route subframe, NWK command identifiers and a raw payload span.
//   * ZigBee APS headers -- frame control, destination endpoint, group
//     address, cluster/profile identifiers, source endpoint, APS counter and
//     the fragmentation bits of the extended header, plus a raw payload
//     span.
//
// No payload is decrypted, no FCS is checked and no network key is touched:
// a secured frame is reported as such and the secured bytes stay opaque.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below.
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`.
//   * bitfields of the 16-bit MAC and NWK frame controls are extracted with
//     division and modulo (`(v / 2^k) % 2`), never with a `&` mask: masking
//     operands with the sign bit set is unreliable in this compiler.
//   * no `&mut Int` out-parameters (miscompiled); helpers return values.
//   * error messages carry the absolute byte offset where the parse failed,
//     formatted by the local `_itoa` (the module imports nothing).
//   * extended addresses are kept as raw 8-byte copies, not as Int, because
//     a 64-bit address with bit 63 set does not fit a signed Int.
//
// See SPEC.md for the byte-level layout tables, the error catalog and the
// test plan.

module xiom.zigbee

/// Parsed IEEE 802.15.4 MAC frame. `frame_type` is 0 beacon, 1 data,
/// 2 acknowledgement or 3 MAC command; `security`, `frame_pending`,
/// `ack_request` and `pan_compress` mirror the frame control flags;
/// `reserved_bits` holds frame control bits 7..9 as read (bit 8 is 802.15.4-
/// 2015 sequence-number suppression and bit 9 IE present; both are rejected
/// before a frame is returned); `frame_version` is 0 (2003), 1 (2006),
/// 2 (2015) or 3. `dest_mode`/`src_mode` are 0 (absent), 2 (short) or 3
/// (extended). `dest_pan`/`src_pan`/`dest_short`/`src_short` are -1 when the
/// field is absent (with PAN ID compression `src_pan` echoes `dest_pan`
/// without consuming bytes); `dest_ext`/`src_ext` hold the 8 raw address
/// bytes (empty when absent). `aux_off` is the offset of the opaque
/// auxiliary security header, or -1. The payload span is
/// [payload_off, payload_off + payload_len); the FCS is the two bytes at
/// `fcs_off` and is never verified. Beacon frames additionally fill the
/// superframe/GTS/pending fields and set `beacon_end`; MAC command frames
/// set `command_id`/`command_data_off`/`command_data_len` unless the frame is
/// secured (then the command identifier is opaque and stays -1).
/// `consumed` is the number of input bytes the frame spans.
pub type MacFrame = {
  frame_type: Int;
  security: Bool;
  frame_pending: Bool;
  ack_request: Bool;
  pan_compress: Bool;
  reserved_bits: Int;
  frame_version: Int;
  dest_mode: Int;
  src_mode: Int;
  seq: Int;
  dest_pan: Int;
  src_pan: Int;
  dest_short: Int;
  src_short: Int;
  dest_ext: Vec[UInt8];
  src_ext: Vec[UInt8];
  aux_present: Bool;
  aux_off: Int;
  payload_off: Int;
  payload_len: Int;
  fcs_off: Int;
  consumed: Int;
  beacon_order: Int;
  superframe_order: Int;
  final_cap_slot: Int;
  battery_life: Bool;
  pan_coordinator: Bool;
  assoc_permit: Bool;
  gts_permit: Bool;
  gts_addrs: Vec[Int];
  gts_starts: Vec[Int];
  gts_lens: Vec[Int];
  pend_short: Vec[Int];
  pend_ext: Vec[UInt8];
  beacon_end: Int;
  command_id: Int;
  command_data_off: Int;
  command_data_len: Int;
}

/// Parsed ZigBee NWK header. `frame_type` is 0 data or 1 NWK command;
/// `protocol_version` is 0..15; `discover_route` is 0 suppress, 1 enable or
/// 3 force; the five Bool flags mirror the frame control bits (multicast,
/// security, source route, destination/source IEEE addresses present) and
/// `end_device_initiator` is bit 13 (ZigBee PRO r21). `dest`/`src` are the
/// 16-bit addresses; `dest_ext`/`src_ext` hold the 8 raw IEEE address bytes
/// (empty when absent); `multicast_control` is the raw byte or -1, with its
/// three subfields split into `multicast_mode`, `multicast_radius` and
/// `multicast_max_radius` (all -1 when absent). `relay_count` is -1 when the
/// source route subframe is absent; `relays` holds the 16-bit relay list and
/// `relay_index` the sender index. `command_id` is the first payload byte of
/// an unsecured NWK command frame, else -1. The payload span is
/// [payload_off, payload_off + payload_len); `consumed` is the input length.
pub type NwkFrame = {
  frame_type: Int;
  protocol_version: Int;
  discover_route: Int;
  multicast: Bool;
  security: Bool;
  source_route: Bool;
  dest_ieee: Bool;
  src_ieee: Bool;
  end_device_initiator: Bool;
  dest: Int;
  src: Int;
  radius: Int;
  seq: Int;
  dest_ext: Vec[UInt8];
  src_ext: Vec[UInt8];
  multicast_control: Int;
  multicast_mode: Int;
  multicast_radius: Int;
  multicast_max_radius: Int;
  relay_count: Int;
  relays: Vec[Int];
  relay_index: Int;
  command_id: Int;
  payload_off: Int;
  payload_len: Int;
  consumed: Int;
}

/// Parsed ZigBee APS header. `frame_type` is 0 data, 1 command or 2
/// acknowledgement; `delivery_mode` is 0 unicast, 1 broadcast or 2 group;
/// `ack_format` is frame control bit 4 (the ZigBee 2004 indirect-mode bit,
/// documented for 2007+ as acknowledgement format); `security`, `ack_request`
/// and `ext_present` mirror the remaining frame control bits. `dest_endpoint`
/// is -1 when absent (data/command present it only in unicast mode; an
/// acknowledgement always carries it); `group_addr` is -1 unless group mode;
/// `cluster_id`/`profile_id` are -1 for acknowledgements; `src_endpoint` is
/// -1 for acknowledgements; `counter` is the APS counter. `ext_frag_bits` and
/// `ext_block` are the fragmentation bits and block number of the extended
/// header (-1 when absent); the two low bits of `ext_frag_bits` are kept raw
/// (0 none, 1 first, 2 middle, 3 last). The payload span is
/// [payload_off, payload_off + payload_len); `consumed` is the input length.
pub type ApsFrame = {
  frame_type: Int;
  delivery_mode: Int;
  ack_format: Bool;
  security: Bool;
  ack_request: Bool;
  ext_present: Bool;
  dest_endpoint: Int;
  group_addr: Int;
  cluster_id: Int;
  profile_id: Int;
  src_endpoint: Int;
  counter: Int;
  ext_frag_bits: Int;
  ext_block: Int;
  payload_off: Int;
  payload_len: Int;
  consumed: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[MacFrame, Str].
fn _ok_mac(v: MacFrame) -> Result[MacFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[MacFrame, Str].
fn _err_mac(m: Str) -> Result[MacFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[NwkFrame, Str].
fn _ok_nwk(v: NwkFrame) -> Result[NwkFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[NwkFrame, Str].
fn _err_nwk(m: Str) -> Result[NwkFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[ApsFrame, Str].
fn _ok_aps(v: ApsFrame) -> Result[ApsFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[ApsFrame, Str].
fn _err_aps(m: Str) -> Result[ApsFrame, Str] {
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

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal helpers (arithmetic only)
// --------------------------------------------------

// One decimal digit as a Str; the module imports nothing, so this is part
// of the local offset formatter used by every error message.
fn _digit_char(d: Int) -> Str {
  if d == 0 { return "0"; }
  if d == 1 { return "1"; }
  if d == 2 { return "2"; }
  if d == 3 { return "3"; }
  if d == 4 { return "4"; }
  if d == 5 { return "5"; }
  if d == 6 { return "6"; }
  if d == 7 { return "7"; }
  if d == 8 { return "8"; }
  return "9";
}

// Base-10 rendering of `n` (used for byte offsets; handles negatives).
fn _itoa(n: Int) -> Str {
  if n == 0 {
    return "0";
  }
  var v = n;
  var neg = false;
  if v < 0 {
    neg = true;
    v = -v;
  }
  var s = "";
  while v > 0 {
    let d = v % 10;
    s = _digit_char(d) + s;
    v = (v - d) / 10;
  }
  if neg {
    return "-" + s;
  }
  return s;
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit little-endian integer at [pos, pos+2); callers guarantee
// the two bytes are in bounds.
fn _le16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  return b0 + b1 * 256;
}

// True when the `count` bytes starting at `pos` fit inside `limit`.
fn _fits(pos: Int, count: Int, limit: Int) -> Bool {
  return pos + count <= limit;
}

// Offset reported by a truncation error: the first byte that was needed but
// not available (never before the field that failed).
fn _fault(off: Int, limit: Int) -> Int {
  if off > limit {
    return off;
  }
  return limit;
}

// Copy the 8 bytes at [pos, pos+8) into a fresh vector; callers guarantee
// the range is in bounds (extended addresses stay raw bytes because a
// 64-bit address does not fit a signed Int).
fn _copy8(data: &Vec[UInt8], pos: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var k = 0;
  while k < 8 {
    out.push(data[pos + k]);
    k = k + 1;
  }
  return out;
}

// Copy the `count` bytes at [pos, pos+count) into a fresh vector; callers
// guarantee the range is in bounds.
fn _copy_span(data: &Vec[UInt8], pos: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var k = 0;
  while k < count {
    out.push(data[pos + k]);
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  Public API: codec revision
// --------------------------------------------------

/// Codec revision marker; 1 for the layout documented in SPEC.md.
/// Complexity: O(1).
pub fn zigbee_version() -> Int {
  return 1;
}

// --------------------------------------------------
//  Public API: IEEE 802.15.4 MAC
// --------------------------------------------------

/// Human name of a MAC frame type: 0 Beacon, 1 Data, 2 Acknowledgement,
/// 3 MAC command; 4..7 are the 802.15.4-2015 reserved/multipurpose/
/// fragment/extended types. Complexity: O(1).
pub fn mac_frame_type_name(t: Int) -> Str {
  if t == 0 { return "Beacon"; }
  if t == 1 { return "Data"; }
  if t == 2 { return "Acknowledgement"; }
  if t == 3 { return "MAC command"; }
  if t == 4 { return "Reserved"; }
  if t == 5 { return "Multipurpose"; }
  if t == 6 { return "Fragment"; }
  if t == 7 { return "Extended"; }
  return "Unknown";
}

/// Human name of a MAC addressing mode: 0 None, 1 Reserved, 2 Short
/// (16-bit), 3 Extended (64-bit). Complexity: O(1).
pub fn mac_addr_mode_name(m: Int) -> Str {
  if m == 0 { return "None"; }
  if m == 1 { return "Reserved"; }
  if m == 2 { return "Short"; }
  if m == 3 { return "Extended"; }
  return "Unknown";
}

/// Human name of a MAC frame version: 0 2003, 1 2006, 2 2015, 3 Reserved.
/// Complexity: O(1).
pub fn mac_frame_version_name(v: Int) -> Str {
  if v == 0 { return "2003"; }
  if v == 1 { return "2006"; }
  if v == 2 { return "2015"; }
  if v == 3 { return "Reserved"; }
  return "Unknown";
}

/// Human name of an IEEE 802.15.4 MAC command identifier (0x01..0x09
/// documented; everything else is Reserved). Complexity: O(1).
pub fn mac_command_name(id: Int) -> Str {
  if id == 1 { return "Association request"; }
  if id == 2 { return "Association response"; }
  if id == 3 { return "Disassociation notification"; }
  if id == 4 { return "Data request"; }
  if id == 5 { return "PAN ID conflict notification"; }
  if id == 6 { return "Orphan notification"; }
  if id == 7 { return "Beacon request"; }
  if id == 8 { return "Coordinator realignment"; }
  if id == 9 { return "GTS request"; }
  return "Reserved";
}

/// Class of a 16-bit MAC address: 0 ordinary, 1 broadcast (0xFFFF),
/// 2 no-address (0xFFFE, IEEE802154_NO_ADDR16). Complexity: O(1).
pub fn mac_short_class(addr: Int) -> Int {
  if addr == 65535 {
    return 1;
  }
  if addr == 65534 {
    return 2;
  }
  return 0;
}

/// Human name of a mac_short_class value. Complexity: O(1).
pub fn mac_short_class_name(c: Int) -> Str {
  if c == 0 { return "unicast"; }
  if c == 1 { return "broadcast"; }
  if c == 2 { return "no-address"; }
  return "unknown";
}

/// True when `addr` is the MAC broadcast short address 0xFFFF.
/// Complexity: O(1).
pub fn mac_short_is_broadcast(addr: Int) -> Bool {
  return addr == 65535;
}

/// Parse one IEEE 802.15.4 MAC frame from the start of `data`. The buffer
/// is a complete PSDU: MAC header, payload and the trailing 2 bytes of FCS
/// (located at `data.len() - 2`, never verified). The addressing fields are
/// walked in order (destination PAN, destination address, source PAN unless
/// PAN ID compression applies, source address); short addresses and PAN IDs
/// are little-endian 16-bit, extended addresses are 8 raw bytes.
///
/// Errors (all stable, `N` is the absolute byte offset):
///   * `zigbee: truncated mac frame at byte N` -- the header or an
///     addressing field does not fit before the FCS;
///   * `zigbee: impossible mac length at byte N` -- a beacon GTS or pending
///     address count cannot possibly fit in the remaining frame;
///   * `zigbee: bad mac addressing mode at byte 0` -- destination or source
///     addressing mode is the reserved value 1;
///   * `zigbee: unsupported mac frame type at byte 0` -- frame type 4..7;
///   * `zigbee: mac sequence number suppression unsupported at byte 0` --
///     frame control bit 8 (802.15.4-2015) is set;
///   * `zigbee: mac information elements unsupported at byte 0` -- frame
///     control bit 9 (802.15.4-2015 IE present) is set;
///   * `zigbee: truncated mac beacon at byte N` -- a beacon payload field
///     does not fit;
///   * `zigbee: truncated mac command frame at byte N` -- a MAC command
///     frame without its 1-byte command identifier.
/// Complexity: O(addressing + beacon counts + payload span).
pub fn mac_parse(data: &Vec[UInt8]) -> Result[MacFrame, Str] {
  let n = data.len();
  if n < 2 {
    return _err_mac("zigbee: truncated mac frame at byte " + _itoa(n));
  }
  let fcf = _le16(data, 0);
  let frame_type = fcf % 8;
  if frame_type > 3 {
    return _err_mac("zigbee: unsupported mac frame type at byte 0");
  }
  let security = (fcf / 8) % 2 == 1;
  let frame_pending = (fcf / 16) % 2 == 1;
  let ack_request = (fcf / 32) % 2 == 1;
  let pan_compress = (fcf / 64) % 2 == 1;
  let reserved_bits = (fcf / 128) % 8;
  if (reserved_bits / 2) % 2 == 1 {
    return _err_mac("zigbee: mac sequence number suppression unsupported at byte 0");
  }
  if (reserved_bits / 4) % 2 == 1 {
    return _err_mac("zigbee: mac information elements unsupported at byte 0");
  }
  let dest_mode = (fcf / 1024) % 4;
  let frame_version = (fcf / 4096) % 4;
  let src_mode = (fcf / 16384) % 4;
  if dest_mode == 1 || src_mode == 1 {
    return _err_mac("zigbee: bad mac addressing mode at byte 0");
  }
  let limit = n - 2;
  var off = 2;
  if !_fits(off, 1, limit) {
    return _err_mac("zigbee: truncated mac frame at byte " + _itoa(_fault(off, limit)));
  }
  let seq = _byte(data, off);
  off = off + 1;
  var dest_pan = -1;
  var src_pan = -1;
  var dest_short = -1;
  var src_short = -1;
  var dest_ext = Vec[UInt8].new();
  var src_ext = Vec[UInt8].new();
  if dest_mode != 0 {
    if !_fits(off, 2, limit) {
      return _err_mac("zigbee: truncated mac frame at byte " + _itoa(_fault(off, limit)));
    }
    dest_pan = _le16(data, off);
    off = off + 2;
    if dest_mode == 2 {
      if !_fits(off, 2, limit) {
        return _err_mac("zigbee: truncated mac frame at byte " + _itoa(_fault(off, limit)));
      }
      dest_short = _le16(data, off);
      off = off + 2;
    } else {
      if !_fits(off, 8, limit) {
        return _err_mac("zigbee: truncated mac frame at byte " + _itoa(_fault(off, limit)));
      }
      dest_ext = _copy8(data, off);
      off = off + 8;
    }
  }
  if src_mode != 0 {
    var src_pan_present = true;
    if pan_compress && dest_mode != 0 {
      src_pan_present = false;
    }
    if src_pan_present {
      if !_fits(off, 2, limit) {
        return _err_mac("zigbee: truncated mac frame at byte " + _itoa(_fault(off, limit)));
      }
      src_pan = _le16(data, off);
      off = off + 2;
    } else {
      src_pan = dest_pan;
    }
    if src_mode == 2 {
      if !_fits(off, 2, limit) {
        return _err_mac("zigbee: truncated mac frame at byte " + _itoa(_fault(off, limit)));
      }
      src_short = _le16(data, off);
      off = off + 2;
    } else {
      if !_fits(off, 8, limit) {
        return _err_mac("zigbee: truncated mac frame at byte " + _itoa(_fault(off, limit)));
      }
      src_ext = _copy8(data, off);
      off = off + 8;
    }
  }
  var aux_present = false;
  var aux_off = -1;
  if security {
    aux_present = true;
    aux_off = off;
  }
  let payload_off = off;
  let payload_len = limit - off;
  if payload_len < 0 {
    return _err_mac("zigbee: impossible mac length at byte " + _itoa(limit));
  }
  var beacon_order = -1;
  var superframe_order = -1;
  var final_cap_slot = -1;
  var battery_life = false;
  var pan_coordinator = false;
  var assoc_permit = false;
  var gts_permit = false;
  var gts_addrs = Vec[Int].new();
  var gts_starts = Vec[Int].new();
  var gts_lens = Vec[Int].new();
  var pend_short = Vec[Int].new();
  var pend_ext = Vec[UInt8].new();
  var beacon_end = -1;
  var command_id = -1;
  var command_data_off = -1;
  var command_data_len = 0;
  if frame_type == 0 && !security {
    if !_fits(off, 2, limit) {
      return _err_mac("zigbee: truncated mac beacon at byte " + _itoa(_fault(off, limit)));
    }
    let sf = _le16(data, off);
    beacon_order = sf % 16;
    superframe_order = (sf / 16) % 16;
    final_cap_slot = (sf / 256) % 16;
    battery_life = (sf / 4096) % 2 == 1;
    pan_coordinator = (sf / 16384) % 2 == 1;
    assoc_permit = (sf / 32768) % 2 == 1;
    off = off + 2;
    if !_fits(off, 1, limit) {
      return _err_mac("zigbee: truncated mac beacon at byte " + _itoa(_fault(off, limit)));
    }
    let g = _byte(data, off);
    let gts_count = g % 8;
    gts_permit = (g / 128) % 2 == 1;
    off = off + 1;
    if gts_count * 3 > limit - off {
      return _err_mac("zigbee: impossible mac length at byte " + _itoa(off));
    }
    var k = 0;
    while k < gts_count {
      let addr = _le16(data, off);
      let sl = _byte(data, off + 2);
      gts_addrs.push(addr);
      gts_starts.push(sl % 16);
      gts_lens.push((sl / 16) % 16);
      off = off + 3;
      k = k + 1;
    }
    if !_fits(off, 1, limit) {
      return _err_mac("zigbee: truncated mac beacon at byte " + _itoa(_fault(off, limit)));
    }
    let p = _byte(data, off);
    let pend_short_n = p % 8;
    let pend_ext_n = (p / 16) % 8;
    off = off + 1;
    if pend_short_n * 2 + pend_ext_n * 8 > limit - off {
      return _err_mac("zigbee: impossible mac length at byte " + _itoa(off));
    }
    k = 0;
    while k < pend_short_n {
      pend_short.push(_le16(data, off));
      off = off + 2;
      k = k + 1;
    }
    k = 0;
    while k < pend_ext_n {
      var j = 0;
      while j < 8 {
        pend_ext.push(data[off + j]);
        j = j + 1;
      }
      off = off + 8;
      k = k + 1;
    }
    beacon_end = off;
  } elif frame_type == 3 && !security {
    if !_fits(off, 1, limit) {
      return _err_mac("zigbee: truncated mac command frame at byte " + _itoa(off));
    }
    command_id = _byte(data, off);
    command_data_off = off + 1;
    command_data_len = limit - off - 1;
  }
  let f = MacFrame{
    frame_type: frame_type;
    security: security;
    frame_pending: frame_pending;
    ack_request: ack_request;
    pan_compress: pan_compress;
    reserved_bits: reserved_bits;
    frame_version: frame_version;
    dest_mode: dest_mode;
    src_mode: src_mode;
    seq: seq;
    dest_pan: dest_pan;
    src_pan: src_pan;
    dest_short: dest_short;
    src_short: src_short;
    dest_ext: dest_ext;
    src_ext: src_ext;
    aux_present: aux_present;
    aux_off: aux_off;
    payload_off: payload_off;
    payload_len: payload_len;
    fcs_off: limit;
    consumed: n;
    beacon_order: beacon_order;
    superframe_order: superframe_order;
    final_cap_slot: final_cap_slot;
    battery_life: battery_life;
    pan_coordinator: pan_coordinator;
    assoc_permit: assoc_permit;
    gts_permit: gts_permit;
    gts_addrs: gts_addrs;
    gts_starts: gts_starts;
    gts_lens: gts_lens;
    pend_short: pend_short;
    pend_ext: pend_ext;
    beacon_end: beacon_end;
    command_id: command_id;
    command_data_off: command_data_off;
    command_data_len: command_data_len;
  };
  return _ok_mac(f);
}

// --------------------------------------------------
//  Public API: parsed MAC accessors
// --------------------------------------------------

/// MAC frame type of a parsed frame (0 beacon, 1 data, 2 ack, 3 command).
/// Complexity: O(1).
pub fn mac_frame_type(f: &MacFrame) -> Int {
  return f.frame_type;
}

/// True when the frame control security-enabled bit is set; the auxiliary
/// security header and the secured payload stay opaque.
/// Complexity: O(1).
pub fn mac_security_enabled(f: &MacFrame) -> Bool {
  return f.security;
}

/// True when the frame-pending bit is set. Complexity: O(1).
pub fn mac_frame_pending(f: &MacFrame) -> Bool {
  return f.frame_pending;
}

/// True when the acknowledgement-request bit is set. Complexity: O(1).
pub fn mac_ack_request(f: &MacFrame) -> Bool {
  return f.ack_request;
}

/// True when the PAN ID compression bit is set. Complexity: O(1).
pub fn mac_pan_compression(f: &MacFrame) -> Bool {
  return f.pan_compress;
}

/// Frame control bits 7..9 as read (bit 8 is 802.15.4-2015 sequence-number
/// suppression, bit 9 IE present; either is rejected during parse).
/// Complexity: O(1).
pub fn mac_reserved_bits(f: &MacFrame) -> Int {
  return f.reserved_bits;
}

/// Frame version: 0 (2003), 1 (2006), 2 (2015) or 3.
/// Complexity: O(1).
pub fn mac_frame_version(f: &MacFrame) -> Int {
  return f.frame_version;
}

/// Destination addressing mode: 0 none, 2 short, 3 extended.
/// Complexity: O(1).
pub fn mac_dest_mode(f: &MacFrame) -> Int {
  return f.dest_mode;
}

/// Source addressing mode: 0 none, 2 short, 3 extended.
/// Complexity: O(1).
pub fn mac_src_mode(f: &MacFrame) -> Int {
  return f.src_mode;
}

/// MAC sequence number (0..255). Complexity: O(1).
pub fn mac_seq(f: &MacFrame) -> Int {
  return f.seq;
}

/// Destination PAN ID, or -1 when the destination addressing fields are
/// absent. Complexity: O(1).
pub fn mac_dest_pan(f: &MacFrame) -> Int {
  return f.dest_pan;
}

/// Source PAN ID. -1 when the source addressing fields are absent; with
/// PAN ID compression it echoes the destination PAN ID without consuming
/// bytes. Complexity: O(1).
pub fn mac_src_pan(f: &MacFrame) -> Int {
  return f.src_pan;
}

/// 16-bit destination short address, or -1 when absent.
/// Complexity: O(1).
pub fn mac_dest_short(f: &MacFrame) -> Int {
  return f.dest_short;
}

/// 16-bit source short address, or -1 when absent. Complexity: O(1).
pub fn mac_src_short(f: &MacFrame) -> Int {
  return f.src_short;
}

/// Raw byte `i` (0..7) of the 64-bit destination extended address; -1 when
/// absent or out of range. Complexity: O(1).
pub fn mac_dest_ext_byte(f: &MacFrame, i: Int) -> Int {
  let d: Vec[UInt8] = f.dest_ext;
  if i < 0 || i >= d.len() {
    return -1;
  }
  let v: Int = (d[i] as Int) & 0xFF;
  return v;
}

/// Raw byte `i` (0..7) of the 64-bit source extended address; -1 when
/// absent or out of range. Complexity: O(1).
pub fn mac_src_ext_byte(f: &MacFrame, i: Int) -> Int {
  let d: Vec[UInt8] = f.src_ext;
  if i < 0 || i >= d.len() {
    return -1;
  }
  let v: Int = (d[i] as Int) & 0xFF;
  return v;
}

/// Number of stored destination extended-address bytes: 8 when present,
/// 0 when absent. Complexity: O(1).
pub fn mac_dest_ext_len(f: &MacFrame) -> Int {
  let d: Vec[UInt8] = f.dest_ext;
  return d.len();
}

/// Number of stored source extended-address bytes: 8 when present, 0 when
/// absent. Complexity: O(1).
pub fn mac_src_ext_len(f: &MacFrame) -> Int {
  let d: Vec[UInt8] = f.src_ext;
  return d.len();
}

/// True when an auxiliary security header follows the addressing fields.
/// Its bytes are opaque: the header length depends on the key identifier
/// mode, which this codec does not decode.
/// Complexity: O(1).
pub fn mac_aux_security_present(f: &MacFrame) -> Bool {
  return f.aux_present;
}

/// Absolute offset of the auxiliary security header, or -1 when the frame
/// is not secured. Complexity: O(1).
pub fn mac_aux_security_off(f: &MacFrame) -> Int {
  return f.aux_off;
}

/// Number of MAC header bytes before the payload: 3 (frame control and
/// sequence number) plus the addressing fields present.
/// Complexity: O(1).
pub fn mac_header_len(f: &MacFrame) -> Int {
  return f.payload_off;
}

/// Absolute offset of the first payload byte. For a secured frame this is
/// the auxiliary security header, not application data.
/// Complexity: O(1).
pub fn mac_payload_off(f: &MacFrame) -> Int {
  return f.payload_off;
}

/// Number of payload bytes (everything between the header and the FCS).
/// Complexity: O(1).
pub fn mac_payload_len(f: &MacFrame) -> Int {
  return f.payload_len;
}

/// Absolute offset of the two FCS bytes (the last two bytes of the input).
/// Complexity: O(1).
pub fn mac_fcs_off(f: &MacFrame) -> Int {
  return f.fcs_off;
}

/// Number of bytes consumed from the input by the parse (the whole input on
/// success). Complexity: O(1).
pub fn mac_consumed(f: &MacFrame) -> Int {
  return f.consumed;
}

/// Copy the MAC payload out of `data` (the buffer passed to mac_parse):
/// `payload_len` bytes starting at `payload_off`.
/// Err("zigbee: mac payload out of bounds at byte N") when the recorded
/// span does not fit in `data`. Complexity: O(payload_len).
pub fn mac_payload(data: &Vec[UInt8], f: &MacFrame) -> Result[Vec[UInt8], Str] {
  let off: Int = f.payload_off;
  let len: Int = f.payload_len;
  if off < 0 || len < 0 {
    return _err_bytes("zigbee: mac payload out of bounds at byte 0");
  }
  if off + len > data.len() {
    return _err_bytes("zigbee: mac payload out of bounds at byte " + _itoa(data.len()));
  }
  return _ok_bytes(_copy_span(data, off, len));
}

/// Copy the two FCS bytes out of `data` (the buffer passed to mac_parse).
/// The bytes are returned as read and are never verified.
/// Err("zigbee: mac fcs out of bounds at byte N") when they do not fit.
/// Complexity: O(1).
pub fn mac_fcs_bytes(data: &Vec[UInt8], f: &MacFrame) -> Result[Vec[UInt8], Str] {
  let off: Int = f.fcs_off;
  if off < 0 || off + 2 > data.len() {
    return _err_bytes("zigbee: mac fcs out of bounds at byte " + _itoa(data.len()));
  }
  return _ok_bytes(_copy_span(data, off, 2));
}

/// The two FCS bytes as a little-endian unsigned 16-bit value (0..65535).
/// Err("zigbee: mac fcs out of bounds at byte N") when they do not fit.
/// Complexity: O(1).
pub fn mac_fcs_value(data: &Vec[UInt8], f: &MacFrame) -> Result[Int, Str] {
  let off: Int = f.fcs_off;
  if off < 0 || off + 2 > data.len() {
    return _err_int("zigbee: mac fcs out of bounds at byte " + _itoa(data.len()));
  }
  return _ok_int(_le16(data, off));
}

/// Beacon transmission order (0..15), or -1 when the frame is not an
/// unsecured beacon. Complexity: O(1).
pub fn mac_beacon_order(f: &MacFrame) -> Int {
  return f.beacon_order;
}

/// Beacon superframe order (0..15), or -1 when not an unsecured beacon.
/// Complexity: O(1).
pub fn mac_superframe_order(f: &MacFrame) -> Int {
  return f.superframe_order;
}

/// Beacon final CAP slot (0..15), or -1 when not an unsecured beacon.
/// Complexity: O(1).
pub fn mac_final_cap_slot(f: &MacFrame) -> Int {
  return f.final_cap_slot;
}

/// True when the beacon battery-life-extension bit is set.
/// Complexity: O(1).
pub fn mac_battery_life(f: &MacFrame) -> Bool {
  return f.battery_life;
}

/// True when the beacon PAN-coordinator bit is set. Complexity: O(1).
pub fn mac_pan_coordinator(f: &MacFrame) -> Bool {
  return f.pan_coordinator;
}

/// True when the beacon association-permit bit is set. Complexity: O(1).
pub fn mac_assoc_permit(f: &MacFrame) -> Bool {
  return f.assoc_permit;
}

/// True when the beacon GTS permit bit is set. Complexity: O(1).
pub fn mac_gts_permit(f: &MacFrame) -> Bool {
  return f.gts_permit;
}

/// Number of GTS descriptors parsed from a beacon (0..7). Only meaningful
/// when the frame is an unsecured beacon.
/// Complexity: O(1).
pub fn mac_gts_count(f: &MacFrame) -> Int {
  let a: Vec[Int] = f.gts_addrs;
  return a.len();
}

/// 16-bit short address of GTS descriptor `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn mac_gts_addr(f: &MacFrame, i: Int) -> Int {
  let a: Vec[Int] = f.gts_addrs;
  if i < 0 || i >= a.len() {
    return -1;
  }
  let v: Int = a[i];
  return v;
}

/// GTS starting slot (0..15) of descriptor `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn mac_gts_start_slot(f: &MacFrame, i: Int) -> Int {
  let a: Vec[Int] = f.gts_starts;
  if i < 0 || i >= a.len() {
    return -1;
  }
  let v: Int = a[i];
  return v;
}

/// GTS length (0..15) of descriptor `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn mac_gts_length(f: &MacFrame, i: Int) -> Int {
  let a: Vec[Int] = f.gts_lens;
  if i < 0 || i >= a.len() {
    return -1;
  }
  let v: Int = a[i];
  return v;
}

/// Number of 16-bit pending short addresses in a beacon (0..7).
/// Complexity: O(1).
pub fn mac_pending_short_count(f: &MacFrame) -> Int {
  let a: Vec[Int] = f.pend_short;
  return a.len();
}

/// Number of 64-bit pending extended addresses in a beacon (0..7).
/// Complexity: O(1).
pub fn mac_pending_ext_count(f: &MacFrame) -> Int {
  let a: Vec[UInt8] = f.pend_ext;
  return a.len() / 8;
}

/// Pending short address `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn mac_pending_short(f: &MacFrame, i: Int) -> Int {
  let a: Vec[Int] = f.pend_short;
  if i < 0 || i >= a.len() {
    return -1;
  }
  let v: Int = a[i];
  return v;
}

/// Raw byte `k` (0..7) of pending extended address `i`, or -1 when out of
/// range. Complexity: O(1).
pub fn mac_pending_ext_byte(f: &MacFrame, i: Int, k: Int) -> Int {
  let a: Vec[UInt8] = f.pend_ext;
  if i < 0 || k < 0 {
    return -1;
  }
  if k >= 8 {
    return -1;
  }
  let pos = i * 8 + k;
  if pos >= a.len() {
    return -1;
  }
  let v: Int = (a[pos] as Int) & 0xFF;
  return v;
}

/// Absolute offset just past the beacon payload fields (superframe spec,
/// GTS descriptors, pending addresses), or -1 when the frame is not an
/// unsecured beacon. Complexity: O(1).
pub fn mac_beacon_end(f: &MacFrame) -> Int {
  return f.beacon_end;
}

/// MAC command identifier of a MAC command frame (1..255), or -1 when the
/// frame is not an unsecured command frame.
/// Complexity: O(1).
pub fn mac_command_id(f: &MacFrame) -> Int {
  return f.command_id;
}

/// Absolute offset of the first MAC command payload byte (after the
/// command identifier), or -1 when not an unsecured command frame.
/// Complexity: O(1).
pub fn mac_command_data_off(f: &MacFrame) -> Int {
  return f.command_data_off;
}

/// Number of MAC command payload bytes after the command identifier, or 0
/// when not an unsecured command frame. Complexity: O(1).
pub fn mac_command_data_len(f: &MacFrame) -> Int {
  return f.command_data_len;
}

// --------------------------------------------------
//  Public API: ZigBee NWK
// --------------------------------------------------

/// Human name of a NWK frame type: 0 Data, 1 NWK command; 2 reserved,
/// 3 Inter-PAN (not walked by this codec). Complexity: O(1).
pub fn nwk_frame_type_name(t: Int) -> Str {
  if t == 0 { return "Data"; }
  if t == 1 { return "NWK command"; }
  if t == 2 { return "Reserved"; }
  if t == 3 { return "Inter-PAN"; }
  return "Unknown";
}

/// Human name of a NWK command identifier. Identifiers 0x01..0x0f are named
/// (route request/reply, network status, leave, route record, rejoin,
/// link status, network report/update, end device timeout, link power
/// delta, commissioning); everything else is Reserved. Complexity: O(1).
pub fn nwk_command_name(id: Int) -> Str {
  if id == 1 { return "Route request"; }
  if id == 2 { return "Route reply"; }
  if id == 3 { return "Network status"; }
  if id == 4 { return "Leave"; }
  if id == 5 { return "Route record"; }
  if id == 6 { return "Rejoin request"; }
  if id == 7 { return "Rejoin response"; }
  if id == 8 { return "Link status"; }
  if id == 9 { return "Network report"; }
  if id == 10 { return "Network update"; }
  if id == 11 { return "End device timeout request"; }
  if id == 12 { return "End device timeout response"; }
  if id == 13 { return "Link power delta"; }
  if id == 14 { return "Commissioning request"; }
  if id == 15 { return "Commissioning response"; }
  return "Reserved";
}

/// Class of a 16-bit NWK address: 0 unicast, 1 broadcast to all devices
/// (0xFFFF), 2 broadcast to low-power routers (0xFFFB), 3 broadcast to
/// routers (0xFFFC), 4 broadcast to rx-on devices (0xFFFD), 5 reserved
/// broadcast range (0xFFF8..0xFFFE, excluding 0xFFFB..0xFFFD).
/// Complexity: O(1).
pub fn nwk_addr_class(addr: Int) -> Int {
  if addr == 65535 {
    return 1;
  }
  if addr == 65533 {
    return 4;
  }
  if addr == 65532 {
    return 3;
  }
  if addr == 65531 {
    return 2;
  }
  if addr >= 65528 {
    return 5;
  }
  return 0;
}

/// Human name of a nwk_addr_class value. Complexity: O(1).
pub fn nwk_addr_class_name(c: Int) -> Str {
  if c == 0 { return "unicast"; }
  if c == 1 { return "broadcast to all devices"; }
  if c == 2 { return "broadcast to low-power routers"; }
  if c == 3 { return "broadcast to routers"; }
  if c == 4 { return "broadcast to rx-on devices"; }
  if c == 5 { return "reserved broadcast"; }
  return "unknown";
}

/// True when `addr` is the NWK broadcast-to-all-devices address 0xFFFF.
/// Complexity: O(1).
pub fn nwk_is_broadcast(addr: Int) -> Bool {
  return addr == 65535;
}

/// Parse one ZigBee NWK frame header from the start of `data` (typically
/// the MAC payload, without the MAC FCS). `data` must hold exactly one NWK
/// frame: the payload runs to the end of the buffer.
///
/// Errors (all stable, `N` is the absolute byte offset):
///   * `zigbee: truncated nwk frame at byte N` -- a header field does not
///     fit in the buffer;
///   * `zigbee: impossible nwk length at byte N` -- the source route relay
///     count cannot possibly fit in the remaining bytes;
///   * `zigbee: unsupported nwk frame type at byte 0` -- frame type 2 or 3;
///   * `zigbee: truncated nwk command at byte N` -- an unsecured NWK
///     command frame without its 1-byte command identifier.
/// Complexity: O(header + relay count + payload span).
pub fn nwk_parse(data: &Vec[UInt8]) -> Result[NwkFrame, Str] {
  let n = data.len();
  if n < 2 {
    return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
  }
  let fcf = _le16(data, 0);
  let frame_type = fcf % 4;
  if frame_type > 1 {
    return _err_nwk("zigbee: unsupported nwk frame type at byte 0");
  }
  let protocol_version = (fcf / 4) % 16;
  let discover_route = (fcf / 64) % 4;
  let multicast = (fcf / 256) % 2 == 1;
  let security = (fcf / 512) % 2 == 1;
  let source_route = (fcf / 1024) % 2 == 1;
  let dest_ieee = (fcf / 2048) % 2 == 1;
  let src_ieee = (fcf / 4096) % 2 == 1;
  let end_device_initiator = (fcf / 8192) % 2 == 1;
  var off = 2;
  if !_fits(off, 4, n) {
    return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
  }
  let dest = _le16(data, off);
  off = off + 2;
  let src = _le16(data, off);
  off = off + 2;
  if !_fits(off, 1, n) {
    return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
  }
  let radius = _byte(data, off);
  off = off + 1;
  if !_fits(off, 1, n) {
    return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
  }
  let seq = _byte(data, off);
  off = off + 1;
  var dest_ext = Vec[UInt8].new();
  var src_ext = Vec[UInt8].new();
  if dest_ieee {
    if !_fits(off, 8, n) {
      return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
    }
    dest_ext = _copy8(data, off);
    off = off + 8;
  }
  if src_ieee {
    if !_fits(off, 8, n) {
      return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
    }
    src_ext = _copy8(data, off);
    off = off + 8;
  }
  var multicast_control = -1;
  var multicast_mode = -1;
  var multicast_radius = -1;
  var multicast_max_radius = -1;
  if multicast {
    if !_fits(off, 1, n) {
      return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
    }
    multicast_control = _byte(data, off);
    multicast_mode = multicast_control % 4;
    multicast_radius = (multicast_control / 4) % 8;
    multicast_max_radius = (multicast_control / 32) % 8;
    off = off + 1;
  }
  var relay_count = -1;
  var relay_index = -1;
  var relays = Vec[Int].new();
  if source_route {
    if !_fits(off, 1, n) {
      return _err_nwk("zigbee: truncated nwk frame at byte " + _itoa(n));
    }
    relay_count = _byte(data, off);
    off = off + 1;
    if relay_count * 2 + 1 > n - off {
      return _err_nwk("zigbee: impossible nwk length at byte " + _itoa(off));
    }
    var k = 0;
    while k < relay_count {
      relays.push(_le16(data, off));
      off = off + 2;
      k = k + 1;
    }
    relay_index = _byte(data, off);
    off = off + 1;
  }
  var command_id = -1;
  let payload_off = off;
  let payload_len = n - off;
  if frame_type == 1 && !security {
    if payload_len < 1 {
      return _err_nwk("zigbee: truncated nwk command at byte " + _itoa(off));
    }
    command_id = _byte(data, off);
  }
  let f = NwkFrame{
    frame_type: frame_type;
    protocol_version: protocol_version;
    discover_route: discover_route;
    multicast: multicast;
    security: security;
    source_route: source_route;
    dest_ieee: dest_ieee;
    src_ieee: src_ieee;
    end_device_initiator: end_device_initiator;
    dest: dest;
    src: src;
    radius: radius;
    seq: seq;
    dest_ext: dest_ext;
    src_ext: src_ext;
    multicast_control: multicast_control;
    multicast_mode: multicast_mode;
    multicast_radius: multicast_radius;
    multicast_max_radius: multicast_max_radius;
    relay_count: relay_count;
    relays: relays;
    relay_index: relay_index;
    command_id: command_id;
    payload_off: payload_off;
    payload_len: payload_len;
    consumed: n;
  };
  return _ok_nwk(f);
}

/// NWK frame type of a parsed frame (0 data, 1 NWK command).
/// Complexity: O(1).
pub fn nwk_frame_type(f: &NwkFrame) -> Int {
  return f.frame_type;
}

/// NWK protocol version (0..15). Complexity: O(1).
pub fn nwk_protocol_version(f: &NwkFrame) -> Int {
  return f.protocol_version;
}

/// Discover-route subfield: 0 suppress, 1 enable, 2 reserved, 3 force.
/// Complexity: O(1).
pub fn nwk_discover_route(f: &NwkFrame) -> Int {
  return f.discover_route;
}

/// True when the multicast flag is set. Complexity: O(1).
pub fn nwk_multicast(f: &NwkFrame) -> Bool {
  return f.multicast;
}

/// True when the security flag is set; the NWK payload stays opaque.
/// Complexity: O(1).
pub fn nwk_security_enabled(f: &NwkFrame) -> Bool {
  return f.security;
}

/// True when the source route subframe is present. Complexity: O(1).
pub fn nwk_source_route(f: &NwkFrame) -> Bool {
  return f.source_route;
}

/// True when a 64-bit destination IEEE address follows the header.
/// Complexity: O(1).
pub fn nwk_dest_ieee_present(f: &NwkFrame) -> Bool {
  return f.dest_ieee;
}

/// True when a 64-bit source IEEE address follows the header.
/// Complexity: O(1).
pub fn nwk_src_ieee_present(f: &NwkFrame) -> Bool {
  return f.src_ieee;
}

/// True when the end-device-initiator bit (ZigBee PRO r21, frame control
/// bit 13) is set. Complexity: O(1).
pub fn nwk_end_device_initiator(f: &NwkFrame) -> Bool {
  return f.end_device_initiator;
}

/// 16-bit NWK destination address. Complexity: O(1).
pub fn nwk_dest(f: &NwkFrame) -> Int {
  return f.dest;
}

/// 16-bit NWK source address. Complexity: O(1).
pub fn nwk_src(f: &NwkFrame) -> Int {
  return f.src;
}

/// NWK radius (0..255). Complexity: O(1).
pub fn nwk_radius(f: &NwkFrame) -> Int {
  return f.radius;
}

/// NWK sequence number (0..255). Complexity: O(1).
pub fn nwk_seq(f: &NwkFrame) -> Int {
  return f.seq;
}

/// Raw byte `i` (0..7) of the 64-bit destination IEEE address; -1 when
/// absent or out of range. Complexity: O(1).
pub fn nwk_dest_ext_byte(f: &NwkFrame, i: Int) -> Int {
  let d: Vec[UInt8] = f.dest_ext;
  if i < 0 || i >= d.len() {
    return -1;
  }
  let v: Int = (d[i] as Int) & 0xFF;
  return v;
}

/// Raw byte `i` (0..7) of the 64-bit source IEEE address; -1 when absent
/// or out of range. Complexity: O(1).
pub fn nwk_src_ext_byte(f: &NwkFrame, i: Int) -> Int {
  let d: Vec[UInt8] = f.src_ext;
  if i < 0 || i >= d.len() {
    return -1;
  }
  let v: Int = (d[i] as Int) & 0xFF;
  return v;
}

/// Number of stored destination IEEE address bytes (8 or 0).
/// Complexity: O(1).
pub fn nwk_dest_ext_len(f: &NwkFrame) -> Int {
  let d: Vec[UInt8] = f.dest_ext;
  return d.len();
}

/// Number of stored source IEEE address bytes (8 or 0).
/// Complexity: O(1).
pub fn nwk_src_ext_len(f: &NwkFrame) -> Int {
  let d: Vec[UInt8] = f.src_ext;
  return d.len();
}

/// Raw multicast control byte, or -1 when the multicast flag is clear.
/// Complexity: O(1).
pub fn nwk_multicast_control(f: &NwkFrame) -> Int {
  return f.multicast_control;
}

/// Multicast mode (0 non-member, 1 member), or -1 when absent.
/// Complexity: O(1).
pub fn nwk_multicast_mode(f: &NwkFrame) -> Int {
  return f.multicast_mode;
}

/// Non-member multicast radius, or -1 when absent. Complexity: O(1).
pub fn nwk_multicast_radius(f: &NwkFrame) -> Int {
  return f.multicast_radius;
}

/// Maximum non-member multicast radius, or -1 when absent.
/// Complexity: O(1).
pub fn nwk_multicast_max_radius(f: &NwkFrame) -> Int {
  return f.multicast_max_radius;
}

/// Source route relay count, or -1 when the source route subframe is
/// absent. Complexity: O(1).
pub fn nwk_relay_count(f: &NwkFrame) -> Int {
  return f.relay_count;
}

/// Relay list entry `i` (16-bit address), or -1 when out of range.
/// Complexity: O(1).
pub fn nwk_relay(f: &NwkFrame, i: Int) -> Int {
  let a: Vec[Int] = f.relays;
  if i < 0 || i >= a.len() {
    return -1;
  }
  let v: Int = a[i];
  return v;
}

/// Source route relay index, or -1 when the source route subframe is
/// absent. Complexity: O(1).
pub fn nwk_relay_index(f: &NwkFrame) -> Int {
  return f.relay_index;
}

/// NWK command identifier of an unsecured NWK command frame, or -1 for a
/// data frame (or a secured command frame, whose payload is opaque).
/// Complexity: O(1).
pub fn nwk_command_id(f: &NwkFrame) -> Int {
  return f.command_id;
}

/// Number of NWK header bytes before the payload.
/// Complexity: O(1).
pub fn nwk_header_len(f: &NwkFrame) -> Int {
  return f.payload_off;
}

/// Absolute offset of the first NWK payload byte.
/// Complexity: O(1).
pub fn nwk_payload_off(f: &NwkFrame) -> Int {
  return f.payload_off;
}

/// Number of NWK payload bytes (to the end of the input buffer).
/// Complexity: O(1).
pub fn nwk_payload_len(f: &NwkFrame) -> Int {
  return f.payload_len;
}

/// Number of bytes consumed from the input by the parse (the whole input on
/// success). Complexity: O(1).
pub fn nwk_consumed(f: &NwkFrame) -> Int {
  return f.consumed;
}

/// Copy the NWK payload out of `data` (the buffer passed to nwk_parse):
/// `payload_len` bytes starting at `payload_off`.
/// Err("zigbee: nwk payload out of bounds at byte N") when the recorded
/// span does not fit in `data`. Complexity: O(payload_len).
pub fn nwk_payload(data: &Vec[UInt8], f: &NwkFrame) -> Result[Vec[UInt8], Str] {
  let off: Int = f.payload_off;
  let len: Int = f.payload_len;
  if off < 0 || len < 0 {
    return _err_bytes("zigbee: nwk payload out of bounds at byte 0");
  }
  if off + len > data.len() {
    return _err_bytes("zigbee: nwk payload out of bounds at byte " + _itoa(data.len()));
  }
  return _ok_bytes(_copy_span(data, off, len));
}

// --------------------------------------------------
//  Public API: ZigBee APS
// --------------------------------------------------

/// Human name of an APS frame type: 0 Data, 1 Command, 2 Acknowledgement;
/// 3 (Inter-PAN) is not walked by this codec. Complexity: O(1).
pub fn aps_frame_type_name(t: Int) -> Str {
  if t == 0 { return "Data"; }
  if t == 1 { return "Command"; }
  if t == 2 { return "Acknowledgement"; }
  if t == 3 { return "Inter-PAN"; }
  return "Unknown";
}

/// Human name of an APS delivery mode: 0 Unicast, 1 Broadcast, 2 Group;
/// 3 is reserved. Complexity: O(1).
pub fn aps_delivery_name(m: Int) -> Str {
  if m == 0 { return "Unicast"; }
  if m == 1 { return "Broadcast"; }
  if m == 2 { return "Group"; }
  if m == 3 { return "Reserved"; }
  return "Unknown";
}

/// Class of a 16-bit APS group address: 0 reserved (0x0000), 1 assignable
/// group (0x0001..0xFFF7, the ZigBee group range), 2 reserved
/// (0xFFF8..0xFFFE), 3 broadcast group (0xFFFF, all groups), 4 out of
/// range (negative or above 0xFFFF). Complexity: O(1).
pub fn aps_group_class(addr: Int) -> Int {
  if addr < 0 {
    return 4;
  }
  if addr > 65535 {
    return 4;
  }
  if addr == 0 {
    return 0;
  }
  if addr == 65535 {
    return 3;
  }
  if addr >= 65528 {
    return 2;
  }
  return 1;
}

/// Human name of an aps_group_class value. Complexity: O(1).
pub fn aps_group_class_name(c: Int) -> Str {
  if c == 0 { return "reserved"; }
  if c == 1 { return "group"; }
  if c == 2 { return "reserved range"; }
  if c == 3 { return "broadcast group"; }
  if c == 4 { return "out of range"; }
  return "unknown";
}

/// Parse one ZigBee APS frame header from the start of `data` (typically
/// the NWK payload). `data` must hold exactly one APS frame: the payload
/// runs to the end of the buffer.
///
/// Field presence follows the ZigBee APS frame format: data and command
/// frames carry the destination endpoint only in unicast mode, the group
/// address only in group mode, then cluster and profile identifiers and the
/// source endpoint; acknowledgement frames carry the destination endpoint
/// and the APS counter only. When the extended-header bit is set, the
/// 1-byte fragmentation field (and, when fragmentation is not none, the
/// block number byte) is decoded; any further extended-header content is
/// left in the payload span.
///
/// Errors (all stable, `N` is the absolute byte offset):
///   * `zigbee: truncated aps frame at byte N` -- a header field does not
///     fit in the buffer;
///   * `zigbee: unsupported aps frame type at byte 0` -- frame type 3;
///   * `zigbee: bad aps delivery mode at byte 0` -- delivery mode 3;
///   * `zigbee: truncated aps extended header at byte N` -- the
///     fragmentation field or block number byte is missing.
/// Complexity: O(header + payload span).
pub fn aps_parse(data: &Vec[UInt8]) -> Result[ApsFrame, Str] {
  let n = data.len();
  if n < 1 {
    return _err_aps("zigbee: truncated aps frame at byte 0");
  }
  let fc = _byte(data, 0);
  let frame_type = fc % 4;
  let delivery_mode = (fc / 4) % 4;
  let ack_format = (fc / 16) % 2 == 1;
  let security = (fc / 32) % 2 == 1;
  let ack_request = (fc / 64) % 2 == 1;
  let ext_present = fc / 128 == 1;
  if frame_type == 3 {
    return _err_aps("zigbee: unsupported aps frame type at byte 0");
  }
  if delivery_mode == 3 {
    return _err_aps("zigbee: bad aps delivery mode at byte 0");
  }
  var off = 1;
  var dest_endpoint = -1;
  var group_addr = -1;
  var cluster_id = -1;
  var profile_id = -1;
  var src_endpoint = -1;
  if frame_type == 2 {
    if !_fits(off, 1, n) {
      return _err_aps("zigbee: truncated aps frame at byte " + _itoa(n));
    }
    dest_endpoint = _byte(data, off);
    off = off + 1;
  } else {
    if delivery_mode == 0 {
      if !_fits(off, 1, n) {
        return _err_aps("zigbee: truncated aps frame at byte " + _itoa(n));
      }
      dest_endpoint = _byte(data, off);
      off = off + 1;
    }
    if delivery_mode == 2 {
      if !_fits(off, 2, n) {
        return _err_aps("zigbee: truncated aps frame at byte " + _itoa(n));
      }
      group_addr = _le16(data, off);
      off = off + 2;
    }
    if !_fits(off, 2, n) {
      return _err_aps("zigbee: truncated aps frame at byte " + _itoa(n));
    }
    cluster_id = _le16(data, off);
    off = off + 2;
    if !_fits(off, 2, n) {
      return _err_aps("zigbee: truncated aps frame at byte " + _itoa(n));
    }
    profile_id = _le16(data, off);
    off = off + 2;
    if !_fits(off, 1, n) {
      return _err_aps("zigbee: truncated aps frame at byte " + _itoa(n));
    }
    src_endpoint = _byte(data, off);
    off = off + 1;
  }
  if !_fits(off, 1, n) {
    return _err_aps("zigbee: truncated aps frame at byte " + _itoa(n));
  }
  let counter = _byte(data, off);
  off = off + 1;
  var ext_frag_bits = -1;
  var ext_block = -1;
  if ext_present {
    if !_fits(off, 1, n) {
      return _err_aps("zigbee: truncated aps extended header at byte " + _itoa(n));
    }
    ext_frag_bits = _byte(data, off) % 4;
    off = off + 1;
    if ext_frag_bits != 0 {
      if !_fits(off, 1, n) {
        return _err_aps("zigbee: truncated aps extended header at byte " + _itoa(n));
      }
      ext_block = _byte(data, off);
      off = off + 1;
    }
  }
  let f = ApsFrame{
    frame_type: frame_type;
    delivery_mode: delivery_mode;
    ack_format: ack_format;
    security: security;
    ack_request: ack_request;
    ext_present: ext_present;
    dest_endpoint: dest_endpoint;
    group_addr: group_addr;
    cluster_id: cluster_id;
    profile_id: profile_id;
    src_endpoint: src_endpoint;
    counter: counter;
    ext_frag_bits: ext_frag_bits;
    ext_block: ext_block;
    payload_off: off;
    payload_len: n - off;
    consumed: n;
  };
  return _ok_aps(f);
}

/// APS frame type of a parsed frame (0 data, 1 command, 2 ack).
/// Complexity: O(1).
pub fn aps_frame_type(f: &ApsFrame) -> Int {
  return f.frame_type;
}

/// APS delivery mode (0 unicast, 1 broadcast, 2 group).
/// Complexity: O(1).
pub fn aps_delivery_mode(f: &ApsFrame) -> Int {
  return f.delivery_mode;
}

/// True when frame control bit 4 is set (acknowledgement format for
/// ZigBee 2007+, indirect mode in ZigBee 2004).
/// Complexity: O(1).
pub fn aps_ack_format(f: &ApsFrame) -> Bool {
  return f.ack_format;
}

/// True when the APS security bit is set; the ASDU stays opaque.
/// Complexity: O(1).
pub fn aps_security_enabled(f: &ApsFrame) -> Bool {
  return f.security;
}

/// True when the APS acknowledgement-request bit is set.
/// Complexity: O(1).
pub fn aps_ack_request(f: &ApsFrame) -> Bool {
  return f.ack_request;
}

/// True when the extended-header-present bit is set.
/// Complexity: O(1).
pub fn aps_ext_header_present(f: &ApsFrame) -> Bool {
  return f.ext_present;
}

/// APS destination endpoint (0..255), or -1 when the field is absent.
/// Complexity: O(1).
pub fn aps_dest_endpoint(f: &ApsFrame) -> Int {
  return f.dest_endpoint;
}

/// APS group address (16-bit), or -1 when the frame is not in group mode.
/// Complexity: O(1).
pub fn aps_group_addr(f: &ApsFrame) -> Int {
  return f.group_addr;
}

/// APS cluster identifier (16-bit), or -1 for acknowledgement frames.
/// Complexity: O(1).
pub fn aps_cluster_id(f: &ApsFrame) -> Int {
  return f.cluster_id;
}

/// APS profile identifier (16-bit), or -1 for acknowledgement frames.
/// Complexity: O(1).
pub fn aps_profile_id(f: &ApsFrame) -> Int {
  return f.profile_id;
}

/// APS source endpoint (0..255), or -1 for acknowledgement frames.
/// Complexity: O(1).
pub fn aps_src_endpoint(f: &ApsFrame) -> Int {
  return f.src_endpoint;
}

/// APS counter (0..255). Complexity: O(1).
pub fn aps_counter(f: &ApsFrame) -> Int {
  return f.counter;
}

/// Extended-header fragmentation bits (0 none, 1 first, 2 middle, 3 last),
/// or -1 when the extended header is absent. Complexity: O(1).
pub fn aps_ext_frag_bits(f: &ApsFrame) -> Int {
  return f.ext_frag_bits;
}

/// Extended-header block number, or -1 when absent (no extended header, or
/// fragmentation bits are none). Complexity: O(1).
pub fn aps_ext_block(f: &ApsFrame) -> Int {
  return f.ext_block;
}

/// Number of APS header bytes before the payload (including the extended
/// header bytes that were decoded). Complexity: O(1).
pub fn aps_header_len(f: &ApsFrame) -> Int {
  return f.payload_off;
}

/// Absolute offset of the first APS payload byte.
/// Complexity: O(1).
pub fn aps_payload_off(f: &ApsFrame) -> Int {
  return f.payload_off;
}

/// Number of APS payload bytes (to the end of the input buffer).
/// Complexity: O(1).
pub fn aps_payload_len(f: &ApsFrame) -> Int {
  return f.payload_len;
}

/// Number of bytes consumed from the input by the parse (the whole input on
/// success). Complexity: O(1).
pub fn aps_consumed(f: &ApsFrame) -> Int {
  return f.consumed;
}

/// Copy the APS payload out of `data` (the buffer passed to aps_parse):
/// `payload_len` bytes starting at `payload_off`.
/// Err("zigbee: aps payload out of bounds at byte N") when the recorded
/// span does not fit in `data`. Complexity: O(payload_len).
pub fn aps_payload(data: &Vec[UInt8], f: &ApsFrame) -> Result[Vec[UInt8], Str] {
  let off: Int = f.payload_off;
  let len: Int = f.payload_len;
  if off < 0 || len < 0 {
    return _err_bytes("zigbee: aps payload out of bounds at byte 0");
  }
  if off + len > data.len() {
    return _err_bytes("zigbee: aps payload out of bounds at byte " + _itoa(data.len()));
  }
  return _ok_bytes(_copy_span(data, off, len));
}
