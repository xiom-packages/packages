// XIOM -- xiom.wireless: IEEE 802.11 MAC frame structure parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the *structure* of an IEEE 802.11 MAC frame -- no cryptography, no
// PHY, no over-the-air semantics. This module parses:
//   * the 2-byte Frame Control field (little-endian u16): protocol version,
//     type, subtype and the eight flag bits;
//   * the Duration/ID field and the Address 1..4 matrix (presence decided
//     by type, subtype and the To DS / From DS bits);
//   * the Sequence Control field (fragment number low 4 bits, sequence
//     number high 12 bits) where the frame type has one;
//   * the optional QoS Control field of QoS data frames (TID, EOSP, ack
//     policy, A-MSDU, TXOP limit) and the presence of a 4-byte HT Control
//     field when the Order bit marks one;
//   * the fixed fields of the common management bodies (beacon / probe
//     response, probe request, association / reassociation request and
//     response, authentication, deauthentication / dissociation, ATIM,
//     action) and the information element TLV walk over the body tail.
//
// Subtype numbering follows IEEE 802.11-2016 Table 9-1 for every frame
// type. Control subtypes 2..7 (Trigger, TACK, beamforming report poll, VHT
// NDP announcement, control frame extension, control wrapper) are named but
// not structurally decoded: their layouts are variable or extension
// specific, so the parser rejects them instead of guessing. Control
// subtypes 0..1 are reserved and rejected as well.
//
// Parsing policy:
//   * a frame that does not fit the buffer is rejected with an error that
//     names the byte offset and the missing length;
//   * management and control frames whose To DS / From DS bits are set are
//     rejected (only data and extension frames use the DS matrix);
//   * control subtypes 0..7 are rejected (0..1 reserved, 2..7 named but not
//     structurally decoded); reserved management subtypes parse structurally
//     but their body parser reports them unsupported;
//   * information elements with an impossible length (a TLV that crosses
//     the body end, a DS/TIM/country/RSN/HT/VHT element whose payload cannot
//     hold its declared fields) are rejected;
//   * unknown information elements are preserved raw: the walk records id,
//     payload offset and payload length for every element in order.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with `(data[pos] as Int)
//     & 0xFF` before entering Int arithmetic.
//   * bitfields (frame control, flags, sequence, QoS, capability) are
//     extracted with divisor/modulo arithmetic only -- sign-bit bit tests
//     are unreliable in this compiler, so no `&` mask touches raw fields.
//   * WirelessFrame / WirelessMgmt are constructed inside their parse
//     functions and cross function boundaries only by reference or through
//     the _ok_* helpers, following the xiom.acpi precedent.
//   * multi-byte string fields stay as raw byte vectors; no Str ever comes
//     out of a Vec and gets compared with `==` (BUG 17 discipline).
// See SPEC.md for the byte-level layouts, the error catalog and the test
// plan.

module xiom.wireless

/// Package version string. Complexity: O(1).
pub fn wireless_version() -> Str {
  return "xiom.wireless 0.1.0";
}

// --------------------------------------------------
//  Public constants: frame types and subtypes
// --------------------------------------------------

/// Frame Control type 0: management frames.
pub const WIRELESS_TYPE_MANAGEMENT: Int = 0;
/// Frame Control type 1: control frames.
pub const WIRELESS_TYPE_CONTROL: Int = 1;
/// Frame Control type 2: data frames.
pub const WIRELESS_TYPE_DATA: Int = 2;
/// Frame Control type 3: extension frames.
pub const WIRELESS_TYPE_EXTENSION: Int = 3;

/// Control subtype 2: Trigger.
pub const WIRELESS_CTRL_TRIGGER: Int = 2;
/// Control subtype 3: TACK.
pub const WIRELESS_CTRL_TACK: Int = 3;
/// Control subtype 4: beamforming report poll.
pub const WIRELESS_CTRL_BEAMFORMING_REPORT_POLL: Int = 4;
/// Control subtype 5: VHT NDP announcement.
pub const WIRELESS_CTRL_VHT_NDP_ANNOUNCEMENT: Int = 5;
/// Control subtype 6: control frame extension.
pub const WIRELESS_CTRL_CONTROL_FRAME_EXTENSION: Int = 6;
/// Control subtype 7: control wrapper.
pub const WIRELESS_CTRL_CONTROL_WRAPPER: Int = 7;
/// Control subtype 8: block ack request (BAR).
pub const WIRELESS_CTRL_BAR: Int = 8;
/// Control subtype 9: block ack (BA).
pub const WIRELESS_CTRL_BA: Int = 9;
/// Control subtype 10: PS-Poll (Duration/ID carries the AID).
pub const WIRELESS_CTRL_PS_POLL: Int = 10;
/// Control subtype 11: RTS.
pub const WIRELESS_CTRL_RTS: Int = 11;
/// Control subtype 12: CTS.
pub const WIRELESS_CTRL_CTS: Int = 12;
/// Control subtype 13: ACK.
pub const WIRELESS_CTRL_ACK: Int = 13;
/// Control subtype 14: CF-End.
pub const WIRELESS_CTRL_CF_END: Int = 14;
/// Control subtype 15: CF-End + CF-Ack.
pub const WIRELESS_CTRL_CF_END_ACK: Int = 15;

/// Management subtype 0: association request.
pub const WIRELESS_MGMT_ASSOC_REQ: Int = 0;
/// Management subtype 1: association response.
pub const WIRELESS_MGMT_ASSOC_RESP: Int = 1;
/// Management subtype 2: reassociation request.
pub const WIRELESS_MGMT_REASSOC_REQ: Int = 2;
/// Management subtype 3: reassociation response.
pub const WIRELESS_MGMT_REASSOC_RESP: Int = 3;
/// Management subtype 4: probe request.
pub const WIRELESS_MGMT_PROBE_REQ: Int = 4;
/// Management subtype 5: probe response.
pub const WIRELESS_MGMT_PROBE_RESP: Int = 5;
/// Management subtype 8: beacon.
pub const WIRELESS_MGMT_BEACON: Int = 8;
/// Management subtype 9: ATIM.
pub const WIRELESS_MGMT_ATIM: Int = 9;
/// Management subtype 10: disassociation.
pub const WIRELESS_MGMT_DISASSOC: Int = 10;
/// Management subtype 11: authentication.
pub const WIRELESS_MGMT_AUTH: Int = 11;
/// Management subtype 12: deauthentication.
pub const WIRELESS_MGMT_DEAUTH: Int = 12;
/// Management subtype 13: action.
pub const WIRELESS_MGMT_ACTION: Int = 13;
/// Management subtype 14: action no ack.
pub const WIRELESS_MGMT_ACTION_NO_ACK: Int = 14;

// --------------------------------------------------
//  Public constants: information element ids
// --------------------------------------------------

/// Information element 0: SSID.
pub const WIRELESS_IE_SSID: Int = 0;
/// Information element 1: supported rates.
pub const WIRELESS_IE_SUPPORTED_RATES: Int = 1;
/// Information element 3: DS parameter set.
pub const WIRELESS_IE_DS_PARAMETER_SET: Int = 3;
/// Information element 5: traffic indication map.
pub const WIRELESS_IE_TIM: Int = 5;
/// Information element 7: country.
pub const WIRELESS_IE_COUNTRY: Int = 7;
/// Information element 45: HT capabilities.
pub const WIRELESS_IE_HT_CAPABILITIES: Int = 45;
/// Information element 48: robust security network.
pub const WIRELESS_IE_RSN: Int = 48;
/// Information element 127: extended capabilities.
pub const WIRELESS_IE_EXTENDED_CAPABILITIES: Int = 127;
/// Information element 191: VHT capabilities.
pub const WIRELESS_IE_VHT_CAPABILITIES: Int = 191;
/// Information element 221: vendor specific.
pub const WIRELESS_IE_VENDOR_SPECIFIC: Int = 221;

// Body-kind codes carried by WirelessMgmt.body_kind.
pub const WIRELESS_BODY_BEACON_LIKE: Int = 1;
pub const WIRELESS_BODY_PROBE_REQ: Int = 2;
pub const WIRELESS_BODY_ASSOC_REQ: Int = 3;
pub const WIRELESS_BODY_REASSOC_REQ: Int = 4;
pub const WIRELESS_BODY_ASSOC_RESP: Int = 5;
pub const WIRELESS_BODY_REASON: Int = 6;
pub const WIRELESS_BODY_AUTH: Int = 7;
pub const WIRELESS_BODY_ACTION: Int = 8;
pub const WIRELESS_BODY_ATIM: Int = 9;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed MAC header structure. `header_len` is the number of bytes the
/// header consumes (10 or 16 for control frames, 24 for a plain management
/// or data frame, plus 6 for a fourth address, 2 for QoS control and 4 for
/// HT control); `body_off`/`body_len` locate the bytes after the header in
/// the parsed buffer. `seq_control`/`fragment_number`/`sequence_number` are
/// -1 for control frames, which carry no Sequence Control field, and
/// `qos_*`/`tid`/`eosp`/`ack_policy`/`txop_limit`/`ht_*` are likewise -1 or
/// false when the field is absent. Fields are implementation details;
/// callers should go through the free functions below.
pub type WirelessFrame = {
  frame_control: Int;
  protocol_version: Int;
  frame_type: Int;
  subtype: Int;
  flag_byte: Int;
  to_ds: Bool;
  from_ds: Bool;
  more_fragments: Bool;
  retry: Bool;
  power_management: Bool;
  more_data: Bool;
  protected_frame: Bool;
  order: Bool;
  duration_id: Int;
  addr1: Vec[UInt8];
  addr2: Vec[UInt8];
  addr3: Vec[UInt8];
  addr4: Vec[UInt8];
  addr_count: Int;
  seq_control_present: Bool;
  seq_control: Int;
  fragment_number: Int;
  sequence_number: Int;
  qos_control_present: Bool;
  qos_control_off: Int;
  qos_control: Int;
  tid: Int;
  eosp: Bool;
  ack_policy: Int;
  a_msdu_present: Bool;
  txop_limit: Int;
  ht_control_present: Bool;
  ht_control_off: Int;
  header_len: Int;
  body_off: Int;
  body_len: Int;
}

/// Parsed management body plus the information element walk. `subtype` is
/// the management subtype and `body_kind` its fixed-field family (the
/// WIRELESS_BODY_* constants). Fixed fields absent from the family are -1;
/// `current_ap` is the 6-byte reassociation target (empty otherwise);
/// `action_off`/`action_len` locate the action-specific payload.
/// `ie_area_off`/`ie_area_len` bound the TLV area and `ie_ids`,
/// `ie_offsets`, `ie_lengths` are parallel pools, one entry per element in
/// order (`ie_offsets` are absolute payload offsets into the parsed
/// buffer). The decoded fields (`ssid`, `rates`, `ds_channel`, TIM,
/// `country_*`, `rsn_*`, `vendor_*`, HT/VHT/extended capabilities) describe
/// the first element of each kind; -1 marks "absent". Fields are
/// implementation details; callers should go through the free functions
/// below.
pub type WirelessMgmt = {
  subtype: Int;
  body_kind: Int;
  timestamp: Int;
  beacon_interval: Int;
  capability: Int;
  status_code: Int;
  reason_code: Int;
  auth_algorithm: Int;
  auth_sequence: Int;
  listen_interval: Int;
  aid: Int;
  category: Int;
  action: Int;
  current_ap: Vec[UInt8];
  action_off: Int;
  action_len: Int;
  ie_area_off: Int;
  ie_area_len: Int;
  ie_ids: Vec[Int];
  ie_offsets: Vec[Int];
  ie_lengths: Vec[Int];
  ssid: Vec[UInt8];
  rates: Vec[UInt8];
  ds_channel: Int;
  tim_dtim_count: Int;
  tim_dtim_period: Int;
  tim_bitmap_off: Int;
  tim_bitmap_len: Int;
  country_code: Int;
  country_triplets: Int;
  rsn_version: Int;
  rsn_group: Int;
  rsn_pairwise: Vec[Int];
  rsn_akm: Vec[Int];
  rsn_capabilities: Int;
  rsn_pmkid_count: Int;
  vendor_ouis: Vec[Int];
  vendor_types: Vec[Int];
  vendor_wpa: Bool;
  vendor_wmm: Bool;
  ht_present: Bool;
  ht_info: Int;
  ht_ampdu: Int;
  vht_present: Bool;
  vht_info: Int;
  ext_present: Bool;
  ext_len: Int;
}

// Internal RSN element decode result (one private struct so the IE walk
// stays readable; no Vec[StructType] is built).
type WirelessRsn = {
  version: Int;
  group: Int;
  pairwise: Vec[Int];
  akm: Vec[Int];
  capabilities: Int;
  pmkid_count: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[WirelessFrame, Str].
fn _ok_frame(v: WirelessFrame) -> Result[WirelessFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[WirelessFrame, Str].
fn _err_frame(m: Str) -> Result[WirelessFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[WirelessMgmt, Str].
fn _ok_mgmt(v: WirelessMgmt) -> Result[WirelessMgmt, Str] {
  return Ok(v);
}

// Err(m) for Result[WirelessMgmt, Str].
fn _err_mgmt(m: Str) -> Result[WirelessMgmt, Str] {
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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[WirelessRsn, Str].
fn _ok_rsn(v: WirelessRsn) -> Result[WirelessRsn, Str] {
  return Ok(v);
}

// Err(m) for Result[WirelessRsn, Str].
fn _err_rsn(m: Str) -> Result[WirelessRsn, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic and byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; the caller guarantees the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  let b: UInt8 = data[pos];
  return (b as Int) & 0xFF;
}

// Unsigned 16-bit little-endian integer at [pos, pos+2).
fn _le_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256;
}

// Unsigned 32-bit little-endian integer at [pos, pos+4).
fn _le_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
}

// Unsigned 64-bit little-endian integer at [pos, pos+8). The caller has
// already rejected a byte 7 above 127 (the value must fit a signed Int).
fn _le_u64(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var shift: Int = 1;
  var i = 0;
  while i < 8 {
    v = v + _byte(data, pos + i) * shift;
    shift = shift * 256;
    i = i + 1;
  }
  return v;
}

// 2^k for k in 0..62 (used by the bitfield extractors).
fn _pow2(k: Int) -> Int {
  var v: Int = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Low `count` bits of `v` (v non-negative).
fn _bits_lo(v: Int, count: Int) -> Int {
  return v % _pow2(count);
}

// `count` bits of `v` starting at `shift` (v non-negative).
fn _bits_at(v: Int, shift: Int, count: Int) -> Int {
  return (v / _pow2(shift)) % _pow2(count);
}

// True when bit `bit` of non-negative `v` is set.
fn _bit(v: Int, bit: Int) -> Bool {
  return _bits_at(v, bit, 1) == 1;
}

// Decimal text of a non-negative Int (error messages carry offsets and
// lengths; the standard library stays out of the library module).
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
  if d == 9 { return "9"; }
  return "?";
}

// Decimal text of `n` (n >= 0).
fn _digits(n: Int) -> Str {
  if n == 0 {
    return "0";
  }
  var v = n;
  var s = "";
  while v > 0 {
    s = _digit_char(v % 10) + s;
    v = v / 10;
  }
  return s;
}

// Copy data[offset, offset+length) into a fresh vector; the caller has
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

// Copy the six bytes at `offset` (an address).
fn _copy6(data: &Vec[UInt8], offset: Int) -> Vec[UInt8] {
  return _copy_range(data, offset, 6);
}

// Combined 32-bit cipher suite identifier of the four bytes at `offset`:
// three OUI bytes in the high 24 bits, the suite type in the low byte.
fn _suite_id(data: &Vec[UInt8], offset: Int) -> Int {
  let oui: Int = _byte(data, offset) * 65536 + _byte(data, offset + 1) * 256 + _byte(data, offset + 2);
  return oui * 256 + _byte(data, offset + 3);
}

// --------------------------------------------------
//  Internal error-message builders
// --------------------------------------------------

// Truncated-mac-header message naming the missing byte count.
fn _short_frame(need: Int, have: Int) -> Str {
  return "wireless: truncated frame at offset 0: need " + _digits(need) + " bytes, have " + _digits(have);
}

// Truncated management-body message.
fn _short_body(off: Int, need: Int, have: Int) -> Str {
  return "wireless: truncated management body at offset " + _digits(off) + ": need " + _digits(need) + " bytes, have " + _digits(have);
}

// Unexpected trailing management-body message.
fn _extra_body(off: Int, count: Int) -> Str {
  return "wireless: unexpected management body bytes at offset " + _digits(off) + ": " + _digits(count);
}

// Bad information element length message (offset of the element header).
fn _bad_ie(off: Int, what: Str, len: Int) -> Str {
  return "wireless: bad " + what + " ie length at offset " + _digits(off) + ": " + _digits(len);
}

// --------------------------------------------------
//  Address-count matrix
// --------------------------------------------------

// Number of addresses for a control frame subtype (0 = reserved or not
// structurally decoded): BAR, BA, PS-Poll and RTS carry Address 1 and
// Address 2; CTS, ACK, CF-End and CF-End + CF-Ack carry only Address 1.
fn _ctrl_addr_count(subtype: Int) -> Int {
  if subtype == WIRELESS_CTRL_CTS || subtype == WIRELESS_CTRL_ACK {
    return 1;
  }
  if subtype == WIRELESS_CTRL_CF_END || subtype == WIRELESS_CTRL_CF_END_ACK {
    return 1;
  }
  if subtype == WIRELESS_CTRL_BAR || subtype == WIRELESS_CTRL_BA {
    return 2;
  }
  if subtype == WIRELESS_CTRL_PS_POLL || subtype == WIRELESS_CTRL_RTS {
    return 2;
  }
  return 0;
}

// --------------------------------------------------
//  Subtype, flag, code and IE name tables
// --------------------------------------------------

// Management subtype name.
fn _mgmt_subtype_name(s: Int) -> Str {
  if s == 0 { return "assoc-req"; }
  if s == 1 { return "assoc-resp"; }
  if s == 2 { return "reassoc-req"; }
  if s == 3 { return "reassoc-resp"; }
  if s == 4 { return "probe-req"; }
  if s == 5 { return "probe-resp"; }
  if s == 6 { return "timing-adv"; }
  if s == 7 { return "reserved"; }
  if s == 8 { return "beacon"; }
  if s == 9 { return "atim"; }
  if s == 10 { return "disassoc"; }
  if s == 11 { return "auth"; }
  if s == 12 { return "deauth"; }
  if s == 13 { return "action"; }
  if s == 14 { return "action-no-ack"; }
  return "reserved";
}

// Control subtype name (IEEE 802.11-2016 Table 9-1).
fn _ctrl_subtype_name(s: Int) -> Str {
  if s == 0 { return "reserved"; }
  if s == 1 { return "reserved"; }
  if s == 2 { return "trigger"; }
  if s == 3 { return "tack"; }
  if s == 4 { return "beamforming-report-poll"; }
  if s == 5 { return "vht-ndp-announcement"; }
  if s == 6 { return "control-frame-extension"; }
  if s == 7 { return "control-wrapper"; }
  if s == 8 { return "bar"; }
  if s == 9 { return "ba"; }
  if s == 10 { return "ps-poll"; }
  if s == 11 { return "rts"; }
  if s == 12 { return "cts"; }
  if s == 13 { return "ack"; }
  if s == 14 { return "cf-end"; }
  if s == 15 { return "cf-end+cf-ack"; }
  return "reserved";
}

// Data subtype name.
fn _data_subtype_name(s: Int) -> Str {
  if s == 0 { return "data"; }
  if s == 1 { return "data+cf-ack"; }
  if s == 2 { return "data+cf-poll"; }
  if s == 3 { return "data+cf-ack+cf-poll"; }
  if s == 4 { return "null"; }
  if s == 5 { return "cf-ack"; }
  if s == 6 { return "cf-poll"; }
  if s == 7 { return "cf-ack+cf-poll"; }
  if s == 8 { return "qos-data"; }
  if s == 9 { return "qos-data+cf-ack"; }
  if s == 10 { return "qos-data+cf-poll"; }
  if s == 11 { return "qos-data+cf-ack+cf-poll"; }
  if s == 12 { return "qos-null"; }
  if s == 14 { return "qos-cf-poll"; }
  if s == 15 { return "qos-cf-ack+cf-poll"; }
  return "reserved";
}

// Extension subtype name.
fn _ext_subtype_name(s: Int) -> Str {
  if s == 0 { return "dmg-beacon"; }
  return "reserved";
}

/// Human name of the Frame Control type (0 management, 1 control,
/// 2 data, 3 extension). Complexity: O(1).
pub fn wireless_type_name(frame_type: Int) -> Str {
  if frame_type == 0 { return "management"; }
  if frame_type == 1 { return "control"; }
  if frame_type == 2 { return "data"; }
  if frame_type == 3 { return "extension"; }
  return "unknown";
}

/// Human name of a subtype within its frame type. Control slots follow
/// IEEE 802.11-2016 Table 9-1; control subtypes 2..7 are named but not
/// structurally supported by this parser, and unknown slots return
/// "reserved". Complexity: O(1).
pub fn wireless_subtype_name(frame_type: Int, subtype: Int) -> Str {
  if subtype < 0 || subtype > 15 {
    return "unknown";
  }
  if frame_type == 0 { return _mgmt_subtype_name(subtype); }
  if frame_type == 1 { return _ctrl_subtype_name(subtype); }
  if frame_type == 2 { return _data_subtype_name(subtype); }
  if frame_type == 3 { return _ext_subtype_name(subtype); }
  return "unknown";
}

/// Name of Frame Control flag `bit` (0 to-ds, 1 from-ds, 2 more-fragments,
/// 3 retry, 4 power-management, 5 more-data, 6 protected, 7 order).
/// Complexity: O(1).
pub fn wireless_flag_name(bit: Int) -> Str {
  if bit == 0 { return "to-ds"; }
  if bit == 1 { return "from-ds"; }
  if bit == 2 { return "more-fragments"; }
  if bit == 3 { return "retry"; }
  if bit == 4 { return "power-management"; }
  if bit == 5 { return "more-data"; }
  if bit == 6 { return "protected"; }
  if bit == 7 { return "order"; }
  return "unknown";
}

/// IEEE 802.11 status code name (Table 9-46 subset, 0..70). Codes without
/// a documented name return "reserved" below 70 and "unknown" above.
/// Complexity: O(1).
pub fn wireless_status_name(code: Int) -> Str {
  if code == 0 { return "success"; }
  if code == 1 { return "unspecified-failure"; }
  if code >= 2 && code <= 9 { return "reserved"; }
  if code == 10 { return "capabilities-unsupported"; }
  if code == 11 { return "reassoc-no-assoc"; }
  if code == 12 { return "assoc-denied-unspecified"; }
  if code == 13 { return "auth-algorithm-not-supported"; }
  if code == 14 { return "unknown-auth-transaction"; }
  if code == 15 { return "challenge-failure"; }
  if code == 16 { return "auth-timeout"; }
  if code == 17 { return "ap-unable-to-handle-stas"; }
  if code == 18 { return "assoc-denied-rates"; }
  if code == 19 { return "assoc-denied-short-preamble"; }
  if code == 20 { return "assoc-denied-pbcc"; }
  if code == 21 { return "assoc-denied-channel-agility"; }
  if code == 22 { return "assoc-denied-spectrum-mgmt"; }
  if code == 23 { return "assoc-rejected-bad-power"; }
  if code == 24 { return "assoc-rejected-bad-channels"; }
  if code == 25 { return "assoc-denied-short-slot"; }
  if code == 26 { return "assoc-denied-dsss-ofdm"; }
  if code >= 27 && code <= 29 { return "reserved"; }
  if code == 30 { return "temporarily-rejected"; }
  if code == 31 { return "robust-mgmt-policy-violation"; }
  if code == 32 { return "qos-unspecified"; }
  if code == 33 { return "insufficient-bandwidth"; }
  if code == 34 { return "poor-channel-conditions"; }
  if code == 35 { return "qos-not-supported"; }
  if code == 36 { return "block-ack-not-supported"; }
  if code == 37 { return "request-declined"; }
  if code == 38 { return "invalid-parameters"; }
  if code == 39 { return "rejected-with-suggested-changes"; }
  if code == 40 { return "invalid-ie"; }
  if code == 41 { return "group-cipher-not-valid"; }
  if code == 42 { return "pairwise-cipher-not-valid"; }
  if code == 43 { return "akmp-not-valid"; }
  if code == 44 { return "unsupported-rsn-ie-version"; }
  if code == 45 { return "invalid-rsn-ie-capabilities"; }
  if code == 46 { return "cipher-rejected-per-policy"; }
  if code == 47 { return "ts-not-created"; }
  if code == 48 { return "direct-link-not-allowed"; }
  if code == 49 { return "destination-sta-not-present"; }
  if code == 50 { return "destination-sta-not-qos"; }
  if code == 51 { return "listen-interval-too-large"; }
  if code == 52 { return "invalid-ft-action-frame-count"; }
  if code == 53 { return "invalid-pmkid"; }
  if code == 54 { return "invalid-mdie"; }
  if code == 55 { return "invalid-ftie"; }
  if code == 56 { return "requested-tclas-not-supported"; }
  if code == 57 { return "insufficient-tclas-resources"; }
  if code == 58 { return "try-another-bss"; }
  if code == 59 { return "gas-adv-proto-not-supported"; }
  if code == 60 { return "no-outstanding-gas-request"; }
  if code == 61 { return "gas-response-not-received"; }
  if code == 62 { return "sta-timed-out-waiting-for-gas-response"; }
  if code == 63 { return "gas-response-larger-than-limit"; }
  if code == 64 { return "request-refused-home"; }
  if code == 65 { return "advertisement-service-unreachable"; }
  if code == 66 { return "reserved"; }
  if code == 67 { return "request-refused-sspn"; }
  if code == 68 { return "request-refused-unauthorized-access"; }
  if code == 69 || code == 70 { return "reserved"; }
  return "unknown";
}

/// IEEE 802.11 reason code name (Table 9-45 subset, 0..40). Codes without
/// a documented name return "reserved" below 40 and "unknown" above.
/// Complexity: O(1).
pub fn wireless_reason_name(code: Int) -> Str {
  if code == 0 { return "reserved"; }
  if code == 1 { return "unspecified"; }
  if code == 2 { return "previous-auth-no-longer-valid"; }
  if code == 3 { return "sta-leaving-ibss-ess"; }
  if code == 4 { return "inactivity"; }
  if code == 5 { return "ap-unable-to-handle-stas"; }
  if code == 6 { return "class2-frame-from-nonauth"; }
  if code == 7 { return "class3-frame-from-nonassoc"; }
  if code == 8 { return "sta-leaving-bss"; }
  if code == 9 { return "not-authenticated"; }
  if code == 10 { return "bad-power-capability"; }
  if code == 11 { return "bad-supported-channels"; }
  if code == 12 { return "reserved"; }
  if code == 13 { return "invalid-ie"; }
  if code == 14 { return "mic-failure"; }
  if code == 15 { return "4way-handshake-timeout"; }
  if code == 16 { return "group-key-handshake-timeout"; }
  if code == 17 { return "ie-different-in-handshake"; }
  if code == 18 { return "invalid-group-cipher"; }
  if code == 19 { return "invalid-pairwise-cipher"; }
  if code == 20 { return "invalid-akmp"; }
  if code == 21 { return "unsupported-rsne-version"; }
  if code == 22 { return "invalid-rsne-capabilities"; }
  if code == 23 { return "802.1x-authentication-failed"; }
  if code == 24 { return "cipher-suite-rejected"; }
  if code == 25 { return "tdls-peer-unreachable"; }
  if code == 26 { return "tdls-teardown"; }
  if code >= 27 && code <= 31 { return "reserved"; }
  if code == 32 { return "qos-unspecified"; }
  if code == 33 { return "qos-no-bandwidth"; }
  if code == 34 { return "qos-low-ack"; }
  if code == 35 { return "qos-exceeded-txop"; }
  if code == 36 { return "qos-sta-leaving-qbss"; }
  if code == 37 { return "qos-sta-not-using-mechanism"; }
  if code == 38 { return "qos-setup-required"; }
  if code == 39 { return "qos-sta-timeout"; }
  if code == 40 { return "qos-cipher-not-supported"; }
  return "unknown";
}

/// Authentication algorithm number name (open system, shared key, fast BSS
/// transition, SAE, FILS). Complexity: O(1).
pub fn wireless_auth_algorithm_name(algorithm: Int) -> Str {
  if algorithm == 0 { return "open-system"; }
  if algorithm == 1 { return "shared-key"; }
  if algorithm == 2 { return "fast-bss-transition"; }
  if algorithm == 3 { return "sae"; }
  if algorithm == 4 { return "fils-shared-key"; }
  if algorithm == 5 { return "fils-shared-key-pfs"; }
  return "unknown";
}

/// QoS Control ack policy name (0 normal ack, 1 no ack, 2 no explicit ack,
/// 3 block ack). Complexity: O(1).
pub fn wireless_ack_policy_name(policy: Int) -> Str {
  if policy == 0 { return "normal-ack"; }
  if policy == 1 { return "no-ack"; }
  if policy == 2 { return "no-explicit-ack"; }
  if policy == 3 { return "block-ack"; }
  return "unknown";
}

/// Information element name for the ids this package decodes; other ids
/// return "unknown" (their payloads are still preserved raw).
/// Complexity: O(1).
pub fn wireless_ie_name(ie_id: Int) -> Str {
  if ie_id == 0 { return "ssid"; }
  if ie_id == 1 { return "supported-rates"; }
  if ie_id == 2 { return "fh-parameter-set"; }
  if ie_id == 3 { return "ds-parameter-set"; }
  if ie_id == 4 { return "cf-parameter-set"; }
  if ie_id == 5 { return "tim"; }
  if ie_id == 6 { return "ibss-parameter-set"; }
  if ie_id == 7 { return "country"; }
  if ie_id == 8 { return "hopping-pattern-parameters"; }
  if ie_id == 9 { return "hopping-pattern-table"; }
  if ie_id == 10 { return "request"; }
  if ie_id == 11 { return "bss-load"; }
  if ie_id == 12 { return "edca-parameter-set"; }
  if ie_id == 13 { return "tpc-report"; }
  if ie_id == 14 { return "erp-information"; }
  if ie_id == 32 { return "power-constraint"; }
  if ie_id == 33 { return "power-capability"; }
  if ie_id == 35 { return "tpc-report"; }
  if ie_id == 36 { return "supported-channels"; }
  if ie_id == 37 { return "channel-switch-announcement"; }
  if ie_id == 38 { return "measurement-request"; }
  if ie_id == 39 { return "measurement-report"; }
  if ie_id == 40 { return "quiet"; }
  if ie_id == 41 { return "ibss-dfs"; }
  if ie_id == 42 { return "erp-information"; }
  if ie_id == 45 { return "ht-capabilities"; }
  if ie_id == 48 { return "rsn"; }
  if ie_id == 50 { return "extended-supported-rates"; }
  if ie_id == 61 { return "ht-operation"; }
  if ie_id == 74 { return "overlapping-bss-scan-parameters"; }
  if ie_id == 127 { return "extended-capabilities"; }
  if ie_id == 191 { return "vht-capabilities"; }
  if ie_id == 192 { return "vht-operation"; }
  if ie_id == 221 { return "vendor-specific"; }
  return "unknown";
}

// --------------------------------------------------
//  Frame parse
// --------------------------------------------------

/// Parse the MAC header at offset 0 of `data`.
///
/// Layout: Frame Control (u16 little-endian), Duration/ID (u16), then
/// Address 1..N (6 bytes each) with N from the type/subtype/DS matrix,
/// Sequence Control (u16, absent on control frames), optional QoS Control
/// (u16, present on data subtypes 8..15) and optional HT Control (4 bytes,
/// present when the Order bit marks one on a QoS data or management frame).
///
/// Errors (all stable, offsets absolute):
///   * `wireless: truncated frame at offset 0: need N bytes, have M`;
///   * `wireless: bad protocol version V` -- version is not 0;
///   * `wireless: invalid ds bits for management frame` /
///     `wireless: invalid ds bits for control frame`;
///   * `wireless: unsupported control subtype S` -- reserved control slot;
///   * `wireless: truncated qos control at offset O: need 2 bytes, have M`;
///   * `wireless: truncated ht control at offset O: need 4 bytes, have M`.
/// Complexity: O(1).
pub fn wireless_parse(data: &Vec[UInt8]) -> Result[WirelessFrame, Str] {
  let n = data.len();
  if n < 4 {
    return _err_frame(_short_frame(4, n));
  }
  let frame_control: Int = _le_u16(data, 0);
  let duration_id: Int = _le_u16(data, 2);
  let protocol_version: Int = frame_control % 4;
  if protocol_version != 0 {
    return _err_frame("wireless: bad protocol version " + _digits(protocol_version));
  }
  let frame_type: Int = _bits_at(frame_control, 2, 2);
  let subtype: Int = _bits_at(frame_control, 4, 4);
  let flag_byte: Int = frame_control / 256;
  let to_ds: Bool = _bit(flag_byte, 0);
  let from_ds: Bool = _bit(flag_byte, 1);
  if frame_type == WIRELESS_TYPE_MANAGEMENT {
    if to_ds || from_ds {
      return _err_frame("wireless: invalid ds bits for management frame");
    }
  }
  var addrs = 3;
  var seq_present = true;
  var qos_present = false;
  if frame_type == WIRELESS_TYPE_CONTROL {
    if to_ds || from_ds {
      return _err_frame("wireless: invalid ds bits for control frame");
    }
    seq_present = false;
    addrs = _ctrl_addr_count(subtype);
    if addrs == 0 {
      return _err_frame("wireless: unsupported control subtype " + _digits(subtype));
    }
  } elif frame_type == WIRELESS_TYPE_DATA {
    if to_ds && from_ds {
      addrs = 4;
    }
    qos_present = subtype >= 8;
  } else {
    if to_ds && from_ds {
      addrs = 4;
    }
  }
  var fixed = 4 + addrs * 6;
  if seq_present {
    fixed = fixed + 2;
  }
  if n < fixed {
    return _err_frame(_short_frame(fixed, n));
  }
  let ht_present: Bool = _bit(flag_byte, 7) && (qos_present || frame_type == WIRELESS_TYPE_MANAGEMENT);
  var qos_off = -1;
  if qos_present {
    qos_off = fixed;
    if n < fixed + 2 {
      return _err_frame("wireless: truncated qos control at offset " + _digits(fixed) + ": need 2 bytes, have " + _digits(n - fixed));
    }
  }
  var ht_off = -1;
  if ht_present {
    ht_off = fixed;
    if qos_present {
      ht_off = fixed + 2;
    }
    if n < ht_off + 4 {
      return _err_frame("wireless: truncated ht control at offset " + _digits(ht_off) + ": need 4 bytes, have " + _digits(n - ht_off));
    }
  }
  let addr1: Vec[UInt8] = _copy6(data, 4);
  var addr2 = Vec[UInt8].new();
  var addr3 = Vec[UInt8].new();
  var addr4 = Vec[UInt8].new();
  if addrs >= 2 {
    addr2 = _copy6(data, 10);
  }
  if addrs >= 3 {
    addr3 = _copy6(data, 16);
  }
  if addrs >= 4 {
    addr4 = _copy6(data, 22);
  }
  var seq_control = -1;
  var fragment_number = -1;
  var sequence_number = -1;
  var pos = 4 + addrs * 6;
  if seq_present {
    seq_control = _le_u16(data, pos);
    fragment_number = seq_control % 16;
    sequence_number = seq_control / 16;
    pos = pos + 2;
  }
  var qos_control = -1;
  var tid = -1;
  var eosp = false;
  var ack_policy = -1;
  var a_msdu_present = false;
  var txop_limit = -1;
  if qos_present {
    qos_control = _le_u16(data, qos_off);
    tid = qos_control % 16;
    eosp = _bits_at(qos_control, 4, 1) == 1;
    ack_policy = _bits_at(qos_control, 5, 2);
    a_msdu_present = _bits_at(qos_control, 7, 1) == 1;
    txop_limit = qos_control / 256;
    pos = pos + 2;
  }
  if ht_present {
    pos = pos + 4;
  }
  let f = WirelessFrame{
    frame_control: frame_control;
    protocol_version: protocol_version;
    frame_type: frame_type;
    subtype: subtype;
    flag_byte: flag_byte;
    to_ds: to_ds;
    from_ds: from_ds;
    more_fragments: _bit(flag_byte, 2);
    retry: _bit(flag_byte, 3);
    power_management: _bit(flag_byte, 4);
    more_data: _bit(flag_byte, 5);
    protected_frame: _bit(flag_byte, 6);
    order: _bit(flag_byte, 7);
    duration_id: duration_id;
    addr1: addr1;
    addr2: addr2;
    addr3: addr3;
    addr4: addr4;
    addr_count: addrs;
    seq_control_present: seq_present;
    seq_control: seq_control;
    fragment_number: fragment_number;
    sequence_number: sequence_number;
    qos_control_present: qos_present;
    qos_control_off: qos_off;
    qos_control: qos_control;
    tid: tid;
    eosp: eosp;
    ack_policy: ack_policy;
    a_msdu_present: a_msdu_present;
    txop_limit: txop_limit;
    ht_control_present: ht_present;
    ht_control_off: ht_off;
    header_len: pos;
    body_off: pos;
    body_len: n - pos;
  };
  return _ok_frame(f);
}

// --------------------------------------------------
//  Management body kind
// --------------------------------------------------

// Fixed-field family of a management subtype (0 = unsupported).
fn _mgmt_body_kind(subtype: Int) -> Int {
  if subtype == WIRELESS_MGMT_ASSOC_REQ { return WIRELESS_BODY_ASSOC_REQ; }
  if subtype == WIRELESS_MGMT_ASSOC_RESP { return WIRELESS_BODY_ASSOC_RESP; }
  if subtype == WIRELESS_MGMT_REASSOC_REQ { return WIRELESS_BODY_REASSOC_REQ; }
  if subtype == WIRELESS_MGMT_REASSOC_RESP { return WIRELESS_BODY_ASSOC_RESP; }
  if subtype == WIRELESS_MGMT_PROBE_REQ { return WIRELESS_BODY_PROBE_REQ; }
  if subtype == WIRELESS_MGMT_PROBE_RESP { return WIRELESS_BODY_BEACON_LIKE; }
  if subtype == WIRELESS_MGMT_BEACON { return WIRELESS_BODY_BEACON_LIKE; }
  if subtype == WIRELESS_MGMT_ATIM { return WIRELESS_BODY_ATIM; }
  if subtype == WIRELESS_MGMT_DISASSOC { return WIRELESS_BODY_REASON; }
  if subtype == WIRELESS_MGMT_AUTH { return WIRELESS_BODY_AUTH; }
  if subtype == WIRELESS_MGMT_DEAUTH { return WIRELESS_BODY_REASON; }
  if subtype == WIRELESS_MGMT_ACTION { return WIRELESS_BODY_ACTION; }
  if subtype == WIRELESS_MGMT_ACTION_NO_ACK { return WIRELESS_BODY_ACTION; }
  return 0;
}

/// Human name of a WIRELESS_BODY_* kind. Complexity: O(1).
pub fn wireless_body_kind_name(kind: Int) -> Str {
  if kind == WIRELESS_BODY_BEACON_LIKE { return "beacon-like"; }
  if kind == WIRELESS_BODY_PROBE_REQ { return "probe-req"; }
  if kind == WIRELESS_BODY_ASSOC_REQ { return "assoc-req"; }
  if kind == WIRELESS_BODY_REASSOC_REQ { return "reassoc-req"; }
  if kind == WIRELESS_BODY_ASSOC_RESP { return "assoc-resp"; }
  if kind == WIRELESS_BODY_REASON { return "reason"; }
  if kind == WIRELESS_BODY_AUTH { return "auth"; }
  if kind == WIRELESS_BODY_ACTION { return "action"; }
  if kind == WIRELESS_BODY_ATIM { return "atim"; }
  return "unknown";
}

// --------------------------------------------------
//  RSN and vendor element decode (internal)
// --------------------------------------------------

// Decode a Robust Security Network element payload [off, off+len). The
// layout implemented: version u16, group cipher suite (4), pairwise count
// u16 + suites, AKM count u16 + suites, RSN capabilities u16, optional
// PMKID count u16 + 16-byte PMKIDs, optional 4-byte group management cipher
// suite. `ie_off` is the element header offset, used in error messages.
fn _rsn_decode(data: &Vec[UInt8], off: Int, len: Int, ie_off: Int) -> Result[WirelessRsn, Str] {
  if len < 20 {
    return _err_rsn(_bad_ie(ie_off, "rsn", len));
  }
  let end = off + len;
  var q = off;
  let version: Int = _le_u16(data, q);
  q = q + 2;
  let group: Int = _suite_id(data, q);
  q = q + 4;
  let pw_count: Int = _le_u16(data, q);
  q = q + 2;
  if pw_count < 1 {
    return _err_rsn("wireless: bad rsn pairwise count at offset " + _digits(ie_off) + ": " + _digits(pw_count));
  }
  if q + pw_count * 4 > end {
    return _err_rsn(_bad_ie(ie_off, "rsn", len));
  }
  var pairwise = Vec[Int].new();
  var i = 0;
  while i < pw_count {
    pairwise.push(_suite_id(data, q));
    q = q + 4;
    i = i + 1;
  }
  if q + 2 > end {
    return _err_rsn(_bad_ie(ie_off, "rsn", len));
  }
  let akm_count: Int = _le_u16(data, q);
  q = q + 2;
  if akm_count < 1 {
    return _err_rsn("wireless: bad rsn akm count at offset " + _digits(ie_off) + ": " + _digits(akm_count));
  }
  if q + akm_count * 4 > end {
    return _err_rsn(_bad_ie(ie_off, "rsn", len));
  }
  var akm = Vec[Int].new();
  i = 0;
  while i < akm_count {
    akm.push(_suite_id(data, q));
    q = q + 4;
    i = i + 1;
  }
  if q + 2 > end {
    return _err_rsn(_bad_ie(ie_off, "rsn", len));
  }
  let capabilities: Int = _le_u16(data, q);
  q = q + 2;
  var pmkid_count = -1;
  if q < end {
    if q + 2 > end {
      return _err_rsn(_bad_ie(ie_off, "rsn", len));
    }
    pmkid_count = _le_u16(data, q);
    q = q + 2;
    if q + pmkid_count * 16 > end {
      return _err_rsn("wireless: bad rsn pmkid count at offset " + _digits(ie_off) + ": " + _digits(pmkid_count));
    }
    q = q + pmkid_count * 16;
  }
  // An optional group management cipher suite is four bytes and is
  // preserved raw in the element payload; anything else trailing is
  // malformed.
  if end - q == 4 {
    q = q + 4;
  }
  if q != end {
    return _err_rsn("wireless: trailing bytes in rsn ie at offset " + _digits(q));
  }
  return _ok_rsn(WirelessRsn{
    version: version;
    group: group;
    pairwise: pairwise;
    akm: akm;
    capabilities: capabilities;
    pmkid_count: pmkid_count;
  });
}

// Combined OUI*256+type of a vendor specific element payload; the caller
// has already checked the payload is at least four bytes.
fn _vendor_decode(data: &Vec[UInt8], off: Int, len: Int, ie_off: Int) -> Result[Int, Str] {
  if len < 4 {
    return _err_int(_bad_ie(ie_off, "vendor", len));
  }
  let oui: Int = _byte(data, off) * 65536 + _byte(data, off + 1) * 256 + _byte(data, off + 2);
  return _ok_int(oui * 256 + _byte(data, off + 3));
}

// --------------------------------------------------
//  Management parse
// --------------------------------------------------

/// Parse a management frame at offset 0 of `data`: the MAC header (via
/// wireless_parse, so the same truncation and DS-bit errors apply), the
/// fixed fields of the subtype's body family, and the information element
/// walk over the body tail.
///
/// Body families: assoc/reassoc request (capability, listen interval,
/// reassociation current AP address, IEs), assoc/reassoc response
/// (capability, status, AID, IEs), beacon/probe response (timestamp,
/// beacon interval, capability, IEs), probe request (IEs), authentication
/// (algorithm, sequence, status, optional IEs), disassociation and
/// deauthentication (reason, no IEs), ATIM (empty body) and action
/// (category, action, raw action payload).
///
/// Errors (all stable): the wireless_parse catalog, plus
///   * `wireless: not a management frame`;
///   * `wireless: unsupported management subtype S` -- reserved slots;
///   * `wireless: truncated management body at offset O: need N bytes,
///     have M`;
///   * `wireless: timestamp out of range at offset O` -- beacon timestamp
///     has bit 63 set;
///   * `wireless: unexpected management body bytes at offset O: N`;
///   * `wireless: truncated ie header at offset O: need 2 bytes, have M`;
///   * `wireless: bad ie length at offset O: ie I length L exceeds M
///     remaining bytes`;
///   * `wireless: bad ds parameter set ie length at offset O: L` (not 1);
///   * `wireless: bad tim ie length at offset O: L` (below 2);
///   * `wireless: bad country ie length at offset O: L` (below 3 or not
///     3 + 3k);
///   * `wireless: bad ht capabilities ie length at offset O: L` (not 26);
///   * `wireless: bad vht capabilities ie length at offset O: L` (not 12);
///   * `wireless: bad extended capabilities ie length at offset O: L`
///     (below 1);
///   * `wireless: bad vendor ie length at offset O: L` (below 4);
///   * RSN errors: bad rsn ie length, bad rsn pairwise count, bad rsn akm
///     count, bad rsn pmkid count, trailing bytes in rsn ie.
/// Complexity: O(body length) time.
pub fn wireless_parse_mgmt(data: &Vec[UInt8]) -> Result[WirelessMgmt, Str] {
  let fr = wireless_parse(data);
  if !fr.is_ok {
    return _err_mgmt(fr.error);
  }
  let f: WirelessFrame = fr.value;
  if f.frame_type != WIRELESS_TYPE_MANAGEMENT {
    return _err_mgmt("wireless: not a management frame");
  }
  let subtype: Int = f.subtype;
  let body_kind: Int = _mgmt_body_kind(subtype);
  if body_kind == 0 {
    return _err_mgmt("wireless: unsupported management subtype " + _digits(subtype));
  }
  let off: Int = f.body_off;
  let end: Int = off + f.body_len;
  var timestamp = -1;
  var beacon_interval = -1;
  var capability = -1;
  var status_code = -1;
  var reason_code = -1;
  var auth_algorithm = -1;
  var auth_sequence = -1;
  var listen_interval = -1;
  var aid = -1;
  var category = -1;
  var action = -1;
  var current_ap = Vec[UInt8].new();
  var action_off = -1;
  var action_len = -1;
  var ie_off = end;
  if body_kind == WIRELESS_BODY_BEACON_LIKE {
    if f.body_len < 12 {
      return _err_mgmt(_short_body(off, 12, f.body_len));
    }
    if _byte(data, off + 7) >= 128 {
      return _err_mgmt("wireless: timestamp out of range at offset " + _digits(off));
    }
    timestamp = _le_u64(data, off);
    beacon_interval = _le_u16(data, off + 8);
    capability = _le_u16(data, off + 10);
    ie_off = off + 12;
  } elif body_kind == WIRELESS_BODY_PROBE_REQ {
    ie_off = off;
  } elif body_kind == WIRELESS_BODY_ASSOC_REQ {
    if f.body_len < 4 {
      return _err_mgmt(_short_body(off, 4, f.body_len));
    }
    capability = _le_u16(data, off);
    listen_interval = _le_u16(data, off + 2);
    ie_off = off + 4;
  } elif body_kind == WIRELESS_BODY_REASSOC_REQ {
    if f.body_len < 10 {
      return _err_mgmt(_short_body(off, 10, f.body_len));
    }
    capability = _le_u16(data, off);
    listen_interval = _le_u16(data, off + 2);
    current_ap = _copy6(data, off + 4);
    ie_off = off + 10;
  } elif body_kind == WIRELESS_BODY_ASSOC_RESP {
    if f.body_len < 6 {
      return _err_mgmt(_short_body(off, 6, f.body_len));
    }
    capability = _le_u16(data, off);
    status_code = _le_u16(data, off + 2);
    aid = _le_u16(data, off + 4);
    ie_off = off + 6;
  } elif body_kind == WIRELESS_BODY_REASON {
    if f.body_len < 2 {
      return _err_mgmt(_short_body(off, 2, f.body_len));
    }
    if f.body_len > 2 {
      return _err_mgmt(_extra_body(off + 2, f.body_len - 2));
    }
    reason_code = _le_u16(data, off);
    ie_off = end;
  } elif body_kind == WIRELESS_BODY_AUTH {
    if f.body_len < 6 {
      return _err_mgmt(_short_body(off, 6, f.body_len));
    }
    auth_algorithm = _le_u16(data, off);
    auth_sequence = _le_u16(data, off + 2);
    status_code = _le_u16(data, off + 4);
    ie_off = off + 6;
  } elif body_kind == WIRELESS_BODY_ACTION {
    if f.body_len < 2 {
      return _err_mgmt(_short_body(off, 2, f.body_len));
    }
    category = _byte(data, off);
    action = _byte(data, off + 1);
    action_off = off + 2;
    action_len = f.body_len - 2;
    ie_off = end;
  } else {
    if f.body_len > 0 {
      return _err_mgmt(_extra_body(off, f.body_len));
    }
    ie_off = end;
  }
  var ie_ids = Vec[Int].new();
  var ie_offsets = Vec[Int].new();
  var ie_lengths = Vec[Int].new();
  var ssid = Vec[UInt8].new();
  var ssid_set = false;
  var rates = Vec[UInt8].new();
  var rates_set = false;
  var ds_channel = -1;
  var tim_dtim_count = -1;
  var tim_dtim_period = -1;
  var tim_bitmap_off = -1;
  var tim_bitmap_len = -1;
  var country_code = -1;
  var country_triplets = -1;
  var rsn_version = -1;
  var rsn_group = -1;
  var rsn_pairwise = Vec[Int].new();
  var rsn_akm = Vec[Int].new();
  var rsn_capabilities = -1;
  var rsn_pmkid_count = -1;
  var vendor_ouis = Vec[Int].new();
  var vendor_types = Vec[Int].new();
  var vendor_wpa = false;
  var vendor_wmm = false;
  var ht_present = false;
  var ht_info = -1;
  var ht_ampdu = -1;
  var vht_present = false;
  var vht_info = -1;
  var ext_present = false;
  var ext_len = -1;
  var pos = ie_off;
  while pos < end {
    if pos + 2 > end {
      return _err_mgmt("wireless: truncated ie header at offset " + _digits(pos) + ": need 2 bytes, have " + _digits(end - pos));
    }
    let ie_id: Int = _byte(data, pos);
    let ie_len: Int = _byte(data, pos + 1);
    let payload_off = pos + 2;
    if payload_off + ie_len > end {
      return _err_mgmt("wireless: bad ie length at offset " + _digits(pos) + ": ie " + _digits(ie_id) + " length " + _digits(ie_len) + " exceeds " + _digits(end - payload_off) + " remaining bytes");
    }
    ie_ids.push(ie_id);
    ie_offsets.push(payload_off);
    ie_lengths.push(ie_len);
    if ie_id == WIRELESS_IE_SSID {
      if !ssid_set {
        ssid = _copy_range(data, payload_off, ie_len);
        ssid_set = true;
      }
    } elif ie_id == WIRELESS_IE_SUPPORTED_RATES {
      if !rates_set {
        rates = _copy_range(data, payload_off, ie_len);
        rates_set = true;
      }
    } elif ie_id == WIRELESS_IE_DS_PARAMETER_SET {
      if ie_len != 1 {
        return _err_mgmt(_bad_ie(pos, "ds parameter set", ie_len));
      }
      ds_channel = _byte(data, payload_off);
    } elif ie_id == WIRELESS_IE_TIM {
      if ie_len < 2 {
        return _err_mgmt(_bad_ie(pos, "tim", ie_len));
      }
      tim_dtim_count = _byte(data, payload_off);
      tim_dtim_period = _byte(data, payload_off + 1);
      tim_bitmap_off = payload_off + 2;
      tim_bitmap_len = ie_len - 2;
    } elif ie_id == WIRELESS_IE_COUNTRY {
      if ie_len < 3 || (ie_len - 3) % 3 != 0 {
        return _err_mgmt(_bad_ie(pos, "country", ie_len));
      }
      country_code = _byte(data, payload_off) * 256 + _byte(data, payload_off + 1);
      country_triplets = (ie_len - 3) / 3;
    } elif ie_id == WIRELESS_IE_HT_CAPABILITIES {
      if ie_len != 26 {
        return _err_mgmt(_bad_ie(pos, "ht capabilities", ie_len));
      }
      ht_present = true;
      ht_info = _le_u16(data, payload_off);
      ht_ampdu = _byte(data, payload_off + 2);
    } elif ie_id == WIRELESS_IE_RSN {
      let rr = _rsn_decode(data, payload_off, ie_len, pos);
      if !rr.is_ok {
        return _err_mgmt(rr.error);
      }
      let rsn: WirelessRsn = rr.value;
      rsn_version = rsn.version;
      rsn_group = rsn.group;
      rsn_pairwise = rsn.pairwise;
      rsn_akm = rsn.akm;
      rsn_capabilities = rsn.capabilities;
      rsn_pmkid_count = rsn.pmkid_count;
    } elif ie_id == WIRELESS_IE_VENDOR_SPECIFIC {
      let vr = _vendor_decode(data, payload_off, ie_len, pos);
      if !vr.is_ok {
        return _err_mgmt(vr.error);
      }
      let vendor_id: Int = vr.value;
      vendor_ouis.push(vendor_id / 256);
      vendor_types.push(vendor_id % 256);
      if vendor_id / 256 == 20722 {
        if vendor_id % 256 == 1 {
          vendor_wpa = true;
        }
        if vendor_id % 256 == 2 {
          vendor_wmm = true;
        }
      }
    } elif ie_id == WIRELESS_IE_VHT_CAPABILITIES {
      if ie_len != 12 {
        return _err_mgmt(_bad_ie(pos, "vht capabilities", ie_len));
      }
      vht_present = true;
      vht_info = _le_u32(data, payload_off);
    } elif ie_id == WIRELESS_IE_EXTENDED_CAPABILITIES {
      if ie_len < 1 {
        return _err_mgmt(_bad_ie(pos, "extended capabilities", ie_len));
      }
      ext_present = true;
      ext_len = ie_len;
    }
    pos = payload_off + ie_len;
  }
  let m = WirelessMgmt{
    subtype: subtype;
    body_kind: body_kind;
    timestamp: timestamp;
    beacon_interval: beacon_interval;
    capability: capability;
    status_code: status_code;
    reason_code: reason_code;
    auth_algorithm: auth_algorithm;
    auth_sequence: auth_sequence;
    listen_interval: listen_interval;
    aid: aid;
    category: category;
    action: action;
    current_ap: current_ap;
    action_off: action_off;
    action_len: action_len;
    ie_area_off: ie_off;
    ie_area_len: end - ie_off;
    ie_ids: ie_ids;
    ie_offsets: ie_offsets;
    ie_lengths: ie_lengths;
    ssid: ssid;
    rates: rates;
    ds_channel: ds_channel;
    tim_dtim_count: tim_dtim_count;
    tim_dtim_period: tim_dtim_period;
    tim_bitmap_off: tim_bitmap_off;
    tim_bitmap_len: tim_bitmap_len;
    country_code: country_code;
    country_triplets: country_triplets;
    rsn_version: rsn_version;
    rsn_group: rsn_group;
    rsn_pairwise: rsn_pairwise;
    rsn_akm: rsn_akm;
    rsn_capabilities: rsn_capabilities;
    rsn_pmkid_count: rsn_pmkid_count;
    vendor_ouis: vendor_ouis;
    vendor_types: vendor_types;
    vendor_wpa: vendor_wpa;
    vendor_wmm: vendor_wmm;
    ht_present: ht_present;
    ht_info: ht_info;
    ht_ampdu: ht_ampdu;
    vht_present: vht_present;
    vht_info: vht_info;
    ext_present: ext_present;
    ext_len: ext_len;
  };
  return _ok_mgmt(m);
}

// --------------------------------------------------
//  Frame accessors
// --------------------------------------------------

/// Frame Control type (WIRELESS_TYPE_*). Complexity: O(1).
pub fn wireless_frame_type(f: &WirelessFrame) -> Int {
  return f.frame_type;
}

/// Frame Control subtype (0..15). Complexity: O(1).
pub fn wireless_subtype(f: &WirelessFrame) -> Int {
  return f.subtype;
}

/// Frame Control protocol version (always 0 for an accepted frame).
/// Complexity: O(1).
pub fn wireless_protocol_version(f: &WirelessFrame) -> Int {
  return f.protocol_version;
}

/// Frame Control flag `bit` (0..7) as a Bool; false for out-of-range bits.
/// Complexity: O(1).
pub fn wireless_flag(f: &WirelessFrame, bit: Int) -> Bool {
  if bit < 0 || bit > 7 {
    return false;
  }
  return _bit(f.flag_byte, bit);
}

/// Duration/ID field as read. On a PS-Poll frame this is the AID carrier
/// (see wireless_ps_poll_aid for the extracted AID). Complexity: O(1).
pub fn wireless_duration_id(f: &WirelessFrame) -> Int {
  return f.duration_id;
}

/// AID carried by a PS-Poll frame's Duration/ID field: the low 14 bits
/// (bits 14..15 are marker bits and are masked out). The raw field stays
/// available through wireless_duration_id.
/// Err("wireless: not a ps-poll frame") for any other frame.
/// Complexity: O(1).
pub fn wireless_ps_poll_aid(f: &WirelessFrame) -> Result[Int, Str] {
  if f.frame_type != WIRELESS_TYPE_CONTROL {
    return _err_int("wireless: not a ps-poll frame");
  }
  if f.subtype != WIRELESS_CTRL_PS_POLL {
    return _err_int("wireless: not a ps-poll frame");
  }
  return _ok_int(f.duration_id % 16384);
}

/// Number of addresses present (1..4). Complexity: O(1).
pub fn wireless_address_count(f: &WirelessFrame) -> Int {
  return f.addr_count;
}

/// Sequence Control as read, or -1 when the frame type has none.
/// Complexity: O(1).
pub fn wireless_sequence_control(f: &WirelessFrame) -> Int {
  return f.seq_control;
}

/// Fragment number (low 4 bits of Sequence Control), or -1 when absent.
/// Complexity: O(1).
pub fn wireless_fragment_number(f: &WirelessFrame) -> Int {
  return f.fragment_number;
}

/// Sequence number (high 12 bits of Sequence Control), or -1 when absent.
/// Complexity: O(1).
pub fn wireless_sequence_number(f: &WirelessFrame) -> Int {
  return f.sequence_number;
}

/// True when a QoS Control field is present. Complexity: O(1).
pub fn wireless_qos_present(f: &WirelessFrame) -> Bool {
  return f.qos_control_present;
}

/// Traffic identifier from QoS Control, or -1 when absent. Complexity: O(1).
pub fn wireless_tid(f: &WirelessFrame) -> Int {
  return f.tid;
}

/// End-of-service-period bit from QoS Control; false when absent.
/// Complexity: O(1).
pub fn wireless_eosp(f: &WirelessFrame) -> Bool {
  return f.eosp;
}

/// Ack policy from QoS Control (0..3), or -1 when absent. Complexity: O(1).
pub fn wireless_ack_policy(f: &WirelessFrame) -> Int {
  return f.ack_policy;
}

/// True when the QoS Control A-MSDU bit is set. Complexity: O(1).
pub fn wireless_a_msdu_present(f: &WirelessFrame) -> Bool {
  return f.a_msdu_present;
}

/// TXOP limit from QoS Control (units of 32 microseconds), or -1 when
/// absent. Complexity: O(1).
pub fn wireless_txop_limit(f: &WirelessFrame) -> Int {
  return f.txop_limit;
}

/// True when the Order bit marks a 4-byte HT Control field. Complexity: O(1).
pub fn wireless_ht_control_present(f: &WirelessFrame) -> Bool {
  return f.ht_control_present;
}

/// Header length in bytes: the number of bytes consumed by the MAC header.
/// Complexity: O(1).
pub fn wireless_header_length(f: &WirelessFrame) -> Int {
  return f.header_len;
}

/// Absolute offset of the first frame body byte. Complexity: O(1).
pub fn wireless_body_offset(f: &WirelessFrame) -> Int {
  return f.body_off;
}

/// Number of body bytes after the MAC header in the parsed buffer.
/// Complexity: O(1).
pub fn wireless_body_length(f: &WirelessFrame) -> Int {
  return f.body_len;
}

/// Copy address `index` (1..4). Err("wireless: address absent") when the
/// frame has no such address, Err("wireless: address index out of range")
/// when `index` is outside 1..4. Complexity: O(1).
pub fn wireless_address(f: &WirelessFrame, index: Int) -> Result[Vec[UInt8], Str] {
  if index < 1 || index > 4 {
    return _err_bytes("wireless: address index out of range");
  }
  if index > f.addr_count {
    return _err_bytes("wireless: address absent");
  }
  if index == 1 {
    let a: Vec[UInt8] = f.addr1;
    return _ok_bytes(a);
  }
  if index == 2 {
    let a: Vec[UInt8] = f.addr2;
    return _ok_bytes(a);
  }
  if index == 3 {
    let a: Vec[UInt8] = f.addr3;
    return _ok_bytes(a);
  }
  let a: Vec[UInt8] = f.addr4;
  return _ok_bytes(a);
}

/// Byte `byte_index` (0..5) of address `index` (1..4), or -1 when the
/// address or byte index is absent. Complexity: O(1).
pub fn wireless_address_byte(f: &WirelessFrame, index: Int, byte_index: Int) -> Int {
  if index < 1 || index > 4 {
    return -1;
  }
  if byte_index < 0 || byte_index > 5 {
    return -1;
  }
  if index > f.addr_count {
    return -1;
  }
  var a = f.addr1;
  if index == 2 {
    a = f.addr2;
  } elif index == 3 {
    a = f.addr3;
  } elif index == 4 {
    a = f.addr4;
  }
  if byte_index >= a.len() {
    return -1;
  }
  return _byte(a, byte_index);
}

/// Copy the body bytes (`body_len` bytes at `body_off`) out of `data`.
/// Err("wireless: body out of bounds") when the recorded span does not fit
/// in `data`. Complexity: O(body_len).
pub fn wireless_body(data: &Vec[UInt8], f: &WirelessFrame) -> Result[Vec[UInt8], Str] {
  let off: Int = f.body_off;
  let len: Int = f.body_len;
  if off < 0 || len < 0 {
    return _err_bytes("wireless: body out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("wireless: body out of bounds");
  }
  return _ok_bytes(_copy_range(data, off, len));
}

// --------------------------------------------------
//  Capability field accessors
// --------------------------------------------------

/// Capability information bit `bit` (0..15); false when out of range.
/// Complexity: O(1).
pub fn wireless_capability_bit(capability: Int, bit: Int) -> Bool {
  if bit < 0 || bit > 15 {
    return false;
  }
  return _bits_at(capability, bit, 1) == 1;
}

/// Capability bit 0: ESS. Complexity: O(1).
pub fn wireless_cap_ess(capability: Int) -> Bool {
  return _bits_at(capability, 0, 1) == 1;
}

/// Capability bit 1: IBSS. Complexity: O(1).
pub fn wireless_cap_ibss(capability: Int) -> Bool {
  return _bits_at(capability, 1, 1) == 1;
}

/// Capability bit 4: privacy. Complexity: O(1).
pub fn wireless_cap_privacy(capability: Int) -> Bool {
  return _bits_at(capability, 4, 1) == 1;
}

/// Capability bit 5: short preamble. Complexity: O(1).
pub fn wireless_cap_short_preamble(capability: Int) -> Bool {
  return _bits_at(capability, 5, 1) == 1;
}

/// Capability bit 8: spectrum management. Complexity: O(1).
pub fn wireless_cap_spectrum_management(capability: Int) -> Bool {
  return _bits_at(capability, 8, 1) == 1;
}

/// Capability bit 9: QoS. Complexity: O(1).
pub fn wireless_cap_qos(capability: Int) -> Bool {
  return _bits_at(capability, 9, 1) == 1;
}

/// Capability bit 10: short slot time. Complexity: O(1).
pub fn wireless_cap_short_slot_time(capability: Int) -> Bool {
  return _bits_at(capability, 10, 1) == 1;
}

/// Capability bit 11: APSD. Complexity: O(1).
pub fn wireless_cap_apsd(capability: Int) -> Bool {
  return _bits_at(capability, 11, 1) == 1;
}

/// Capability bit 12: radio measurement. Complexity: O(1).
pub fn wireless_cap_radio_measurement(capability: Int) -> Bool {
  return _bits_at(capability, 12, 1) == 1;
}

/// Capability bit 13: DSSS-OFDM. Complexity: O(1).
pub fn wireless_cap_dsss_ofdm(capability: Int) -> Bool {
  return _bits_at(capability, 13, 1) == 1;
}

// --------------------------------------------------
//  Management accessors
// --------------------------------------------------

/// Management subtype of a parsed body. Complexity: O(1).
pub fn wireless_mgmt_subtype(m: &WirelessMgmt) -> Int {
  return m.subtype;
}

/// Beacon timestamp (u64) or -1 when the family has none. Complexity: O(1).
pub fn wireless_timestamp(m: &WirelessMgmt) -> Int {
  return m.timestamp;
}

/// Beacon interval in time units or -1. Complexity: O(1).
pub fn wireless_beacon_interval(m: &WirelessMgmt) -> Int {
  return m.beacon_interval;
}

/// Capability information field or -1. Complexity: O(1).
pub fn wireless_capability(m: &WirelessMgmt) -> Int {
  return m.capability;
}

/// Status code or -1. Complexity: O(1).
pub fn wireless_status_code(m: &WirelessMgmt) -> Int {
  return m.status_code;
}

/// Reason code or -1. Complexity: O(1).
pub fn wireless_reason_code(m: &WirelessMgmt) -> Int {
  return m.reason_code;
}

/// Authentication algorithm number or -1. Complexity: O(1).
pub fn wireless_auth_algorithm(m: &WirelessMgmt) -> Int {
  return m.auth_algorithm;
}

/// Authentication transaction sequence number or -1. Complexity: O(1).
pub fn wireless_auth_sequence(m: &WirelessMgmt) -> Int {
  return m.auth_sequence;
}

/// Association listen interval or -1. Complexity: O(1).
pub fn wireless_listen_interval(m: &WirelessMgmt) -> Int {
  return m.listen_interval;
}

/// Association ID as read (bits 14..15 preserved) or -1. Complexity: O(1).
pub fn wireless_aid(m: &WirelessMgmt) -> Int {
  return m.aid;
}

/// Action category or -1. Complexity: O(1).
pub fn wireless_action_category(m: &WirelessMgmt) -> Int {
  return m.category;
}

/// Action code or -1. Complexity: O(1).
pub fn wireless_action_code(m: &WirelessMgmt) -> Int {
  return m.action;
}

/// Copy of the reassociation current AP address (empty for other bodies).
/// Complexity: O(1).
pub fn wireless_current_ap(m: &WirelessMgmt) -> Vec[UInt8] {
  let a: Vec[UInt8] = m.current_ap;
  return a;
}

/// Number of information elements walked. Complexity: O(1).
pub fn wireless_ie_count(m: &WirelessMgmt) -> Int {
  return m.ie_ids.len();
}

/// Element id at pool index `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn wireless_ie_id(m: &WirelessMgmt, i: Int) -> Int {
  if i < 0 || i >= m.ie_ids.len() {
    return -1;
  }
  let v: Int = m.ie_ids[i];
  return v;
}

/// Absolute payload offset of element `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn wireless_ie_offset(m: &WirelessMgmt, i: Int) -> Int {
  if i < 0 || i >= m.ie_offsets.len() {
    return -1;
  }
  let v: Int = m.ie_offsets[i];
  return v;
}

/// Payload length of element `i`, or -1 when out of range. Complexity: O(1).
pub fn wireless_ie_length(m: &WirelessMgmt, i: Int) -> Int {
  if i < 0 || i >= m.ie_lengths.len() {
    return -1;
  }
  let v: Int = m.ie_lengths[i];
  return v;
}

/// Index of the first element with id `id`, or -1 when absent.
/// Complexity: O(elements).
pub fn wireless_ie_find(m: &WirelessMgmt, id: Int) -> Int {
  var i = 0;
  while i < m.ie_ids.len() {
    let v: Int = m.ie_ids[i];
    if v == id {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// True when an element with id `id` is present. Complexity: O(elements).
pub fn wireless_ie_present(m: &WirelessMgmt, id: Int) -> Bool {
  return wireless_ie_find(m, id) >= 0;
}

/// Copy the payload of element `i` out of `data` (any id, including
/// unknown ones). Err("wireless: ie index out of range") when `i` is not a
/// walked element, Err("wireless: ie out of bounds") when the recorded span
/// does not fit `data`. Complexity: O(payload).
pub fn wireless_ie_payload(data: &Vec[UInt8], m: &WirelessMgmt, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= m.ie_lengths.len() {
    return _err_bytes("wireless: ie index out of range");
  }
  let off: Int = m.ie_offsets[i];
  let len: Int = m.ie_lengths[i];
  if off < 0 || len < 0 || off + len > data.len() {
    return _err_bytes("wireless: ie out of bounds");
  }
  return _ok_bytes(_copy_range(data, off, len));
}

/// Copy the payload of the first element with id `id`.
/// Err("wireless: ie absent") when no such element exists, Err("wireless:
/// ie out of bounds") when the recorded span does not fit `data`.
/// Complexity: O(elements + payload).
pub fn wireless_ie_payload_of(data: &Vec[UInt8], m: &WirelessMgmt, id: Int) -> Result[Vec[UInt8], Str] {
  let i: Int = wireless_ie_find(m, id);
  if i < 0 {
    return _err_bytes("wireless: ie absent");
  }
  return wireless_ie_payload(data, m, i);
}

/// Copy of the SSID payload, which may legitimately be empty (wildcard
/// probe request). Err("wireless: ssid ie absent") when the frame has no
/// SSID element. Complexity: O(ssid).
pub fn wireless_ssid(m: &WirelessMgmt) -> Result[Vec[UInt8], Str] {
  if !wireless_ie_present(m, WIRELESS_IE_SSID) {
    return _err_bytes("wireless: ssid ie absent");
  }
  let s: Vec[UInt8] = m.ssid;
  return _ok_bytes(s);
}

/// Copy of the supported rates payload (each byte is 0.5 Mbps in the low
/// 7 bits; bit 7 marks a basic rate). Err("wireless: supported rates ie
/// absent") when absent. Complexity: O(rates).
pub fn wireless_rates(m: &WirelessMgmt) -> Result[Vec[UInt8], Str] {
  if !wireless_ie_present(m, WIRELESS_IE_SUPPORTED_RATES) {
    return _err_bytes("wireless: supported rates ie absent");
  }
  let r: Vec[UInt8] = m.rates;
  return _ok_bytes(r);
}

/// True when a supported rate byte is marked basic (bit 7 set).
/// Complexity: O(1).
pub fn wireless_rate_is_basic(rate_byte: Int) -> Bool {
  return rate_byte >= 128;
}

/// Rate in half-Mbps units carried by a supported rate byte (low 7 bits).
/// Complexity: O(1).
pub fn wireless_rate_half_mbps(rate_byte: Int) -> Int {
  return rate_byte % 128;
}

/// DS parameter set channel number, or Err("wireless: ds parameter set ie
/// absent"). Complexity: O(elements).
pub fn wireless_ds_channel(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_DS_PARAMETER_SET) {
    return _err_int("wireless: ds parameter set ie absent");
  }
  return _ok_int(m.ds_channel);
}

/// TIM DTIM count, or Err("wireless: tim ie absent"). Complexity: O(elements).
pub fn wireless_tim_dtim_count(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_TIM) {
    return _err_int("wireless: tim ie absent");
  }
  return _ok_int(m.tim_dtim_count);
}

/// TIM DTIM period, or Err("wireless: tim ie absent"). Complexity: O(elements).
pub fn wireless_tim_dtim_period(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_TIM) {
    return _err_int("wireless: tim ie absent");
  }
  return _ok_int(m.tim_dtim_period);
}

/// TIM bitmap length in bytes (0 when the element declares no bitmap), or
/// Err("wireless: tim ie absent"). Complexity: O(elements).
pub fn wireless_tim_bitmap_len(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_TIM) {
    return _err_int("wireless: tim ie absent");
  }
  return _ok_int(m.tim_bitmap_len);
}

/// Copy the TIM bitmap bytes (length wireless_tim_bitmap_len), or
/// Err("wireless: tim ie absent") / Err("wireless: tim bitmap out of
/// bounds"). Complexity: O(bitmap).
pub fn wireless_tim_bitmap(data: &Vec[UInt8], m: &WirelessMgmt) -> Result[Vec[UInt8], Str] {
  if !wireless_ie_present(m, WIRELESS_IE_TIM) {
    return _err_bytes("wireless: tim ie absent");
  }
  let off: Int = m.tim_bitmap_off;
  let len: Int = m.tim_bitmap_len;
  if off < 0 || len < 0 || off + len > data.len() {
    return _err_bytes("wireless: tim bitmap out of bounds");
  }
  return _ok_bytes(_copy_range(data, off, len));
}

/// Country code of the country element as two packed ASCII bytes
/// (first*256 + second), or Err("wireless: country ie absent").
/// Complexity: O(elements).
pub fn wireless_country_code(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_COUNTRY) {
    return _err_int("wireless: country ie absent");
  }
  return _ok_int(m.country_code);
}

/// Number of channel triplets carried by the country element, or
/// Err("wireless: country ie absent"). Complexity: O(elements).
pub fn wireless_country_triplets(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_COUNTRY) {
    return _err_int("wireless: country ie absent");
  }
  return _ok_int(m.country_triplets);
}

/// RSN element version, or Err("wireless: rsn ie absent"). Complexity: O(elements).
pub fn wireless_rsn_version(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_RSN) {
    return _err_int("wireless: rsn ie absent");
  }
  return _ok_int(m.rsn_version);
}

/// RSN group cipher suite as a combined OUI*256+type identifier
/// (wireless_suite_oui / wireless_suite_type split it), or
/// Err("wireless: rsn ie absent"). Complexity: O(elements).
pub fn wireless_rsn_group(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_RSN) {
    return _err_int("wireless: rsn ie absent");
  }
  return _ok_int(m.rsn_group);
}

/// Number of RSN pairwise cipher suites (0 when no RSN element).
/// Complexity: O(1).
pub fn wireless_rsn_pairwise_count(m: &WirelessMgmt) -> Int {
  return m.rsn_pairwise.len();
}

/// RSN pairwise cipher suite `i` as a combined OUI*256+type identifier.
/// Err("wireless: rsn ie absent") when there is no RSN element,
/// Err("wireless: rsn pairwise index out of range") otherwise.
/// Complexity: O(1).
pub fn wireless_rsn_pairwise(m: &WirelessMgmt, i: Int) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_RSN) {
    return _err_int("wireless: rsn ie absent");
  }
  if i < 0 || i >= m.rsn_pairwise.len() {
    return _err_int("wireless: rsn pairwise index out of range");
  }
  let v: Int = m.rsn_pairwise[i];
  return _ok_int(v);
}

/// Number of RSN AKM suites (0 when no RSN element). Complexity: O(1).
pub fn wireless_rsn_akm_count(m: &WirelessMgmt) -> Int {
  return m.rsn_akm.len();
}

/// RSN AKM suite `i` as a combined OUI*256+type identifier.
/// Err("wireless: rsn ie absent") when there is no RSN element,
/// Err("wireless: rsn akm index out of range") otherwise. Complexity: O(1).
pub fn wireless_rsn_akm(m: &WirelessMgmt, i: Int) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_RSN) {
    return _err_int("wireless: rsn ie absent");
  }
  if i < 0 || i >= m.rsn_akm.len() {
    return _err_int("wireless: rsn akm index out of range");
  }
  let v: Int = m.rsn_akm[i];
  return _ok_int(v);
}

/// RSN capabilities u16, or Err("wireless: rsn ie absent").
/// Complexity: O(elements).
pub fn wireless_rsn_capabilities(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_RSN) {
    return _err_int("wireless: rsn ie absent");
  }
  return _ok_int(m.rsn_capabilities);
}

/// RSN PMKID count, or -1 inside Ok when the RSN element carries no PMKID
/// count field; Err("wireless: rsn ie absent") without an RSN element.
/// Complexity: O(elements).
pub fn wireless_rsn_pmkid_count(m: &WirelessMgmt) -> Result[Int, Str] {
  if !wireless_ie_present(m, WIRELESS_IE_RSN) {
    return _err_int("wireless: rsn ie absent");
  }
  return _ok_int(m.rsn_pmkid_count);
}

/// OUI (24-bit) of a combined suite identifier. Complexity: O(1).
pub fn wireless_suite_oui(suite: Int) -> Int {
  return suite / 256;
}

/// Suite type byte of a combined suite identifier. Complexity: O(1).
pub fn wireless_suite_type(suite: Int) -> Int {
  return suite % 256;
}

/// OUI byte `i` (0..2, most significant first) of a combined suite
/// identifier, or -1 when `i` is out of range. Complexity: O(1).
pub fn wireless_suite_oui_byte(suite: Int, i: Int) -> Int {
  if i < 0 || i > 2 {
    return -1;
  }
  let oui: Int = suite / 256;
  if i == 0 {
    return oui / 65536;
  }
  if i == 1 {
    return (oui / 256) % 256;
  }
  return oui % 256;
}

/// HT capabilities info field (first u16 of element 45), or
/// Err("wireless: ht capabilities ie absent"). Complexity: O(elements).
pub fn wireless_ht_cap_info(m: &WirelessMgmt) -> Result[Int, Str] {
  if !m.ht_present {
    return _err_int("wireless: ht capabilities ie absent");
  }
  return _ok_int(m.ht_info);
}

/// HT A-MPDU parameters byte (third byte of element 45), or
/// Err("wireless: ht capabilities ie absent"). Complexity: O(elements).
pub fn wireless_ht_ampdu(m: &WirelessMgmt) -> Result[Int, Str] {
  if !m.ht_present {
    return _err_int("wireless: ht capabilities ie absent");
  }
  return _ok_int(m.ht_ampdu);
}

/// VHT capabilities info field (first u32 of element 191), or
/// Err("wireless: vht capabilities ie absent"). Complexity: O(elements).
pub fn wireless_vht_cap_info(m: &WirelessMgmt) -> Result[Int, Str] {
  if !m.vht_present {
    return _err_int("wireless: vht capabilities ie absent");
  }
  return _ok_int(m.vht_info);
}

/// Extended capabilities length in bytes (element 127), or
/// Err("wireless: extended capabilities ie absent"). Complexity: O(elements).
pub fn wireless_ext_cap_len(m: &WirelessMgmt) -> Result[Int, Str] {
  if !m.ext_present {
    return _err_int("wireless: extended capabilities ie absent");
  }
  return _ok_int(m.ext_len);
}

/// True when a WPA vendor element (00:50:F2 type 1) is present.
/// Complexity: O(1).
pub fn wireless_vendor_wpa(m: &WirelessMgmt) -> Bool {
  return m.vendor_wpa;
}

/// True when a WMM vendor element (00:50:F2 type 2) is present.
/// Complexity: O(1).
pub fn wireless_vendor_wmm(m: &WirelessMgmt) -> Bool {
  return m.vendor_wmm;
}

/// Number of vendor specific elements walked. Complexity: O(1).
pub fn wireless_vendor_count(m: &WirelessMgmt) -> Int {
  return m.vendor_ouis.len();
}

/// OUI (24-bit) of vendor element `i`, or Err("wireless: vendor index out
/// of range"). Complexity: O(1).
pub fn wireless_vendor_oui(m: &WirelessMgmt, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= m.vendor_ouis.len() {
    return _err_int("wireless: vendor index out of range");
  }
  let v: Int = m.vendor_ouis[i];
  return _ok_int(v);
}

/// OUI type byte of vendor element `i`, or Err("wireless: vendor index out
/// of range"). Complexity: O(1).
pub fn wireless_vendor_type(m: &WirelessMgmt, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= m.vendor_types.len() {
    return _err_int("wireless: vendor index out of range");
  }
  let v: Int = m.vendor_types[i];
  return _ok_int(v);
}
