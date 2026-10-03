// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.streaming: RTP/RTCP/RTSP wire-format codecs
// Port task: promote the xiom.streaming placeholder to a real, tested,
// pure-XIOM package covering the RTP/RTCP/RTSP wire formats:
//   (a) RFC 3550 RTP fixed header: V/P/X/CC, marker, payload type, 16-bit
//       sequence, 32-bit timestamp, SSRC, CSRC list, and the one-byte
//       header extension (16-bit profile, 16-bit length in 32-bit words);
//   (b) wrap-safe 16-bit sequence and 32-bit timestamp arithmetic per
//       RFC 1982 serial-number rules (unsigned wrap, half-range ambiguity
//       resolved toward "not before");
//   (c) the RFC 3550 A.8 interarrival jitter estimator in integer
//       arithmetic (see the jitter section for units and rounding), plus a
//       literal sliding-window mean over the same transit deltas;
//   (d) RTCP SR/RR basics: version/PT/length header (length in 32-bit words
//       minus one), sender SSRC, sender-info fields for SR, and 24-byte
//       report blocks (fraction lost fixed-point, signed 24-bit cumulative
//       packets lost, extended highest sequence, jitter, LSR, DLSR);
//   (e) RTSP text messages: request line (method/URI/version), response
//       status line and header lines parsed into parallel Vec fields, with
//       canonical CRLF builders.
//
// Out of scope (documented in README.md and SPEC.md): WebRTC (SDP, ICE,
// DTLS, SRTP), RTMP, HLS, DASH, RTP payload formats, RTCP SDES/BYE/XR,
// RTSP session state, interleaved TCP framing, and any I/O or sockets.
// Packets and messages go in and out as values.
//
// Conventions that shaped this module (pinned v0.62.1):
//   * free functions only; no methods, lambdas, or Vec[StructType]. The one
//     list in an RTP header (CSRCs) and the report blocks are parallel Vec
//     fields inside plain value types.
//   * Ok/Err construction is confined to the tiny leaf helpers below;
//     constructing Results directly inside other functions miscompiles.
//   * every byte read from a Vec[UInt8] is widened with
//     `(x as Int) & 0xFF` before entering Int arithmetic (`byte_at`
//     comparisons at >= 128 are still miscompiled).
//   * bit fields are extracted with divisor/modulo arithmetic, never with
//     shifts or masks on values that could carry the sign bit; 32-bit
//     fields are packed with the negative-safe `_be_byte` byte extractor.
//   * Str values are compared byte by byte through the local helpers, never
//     with `==`, and Str values read from Vec[Str] are bound to typed locals
//     first (BUG 17).
//   * no Vec[Float64] and no floating-point math anywhere.

module xiom.streaming

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// RTP version implemented by this module (RFC 3550: version = 2).
/// Complexity: O(1).
pub const RTP_VERSION: Int = 2;
/// RTP fixed header length in bytes, without CSRCs or extension.
/// Complexity: O(1).
pub const RTP_FIXED_HEADER_BYTES: Int = 12;
/// Bytes per CSRC identifier. Complexity: O(1).
pub const RTP_CSRC_BYTES: Int = 4;
/// Bytes per header-extension preamble (16-bit profile + 16-bit length).
/// Complexity: O(1).
pub const RTP_EXTENSION_PREAMBLE_BYTES: Int = 4;
/// Maximum CSRC count (the CC field is 4 bits). Complexity: O(1).
pub const RTP_MAX_CSRC_COUNT: Int = 15;
/// Maximum payload type (the M bit leaves 7 bits). Complexity: O(1).
pub const RTP_MAX_PAYLOAD_TYPE: Int = 127;
/// Sequence-number modulus: 2^16. Complexity: O(1).
pub const RTP_SEQ_MOD: Int = 65536;
/// Sequence-number half range: 2^15 (the ambiguous serial-number point).
/// Complexity: O(1).
pub const RTP_SEQ_HALF: Int = 32768;
/// Largest 16-bit sequence number. Complexity: O(1).
pub const RTP_SEQ_MAX: Int = 65535;
/// Timestamp modulus: 2^32. Complexity: O(1).
pub const RTP_TS_MOD: Int = 4294967296;
/// Timestamp half range: 2^31 (the ambiguous serial-number point).
/// Complexity: O(1).
pub const RTP_TS_HALF: Int = 2147483648;
/// Largest 32-bit timestamp / SSRC / CSRC value. Complexity: O(1).
pub const RTP_TS_MAX: Int = 4294967295;

/// RTCP version implemented by this module (RFC 3550: version = 2).
/// Complexity: O(1).
pub const RTCP_VERSION: Int = 2;
/// RTCP packet type of a sender report. Complexity: O(1).
pub const RTCP_PT_SR: Int = 200;
/// RTCP packet type of a receiver report. Complexity: O(1).
pub const RTCP_PT_RR: Int = 201;
/// RTCP common header length in bytes. Complexity: O(1).
pub const RTCP_HEADER_BYTES: Int = 4;
/// RR bytes before the first report block (header + receiver SSRC).
/// Complexity: O(1).
pub const RTCP_RR_HEADER_BYTES: Int = 8;
/// SR bytes before the first report block (header + sender SSRC + sender
/// info). Complexity: O(1).
pub const RTCP_SR_HEADER_BYTES: Int = 28;
/// One RTCP report block in bytes. Complexity: O(1).
pub const RTCP_REPORT_BLOCK_BYTES: Int = 24;
/// Maximum report-block count (the RTCP count field is 5 bits).
/// Complexity: O(1).
pub const RTCP_MAX_BLOCKS: Int = 31;
/// Largest 8-bit fraction-lost value (fixed point: value / 256).
/// Complexity: O(1).
pub const RTCP_FRACTION_MAX: Int = 255;
/// Smallest signed 24-bit cumulative-packets-lost value. Complexity: O(1).
pub const RTCP_CUM_LOST_MIN: Int = -8388608;
/// Largest signed 24-bit cumulative-packets-lost value. Complexity: O(1).
pub const RTCP_CUM_LOST_MAX: Int = 8388607;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A parsed RFC 3550 RTP header. Field values are the raw wire values:
/// `version` is the 2-bit V field (always 2 for a parsed header), `padding`
/// and `extension` are the P and X bits, `csrc_count` the 4-bit CC field,
/// `marker` the M bit, `payload_type` the 7-bit PT field (0..127),
/// `sequence` 0..65535, and `timestamp` / `ssrc` / every element of `csrcs`
/// are unsigned 32-bit values (0..2^32-1).
///
/// `extension_profile` / `extension_words` / `extension_data` describe the
/// header extension: the 16-bit profile id, the declared length in 32-bit
/// words, and exactly `extension_words * 4` payload bytes (all zero/empty
/// when the X bit is clear). `header_bytes` is the total octet length of the
/// parsed header (12 + 4*CC + 4 + 4*W when X is set) and `payload_offset`
/// equals it: the packet payload starts there.
pub type RtpHeader = {
  version: Int;
  padding: Bool;
  extension: Bool;
  csrc_count: Int;
  marker: Bool;
  payload_type: Int;
  sequence: Int;
  timestamp: Int;
  ssrc: Int;
  csrcs: Vec[Int];
  extension_profile: Int;
  extension_words: Int;
  extension_data: Vec[UInt8];
  header_bytes: Int;
  payload_offset: Int;
}

/// Interarrival jitter estimator state (RFC 3550 A.8), a plain immutable
/// value: feed samples with rtp_jitter_update, which returns the next state.
/// `value` is the current estimate in RTP timestamp ticks of the media
/// clock, `prev_arrival` / `prev_send` the last 32-bit arrival and sender
/// timestamps, and `updates` the number of deltas that contributed.
pub type RtpJitter = {
  value: Int;
  has_prev: Bool;
  prev_arrival: Int;
  prev_send: Int;
  updates: Int;
}

/// A parsed RTCP common header plus the values derived from it. `length_words`
/// is the raw 16-bit length field (packet length in 32-bit words minus one);
/// `total_bytes` = (length_words + 1) * 4. `count` is the 5-bit report or
/// sender count (0..31), `packet_type` the 8-bit PT field.
pub type RtcpHeader = {
  version: Int;
  padding: Bool;
  count: Int;
  packet_type: Int;
  length_words: Int;
  total_bytes: Int;
}

/// The report blocks of one RTCP SR or RR packet as parallel Vec fields
/// (each has the same length; index i is one 24-byte block).
/// `receiver_ssrc` is the SSRC of the packet sender (the receiver for RR,
/// the sender for SR). `fraction_lost` holds the raw 8-bit fixed-point field
/// (actual fraction = value / 256, so 25 means 25/256), `cumulative_lost`
/// the signed 24-bit value (-8388608..8388607), `highest_seq` the unsigned
/// 32-bit extended highest sequence number, `jitter` the unsigned 32-bit
/// interarrival jitter, and `lsr` / `dlsr` the unsigned 32-bit last-SR
/// timestamp and delay-since-last-SR fields.
pub type RtcpReports = {
  receiver_ssrc: Int;
  ssrcs: Vec[Int];
  fraction_lost: Vec[Int];
  cumulative_lost: Vec[Int];
  highest_seq: Vec[Int];
  jitter: Vec[Int];
  lsr: Vec[Int];
  dlsr: Vec[Int];
}

/// A parsed RTCP sender report: the 20-byte sender info (`ntp_msw` /
/// `ntp_lsw` are the NTP timestamp halves, `rtp_timestamp` the RTP
/// timestamp, `packet_count` / `octet_count` the sender counters) followed
/// by the report blocks, with `reports.receiver_ssrc` set to the sender
/// SSRC.
pub type RtcpSr = {
  sender_ssrc: Int;
  ntp_msw: Int;
  ntp_lsw: Int;
  rtp_timestamp: Int;
  packet_count: Int;
  octet_count: Int;
  reports: RtcpReports;
}

/// A parsed RTSP request: the request line (method, URI, RTSP version) plus
/// the header lines as parallel Vec fields (`names[i]` / `values[i]`; values
/// are trimmed of leading/trailing SP/TAB) and the body, verbatim ("" when
/// the message has none).
pub type RtspRequest = {
  method: Str;
  uri: Str;
  version: Str;
  names: Vec[Str];
  values: Vec[Str];
  body: Str;
}

/// A parsed RTSP response: the status line (version, 3-digit status code,
/// reason phrase; "" when the status line carried none) plus the header
/// lines as parallel Vec fields and the verbatim body.
pub type RtspResponse = {
  version: Str;
  status: Int;
  reason: Str;
  names: Vec[Str];
  values: Vec[Str];
  body: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
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

// Ok(v) for Result[RtpHeader, Str].
fn _ok_hdr(v: RtpHeader) -> Result[RtpHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[RtpHeader, Str].
fn _err_hdr(m: Str) -> Result[RtpHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[RtcpHeader, Str].
fn _ok_rtcp_hdr(v: RtcpHeader) -> Result[RtcpHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[RtcpHeader, Str].
fn _err_rtcp_hdr(m: Str) -> Result[RtcpHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[RtcpReports, Str].
fn _ok_reports(v: RtcpReports) -> Result[RtcpReports, Str] {
  return Ok(v);
}

// Err(m) for Result[RtcpReports, Str].
fn _err_reports(m: Str) -> Result[RtcpReports, Str] {
  return Err(m);
}

// Ok(v) for Result[RtcpSr, Str].
fn _ok_sr(v: RtcpSr) -> Result[RtcpSr, Str] {
  return Ok(v);
}

// Err(m) for Result[RtcpSr, Str].
fn _err_sr(m: Str) -> Result[RtcpSr, Str] {
  return Err(m);
}

// Ok(v) for Result[RtspRequest, Str].
fn _ok_req(v: RtspRequest) -> Result[RtspRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[RtspRequest, Str].
fn _err_req(m: Str) -> Result[RtspRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[RtspResponse, Str].
fn _ok_resp(v: RtspResponse) -> Result[RtspResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[RtspResponse, Str].
fn _err_resp(m: Str) -> Result[RtspResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _ok_vstr(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_vstr(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte primitives (arithmetic only; see module header)
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); the caller bounds it.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Big-endian byte `shift_bytes` of the raw two's-complement pattern of `v`
// (0 = least significant byte). Exact for negative values.
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

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Unsigned big-endian Int of the `size` bytes at `pos` (0..2^(8*size)-1).
fn _read_be(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < size {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Range and arithmetic helpers
// --------------------------------------------------

// True when 0 <= v <= 65535.
fn _u16_ok(v: Int) -> Bool {
  return v >= 0 && v <= RTP_SEQ_MAX;
}

// True when 0 <= v <= 2^32-1.
fn _u32_ok(v: Int) -> Bool {
  return v >= 0 && v <= RTP_TS_MAX;
}

// True when -2^23 <= v <= 2^23-1 (signed 24-bit).
fn _i24_ok(v: Int) -> Bool {
  return v >= RTCP_CUM_LOST_MIN && v <= RTCP_CUM_LOST_MAX;
}

// Modulo 2^16 with a non-negative result.
fn _wrap16(v: Int) -> Int {
  var r = v % RTP_SEQ_MOD;
  if r < 0 { r = r + RTP_SEQ_MOD; }
  return r;
}

// Modulo 2^32 with a non-negative result.
fn _wrap32(v: Int) -> Int {
  var r = v % RTP_TS_MOD;
  if r < 0 { r = r + RTP_TS_MOD; }
  return r;
}

// Absolute value of an Int.
fn _abs(v: Int) -> Int {
  if v < 0 { return 0 - v; }
  return v;
}

// --------------------------------------------------
//  RTP header parse / build
// --------------------------------------------------

/// Parse an RFC 3550 RTP header from the start of `data` (a full packet or
/// the first bytes of one).
///
/// CSRC identifiers and the header extension are included in the parse:
/// with the X bit set, the 16-bit profile and 16-bit length are read and
/// exactly `length * 4` extension bytes are copied out; the payload (and any
/// padding) follows `payload_offset` and is NOT validated here (use
/// rtp_payload_len and rtp_padding_len). Trailing bytes beyond the declared
/// header are left untouched, so a parse never fails merely because a
/// payload is present.
///
/// Error cases, in validation order:
///   Err("rtp: header needs 12 bytes, have N") when data.len() < 12;
///   Err("rtp: version N is not 2") when the V field is not 2;
///   Err("rtp: header needs N bytes, have M") when the CSRC list or the
///   extension preamble runs past the end of `data`;
///   Err("rtp: extension declares N words, have M bytes") when the declared
///   extension data is not fully present.
/// Complexity: O(header bytes).
pub fn rtp_parse_header(data: &Vec[UInt8]) -> Result[RtpHeader, Str] {
  let n = data.len();
  if n < RTP_FIXED_HEADER_BYTES {
    return _err_hdr("rtp: header needs 12 bytes, have " + convert.int_to_string(n));
  }
  let b0 = _byte(data, 0);
  let version = b0 / 64;
  if version != RTP_VERSION {
    return _err_hdr("rtp: version " + convert.int_to_string(version) + " is not 2");
  }
  let rest = b0 % 64;
  let padding = rest / 32 == 1;
  let rest2 = rest % 32;
  let extension = rest2 / 16 == 1;
  let csrc_count = rest2 % 16;
  let csrc_end = RTP_FIXED_HEADER_BYTES + csrc_count * RTP_CSRC_BYTES;
  if n < csrc_end {
    return _err_hdr("rtp: header needs " + convert.int_to_string(csrc_end) + " bytes, have " + convert.int_to_string(n));
  }
  var csrcs = Vec[Int].new();
  var ci = 0;
  while ci < csrc_count {
    csrcs.push(_read_be(data, RTP_FIXED_HEADER_BYTES + ci * RTP_CSRC_BYTES, RTP_CSRC_BYTES));
    ci = ci + 1;
  }
  var extension_profile = 0;
  var extension_words = 0;
  var extension_data = Vec[UInt8].new();
  var header_bytes = csrc_end;
  if extension {
    let preamble_end = csrc_end + RTP_EXTENSION_PREAMBLE_BYTES;
    if n < preamble_end {
      return _err_hdr("rtp: header needs " + convert.int_to_string(preamble_end) + " bytes, have " + convert.int_to_string(n));
    }
    extension_profile = _read_be(data, csrc_end, 2);
    extension_words = _read_be(data, csrc_end + 2, 2);
    let ext_bytes = extension_words * 4;
    let ext_end = preamble_end + ext_bytes;
    if n < ext_end {
      return _err_hdr("rtp: extension declares " + convert.int_to_string(extension_words) + " words, have " + convert.int_to_string(n - preamble_end) + " bytes");
    }
    var ei = 0;
    while ei < ext_bytes {
      extension_data.push(data[preamble_end + ei]);
      ei = ei + 1;
    }
    header_bytes = ext_end;
  }
  let b1 = _byte(data, 1);
  let marker = b1 / 128 == 1;
  let payload_type = b1 % 128;
  let h = RtpHeader{
    version: version;
    padding: padding;
    extension: extension;
    csrc_count: csrc_count;
    marker: marker;
    payload_type: payload_type;
    sequence: _read_be(data, 2, 2);
    timestamp: _read_be(data, 4, 4);
    ssrc: _read_be(data, 8, 4);
    csrcs: csrcs;
    extension_profile: extension_profile;
    extension_words: extension_words;
    extension_data: extension_data;
    header_bytes: header_bytes;
    payload_offset: header_bytes;
  };
  return _ok_hdr(h);
}

/// Build the RFC 3550 RTP header bytes described by `h` (12 + 4*CC bytes,
/// plus 4 + 4*extension_words when the X bit is set). The payload is not
/// part of the header and is not written.
///
/// Every field is range-checked before a single byte is written, in this
/// order: version = 2, CSRC count 0..15, CSRC count matches
/// `csrcs.len()`, each CSRC 0..2^32-1, payload type 0..127, sequence
/// 0..65535, timestamp 0..2^32-1, SSRC 0..2^32-1, then the extension
/// consistency checks (declared words 0..65535 and exactly
/// `extension_words * 4` data bytes when X is set; both extension fields
/// zero/empty when X is clear) and the extension profile 0..65535.
///
/// Returns: Ok(header bytes).
/// Error cases: the first failing check, with the exact messages listed in
/// SPEC.md, e.g. Err("rtp: version 1 is not 2"),
/// Err("rtp: csrc count 2 does not match 1 identifiers"),
/// Err("rtp: extension declares 2 words but data is 4 bytes").
/// Complexity: O(header bytes).
pub fn rtp_build_header(h: &RtpHeader) -> Result[Vec[UInt8], Str] {
  if h.version != RTP_VERSION {
    return _err_bytes("rtp: version " + convert.int_to_string(h.version) + " is not 2");
  }
  let cc: Int = h.csrc_count;
  if cc < 0 || cc > RTP_MAX_CSRC_COUNT {
    return _err_bytes("rtp: csrc count " + convert.int_to_string(cc) + " out of range 0..15");
  }
  if h.csrcs.len() != cc {
    return _err_bytes("rtp: csrc count " + convert.int_to_string(cc) + " does not match " + convert.int_to_string(h.csrcs.len()) + " identifiers");
  }
  var ci = 0;
  while ci < h.csrcs.len() {
    let x: Int = h.csrcs[ci];
    if !_u32_ok(x) {
      return _err_bytes("rtp: csrc " + convert.int_to_string(x) + " out of range 0..4294967295");
    }
    ci = ci + 1;
  }
  let pt: Int = h.payload_type;
  if pt < 0 || pt > RTP_MAX_PAYLOAD_TYPE {
    return _err_bytes("rtp: payload type " + convert.int_to_string(pt) + " out of range 0..127");
  }
  let seq: Int = h.sequence;
  if !_u16_ok(seq) {
    return _err_bytes("rtp: sequence " + convert.int_to_string(seq) + " out of range 0..65535");
  }
  let ts: Int = h.timestamp;
  if !_u32_ok(ts) {
    return _err_bytes("rtp: timestamp " + convert.int_to_string(ts) + " out of range 0..4294967295");
  }
  let ssrc: Int = h.ssrc;
  if !_u32_ok(ssrc) {
    return _err_bytes("rtp: ssrc " + convert.int_to_string(ssrc) + " out of range 0..4294967295");
  }
  let words: Int = h.extension_words;
  let profile: Int = h.extension_profile;
  if h.extension {
    if words < 0 || words > RTP_SEQ_MAX {
      return _err_bytes("rtp: extension words " + convert.int_to_string(words) + " out of range 0..65535");
    }
    if h.extension_data.len() != words * 4 {
      return _err_bytes("rtp: extension declares " + convert.int_to_string(words) + " words but data is " + convert.int_to_string(h.extension_data.len()) + " bytes");
    }
    if profile < 0 || profile > RTP_SEQ_MAX {
      return _err_bytes("rtp: extension profile " + convert.int_to_string(profile) + " out of range 0..65535");
    }
  } else {
    if words != 0 {
      return _err_bytes("rtp: extension flag clear but extension words is " + convert.int_to_string(words));
    }
    if h.extension_data.len() != 0 {
      return _err_bytes("rtp: extension flag clear but extension data is " + convert.int_to_string(h.extension_data.len()) + " bytes");
    }
  }
  var out = Vec[UInt8].new();
  var b0 = RTP_VERSION * 64 + cc;
  if h.padding { b0 = b0 + 32; }
  if h.extension { b0 = b0 + 16; }
  out.push(_be_byte(b0, 0));
  var b1 = pt;
  if h.marker { b1 = b1 + 128; }
  out.push(_be_byte(b1, 0));
  _push_be(&mut out, seq, 2);
  _push_be(&mut out, ts, 4);
  _push_be(&mut out, ssrc, 4);
  ci = 0;
  while ci < h.csrcs.len() {
    let x2: Int = h.csrcs[ci];
    _push_be(&mut out, x2, 4);
    ci = ci + 1;
  }
  if h.extension {
    _push_be(&mut out, profile, 2);
    _push_be(&mut out, words, 2);
    var ei = 0;
    while ei < h.extension_data.len() {
      let eb: UInt8 = h.extension_data[ei];
      out.push(eb);
      ei = ei + 1;
    }
  }
  return _ok_bytes(out);
}

/// Total header length in bytes of a parsed or built header
/// (12 + 4*csrc_count + 4 + 4*extension_words when the X bit is set).
/// Complexity: O(1).
pub fn rtp_header_bytes(h: &RtpHeader) -> Int {
  return h.header_bytes;
}

/// Declared extension payload length in bytes (`extension_words * 4`).
/// Complexity: O(1).
pub fn rtp_extension_bytes(h: &RtpHeader) -> Int {
  return h.extension_words * 4;
}

/// Number of CSRC identifiers in `h`. Complexity: O(1).
pub fn rtp_csrc_len(h: &RtpHeader) -> Int {
  return h.csrcs.len();
}

/// CSRC identifier `i` of `h` (0..2^32-1), or -1 when `i` is negative or out
/// of range. Complexity: O(1).
pub fn rtp_csrc(h: &RtpHeader, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= h.csrcs.len() { return -1; }
  let x: Int = h.csrcs[i];
  return x;
}

/// Payload length in bytes according to `h` and the packet `data`:
/// `data.len() - payload_offset`, clamped to zero. Padding bytes are counted;
/// use rtp_padding_len to separate them.
/// Complexity: O(1).
pub fn rtp_payload_len(data: &Vec[UInt8], h: &RtpHeader) -> Int {
  let off: Int = h.payload_offset;
  let n = data.len();
  if off >= n { return 0; }
  return n - off;
}

/// Length of the RTP padding trailer when the P bit is set: the last packet
/// byte gives the pad count, itself included, so it must be 1..payload_len.
///
/// Returns: Ok(0) when the P bit is clear; Ok(pad) otherwise.
/// Error cases: Err("rtp: padding set but packet has no payload") when P is
/// set and `data` ends at the header; Err("rtp: padding length N out of
/// range 1..M") when the last byte is 0; Err("rtp: padding length N exceeds
/// payload M") when it is larger than the payload it must fit in.
/// Complexity: O(1).
pub fn rtp_padding_len(data: &Vec[UInt8], h: &RtpHeader) -> Result[Int, Str] {
  if !h.padding {
    return _ok_int(0);
  }
  let off: Int = h.payload_offset;
  let n = data.len();
  let plen = n - off;
  if plen <= 0 {
    return _err_int("rtp: padding set but packet has no payload");
  }
  let last = _byte(data, n - 1);
  if last < 1 {
    return _err_int("rtp: padding length " + convert.int_to_string(last) + " out of range 1.." + convert.int_to_string(plen));
  }
  if last > plen {
    return _err_int("rtp: padding length " + convert.int_to_string(last) + " exceeds payload " + convert.int_to_string(plen));
  }
  return _ok_int(last);
}

// --------------------------------------------------
//  Wrap-safe sequence and timestamp arithmetic
// --------------------------------------------------

/// True when 16-bit sequence number `a` is before `b` under RFC 1982
/// serial-number arithmetic: `(b - a) mod 2^16` is nonzero and strictly
/// less than 2^15. The exact half-range case (distance 2^15) is ambiguous
/// and resolves to false in both directions.
/// Complexity: O(1).
pub fn rtp_seq_before(a: Int, b: Int) -> Bool {
  let d = _wrap16(b - a);
  if d == 0 { return false; }
  return d < RTP_SEQ_HALF;
}

/// Signed distance from 16-bit sequence `a` to `b`: `(b - a) mod 2^16`
/// folded into -32768..32767 (distances above the half range come back
/// negative). The half-range value itself maps to -32768.
/// Complexity: O(1).
pub fn rtp_seq_diff(a: Int, b: Int) -> Int {
  let d = _wrap16(b - a);
  if d > 32767 { return d - RTP_SEQ_MOD; }
  return d;
}

/// Next 16-bit sequence number: (s + 1) mod 2^16. Complexity: O(1).
pub fn rtp_seq_next(s: Int) -> Int {
  return _wrap16(s + 1);
}

/// True when 32-bit timestamp `a` is before `b` under RFC 1982
/// serial-number arithmetic: `(b - a) mod 2^32` is nonzero and strictly
/// less than 2^31. The exact half-range case resolves to false in both
/// directions.
/// Complexity: O(1).
pub fn rtp_ts_before(a: Int, b: Int) -> Bool {
  let d = _wrap32(b - a);
  if d == 0 { return false; }
  return d < RTP_TS_HALF;
}

/// Signed distance from 32-bit timestamp `a` to `b`: `(b - a) mod 2^32`
/// folded into -2^31..2^31-1. The half-range value itself maps to -2^31.
/// Complexity: O(1).
pub fn rtp_ts_diff(a: Int, b: Int) -> Int {
  let d = _wrap32(b - a);
  if d > 2147483647 { return d - RTP_TS_MOD; }
  return d;
}

/// Advance a 32-bit timestamp by `delta` ticks: (ts + delta) mod 2^32.
/// `delta` may be negative. To advance by N milliseconds at a 90 kHz clock,
/// call rtp_ts_add(ts, N * 90).
/// Complexity: O(1).
pub fn rtp_ts_add(ts: Int, delta: Int) -> Int {
  return _wrap32(ts + delta);
}

/// Retreat a 32-bit timestamp by `delta` ticks: (ts - delta) mod 2^32.
/// `delta` may be negative.
/// Complexity: O(1).
pub fn rtp_ts_sub(ts: Int, delta: Int) -> Int {
  return _wrap32(ts - delta);
}

// --------------------------------------------------
//  Interarrival jitter (RFC 3550 A.8)
// --------------------------------------------------

/// Fresh jitter state: estimate 0, no previous sample.
/// Complexity: O(1).
pub fn rtp_jitter_init() -> RtpJitter {
  return RtpJitter{ value: 0; has_prev: false; prev_arrival: 0; prev_send: 0; updates: 0; };
}

/// Feed one sample to the RFC 3550 A.8 estimator and return the next state.
///
/// `arrival` is the 32-bit arrival timestamp in RTP ticks (same clock and
/// modulus as `send_ts`, the packet's RTP timestamp). The estimator is
///     D(i) = (R_i - R_{i-1}) - (S_i - S_{i-1}),
///     J(i) = J(i-1) + (|D(i)| - J(i-1)) / 16,
/// with every timestamp subtraction wrap-safe on 32 bits (rtp_ts_diff) and
/// the division truncating toward zero (the C semantics of the RFC
/// reference implementation). Units are RTP timestamp ticks; convert with
/// rtp_jitter_to_ms. The first call only records the baseline (value stays
/// 0, `updates` stays 0); every later call adds one update. `value` is
/// always >= 0.
/// Complexity: O(1).
pub fn rtp_jitter_update(st: &RtpJitter, arrival: Int, send_ts: Int) -> RtpJitter {
  var value: Int = st.value;
  var updates: Int = st.updates;
  if st.has_prev {
    let prev_arrival: Int = st.prev_arrival;
    let prev_send: Int = st.prev_send;
    let d = rtp_ts_diff(prev_arrival, arrival) - rtp_ts_diff(prev_send, send_ts);
    let ad = _abs(d);
    value = value + (ad - value) / 16;
    updates = updates + 1;
  }
  return RtpJitter{ value: value; has_prev: true; prev_arrival: arrival; prev_send: send_ts; updates: updates; };
}

/// Current jitter estimate in RTP timestamp ticks. Complexity: O(1).
pub fn rtp_jitter_value(st: &RtpJitter) -> Int {
  return st.value;
}

/// Convert a jitter estimate from RTP ticks to whole milliseconds:
/// `jitter * 1000 / clock_rate`, truncating toward zero. For the usual
/// 90 kHz video clock, jitter 181 ticks maps to 2 ms.
///
/// Error case: Err("rtp: clock rate N out of range 1..1000000000") when
/// clock_rate is outside 1..10^9.
/// Complexity: O(1).
pub fn rtp_jitter_to_ms(jitter: Int, clock_rate: Int) -> Result[Int, Str] {
  if clock_rate < 1 || clock_rate > 1000000000 {
    return _err_int("rtp: clock rate " + convert.int_to_string(clock_rate) + " out of range 1..1000000000");
  }
  return _ok_int((jitter * 1000) / clock_rate);
}

/// The raw transit-difference magnitudes |D(i)| of one arrival series:
/// for i in 1..n, `|rtp_ts_diff(arrivals[i-1], arrivals[i]) -
/// rtp_ts_diff(sends[i-1], sends[i])|`.
///
/// Returns: Ok(n - 1 deltas; Ok(empty) for fewer than two samples).
/// Error case: Err("rtp: arrivals N do not match sends M") when the two
/// series have different lengths.
/// Complexity: O(n).
pub fn rtp_jitter_deltas(arrivals: &Vec[Int], sends: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = arrivals.len();
  let m = sends.len();
  if n != m {
    return _err_ints("rtp: arrivals " + convert.int_to_string(n) + " do not match sends " + convert.int_to_string(m));
  }
  var out = Vec[Int].new();
  if n < 2 {
    return _ok_ints(out);
  }
  var i = 1;
  while i < n {
    let a0: Int = arrivals[i - 1];
    let a1: Int = arrivals[i];
    let s0: Int = sends[i - 1];
    let s1: Int = sends[i];
    let d = rtp_ts_diff(a0, a1) - rtp_ts_diff(s0, s1);
    out.push(_abs(d));
    i = i + 1;
  }
  return _ok_ints(out);
}

/// Arithmetic mean (truncated) of the last `window` deltas in `deltas`: the
/// literal sliding-window view of the same transit deltas the EWMA consumes.
/// The window is clamped to the series length; an empty series yields 0.
///
/// Returns: Ok(mean delta in RTP ticks).
/// Error case: Err("rtp: jitter window N is not positive") when window < 1.
/// Complexity: O(min(window, deltas.len())).
pub fn rtp_jitter_mean(deltas: &Vec[Int], window: Int) -> Result[Int, Str] {
  if window < 1 {
    return _err_int("rtp: jitter window " + convert.int_to_string(window) + " is not positive");
  }
  let n = deltas.len();
  if n == 0 {
    return _ok_int(0);
  }
  var k = window;
  if k > n { k = n; }
  var sum: Int = 0;
  var i = n - k;
  while i < n {
    let x: Int = deltas[i];
    sum = sum + x;
    i = i + 1;
  }
  return _ok_int(sum / k);
}

// --------------------------------------------------
//  RTCP common header and report blocks
// --------------------------------------------------

/// Parse the RTCP common header at the start of `data`:
/// V (2 bits, must be 2), P (1 bit), count (5 bits), PT (8 bits), and the
/// 16-bit length field in 32-bit words minus one (`total_bytes` =
/// (length_words + 1) * 4).
///
/// Returns: Ok(header).
/// Error cases: Err("rtcp: packet needs 4 bytes, have N") when data.len() < 4;
/// Err("rtcp: version N is not 2") when the V field is not 2.
/// Complexity: O(1).
pub fn rtcp_parse_header(data: &Vec[UInt8]) -> Result[RtcpHeader, Str] {
  if data.len() < RTCP_HEADER_BYTES {
    return _err_rtcp_hdr("rtcp: packet needs 4 bytes, have " + convert.int_to_string(data.len()));
  }
  let b0 = _byte(data, 0);
  let version = b0 / 64;
  if version != RTCP_VERSION {
    return _err_rtcp_hdr("rtcp: version " + convert.int_to_string(version) + " is not 2");
  }
  let rest = b0 % 64;
  let padding = rest / 32 == 1;
  let count = b0 % 32;
  let length_words = _read_be(data, 2, 2);
  let h = RtcpHeader{
    version: version;
    padding: padding;
    count: count;
    packet_type: _byte(data, 1);
    length_words: length_words;
    total_bytes: (length_words + 1) * 4;
  };
  return _ok_rtcp_hdr(h);
}

// Parse `count` 24-byte report blocks starting at `pos` into parallel Vecs.
// The caller has validated the packet bounds. `receiver_ssrc` is stored as
// the reports' sender SSRC.
fn _parse_blocks(data: &Vec[UInt8], pos: Int, count: Int, receiver_ssrc: Int) -> Result[RtcpReports, Str] {
  var ssrcs = Vec[Int].new();
  var fraction_lost = Vec[Int].new();
  var cumulative_lost = Vec[Int].new();
  var highest_seq = Vec[Int].new();
  var jitter = Vec[Int].new();
  var lsr = Vec[Int].new();
  var dlsr = Vec[Int].new();
  var i = 0;
  while i < count {
    let p = pos + i * RTCP_REPORT_BLOCK_BYTES;
    ssrcs.push(_read_be(data, p, 4));
    fraction_lost.push(_byte(data, p + 4));
    var cum = _read_be(data, p + 5, 3);
    if cum >= 8388608 {
      cum = cum - 16777216;
    }
    cumulative_lost.push(cum);
    highest_seq.push(_read_be(data, p + 8, 4));
    jitter.push(_read_be(data, p + 12, 4));
    lsr.push(_read_be(data, p + 16, 4));
    dlsr.push(_read_be(data, p + 20, 4));
    i = i + 1;
  }
  return _ok_reports(RtcpReports{
    receiver_ssrc: receiver_ssrc;
    ssrcs: ssrcs;
    fraction_lost: fraction_lost;
    cumulative_lost: cumulative_lost;
    highest_seq: highest_seq;
    jitter: jitter;
    lsr: lsr;
    dlsr: dlsr;
  });
}

// Shared RTCP packet-bound checks for RR and SR. Returns "" when the header
// and declared packet length agree with `data`, else the error message.
fn _packet_bounds_error(data: &Vec[UInt8], h: &RtcpHeader, min_bytes: Int, want_pt: Int) -> Str {
  let pt: Int = h.packet_type;
  if pt != want_pt {
    return "rtcp: packet type " + convert.int_to_string(pt) + " is not " + convert.int_to_string(want_pt);
  }
  let n = data.len();
  if n < min_bytes {
    return "rtcp: packet needs " + convert.int_to_string(min_bytes) + " bytes, have " + convert.int_to_string(n);
  }
  let total: Int = h.total_bytes;
  if n < total {
    return "rtcp: packet length says " + convert.int_to_string(total) + " bytes, have " + convert.int_to_string(n);
  }
  let count: Int = h.count;
  let need = min_bytes + count * RTCP_REPORT_BLOCK_BYTES;
  if need > total {
    return "rtcp: " + convert.int_to_string(count) + " report blocks need " + convert.int_to_string(need) + " bytes, packet has " + convert.int_to_string(total);
  }
  return "";
}

/// Parse the first RTCP receiver report (PT 201) in `data` into its report
/// blocks. The packet must carry the receiver SSRC (8 bytes) before the
/// blocks; the declared length field bounds the packet, and any trailing
/// bytes (e.g. a compound packet) are ignored.
///
/// Error cases, in validation order: the rtcp_parse_header errors;
/// Err("rtcp: packet type N is not 201");
/// Err("rtcp: packet needs 8 bytes, have N");
/// Err("rtcp: packet length says T bytes, have N");
/// Err("rtcp: C report blocks need B bytes, packet has T") when the count
/// field does not fit the declared packet.
/// Complexity: O(report blocks).
pub fn rtcp_parse_rr(data: &Vec[UInt8]) -> Result[RtcpReports, Str] {
  let hr = rtcp_parse_header(data);
  if !hr.is_ok {
    return _err_reports(hr.error);
  }
  let h: RtcpHeader = hr.value;
  let msg = _packet_bounds_error(data, &h, RTCP_RR_HEADER_BYTES, RTCP_PT_RR);
  if msg.len() != 0 {
    return _err_reports(msg);
  }
  let rssrc = _read_be(data, 4, 4);
  return _parse_blocks(data, RTCP_RR_HEADER_BYTES, h.count, rssrc);
}

/// Parse the first RTCP sender report (PT 200) in `data`: the 20-byte
/// sender info (NTP timestamp halves, RTP timestamp, packet and octet
/// counts) followed by the report blocks, with `reports.receiver_ssrc` set
/// to the sender SSRC.
///
/// Error cases, in validation order: the rtcp_parse_header errors;
/// Err("rtcp: packet type N is not 200");
/// Err("rtcp: packet needs 28 bytes, have N");
/// Err("rtcp: packet length says T bytes, have N");
/// Err("rtcp: C report blocks need B bytes, packet has T").
/// Complexity: O(report blocks).
pub fn rtcp_parse_sr(data: &Vec[UInt8]) -> Result[RtcpSr, Str] {
  let hr = rtcp_parse_header(data);
  if !hr.is_ok {
    return _err_sr(hr.error);
  }
  let h: RtcpHeader = hr.value;
  let msg = _packet_bounds_error(data, &h, RTCP_SR_HEADER_BYTES, RTCP_PT_SR);
  if msg.len() != 0 {
    return _err_sr(msg);
  }
  let ssrc = _read_be(data, 4, 4);
  let reports = _parse_blocks(data, RTCP_SR_HEADER_BYTES, h.count, ssrc);
  if !reports.is_ok {
    return _err_sr(reports.error);
  }
  let rb: RtcpReports = reports.value;
  let s = RtcpSr{
    sender_ssrc: ssrc;
    ntp_msw: _read_be(data, 8, 4);
    ntp_lsw: _read_be(data, 12, 4);
    rtp_timestamp: _read_be(data, 16, 4);
    packet_count: _read_be(data, 20, 4);
    octet_count: _read_be(data, 24, 4);
    reports: rb;
  };
  return _ok_sr(s);
}

// Validate a RtcpReports value for building. Returns "" when valid, else the
// first error message (fixed order: receiver SSRC, block count, field
// lengths, then per-block fields).
fn _reports_error(r: &RtcpReports) -> Str {
  let rssrc: Int = r.receiver_ssrc;
  if !_u32_ok(rssrc) {
    return "rtcp: receiver ssrc " + convert.int_to_string(rssrc) + " out of range 0..4294967295";
  }
  let n: Int = r.ssrcs.len();
  if n > RTCP_MAX_BLOCKS {
    return "rtcp: block count " + convert.int_to_string(n) + " out of range 0..31";
  }
  let fl: Int = r.fraction_lost.len();
  if fl != n {
    return "rtcp: block field count " + convert.int_to_string(fl) + " does not match " + convert.int_to_string(n);
  }
  let cl: Int = r.cumulative_lost.len();
  if cl != n {
    return "rtcp: block field count " + convert.int_to_string(cl) + " does not match " + convert.int_to_string(n);
  }
  let hs: Int = r.highest_seq.len();
  if hs != n {
    return "rtcp: block field count " + convert.int_to_string(hs) + " does not match " + convert.int_to_string(n);
  }
  let jl: Int = r.jitter.len();
  if jl != n {
    return "rtcp: block field count " + convert.int_to_string(jl) + " does not match " + convert.int_to_string(n);
  }
  let ll: Int = r.lsr.len();
  if ll != n {
    return "rtcp: block field count " + convert.int_to_string(ll) + " does not match " + convert.int_to_string(n);
  }
  let dl: Int = r.dlsr.len();
  if dl != n {
    return "rtcp: block field count " + convert.int_to_string(dl) + " does not match " + convert.int_to_string(n);
  }
  var i = 0;
  while i < n {
    let s: Int = r.ssrcs[i];
    if !_u32_ok(s) {
      return "rtcp: ssrc " + convert.int_to_string(s) + " out of range 0..4294967295";
    }
    let f: Int = r.fraction_lost[i];
    if f < 0 || f > RTCP_FRACTION_MAX {
      return "rtcp: fraction lost " + convert.int_to_string(f) + " out of range 0..255";
    }
    let c: Int = r.cumulative_lost[i];
    if !_i24_ok(c) {
      return "rtcp: cumulative lost " + convert.int_to_string(c) + " out of range -8388608..8388607";
    }
    let h2: Int = r.highest_seq[i];
    if !_u32_ok(h2) {
      return "rtcp: highest sequence " + convert.int_to_string(h2) + " out of range 0..4294967295";
    }
    let j: Int = r.jitter[i];
    if !_u32_ok(j) {
      return "rtcp: jitter " + convert.int_to_string(j) + " out of range 0..4294967295";
    }
    let l: Int = r.lsr[i];
    if !_u32_ok(l) {
      return "rtcp: lsr " + convert.int_to_string(l) + " out of range 0..4294967295";
    }
    let d: Int = r.dlsr[i];
    if !_u32_ok(d) {
      return "rtcp: dlsr " + convert.int_to_string(d) + " out of range 0..4294967295";
    }
    i = i + 1;
  }
  return "";
}

// Append `count` report blocks from a validated RtcpReports to `out`.
fn _push_blocks(out: &mut Vec[UInt8], r: &RtcpReports, count: Int) {
  var i = 0;
  while i < count {
    let s: Int = r.ssrcs[i];
    _push_be(out, s, 4);
    let f: Int = r.fraction_lost[i];
    _push_be(out, f, 1);
    let c: Int = r.cumulative_lost[i];
    _push_be(out, c, 3);
    let h: Int = r.highest_seq[i];
    _push_be(out, h, 4);
    let j: Int = r.jitter[i];
    _push_be(out, j, 4);
    let l: Int = r.lsr[i];
    _push_be(out, l, 4);
    let d: Int = r.dlsr[i];
    _push_be(out, d, 4);
    i = i + 1;
  }
}

/// Build a complete RTCP receiver report (PT 201) from `r`: header (V=2,
/// P=0, count = block count, length in 32-bit words minus one), the receiver
/// SSRC, then the report blocks in order. The packet is
/// 8 + 24 * block_count bytes.
///
/// Returns: Ok(packet bytes).
/// Error cases: the _reports_error catalog, e.g.
/// Err("rtcp: receiver ssrc N out of range 0..4294967295"),
/// Err("rtcp: block count N out of range 0..31"),
/// Err("rtcp: block field count L does not match N"),
/// Err("rtcp: fraction lost N out of range 0..255"),
/// Err("rtcp: cumulative lost N out of range -8388608..8388607").
/// Complexity: O(report blocks).
pub fn rtcp_build_rr(r: &RtcpReports) -> Result[Vec[UInt8], Str] {
  let msg = _reports_error(r);
  if msg.len() != 0 {
    return _err_bytes(msg);
  }
  let n: Int = r.ssrcs.len();
  let total = RTCP_RR_HEADER_BYTES + n * RTCP_REPORT_BLOCK_BYTES;
  let words = total / 4;
  var out = Vec[UInt8].new();
  out.push(_be_byte(RTCP_VERSION * 64 + n, 0));
  out.push(_be_byte(RTCP_PT_RR, 0));
  _push_be(&mut out, words - 1, 2);
  let rssrc: Int = r.receiver_ssrc;
  _push_be(&mut out, rssrc, 4);
  _push_blocks(&mut out, r, n);
  return _ok_bytes(out);
}

/// Build a complete RTCP sender report (PT 200) from `s`: header, the sender
/// SSRC, the 20-byte sender info, then the report blocks
/// (28 + 24 * block_count bytes).
///
/// Returns: Ok(packet bytes).
/// Error cases: sender-field range errors first, then the _reports_error
/// catalog: Err("rtcp: sender ssrc N out of range 0..4294967295"),
/// Err("rtcp: ntp msw N out of range 0..4294967295"),
/// Err("rtcp: ntp lsw N out of range 0..4294967295"),
/// Err("rtcp: rtp timestamp N out of range 0..4294967295"),
/// Err("rtcp: packet count N out of range 0..4294967295"),
/// Err("rtcp: octet count N out of range 0..4294967295"), then the
/// report-block messages.
/// Complexity: O(report blocks).
pub fn rtcp_build_sr(s: &RtcpSr) -> Result[Vec[UInt8], Str] {
  let ssrc: Int = s.sender_ssrc;
  if !_u32_ok(ssrc) {
    return _err_bytes("rtcp: sender ssrc " + convert.int_to_string(ssrc) + " out of range 0..4294967295");
  }
  let msw: Int = s.ntp_msw;
  if !_u32_ok(msw) {
    return _err_bytes("rtcp: ntp msw " + convert.int_to_string(msw) + " out of range 0..4294967295");
  }
  let lsw: Int = s.ntp_lsw;
  if !_u32_ok(lsw) {
    return _err_bytes("rtcp: ntp lsw " + convert.int_to_string(lsw) + " out of range 0..4294967295");
  }
  let rts: Int = s.rtp_timestamp;
  if !_u32_ok(rts) {
    return _err_bytes("rtcp: rtp timestamp " + convert.int_to_string(rts) + " out of range 0..4294967295");
  }
  let pc: Int = s.packet_count;
  if !_u32_ok(pc) {
    return _err_bytes("rtcp: packet count " + convert.int_to_string(pc) + " out of range 0..4294967295");
  }
  let oc: Int = s.octet_count;
  if !_u32_ok(oc) {
    return _err_bytes("rtcp: octet count " + convert.int_to_string(oc) + " out of range 0..4294967295");
  }
  let msg = _reports_error(&s.reports);
  if msg.len() != 0 {
    return _err_bytes(msg);
  }
  let n: Int = s.reports.ssrcs.len();
  let total = RTCP_SR_HEADER_BYTES + n * RTCP_REPORT_BLOCK_BYTES;
  let words = total / 4;
  var out = Vec[UInt8].new();
  out.push(_be_byte(RTCP_VERSION * 64 + n, 0));
  out.push(_be_byte(RTCP_PT_SR, 0));
  _push_be(&mut out, words - 1, 2);
  _push_be(&mut out, ssrc, 4);
  _push_be(&mut out, msw, 4);
  _push_be(&mut out, lsw, 4);
  _push_be(&mut out, rts, 4);
  _push_be(&mut out, pc, 4);
  _push_be(&mut out, oc, 4);
  _push_blocks(&mut out, &s.reports, n);
  return _ok_bytes(out);
}

/// Number of report blocks in `r`. Complexity: O(1).
pub fn rtcp_block_count(r: &RtcpReports) -> Int {
  return r.ssrcs.len();
}

/// SSRC of report block `i`, or -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn rtcp_block_ssrc(r: &RtcpReports, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.ssrcs.len() { return -1; }
  let x: Int = r.ssrcs[i];
  return x;
}

/// Raw 8-bit fraction-lost field of report block `i` (0..255; the actual
/// fraction is the value / 256), or -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn rtcp_block_fraction_lost(r: &RtcpReports, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.fraction_lost.len() { return -1; }
  let x: Int = r.fraction_lost[i];
  return x;
}

/// Signed 24-bit cumulative packets lost of report block `i`
/// (-8388608..8388607), or 0 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn rtcp_block_cumulative_lost(r: &RtcpReports, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= r.cumulative_lost.len() { return 0; }
  let x: Int = r.cumulative_lost[i];
  return x;
}

/// Extended highest sequence number received of report block `i`, or -1 when
/// `i` is negative or out of range. Complexity: O(1).
pub fn rtcp_block_highest_seq(r: &RtcpReports, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.highest_seq.len() { return -1; }
  let x: Int = r.highest_seq[i];
  return x;
}

/// Interarrival jitter of report block `i` in RTP ticks, or -1 when `i` is
/// negative or out of range. Complexity: O(1).
pub fn rtcp_block_jitter(r: &RtcpReports, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.jitter.len() { return -1; }
  let x: Int = r.jitter[i];
  return x;
}

/// Last-SR timestamp (LSR) of report block `i`, or -1 when `i` is negative
/// or out of range. Complexity: O(1).
pub fn rtcp_block_lsr(r: &RtcpReports, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.lsr.len() { return -1; }
  let x: Int = r.lsr[i];
  return x;
}

/// Delay since last SR (DLSR) of report block `i`, or -1 when `i` is
/// negative or out of range. Complexity: O(1).
pub fn rtcp_block_dlsr(r: &RtcpReports, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.dlsr.len() { return -1; }
  let x: Int = r.dlsr[i];
  return x;
}

// --------------------------------------------------
//  RTSP text messages
// --------------------------------------------------

// ASCII byte constants used by the RTSP scanners.
const _TAB: Int = 9;
const _LF: Int = 10;
const _CR: Int = 13;
const _SPACE: Int = 32;
const _COLON: Int = 58;
const _ZERO: Int = 48;
const _NINE: Int = 57;

// True when `s` is empty (Str equality goes through length, never `==`).
fn _is_blank(s: Str) -> Bool {
  return s.len() == 0;
}

// Byte `pos` of `s` as an Int (0..255); callers bound it.
fn _str_byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Split `text` into lines on LF; a CR before the LF is dropped. A trailing
// LF does not produce a final empty line.
fn _split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var start = 0;
  var i = 0;
  while i < len {
    if _str_byte(text, i) == _LF {
      var end = i;
      if end > start && _str_byte(text, end - 1) == _CR { end = end - 1; }
      out.push(string.str_slice(text, start, end));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < len {
    var end = len;
    if end > start && _str_byte(text, end - 1) == _CR { end = end - 1; }
    out.push(string.str_slice(text, start, end));
  }
  return out;
}

// First blank line of `text`: the position of the first byte of the first
// line that is empty (CRLF-aware), or -1 when there is none.
fn _rtsp_blank_start(text: Str) -> Int {
  let n = text.len();
  var line_start = 0;
  var i = 0;
  while i < n {
    if _str_byte(text, i) == _LF {
      var content_end = i;
      if content_end > line_start && _str_byte(text, content_end - 1) == _CR { content_end = content_end - 1; }
      if content_end == line_start { return line_start; }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return -1;
}

// Index just past the LF that terminates the blank line starting at `bs`
// (the start of the body); text.len() when there is no LF (defensive).
fn _body_start(text: Str, bs: Int) -> Int {
  var i = bs;
  while i < text.len() {
    if _str_byte(text, i) == _LF { return i + 1; }
    i = i + 1;
  }
  return text.len();
}

// Index of the first space at or after `from`, or -1.
fn _find_space(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    if _str_byte(s, i) == _SPACE { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of the first colon at or after `from`, or -1.
fn _find_colon(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    if _str_byte(s, i) == _COLON { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `s` contains a space or tab.
fn _has_ws(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let c = _str_byte(s, i);
    if c == _SPACE || c == _TAB { return true; }
    i = i + 1;
  }
  return false;
}

// True when `s` contains a space.
fn _has_space(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _str_byte(s, i) == _SPACE { return true; }
    i = i + 1;
  }
  return false;
}

// True when `s` contains a colon.
fn _has_colon(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _str_byte(s, i) == _COLON { return true; }
    i = i + 1;
  }
  return false;
}

// True when `s` contains a CR or LF.
fn _has_crlf(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let c = _str_byte(s, i);
    if c == _CR || c == _LF { return true; }
    i = i + 1;
  }
  return false;
}

// Value of three ASCII digits at `pos`, or -1 unless the string is exactly
// three digits long and all of them are decimal.
fn _three_digits(s: Str, pos: Int) -> Int {
  if s.len() != 3 { return -1; }
  let a = _str_byte(s, pos);
  let b = _str_byte(s, pos + 1);
  let c = _str_byte(s, pos + 2);
  if a < _ZERO || a > _NINE { return -1; }
  if b < _ZERO || b > _NINE { return -1; }
  if c < _ZERO || c > _NINE { return -1; }
  return (a - _ZERO) * 100 + (b - _ZERO) * 10 + (c - _ZERO);
}

// True when `v` has the shape "RTSP/" + at least one digit (lenient about
// the digits after the first one; "RTSP/1.0" and "RTSP/2.0" both pass).
fn _is_rtsp_version(v: Str) -> Bool {
  if v.len() < 6 { return false; }
  if _str_byte(v, 0) != 82 { return false; }
  if _str_byte(v, 1) != 84 { return false; }
  if _str_byte(v, 2) != 83 { return false; }
  if _str_byte(v, 3) != 80 { return false; }
  if _str_byte(v, 4) != 47 { return false; }
  let c = _str_byte(v, 5);
  return c >= _ZERO && c <= _NINE;
}

// Lowercase one ASCII byte.
fn _ascii_lower(c: Int) -> Int {
  if c >= 65 && c <= 90 { return c + 32; }
  return c;
}

// Case-insensitive ASCII equality of two header names.
fn _name_eq(a: Str, b: Str) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x = _ascii_lower(_str_byte(a, i));
    let y = _ascii_lower(_str_byte(b, i));
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

// Trim [from, to) of spaces/tabs.
fn _trim_range(s: Str, from: Int, to: Int) -> Str {
  var a = from;
  var go = true;
  while a < to && go {
    let c = _str_byte(s, a);
    if c == _SPACE || c == _TAB { a = a + 1; } else { go = false; }
  }
  var b = to;
  var go2 = true;
  while b > a && go2 {
    let c = _str_byte(s, b - 1);
    if c == _SPACE || c == _TAB { b = b - 1; } else { go2 = false; }
  }
  if a > b { return ""; }
  return string.str_slice(s, a, b);
}

// Parse the header section of an RTSP message: rejects empty messages and
// messages without the blank line, and returns the header lines (the first
// line is the request or status line; later lines are headers).
fn _rtsp_parts(text: Str) -> Result[Vec[Str], Str] {
  if text.len() == 0 {
    return _err_vstr("rtsp: empty message");
  }
  let bs = _rtsp_blank_start(text);
  if bs < 0 {
    return _err_vstr("rtsp: missing blank line after headers");
  }
  let sec = string.str_slice(text, 0, bs);
  let lines = _split_lines(sec);
  if lines.len() == 0 {
    return _err_vstr("rtsp: empty message");
  }
  let first: Str = lines[0];
  if _is_blank(first) {
    return _err_vstr("rtsp: empty message");
  }
  return _ok_vstr(lines);
}

// Parse one header line and push name/value into the parallel vectors.
// Returns "" on success, else the exact error message.
fn _push_header(line: Str, names: &mut Vec[Str], values: &mut Vec[Str]) -> Str {
  let len = line.len();
  if len > 0 {
    let c0 = _str_byte(line, 0);
    if c0 == _SPACE || c0 == _TAB {
      return "rtsp: folded header not supported";
    }
  }
  let colon = _find_colon(line, 0);
  if colon < 1 {
    return "rtsp: bad header line";
  }
  let name = string.str_slice(line, 0, colon);
  if _has_ws(name) {
    return "rtsp: bad header name " + name;
  }
  let val = _trim_range(line, colon + 1, len);
  names.push(name);
  values.push(val);
  return "";
}

/// Parse one complete RTSP request (request line, headers, blank line; the
/// body is kept verbatim).
///
/// The request line is `Method SP URI SP RTSP-Version` with single-space
/// separators; the version must start with "RTSP/" followed by a digit.
/// Header lines are `Name: value` with no leading whitespace (obs-fold is
/// rejected); names are stored untrimmed and values trimmed of SP/TAB. Lines
/// may end with LF or CRLF.
///
/// Error cases: Err("rtsp: empty message"), Err("rtsp: missing blank line
/// after headers"), Err("rtsp: bad request line"), Err("rtsp: bad version
/// X"), Err("rtsp: folded header not supported"),
/// Err("rtsp: bad header line"), Err("rtsp: bad header name X").
/// Complexity: O(message length).
pub fn rtsp_parse_request(text: Str) -> Result[RtspRequest, Str] {
  let pr = _rtsp_parts(text);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let lines: Vec[Str] = pr.value;
  let first: Str = lines[0];
  let sp1 = _find_space(first, 0);
  if sp1 <= 0 {
    return _err_req("rtsp: bad request line");
  }
  let sp2 = _find_space(first, sp1 + 1);
  if sp2 < 0 {
    return _err_req("rtsp: bad request line");
  }
  if sp2 == sp1 + 1 {
    return _err_req("rtsp: bad request line");
  }
  let method = string.str_slice(first, 0, sp1);
  let uri = string.str_slice(first, sp1 + 1, sp2);
  let version = string.str_slice(first, sp2 + 1, first.len());
  if version.len() == 0 {
    return _err_req("rtsp: bad request line");
  }
  if _has_space(version) {
    return _err_req("rtsp: bad request line");
  }
  if !_is_rtsp_version(version) {
    return _err_req("rtsp: bad version " + version);
  }
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var i = 1;
  while i < lines.len() {
    let line: Str = lines[i];
    let hm = _push_header(line, &mut names, &mut values);
    if hm.len() != 0 {
      return _err_req(hm);
    }
    i = i + 1;
  }
  let bs = _rtsp_blank_start(text);
  let bstart = _body_start(text, bs);
  let body = string.str_slice(text, bstart, text.len());
  let req = RtspRequest{
    method: method;
    uri: uri;
    version: version;
    names: names;
    values: values;
    body: body;
  };
  return _ok_req(req);
}

/// Parse one complete RTSP response (status line, headers, blank line; the
/// body is kept verbatim).
///
/// The status line is `RTSP-Version SP Status-Code [SP Reason-Phrase]`; the
/// status code must be exactly three digits in 100..999 and the reason may
/// be absent or empty.
///
/// Error cases: the shared header-section errors, Err("rtsp: bad status
/// line"), Err("rtsp: bad version X"), Err("rtsp: bad status code X"),
/// Err("rtsp: status code N out of range 100..999"), and the header-line
/// errors of rtsp_parse_request.
/// Complexity: O(message length).
pub fn rtsp_parse_response(text: Str) -> Result[RtspResponse, Str] {
  let pr = _rtsp_parts(text);
  if !pr.is_ok {
    return _err_resp(pr.error);
  }
  let lines: Vec[Str] = pr.value;
  let first: Str = lines[0];
  let sp1 = _find_space(first, 0);
  if sp1 <= 0 {
    return _err_resp("rtsp: bad status line");
  }
  let version = string.str_slice(first, 0, sp1);
  if !_is_rtsp_version(version) {
    return _err_resp("rtsp: bad version " + version);
  }
  let sp2 = _find_space(first, sp1 + 1);
  var status_str = "";
  var reason = "";
  if sp2 < 0 {
    status_str = string.str_slice(first, sp1 + 1, first.len());
  } else {
    if sp2 == sp1 + 1 {
      return _err_resp("rtsp: bad status line");
    }
    status_str = string.str_slice(first, sp1 + 1, sp2);
    reason = string.str_slice(first, sp2 + 1, first.len());
  }
  let sc = _three_digits(status_str, 0);
  if sc < 0 {
    return _err_resp("rtsp: bad status code " + status_str);
  }
  if sc < 100 {
    return _err_resp("rtsp: status code " + convert.int_to_string(sc) + " out of range 100..999");
  }
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var i = 1;
  while i < lines.len() {
    let line: Str = lines[i];
    let hm = _push_header(line, &mut names, &mut values);
    if hm.len() != 0 {
      return _err_resp(hm);
    }
    i = i + 1;
  }
  let bs = _rtsp_blank_start(text);
  let bstart = _body_start(text, bs);
  let body = string.str_slice(text, bstart, text.len());
  let resp = RtspResponse{
    version: version;
    status: sc;
    reason: reason;
    names: names;
    values: values;
    body: body;
  };
  return _ok_resp(resp);
}

/// Build canonical RTSP request text: `METHOD URI VERSION\r\n`, one
/// `Name: value\r\n` line per header pair, a blank line, then the body
/// verbatim (so a parsed request round-trips, CRLF canonical form).
///
/// Returns: Ok(text).
/// Error cases: Err("rtsp: method is empty"), Err("rtsp: method contains
/// space"), Err("rtsp: uri is empty"), Err("rtsp: uri contains space"),
/// Err("rtsp: bad version X"), then the header errors
/// Err("rtsp: header count mismatch N vs M"), Err("rtsp: header name N is
/// empty"), Err("rtsp: header name N is invalid"),
/// Err("rtsp: header value N contains CR or LF").
/// Complexity: O(text length).
pub fn rtsp_build_request(r: &RtspRequest) -> Result[Str, Str] {
  let method: Str = r.method;
  if method.len() == 0 {
    return _err_str("rtsp: method is empty");
  }
  if _has_space(method) {
    return _err_str("rtsp: method contains space");
  }
  let uri: Str = r.uri;
  if uri.len() == 0 {
    return _err_str("rtsp: uri is empty");
  }
  if _has_space(uri) {
    return _err_str("rtsp: uri contains space");
  }
  let version: Str = r.version;
  if !_is_rtsp_version(version) {
    return _err_str("rtsp: bad version " + version);
  }
  let hn: Int = r.names.len();
  let vn: Int = r.values.len();
  if hn != vn {
    return _err_str("rtsp: header count mismatch " + convert.int_to_string(hn) + " vs " + convert.int_to_string(vn));
  }
  var i = 0;
  while i < hn {
    let name: Str = r.names[i];
    let val: Str = r.values[i];
    if name.len() == 0 {
      return _err_str("rtsp: header name " + convert.int_to_string(i) + " is empty");
    }
    if _has_ws(name) || _has_colon(name) || _has_crlf(name) {
      return _err_str("rtsp: header name " + convert.int_to_string(i) + " is invalid");
    }
    if _has_crlf(val) {
      return _err_str("rtsp: header value " + convert.int_to_string(i) + " contains CR or LF");
    }
    i = i + 1;
  }
  var out = method + " " + uri + " " + version + "\r\n";
  i = 0;
  while i < hn {
    let name2: Str = r.names[i];
    let val2: Str = r.values[i];
    out = out + name2 + ": " + val2 + "\r\n";
    i = i + 1;
  }
  out = out + "\r\n";
  out = out + r.body;
  return _ok_str(out);
}

/// Build canonical RTSP response text: `VERSION STATUS REASON\r\n` (the
/// reason phrase is omitted, along with its space, when empty), one
/// `Name: value\r\n` line per header pair, a blank line, then the body
/// verbatim.
///
/// Returns: Ok(text).
/// Error cases: Err("rtsp: bad version X"),
/// Err("rtsp: status code N out of range 100..999"),
/// Err("rtsp: reason contains CR or LF"), then the header errors of
/// rtsp_build_request.
/// Complexity: O(text length).
pub fn rtsp_build_response(r: &RtspResponse) -> Result[Str, Str] {
  let version: Str = r.version;
  if !_is_rtsp_version(version) {
    return _err_str("rtsp: bad version " + version);
  }
  let status: Int = r.status;
  if status < 100 || status > 999 {
    return _err_str("rtsp: status code " + convert.int_to_string(status) + " out of range 100..999");
  }
  let reason: Str = r.reason;
  if _has_crlf(reason) {
    return _err_str("rtsp: reason contains CR or LF");
  }
  let hn: Int = r.names.len();
  let vn: Int = r.values.len();
  if hn != vn {
    return _err_str("rtsp: header count mismatch " + convert.int_to_string(hn) + " vs " + convert.int_to_string(vn));
  }
  var i = 0;
  while i < hn {
    let name: Str = r.names[i];
    let val: Str = r.values[i];
    if name.len() == 0 {
      return _err_str("rtsp: header name " + convert.int_to_string(i) + " is empty");
    }
    if _has_ws(name) || _has_colon(name) || _has_crlf(name) {
      return _err_str("rtsp: header name " + convert.int_to_string(i) + " is invalid");
    }
    if _has_crlf(val) {
      return _err_str("rtsp: header value " + convert.int_to_string(i) + " contains CR or LF");
    }
    i = i + 1;
  }
  var out = version + " " + convert.int_to_string(status);
  if reason.len() != 0 {
    out = out + " " + reason;
  }
  out = out + "\r\n";
  i = 0;
  while i < hn {
    let name2: Str = r.names[i];
    let val2: Str = r.values[i];
    out = out + name2 + ": " + val2 + "\r\n";
    i = i + 1;
  }
  out = out + "\r\n";
  out = out + r.body;
  return _ok_str(out);
}

/// Number of header lines in a request. Complexity: O(1).
pub fn rtsp_request_header_count(r: &RtspRequest) -> Int {
  return r.names.len();
}

/// Header name `i` of a request ("" when `i` is negative or out of range).
/// Complexity: O(1).
pub fn rtsp_request_header_name(r: &RtspRequest, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= r.names.len() { return ""; }
  let x: Str = r.names[i];
  return x;
}

/// Header value `i` of a request ("" when `i` is negative or out of range).
/// Complexity: O(1).
pub fn rtsp_request_header_value(r: &RtspRequest, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= r.values.len() { return ""; }
  let x: Str = r.values[i];
  return x;
}

/// Value of the first request header whose name matches `name`
/// (case-insensitive ASCII), or "" when absent.
/// Complexity: O(headers * name length).
pub fn rtsp_request_header_get(r: &RtspRequest, name: Str) -> Str {
  let n = r.names.len();
  var i = 0;
  while i < n {
    let hn: Str = r.names[i];
    if _name_eq(hn, name) {
      let hv: Str = r.values[i];
      return hv;
    }
    i = i + 1;
  }
  return "";
}

/// Number of header lines in a response. Complexity: O(1).
pub fn rtsp_response_header_count(r: &RtspResponse) -> Int {
  return r.names.len();
}

/// Header name `i` of a response ("" when `i` is negative or out of range).
/// Complexity: O(1).
pub fn rtsp_response_header_name(r: &RtspResponse, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= r.names.len() { return ""; }
  let x: Str = r.names[i];
  return x;
}

/// Header value `i` of a response ("" when `i` is negative or out of range).
/// Complexity: O(1).
pub fn rtsp_response_header_value(r: &RtspResponse, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= r.values.len() { return ""; }
  let x: Str = r.values[i];
  return x;
}

/// Value of the first response header whose name matches `name`
/// (case-insensitive ASCII), or "" when absent.
/// Complexity: O(headers * name length).
pub fn rtsp_response_header_get(r: &RtspResponse, name: Str) -> Str {
  let n = r.names.len();
  var i = 0;
  while i < n {
    let hn: Str = r.names[i];
    if _name_eq(hn, name) {
      let hv: Str = r.values[i];
      return hv;
    }
    i = i + 1;
  }
  return "";
}
