// XIOM -- xiom.syslog: RFC 5424 syslog message codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a parsed message is a flat SyslogMsg. The NILVALUE header fields
// (TIMESTAMP, HOSTNAME, APP-NAME, PROCID, MSGID) use the empty string for
// "-" and the builder re-emits "-" for an empty field. MSG is stored after
// an optional UTF-8 BOM; the BOM itself is stripped and flagged by `bom`.
// Structured data is stored as parallel vectors -- `sd_ids` plus, per
// parameter, `sd_param_elem` (the owning element index), `sd_param_names`
// and `sd_param_values` -- because Vec[StructType] is unsupported in this
// compiler. Parameters keep wire order inside their element.
//
// Wire grammar (RFC 5424 section 6; SPEC.md states it exactly):
//   SYSLOG-MSG      = HEADER SP STRUCTURED-DATA [SP MSG]
//   HEADER          = PRI VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME
//                     SP PROCID SP MSGID
//   PRI             = "<" 1*3DIGIT ">"          ; value 0..191
//   VERSION         = NONZERO-DIGIT 0*2DIGIT
//   TIMESTAMP       = NILVALUE / FULL-DATE "T" FULL-TIME
//   STRUCTURED-DATA = NILVALUE / 1*SD-ELEMENT
//   SD-ELEMENT      = "[" SD-ID *(SP SD-PARAM) "]"
//   SD-PARAM        = PARAM-NAME "=" %d34 PARAM-VALUE %d34
//   MSG             = *OCTET, optionally prefixed with a UTF-8 BOM
//
// TIMESTAMP is validated (RFC 3339 shape, uppercase T/Z, 1..6 fraction
// digits, calendar-correct day of month) but kept as text: no arithmetic
// and no timezone conversion. PARAM-VALUE bytes are kept verbatim except
// that '"', '\' and ']' must be backslash-escaped on the wire; the parser
// rejects an unescaped ']' and any escape other than \", \\ and \].
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[StructType];
//   * byte-wise scanning with xiom.string.byte_at; widened byte values are
//     masked with `& 0xFF` before arithmetic and are never compared with a
//     UInt8 constant >= 128;
//   * output bytes are collected in a Vec[UInt8] and materialized once with
//     xiom.string.builder.sb_to_str;
//   * Ok/Err for every Result[...] are constructed only in the tiny leaf
//     helpers _ok_msg/_err_msg/_ok_str/_err_str;
//   * Str equality (the syslog_sd_param lookup) goes through
//     xiom.string.compare.str_compare, never `==` (BUG 17: `==` on a Str
//     read from a Vec[Str] element lowers to a pointer comparison).

module xiom.syslog

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _SYSLOG_SP: UInt8 = 32u8;
const _SYSLOG_PRINT_MIN: UInt8 = 33u8;
const _SYSLOG_DQUOTE: UInt8 = 34u8;
const _SYSLOG_PLUS: UInt8 = 43u8;
const _SYSLOG_DASH: UInt8 = 45u8;
const _SYSLOG_DOT: UInt8 = 46u8;
const _SYSLOG_ZERO: UInt8 = 48u8;
const _SYSLOG_NINE: UInt8 = 57u8;
const _SYSLOG_COLON: UInt8 = 58u8;
const _SYSLOG_LT: UInt8 = 60u8;
const _SYSLOG_EQ: UInt8 = 61u8;
const _SYSLOG_GT: UInt8 = 62u8;
const _SYSLOG_T: UInt8 = 84u8;
const _SYSLOG_Z: UInt8 = 90u8;
const _SYSLOG_LBRACKET: UInt8 = 91u8;
const _SYSLOG_BACKSLASH: UInt8 = 92u8;
const _SYSLOG_RBRACKET: UInt8 = 93u8;
const _SYSLOG_PRINT_MAX: UInt8 = 126u8;
const _SYSLOG_BOM0: UInt8 = 239u8;
const _SYSLOG_BOM1: UInt8 = 187u8;
const _SYSLOG_BOM2: UInt8 = 191u8;

// RFC 5424 section 6.1 header field limits (bytes).
const _SYSLOG_HOSTNAME_MAX: Int = 255;
const _SYSLOG_APP_NAME_MAX: Int = 48;
const _SYSLOG_PROCID_MAX: Int = 128;
const _SYSLOG_MSGID_MAX: Int = 32;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed RFC 5424 message. NILVALUE header fields are stored as "" (the
/// builder re-emits "-"); `msg` excludes a leading UTF-8 BOM, which is
/// flagged by `bom`; `has_msg` records whether the optional SP MSG part was
/// present. Structured data is flattened into parallel vectors: `sd_ids`
/// holds one SD-ID per element, and parameter `p` belongs to element
/// `sd_param_elem[p]` with name `sd_param_names[p]` and unescaped value
/// `sd_param_values[p]`. Vec[StructType] is unsupported, so the element
/// list is deliberately flat instead of a vector of element structs.
pub type SyslogMsg = {
  facility: Int;
  severity: Int;
  version: Int;
  timestamp: Str;
  hostname: Str;
  app_name: Str;
  procid: Str;
  msgid: Str;
  msg: Str;
  bom: Bool;
  has_msg: Bool;
  sd_ids: Vec[Str];
  sd_param_elem: Vec[Int];
  sd_param_names: Vec[Str];
  sd_param_values: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(m) for Result[SyslogMsg, Str].
fn _ok_msg(m: SyslogMsg) -> Result[SyslogMsg, Str] {
  return Ok(m);
}

// Err(m) for Result[SyslogMsg, Str].
fn _err_msg(m: Str) -> Result[SyslogMsg, Str] {
  return Err(m);
}

// Ok(s) for Result[Str, Str].
fn _ok_str(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for an ASCII decimal digit.
fn _is_digit(b: UInt8) -> Bool {
  return b >= _SYSLOG_ZERO && b <= _SYSLOG_NINE;
}

// True when every byte of `s` is PRINTUSASCII (%d33-126); true for "".
fn _print_ascii_ok(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b < _SYSLOG_PRINT_MIN || b > _SYSLOG_PRINT_MAX {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True for a valid SD-NAME: 1..32 PRINTUSASCII bytes, none of '=', SP, ']'
// or '"' (RFC 5424 section 6.3.3). "" is not a valid name.
fn _sd_name_ok(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 32 {
    return false;
  }
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b < _SYSLOG_PRINT_MIN || b > _SYSLOG_PRINT_MAX {
      return false;
    }
    if b == _SYSLOG_EQ || b == _SYSLOG_SP || b == _SYSLOG_RBRACKET || b == _SYSLOG_DQUOTE {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the first SP at or after `from`, or -1 when there is none.
fn _field_end(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    if string.byte_at(s, i) == _SYSLOG_SP {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Decimal value of s[start, end); -1 when the range is empty or holds a
// non-digit byte.
fn _digits_value(s: Str, start: Int, end: Int) -> Int {
  var acc = 0;
  var i = start;
  while i < end {
    let b = string.byte_at(s, i);
    if !_is_digit(b) {
      return -1;
    }
    acc = acc * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  return acc;
}

// True for a VERSION text: 1..3 digits with a nonzero first digit.
fn _version_ok(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 3 {
    return false;
  }
  if string.byte_at(s, 0) == _SYSLOG_ZERO {
    return false;
  }
  var i = 0;
  while i < n {
    if !_is_digit(string.byte_at(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Validate one non-timestamp header field. Returns "" when `value` is
// acceptable (NILVALUE "" or 1..max_len PRINTUSASCII bytes), otherwise the
// deterministic "syslog: ..." error. Length is checked before charset.
fn _check_header_field(name: Str, value: Str, max_len: Int) -> Str {
  if value.len() == 0 {
    return "";
  }
  if value.len() > max_len {
    return "syslog: " + name + " too long";
  }
  if !_print_ascii_ok(value) {
    return "syslog: bad " + name + ": " + value;
  }
  return "";
}

// True when a UTF-8 BOM (EF BB BF) starts at byte `at`.
fn _bom_at(s: Str, at: Int) -> Bool {
  if at + 3 > s.len() {
    return false;
  }
  let b0 = (string.byte_at(s, at) as Int) & 0xFF;
  let b1 = (string.byte_at(s, at + 1) as Int) & 0xFF;
  let b2 = (string.byte_at(s, at + 2) as Int) & 0xFF;
  return b0 == ((_SYSLOG_BOM0 as Int) & 0xFF) && b1 == ((_SYSLOG_BOM1 as Int) & 0xFF) && b2 == ((_SYSLOG_BOM2 as Int) & 0xFF);
}

// Decimal representation of an Int (build-time diagnostics only).
fn _int_to_str(v: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Timestamp helpers
// --------------------------------------------------

// Value of s[at], s[at+1] as two decimal digits; -1 when either byte is
// missing or not a digit.
fn _digits2(s: Str, at: Int) -> Int {
  if at < 0 || at + 2 > s.len() {
    return -1;
  }
  let b0 = string.byte_at(s, at);
  let b1 = string.byte_at(s, at + 1);
  if !_is_digit(b0) || !_is_digit(b1) {
    return -1;
  }
  return ((b0 as Int) - 48) * 10 + ((b1 as Int) - 48);
}

// Value of s[at..at+3] as four decimal digits; -1 when any byte is missing
// or not a digit.
fn _digits4(s: Str, at: Int) -> Int {
  if at < 0 || at + 4 > s.len() {
    return -1;
  }
  var acc = 0;
  var i = at;
  while i < at + 4 {
    let b = string.byte_at(s, i);
    if !_is_digit(b) {
      return -1;
    }
    acc = acc * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  return acc;
}

// Proleptic Gregorian leap year test.
fn _is_leap(year: Int) -> Bool {
  if year % 400 == 0 {
    return true;
  }
  if year % 100 == 0 {
    return false;
  }
  return year % 4 == 0;
}

// Calendar length of `month` (1..12) in `year`.
fn _days_in_month(year: Int, month: Int) -> Int {
  if month == 2 {
    if _is_leap(year) {
      return 29;
    }
    return 28;
  }
  if month == 4 || month == 6 || month == 9 || month == 11 {
    return 30;
  }
  return 31;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Validate an RFC 5424 TIMESTAMP string.
/// Params: s - the timestamp text alone (not the NILVALUE "-" and not "").
/// Grammar: `date-fullyear "-" date-month "-" date-mday "T" time-hour ":"
/// time-minute ":" time-second [ "." 1*6DIGIT ] time-offset` with
/// `time-offset = "Z" / ("+" / "-") time-hour ":" time-minute`. Uppercase
/// "T" and "Z" only. Month 01-12, day 01-(calendar length for the year,
/// including 29 February on leap years), hour 00-23, minute 00-59, second
/// 00-59, fraction 1-6 digits, offset hour 00-23 and offset minute 00-59.
/// "-00:00" (RFC 3339 "unknown offset") is accepted.
/// Returns: true for a conforming timestamp, false otherwise (including ""
/// and "-", which are not timestamps of this form).
/// Error case: none.
/// Complexity: O(len(s)).
pub fn syslog_timestamp_valid(s: Str) -> Bool {
  if s.len() < 20 {
    return false;
  }
  let year = _digits4(s, 0);
  if year < 0 {
    return false;
  }
  if string.byte_at(s, 4) != _SYSLOG_DASH {
    return false;
  }
  let month = _digits2(s, 5);
  if month < 1 || month > 12 {
    return false;
  }
  if string.byte_at(s, 7) != _SYSLOG_DASH {
    return false;
  }
  let day = _digits2(s, 8);
  if day < 1 || day > _days_in_month(year, month) {
    return false;
  }
  if string.byte_at(s, 10) != _SYSLOG_T {
    return false;
  }
  let hour = _digits2(s, 11);
  if hour < 0 || hour > 23 {
    return false;
  }
  if string.byte_at(s, 13) != _SYSLOG_COLON {
    return false;
  }
  let minute = _digits2(s, 14);
  if minute < 0 || minute > 59 {
    return false;
  }
  if string.byte_at(s, 16) != _SYSLOG_COLON {
    return false;
  }
  let second = _digits2(s, 17);
  if second < 0 || second > 59 {
    return false;
  }
  var i = 19;
  if i < s.len() && string.byte_at(s, i) == _SYSLOG_DOT {
    i = i + 1;
    var frac = 0;
    while i < s.len() && _is_digit(string.byte_at(s, i)) {
      frac = frac + 1;
      i = i + 1;
    }
    if frac < 1 || frac > 6 {
      return false;
    }
  }
  if i >= s.len() {
    return false;
  }
  let off = string.byte_at(s, i);
  if off == _SYSLOG_Z {
    return i + 1 == s.len();
  }
  if off == _SYSLOG_PLUS || off == _SYSLOG_DASH {
    let off_hour = _digits2(s, i + 1);
    if off_hour < 0 || off_hour > 23 {
      return false;
    }
    if i + 3 >= s.len() || string.byte_at(s, i + 3) != _SYSLOG_COLON {
      return false;
    }
    let off_minute = _digits2(s, i + 4);
    if off_minute < 0 || off_minute > 59 {
      return false;
    }
    return i + 6 == s.len();
  }
  return false;
}

/// Parse one RFC 5424 syslog message.
/// Params: text - the complete message; no transport framing is removed, so
/// a trailing LF/CRLF is MSG content when a MSG part is present and is
/// rejected as trailing junk otherwise.
/// Returns: Ok(SyslogMsg) for a well-formed message, otherwise Err with one
/// of the exact "syslog: ..." messages catalogued in SPEC.md (bad or
/// missing PRI, PRI out of range, bad version, missing field, bad
/// TIMESTAMP, bad/long header field, truncation, structured-data errors).
/// NILVALUE header fields and a NILVALUE structured-data section parse to
/// "" / zero elements; parameter escapes are decoded and a leading UTF-8
/// BOM is stripped and flagged (`bom`).
/// Complexity: O(len(text)).
pub fn syslog_parse(text: Str) -> Result[SyslogMsg, Str] {
  var m = SyslogMsg{
    facility: 0;
    severity: 0;
    version: 1;
    timestamp: "";
    hostname: "";
    app_name: "";
    procid: "";
    msgid: "";
    msg: "";
    bom: false;
    has_msg: false;
    sd_ids: Vec[Str].new();
    sd_param_elem: Vec[Int].new();
    sd_param_names: Vec[Str].new();
    sd_param_values: Vec[Str].new();
  };
  let n = text.len();
  // PRI
  if n == 0 {
    return _err_msg("syslog: missing PRI");
  }
  if string.byte_at(text, 0) != _SYSLOG_LT {
    return _err_msg("syslog: missing PRI");
  }
  var i = 1;
  var pri = 0;
  var pri_digits = 0;
  while i < n && pri_digits < 3 && _is_digit(string.byte_at(text, i)) {
    pri = pri * 10 + ((string.byte_at(text, i) as Int) - 48);
    pri_digits = pri_digits + 1;
    i = i + 1;
  }
  if pri_digits == 0 {
    return _err_msg("syslog: bad PRI");
  }
  if i < n && _is_digit(string.byte_at(text, i)) {
    return _err_msg("syslog: bad PRI");
  }
  if i >= n || string.byte_at(text, i) != _SYSLOG_GT {
    return _err_msg("syslog: bad PRI");
  }
  if pri > 191 {
    return _err_msg("syslog: PRI out of range: " + string.str_slice(text, 1, i));
  }
  m.facility = pri / 8;
  m.severity = pri % 8;
  i = i + 1;
  // VERSION
  let sp_ver = _field_end(text, i);
  var ver_end = n;
  if sp_ver >= 0 {
    ver_end = sp_ver;
  }
  let ver_text = string.str_slice(text, i, ver_end);
  if !_version_ok(ver_text) {
    return _err_msg("syslog: bad version: " + ver_text);
  }
  m.version = _digits_value(ver_text, 0, ver_text.len());
  if sp_ver < 0 {
    return _err_msg("syslog: missing field: TIMESTAMP");
  }
  i = sp_ver + 1;
  // TIMESTAMP
  let sp_ts = _field_end(text, i);
  if sp_ts < 0 {
    return _err_msg("syslog: missing field: TIMESTAMP");
  }
  let ts_text = string.str_slice(text, i, sp_ts);
  if ts_text.len() == 0 {
    return _err_msg("syslog: missing field: TIMESTAMP");
  }
  if ts_text.len() == 1 && string.byte_at(ts_text, 0) == _SYSLOG_DASH {
    m.timestamp = "";
  } else {
    if !syslog_timestamp_valid(ts_text) {
      return _err_msg("syslog: bad TIMESTAMP: " + ts_text);
    }
    m.timestamp = ts_text;
  }
  i = sp_ts + 1;
  // HOSTNAME
  let sp_hn = _field_end(text, i);
  if sp_hn < 0 {
    return _err_msg("syslog: missing field: HOSTNAME");
  }
  let hn_text = string.str_slice(text, i, sp_hn);
  if hn_text.len() == 0 {
    return _err_msg("syslog: missing field: HOSTNAME");
  }
  let hn_err = _check_header_field("HOSTNAME", hn_text, _SYSLOG_HOSTNAME_MAX);
  if hn_err.len() > 0 {
    return _err_msg(hn_err);
  }
  if hn_text.len() == 1 && string.byte_at(hn_text, 0) == _SYSLOG_DASH {
    m.hostname = "";
  } else {
    m.hostname = hn_text;
  }
  i = sp_hn + 1;
  // APP-NAME
  let sp_ap = _field_end(text, i);
  if sp_ap < 0 {
    return _err_msg("syslog: missing field: APP-NAME");
  }
  let ap_text = string.str_slice(text, i, sp_ap);
  if ap_text.len() == 0 {
    return _err_msg("syslog: missing field: APP-NAME");
  }
  let ap_err = _check_header_field("APP-NAME", ap_text, _SYSLOG_APP_NAME_MAX);
  if ap_err.len() > 0 {
    return _err_msg(ap_err);
  }
  if ap_text.len() == 1 && string.byte_at(ap_text, 0) == _SYSLOG_DASH {
    m.app_name = "";
  } else {
    m.app_name = ap_text;
  }
  i = sp_ap + 1;
  // PROCID
  let sp_pr = _field_end(text, i);
  if sp_pr < 0 {
    return _err_msg("syslog: missing field: PROCID");
  }
  let pr_text = string.str_slice(text, i, sp_pr);
  if pr_text.len() == 0 {
    return _err_msg("syslog: missing field: PROCID");
  }
  let pr_err = _check_header_field("PROCID", pr_text, _SYSLOG_PROCID_MAX);
  if pr_err.len() > 0 {
    return _err_msg(pr_err);
  }
  if pr_text.len() == 1 && string.byte_at(pr_text, 0) == _SYSLOG_DASH {
    m.procid = "";
  } else {
    m.procid = pr_text;
  }
  i = sp_pr + 1;
  // MSGID
  let sp_mid = _field_end(text, i);
  if sp_mid < 0 {
    return _err_msg("syslog: truncated message");
  }
  let mid_text = string.str_slice(text, i, sp_mid);
  if mid_text.len() == 0 {
    return _err_msg("syslog: missing field: MSGID");
  }
  let mid_err = _check_header_field("MSGID", mid_text, _SYSLOG_MSGID_MAX);
  if mid_err.len() > 0 {
    return _err_msg(mid_err);
  }
  if mid_text.len() == 1 && string.byte_at(mid_text, 0) == _SYSLOG_DASH {
    m.msgid = "";
  } else {
    m.msgid = mid_text;
  }
  i = sp_mid + 1;
  if i >= n {
    return _err_msg("syslog: truncated message");
  }
  // STRUCTURED-DATA
  let sd_first = string.byte_at(text, i);
  if sd_first == _SYSLOG_DASH {
    i = i + 1;
    if i < n && string.byte_at(text, i) != _SYSLOG_SP {
      return _err_msg("syslog: bad structured data");
    }
  } elif sd_first == _SYSLOG_LBRACKET {
    while i < n && string.byte_at(text, i) == _SYSLOG_LBRACKET {
      i = i + 1;
      // SD-ID
      let id_start = i;
      while i < n {
        let b = string.byte_at(text, i);
        if b == _SYSLOG_SP || b == _SYSLOG_RBRACKET {
          break;
        }
        i = i + 1;
      }
      let sd_id = string.str_slice(text, id_start, i);
      if !_sd_name_ok(sd_id) {
        return _err_msg("syslog: bad SD-ID: " + sd_id);
      }
      m.sd_ids.push(sd_id);
      let elem = m.sd_ids.len() - 1;
      // SD-PARAM*
      while i < n && string.byte_at(text, i) == _SYSLOG_SP {
        i = i + 1;
        let pn_start = i;
        while i < n && string.byte_at(text, i) != _SYSLOG_EQ {
          let pb = string.byte_at(text, i);
          if pb == _SYSLOG_SP || pb == _SYSLOG_RBRACKET {
            break;
          }
          i = i + 1;
        }
        let pn_text = string.str_slice(text, pn_start, i);
        if i >= n || string.byte_at(text, i) != _SYSLOG_EQ {
          return _err_msg("syslog: bad param name: " + pn_text);
        }
        if !_sd_name_ok(pn_text) {
          return _err_msg("syslog: bad param name: " + pn_text);
        }
        i = i + 1;
        if i >= n || string.byte_at(text, i) != _SYSLOG_DQUOTE {
          return _err_msg("syslog: bad param quote");
        }
        i = i + 1;
        var val = Vec[UInt8].new();
        var closed = false;
        while i < n {
          let vb = string.byte_at(text, i);
          if vb == _SYSLOG_BACKSLASH {
            if i + 1 >= n {
              return _err_msg("syslog: bad param escape");
            }
            let eb = string.byte_at(text, i + 1);
            if eb == _SYSLOG_DQUOTE || eb == _SYSLOG_BACKSLASH || eb == _SYSLOG_RBRACKET {
              val.push(eb);
              i = i + 2;
            } else {
              return _err_msg("syslog: bad param escape");
            }
          } elif vb == _SYSLOG_DQUOTE {
            closed = true;
            i = i + 1;
            break;
          } elif vb == _SYSLOG_RBRACKET {
            return _err_msg("syslog: bad param value");
          } else {
            val.push(vb);
            i = i + 1;
          }
        }
        if !closed {
          return _err_msg("syslog: bad param quote");
        }
        if i < n && string.byte_at(text, i) != _SYSLOG_SP && string.byte_at(text, i) != _SYSLOG_RBRACKET {
          return _err_msg("syslog: bad structured data");
        }
        m.sd_param_elem.push(elem);
        m.sd_param_names.push(pn_text);
        m.sd_param_values.push(builder.sb_to_str(&val));
      }
      if i >= n {
        return _err_msg("syslog: unterminated structured data");
      }
      if string.byte_at(text, i) != _SYSLOG_RBRACKET {
        return _err_msg("syslog: unterminated structured data");
      }
      i = i + 1;
    }
  } else {
    return _err_msg("syslog: bad structured data");
  }
  if i < n && string.byte_at(text, i) != _SYSLOG_SP {
    return _err_msg("syslog: bad structured data");
  }
  // MSG (optional)
  if i < n {
    i = i + 1;
    if _bom_at(text, i) {
      m.bom = true;
      i = i + 3;
    }
    m.has_msg = true;
    m.msg = string.str_slice(text, i, n);
  }
  return _ok_msg(m);
}

/// True when `text` parses as a well-formed RFC 5424 message.
/// Params: text - the message text.
/// Returns: true when syslog_parse would return Ok; false otherwise.
/// Error case: none.
/// Complexity: O(len(text)).
pub fn syslog_ok(text: Str) -> Bool {
  match syslog_parse(text) {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

/// PRI value of a parsed message: facility * 8 + severity (0..191).
pub fn syslog_pri(m: &SyslogMsg) -> Int {
  return m.facility * 8 + m.severity;
}

/// Facility code (0..23) of a parsed message.
pub fn syslog_facility(m: &SyslogMsg) -> Int {
  return m.facility;
}

/// Severity code (0..7) of a parsed message.
pub fn syslog_severity(m: &SyslogMsg) -> Int {
  return m.severity;
}

/// VERSION of a parsed message (1..999).
pub fn syslog_version(m: &SyslogMsg) -> Int {
  return m.version;
}

/// TIMESTAMP text of a parsed message; "" for the NILVALUE "-".
pub fn syslog_timestamp(m: &SyslogMsg) -> Str {
  return m.timestamp;
}

/// HOSTNAME of a parsed message; "" for the NILVALUE "-".
pub fn syslog_hostname(m: &SyslogMsg) -> Str {
  return m.hostname;
}

/// APP-NAME of a parsed message; "" for the NILVALUE "-".
pub fn syslog_app_name(m: &SyslogMsg) -> Str {
  return m.app_name;
}

/// PROCID of a parsed message; "" for the NILVALUE "-".
pub fn syslog_procid(m: &SyslogMsg) -> Str {
  return m.procid;
}

/// MSGID of a parsed message; "" for the NILVALUE "-".
pub fn syslog_msgid(m: &SyslogMsg) -> Str {
  return m.msgid;
}

/// MSG text of a parsed message, without a leading UTF-8 BOM; "" when the
/// message carried no MSG part or an empty one.
pub fn syslog_msg(m: &SyslogMsg) -> Str {
  return m.msg;
}

/// True when MSG began with a UTF-8 BOM (stripped from syslog_msg).
pub fn syslog_has_bom(m: &SyslogMsg) -> Bool {
  return m.bom;
}

/// True when the wire message carried the optional SP MSG part (even when
/// MSG is empty); false when it ended at the structured-data section.
pub fn syslog_has_msg(m: &SyslogMsg) -> Bool {
  return m.has_msg;
}

/// Number of structured-data elements (0 for the NILVALUE section).
pub fn syslog_sd_count(m: &SyslogMsg) -> Int {
  return m.sd_ids.len();
}

/// SD-ID of element `i`; "" when `i` is out of range.
pub fn syslog_sd_id(m: &SyslogMsg, i: Int) -> Str {
  if i < 0 || i >= m.sd_ids.len() {
    return "";
  }
  let v: Str = m.sd_ids[i];
  return v;
}

// Flat parameter slot of the `i`-th parameter of element `elem`, or -1.
fn _param_slot(m: &SyslogMsg, elem: Int, i: Int) -> Int {
  if elem < 0 || elem >= m.sd_ids.len() || i < 0 {
    return -1;
  }
  var seen = 0;
  var p = 0;
  while p < m.sd_param_elem.len() {
    let e: Int = m.sd_param_elem[p];
    if e == elem {
      if seen == i {
        return p;
      }
      seen = seen + 1;
    }
    p = p + 1;
  }
  return -1;
}

/// Number of parameters of structured-data element `elem`; 0 when `elem` is
/// out of range.
pub fn syslog_sd_param_count(m: &SyslogMsg, elem: Int) -> Int {
  if elem < 0 || elem >= m.sd_ids.len() {
    return 0;
  }
  var count = 0;
  var p = 0;
  while p < m.sd_param_elem.len() {
    let e: Int = m.sd_param_elem[p];
    if e == elem {
      count = count + 1;
    }
    p = p + 1;
  }
  return count;
}

/// Name of the `i`-th parameter (0-based) of element `elem`; "" when the
/// element or parameter index is out of range.
pub fn syslog_sd_param_name(m: &SyslogMsg, elem: Int, i: Int) -> Str {
  let at = _param_slot(m, elem, i);
  if at < 0 {
    return "";
  }
  let v: Str = m.sd_param_names[at];
  return v;
}

/// Unescaped value of the `i`-th parameter (0-based) of element `elem`;
/// "" when the element or parameter index is out of range.
pub fn syslog_sd_param_value(m: &SyslogMsg, elem: Int, i: Int) -> Str {
  let at = _param_slot(m, elem, i);
  if at < 0 {
    return "";
  }
  let v: Str = m.sd_param_values[at];
  return v;
}

/// First parameter named `name` of element `elem`; None when the element is
/// out of range or no parameter has that exact name (names are matched
/// byte-exactly and are case-sensitive per RFC 5424).
pub fn syslog_sd_param(m: &SyslogMsg, elem: Int, name: Str) -> Option[Str] {
  if elem < 0 || elem >= m.sd_ids.len() {
    return None;
  }
  var p = 0;
  while p < m.sd_param_elem.len() {
    let e: Int = m.sd_param_elem[p];
    if e == elem {
      let pn: Str = m.sd_param_names[p];
      if compare.str_compare(pn, name) == 0 {
        let pv: Str = m.sd_param_values[p];
        return Some(pv);
      }
    }
    p = p + 1;
  }
  return None;
}

// Append a header field: "" becomes the NILVALUE "-", anything else is
// copied verbatim (the caller validated charset and length).
fn _append_field(out: &mut Vec[UInt8], v: Str) {
  if v.len() == 0 {
    out.push(_SYSLOG_DASH);
    return;
  }
  builder.sb_push_str(out, v);
}

// Append a PARAM-VALUE: '"', '\' and ']' are backslash-escaped, every other
// byte is copied verbatim.
fn _append_escaped(out: &mut Vec[UInt8], v: Str) {
  var i = 0;
  while i < v.len() {
    let b = string.byte_at(v, i);
    if b == _SYSLOG_DQUOTE || b == _SYSLOG_BACKSLASH || b == _SYSLOG_RBRACKET {
      out.push(_SYSLOG_BACKSLASH);
    }
    out.push(b);
    i = i + 1;
  }
}

/// Build the RFC 5424 wire form of a message.
/// Params: m - the message; TIMESTAMP "" becomes NILVALUE, header fields ""
/// become NILVALUE, an empty structured-data list becomes NILVALUE, and
/// parameter values are escaped ("\"", "\\", "\]").
/// Returns: Ok(text) with the canonical wire form. The optional SP MSG part
/// is emitted when `has_msg` is true, or when `msg` is non-empty, or when
/// `bom` is true (the BOM is then re-emitted before `msg`).
/// Error case: Err("syslog: ...") when the struct cannot be encoded --
/// facility outside 0..23, severity outside 0..7, version outside 1..999, a
/// non-empty invalid TIMESTAMP, an over-long or non-printable header field,
/// an invalid SD-ID or param name, or inconsistent parallel vectors.
/// Complexity: O(field bytes).
pub fn syslog_build(m: &SyslogMsg) -> Result[Str, Str] {
  if m.facility < 0 || m.facility > 23 {
    return _err_str("syslog: facility out of range");
  }
  if m.severity < 0 || m.severity > 7 {
    return _err_str("syslog: severity out of range");
  }
  if m.version < 1 || m.version > 999 {
    return _err_str("syslog: bad version: " + _int_to_str(m.version));
  }
  if m.timestamp.len() > 0 && !syslog_timestamp_valid(m.timestamp) {
    return _err_str("syslog: bad TIMESTAMP: " + m.timestamp);
  }
  let e_hn = _check_header_field("HOSTNAME", m.hostname, _SYSLOG_HOSTNAME_MAX);
  if e_hn.len() > 0 {
    return _err_str(e_hn);
  }
  let e_ap = _check_header_field("APP-NAME", m.app_name, _SYSLOG_APP_NAME_MAX);
  if e_ap.len() > 0 {
    return _err_str(e_ap);
  }
  let e_pr = _check_header_field("PROCID", m.procid, _SYSLOG_PROCID_MAX);
  if e_pr.len() > 0 {
    return _err_str(e_pr);
  }
  let e_mid = _check_header_field("MSGID", m.msgid, _SYSLOG_MSGID_MAX);
  if e_mid.len() > 0 {
    return _err_str(e_mid);
  }
  if m.sd_param_names.len() != m.sd_param_values.len() {
    return _err_str("syslog: bad structured data: inconsistent layout");
  }
  var d = 0;
  while d < m.sd_ids.len() {
    let id: Str = m.sd_ids[d];
    if !_sd_name_ok(id) {
      return _err_str("syslog: bad SD-ID: " + id);
    }
    d = d + 1;
  }
  var q = 0;
  while q < m.sd_param_names.len() {
    let pn: Str = m.sd_param_names[q];
    if !_sd_name_ok(pn) {
      return _err_str("syslog: bad param name: " + pn);
    }
    let e: Int = m.sd_param_elem[q];
    if e < 0 || e >= m.sd_ids.len() {
      return _err_str("syslog: bad structured data: inconsistent layout");
    }
    q = q + 1;
  }
  var out = Vec[UInt8].new();
  out.push(_SYSLOG_LT);
  builder.sb_push_int(&mut out, m.facility * 8 + m.severity);
  out.push(_SYSLOG_GT);
  builder.sb_push_int(&mut out, m.version);
  out.push(_SYSLOG_SP);
  _append_field(&mut out, m.timestamp);
  out.push(_SYSLOG_SP);
  _append_field(&mut out, m.hostname);
  out.push(_SYSLOG_SP);
  _append_field(&mut out, m.app_name);
  out.push(_SYSLOG_SP);
  _append_field(&mut out, m.procid);
  out.push(_SYSLOG_SP);
  _append_field(&mut out, m.msgid);
  out.push(_SYSLOG_SP);
  if m.sd_ids.len() == 0 {
    out.push(_SYSLOG_DASH);
  } else {
    var d2 = 0;
    while d2 < m.sd_ids.len() {
      out.push(_SYSLOG_LBRACKET);
      let id2: Str = m.sd_ids[d2];
      builder.sb_push_str(&mut out, id2);
      var q2 = 0;
      while q2 < m.sd_param_names.len() {
        let e2: Int = m.sd_param_elem[q2];
        if e2 == d2 {
          out.push(_SYSLOG_SP);
          let pn2: Str = m.sd_param_names[q2];
          builder.sb_push_str(&mut out, pn2);
          out.push(_SYSLOG_EQ);
          out.push(_SYSLOG_DQUOTE);
          let pv2: Str = m.sd_param_values[q2];
          _append_escaped(&mut out, pv2);
          out.push(_SYSLOG_DQUOTE);
        }
        q2 = q2 + 1;
      }
      out.push(_SYSLOG_RBRACKET);
      d2 = d2 + 1;
    }
  }
  if m.has_msg || m.msg.len() > 0 || m.bom {
    out.push(_SYSLOG_SP);
    if m.bom {
      out.push(_SYSLOG_BOM0);
      out.push(_SYSLOG_BOM1);
      out.push(_SYSLOG_BOM2);
    }
    builder.sb_push_str(&mut out, m.msg);
  }
  return _ok_str(builder.sb_to_str(&out));
}
