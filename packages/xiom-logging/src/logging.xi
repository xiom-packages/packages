// XIOM -- xiom.logging: syslog message structure codecs (RFC 3164 + RFC 5424)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement xiom.logging as a real, tested, pure-XIOM syslog
// message STRUCTURE decoder. Scope: the PRI field, the RFC 3164 BSD message
// format and the RFC 5424 message format, plus PRI/facility/severity tables,
// auto-detection between the two formats and field accessors. Non-goals: no
// transports (no sockets, files, journald, rotation), no message building or
// rendering, no timezone conversion, no UTF-8 validation (see SPEC.md).
//
// Model: a parsed message is a flat value. RFC 3164 yields Log3164 (month
// table plus a fixed 15-byte "Mmm dd hh:mm:ss" timestamp with no year, a
// hostname, an alphanumeric TAG of at most 32 bytes with an optional [pid],
// a content tail, and byte offsets plus the number of bytes consumed by the
// message walk). RFC 5424 yields Log5424 (version, RFC 3339 timestamp parsed
// into LogTimestamp fields, NILVALUE header fields stored as "", structured
// data as parallel vectors, MSG with an optional UTF-8 BOM stripped and
// flagged). Vec[StructType] is unsupported in this compiler, so structured
// data is stored as parallel vectors: `sd_ids` holds one SD-ID per element,
// and parameter `p` belongs to element `sd_param_elem[p]` with name
// `sd_param_names[p]`, unescaped value `sd_param_values[p]` and the byte
// span of its raw (still escaped) wire value in `sd_param_val_at[p]` /
// `sd_param_val_len[p]` -- byte-exact spans into the original text.
//
// Wire grammar (SPEC.md states both grammars exactly):
//   RFC 3164:  PRI TIMESTAMP SP HOSTNAME SP TAG [ "[" pid "]" ] ":" [ SP ] CONTENT
//   RFC 5424:  PRI VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME SP PROCID
//              SP MSGID SP STRUCTURED-DATA [ SP MSG ]
//   PRI:       "<" 1*3DIGIT ">"                  ; value 0..191
//   TIMESTAMP (3164): "Mmm dd hh:mm:ss"          ; exactly 15 bytes, no year
//   TIMESTAMP (5424): NILVALUE / FULL-DATE "T" FULL-TIME [ frac ] offset
//   SD-ELEMENT: "[" SD-ID *(SP PARAM-NAME "=" DQUOTE PARAM-VALUE DQUOTE) "]"
//
// Every error is the deterministic string "logging: <reason> at <byte
// offset>" (offsets are relative to the input text, or to the timestamp text
// for log5424_timestamp_parse). Errors never carry hidden state.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[StructType];
//   * byte-wise scanning with xiom.string.byte_at; widened byte values are
//     masked with `& 0xFF` before arithmetic and are never compared with a
//     UInt8 constant >= 128 unless both sides are masked;
//   * output bytes are collected in a Vec[UInt8] and materialized once with
//     xiom.string.builder.sb_to_str;
//   * Str equality never uses `==` on a value read from a Vec[Str] (BUG 17
//     lowers that to a pointer comparison); every table lookup goes through
//     xiom.string.compare.str_compare and every Vec element read is bound
//     with a typed `let`;
//   * Ok/Err for every Result[...] are constructed only in the tiny leaf
//     helpers below (constructing a Result inside a larger function
//     miscompiles); the parsers return Err through those helpers.

module xiom.logging

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _LOG_LF: UInt8 = 10u8;
const _LOG_CR: UInt8 = 13u8;
const _LOG_SP: UInt8 = 32u8;
const _LOG_PRINT_MIN: UInt8 = 33u8;
const _LOG_DQUOTE: UInt8 = 34u8;
const _LOG_PLUS: UInt8 = 43u8;
const _LOG_DASH: UInt8 = 45u8;
const _LOG_DOT: UInt8 = 46u8;
const _LOG_ZERO: UInt8 = 48u8;
const _LOG_NINE: UInt8 = 57u8;
const _LOG_COLON: UInt8 = 58u8;
const _LOG_LT: UInt8 = 60u8;
const _LOG_EQ: UInt8 = 61u8;
const _LOG_GT: UInt8 = 62u8;
const _LOG_UPPER_A: UInt8 = 65u8;
const _LOG_UPPER_Z: UInt8 = 90u8;
const _LOG_T: UInt8 = 84u8;
const _LOG_Z: UInt8 = 90u8;
const _LOG_LBRACKET: UInt8 = 91u8;
const _LOG_BACKSLASH: UInt8 = 92u8;
const _LOG_RBRACKET: UInt8 = 93u8;
const _LOG_LOWER_A: UInt8 = 97u8;
const _LOG_LOWER_Z: UInt8 = 122u8;
const _LOG_PRINT_MAX: UInt8 = 126u8;
const _LOG_BOM0: UInt8 = 239u8;
const _LOG_BOM1: UInt8 = 187u8;
const _LOG_BOM2: UInt8 = 191u8;

// RFC 5424 section 6.1 header field limits (bytes); the 3164 hostname and
// TAG limits come from the task grammar (255 / 32).
const _LOG_HOSTNAME_MAX: Int = 255;
const _LOG_APP_NAME_MAX: Int = 48;
const _LOG_PROCID_MAX: Int = 128;
const _LOG_MSGID_MAX: Int = 32;
const _LOG_TAG_MAX: Int = 32;
const _LOG_PID_MAX: Int = 10;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// Parsed RFC 3339 timestamp fields (the RFC 5424 TIMESTAMP). `frac` holds
/// the fractional-second digits without the leading dot ("" when absent);
/// `offset_min` is the signed UTC offset in minutes (0 for "Z" and for
/// "-00:00"); `present` is false for the NILVALUE "-" (every other field is
/// then 0 / "").
pub type LogTimestamp = {
  year: Int;
  month: Int;
  day: Int;
  hour: Int;
  minute: Int;
  second: Int;
  frac: Str;
  offset_min: Int;
  present: Bool;
}

/// One parsed RFC 3164 (BSD syslog) message. `timestamp` is the raw 15-byte
/// "Mmm dd hh:mm:ss" text (there is no year on the wire); `tag` excludes the
/// optional "[pid]" part; `consumed` is the byte length of the message up to
/// the first CR/LF (so a caller can walk a buffer); `ts_at`, `host_at`,
/// `tag_at` and `content_at` are byte offsets of the field starts in the
/// input. `has_content` distinguishes "TAG:" (no content) from "TAG:" plus
/// bytes.
pub type Log3164 = {
  facility: Int;
  severity: Int;
  month: Int;
  day: Int;
  hour: Int;
  minute: Int;
  second: Int;
  timestamp: Str;
  hostname: Str;
  tag: Str;
  pid: Str;
  has_pid: Bool;
  content: Str;
  has_content: Bool;
  consumed: Int;
  ts_at: Int;
  host_at: Int;
  tag_at: Int;
  content_at: Int;
}

/// One parsed RFC 5424 message. NILVALUE header fields are stored as ""
/// (DATAGRAM: `timestamp` is the raw text, "" for NILVALUE); `msg` excludes
/// a leading UTF-8 BOM, which is flagged by `bom`; `has_msg` records whether
/// the optional SP MSG part was present. Structured data is flattened into
/// parallel vectors: `sd_ids` holds one SD-ID per element, and parameter `p`
/// belongs to element `sd_param_elem[p]` with name `sd_param_names[p]`,
/// unescaped value `sd_param_values[p]` and raw wire value span
/// `sd_param_val_at[p]` / `sd_param_val_len[p]` (byte offsets into the
/// original input).
pub type Log5424 = {
  facility: Int;
  severity: Int;
  version: Int;
  timestamp: Str;
  ts_present: Bool;
  ts_year: Int;
  ts_month: Int;
  ts_day: Int;
  ts_hour: Int;
  ts_minute: Int;
  ts_second: Int;
  ts_frac: Str;
  ts_offset_min: Int;
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
  sd_param_val_at: Vec[Int];
  sd_param_val_len: Vec[Int];
}

// Private scan results (plain values so the parsers never construct a
// Result outside the leaf helpers below).

// One scanned header field: `text` ("" for NILVALUE), the offset after the
// field text (`next`), whether a separating SP terminated it (`sep`) and the
// deterministic reason/offset when it is malformed.
type _Scan = {
  text: Str;
  next: Int;
  sep: Bool;
  err: Str;
  pos: Int;
}

// One scanned PRI field: `value` 0..191 and `next` (the byte after '>').
type _PriScan = {
  value: Int;
  next: Int;
  err: Str;
  pos: Int;
}

// One scanned RFC 3339 timestamp: the parsed fields, an ok flag and the
// failure offset (relative to the scan base) when ok is false.
type _TsScan = {
  ts: LogTimestamp;
  ok: Bool;
  err_pos: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[LogTimestamp, Str].
fn _ok_ts(v: LogTimestamp) -> Result[LogTimestamp, Str] {
  return Ok(v);
}

// Err(m) for Result[LogTimestamp, Str].
fn _err_ts(m: Str) -> Result[LogTimestamp, Str] {
  return Err(m);
}

// Ok(v) for Result[Log3164, Str].
fn _ok_3164(v: Log3164) -> Result[Log3164, Str] {
  return Ok(v);
}

// Err(m) for Result[Log3164, Str].
fn _err_3164(m: Str) -> Result[Log3164, Str] {
  return Err(m);
}

// Ok(v) for Result[Log5424, Str].
fn _ok_5424(v: Log5424) -> Result[Log5424, Str] {
  return Ok(v);
}

// Err(m) for Result[Log5424, Str].
fn _err_5424(m: Str) -> Result[Log5424, Str] {
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
//  Byte helpers
// --------------------------------------------------

// Decimal text of an Int (diagnostics and "local0".."local7" names only).
fn _int_to_str(v: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

// "logging: <reason> at <pos>"; the deterministic shape of every error.
fn _err_at(reason: Str, pos: Int) -> Str {
  return "logging: " + reason + " at " + _int_to_str(pos);
}

// ASCII decimal digit.
fn _is_digit(b: UInt8) -> Bool {
  return b >= _LOG_ZERO && b <= _LOG_NINE;
}

// ASCII letter (A-Z or a-z).
fn _is_alpha(b: UInt8) -> Bool {
  if b >= _LOG_UPPER_A && b <= _LOG_UPPER_Z {
    return true;
  }
  return b >= _LOG_LOWER_A && b <= _LOG_LOWER_Z;
}

// ASCII letter or digit.
fn _is_alnum(b: UInt8) -> Bool {
  if _is_alpha(b) {
    return true;
  }
  return _is_digit(b);
}

// Line break byte (CR or LF).
fn _is_eol(b: UInt8) -> Bool {
  return b == _LOG_CR || b == _LOG_LF;
}

// Index of the first CR or LF in `s`, or len(s) when there is none. RFC 3164
// messages are line-oriented, so the walk stops here.
fn _line_end(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    if _is_eol(string.byte_at(s, i)) {
      return i;
    }
    i = i + 1;
  }
  return s.len();
}

// Index of the first `target` byte at or after `from`, or -1.
fn _find_byte(s: Str, from: Int, target: UInt8) -> Int {
  var i = from;
  while i < s.len() {
    if string.byte_at(s, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first SP at or after `from`, or -1.
fn _find_sp(s: Str, from: Int) -> Int {
  return _find_byte(s, from, _LOG_SP);
}

// True when every byte of `s` is PRINTUSASCII (%d33-126); true for "".
fn _print_ascii_ok(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b < _LOG_PRINT_MIN || b > _LOG_PRINT_MAX {
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
    if b < _LOG_PRINT_MIN || b > _LOG_PRINT_MAX {
      return false;
    }
    if b == _LOG_EQ || b == _LOG_SP || b == _LOG_RBRACKET || b == _LOG_DQUOTE {
      return false;
    }
    i = i + 1;
  }
  return true;
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

// True when a UTF-8 BOM (EF BB BF) starts at byte `at`.
fn _bom_at(s: Str, at: Int) -> Bool {
  if at + 3 > s.len() {
    return false;
  }
  let b0 = (string.byte_at(s, at) as Int) & 0xFF;
  let b1 = (string.byte_at(s, at + 1) as Int) & 0xFF;
  let b2 = (string.byte_at(s, at + 2) as Int) & 0xFF;
  return b0 == ((_LOG_BOM0 as Int) & 0xFF) && b1 == ((_LOG_BOM1 as Int) & 0xFF) && b2 == ((_LOG_BOM2 as Int) & 0xFF);
}

// Month number (1..12) for a canonical RFC 3164 month name, or 0. Names are
// matched case-sensitively against the table Jan..Dec.
fn _month_from_name(s: Str) -> Int {
  if s.len() != 3 {
    return 0;
  }
  if compare.str_compare(s, "Jan") == 0 {
    return 1;
  }
  if compare.str_compare(s, "Feb") == 0 {
    return 2;
  }
  if compare.str_compare(s, "Mar") == 0 {
    return 3;
  }
  if compare.str_compare(s, "Apr") == 0 {
    return 4;
  }
  if compare.str_compare(s, "May") == 0 {
    return 5;
  }
  if compare.str_compare(s, "Jun") == 0 {
    return 6;
  }
  if compare.str_compare(s, "Jul") == 0 {
    return 7;
  }
  if compare.str_compare(s, "Aug") == 0 {
    return 8;
  }
  if compare.str_compare(s, "Sep") == 0 {
    return 9;
  }
  if compare.str_compare(s, "Oct") == 0 {
    return 10;
  }
  if compare.str_compare(s, "Nov") == 0 {
    return 11;
  }
  if compare.str_compare(s, "Dec") == 0 {
    return 12;
  }
  return 0;
}

// True for a VERSION text: 1..3 digits with a nonzero first digit (1..999).
fn _version_ok(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 3 {
    return false;
  }
  if string.byte_at(s, 0) == _LOG_ZERO {
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

// --------------------------------------------------
//  Field scanners
// --------------------------------------------------

// Scan the PRI field "<NNN>" at the start of `text`.
fn _scan_pri(text: Str) -> _PriScan {
  let n = text.len();
  var r = _PriScan{ value: 0; next: 0; err: ""; pos: 0 };
  if n == 0 {
    r.err = "missing PRI";
    return r;
  }
  if string.byte_at(text, 0) != _LOG_LT {
    r.err = "missing PRI";
    return r;
  }
  var i = 1;
  var pri = 0;
  var digits = 0;
  while i < n && digits < 3 && _is_digit(string.byte_at(text, i)) {
    pri = pri * 10 + ((string.byte_at(text, i) as Int) - 48);
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 {
    r.err = "bad PRI";
    r.pos = 1;
    return r;
  }
  if i < n && _is_digit(string.byte_at(text, i)) {
    r.err = "bad PRI";
    r.pos = i;
    return r;
  }
  if i >= n || string.byte_at(text, i) != _LOG_GT {
    r.err = "bad PRI";
    r.pos = i;
    return r;
  }
  if pri > 191 {
    r.err = "PRI out of range";
    r.pos = 1;
    return r;
  }
  r.value = pri;
  r.next = i + 1;
  return r;
}

// Scan one SP-terminated RFC 5424 header field starting at `from`. NILVALUE
// "-" scans to text ""; `sep` records whether a separating SP was found;
// content errors (empty, too long, non-printable) fill `err`/`pos`.
fn _scan_field(text: Str, from: Int, name: Str, max_len: Int) -> _Scan {
  let n = text.len();
  var r = _Scan{ text: ""; next: n; sep: false; err: ""; pos: from };
  if from >= n {
    r.err = "missing " + name;
    r.pos = from;
    return r;
  }
  let sp = _find_sp(text, from);
  var end = n;
  if sp >= 0 {
    end = sp;
    r.sep = true;
    r.next = sp;
  }
  let t = string.str_slice(text, from, end);
  if t.len() == 0 {
    r.err = "missing " + name;
    r.pos = from;
    return r;
  }
  if !(t.len() == 1 && string.byte_at(t, 0) == _LOG_DASH) {
    if t.len() > max_len {
      r.err = name + " too long";
      r.pos = from;
      return r;
    }
    if !_print_ascii_ok(t) {
      r.err = "bad " + name;
      r.pos = from;
      return r;
    }
    r.text = t;
  }
  return r;
}

// Scan one RFC 3339 timestamp at the start of `s`; reported failure offsets
// are `base` + the offending byte index.
fn _ts_scan(s: Str, base: Int) -> _TsScan {
  var ts = LogTimestamp{ year: 0; month: 0; day: 0; hour: 0; minute: 0; second: 0; frac: ""; offset_min: 0; present: true };
  var r = _TsScan{ ts: ts; ok: false; err_pos: base };
  let n = s.len();
  if n < 20 {
    r.err_pos = base + n;
    return r;
  }
  let year = _digits4(s, 0);
  if year < 0 {
    r.err_pos = base;
    return r;
  }
  if string.byte_at(s, 4) != _LOG_DASH {
    r.err_pos = base + 4;
    return r;
  }
  let month = _digits2(s, 5);
  if month < 1 || month > 12 {
    r.err_pos = base + 5;
    return r;
  }
  if string.byte_at(s, 7) != _LOG_DASH {
    r.err_pos = base + 7;
    return r;
  }
  let day = _digits2(s, 8);
  if day < 1 || day > _days_in_month(year, month) {
    r.err_pos = base + 8;
    return r;
  }
  if string.byte_at(s, 10) != _LOG_T {
    r.err_pos = base + 10;
    return r;
  }
  let hour = _digits2(s, 11);
  if hour < 0 || hour > 23 {
    r.err_pos = base + 11;
    return r;
  }
  if string.byte_at(s, 13) != _LOG_COLON {
    r.err_pos = base + 13;
    return r;
  }
  let minute = _digits2(s, 14);
  if minute < 0 || minute > 59 {
    r.err_pos = base + 14;
    return r;
  }
  if string.byte_at(s, 16) != _LOG_COLON {
    r.err_pos = base + 16;
    return r;
  }
  let second = _digits2(s, 17);
  if second < 0 || second > 59 {
    r.err_pos = base + 17;
    return r;
  }
  var i = 19;
  var frac = "";
  if i < n && string.byte_at(s, i) == _LOG_DOT {
    i = i + 1;
    let frac_at = i;
    var count = 0;
    while i < n && _is_digit(string.byte_at(s, i)) {
      count = count + 1;
      i = i + 1;
    }
    if count < 1 || count > 6 {
      r.err_pos = base + frac_at;
      return r;
    }
    frac = string.str_slice(s, frac_at, i);
  }
  if i >= n {
    r.err_pos = base + i;
    return r;
  }
  let off = string.byte_at(s, i);
  var off_min = 0;
  if off == _LOG_Z {
    if i + 1 != n {
      r.err_pos = base + i + 1;
      return r;
    }
  } elif off == _LOG_PLUS || off == _LOG_DASH {
    let off_hour = _digits2(s, i + 1);
    if off_hour < 0 || off_hour > 23 {
      r.err_pos = base + i + 1;
      return r;
    }
    if i + 3 >= n || string.byte_at(s, i + 3) != _LOG_COLON {
      r.err_pos = base + i + 3;
      return r;
    }
    let off_minute = _digits2(s, i + 4);
    if off_minute < 0 || off_minute > 59 {
      r.err_pos = base + i + 4;
      return r;
    }
    if i + 6 != n {
      r.err_pos = base + i + 6;
      return r;
    }
    off_min = off_hour * 60 + off_minute;
    if off == _LOG_DASH {
      off_min = 0 - off_min;
    }
  } else {
    r.err_pos = base + i;
    return r;
  }
  ts.year = year;
  ts.month = month;
  ts.day = day;
  ts.hour = hour;
  ts.minute = minute;
  ts.second = second;
  ts.frac = frac;
  ts.offset_min = off_min;
  ts.present = true;
  r.ts = ts;
  r.ok = true;
  return r;
}

// --------------------------------------------------
//  PRI, facility and severity tables
// --------------------------------------------------

/// Facility name for code 0..23 (kern, user, mail, daemon, auth, syslog,
/// lpr, news, uucp, cron, authpriv, ftp, ntp, audit, alert, clock,
/// local0..local7); "" when `facility` is outside 0..23.
pub fn log_facility_name(facility: Int) -> Str {
  if facility == 0 {
    return "kern";
  }
  if facility == 1 {
    return "user";
  }
  if facility == 2 {
    return "mail";
  }
  if facility == 3 {
    return "daemon";
  }
  if facility == 4 {
    return "auth";
  }
  if facility == 5 {
    return "syslog";
  }
  if facility == 6 {
    return "lpr";
  }
  if facility == 7 {
    return "news";
  }
  if facility == 8 {
    return "uucp";
  }
  if facility == 9 {
    return "cron";
  }
  if facility == 10 {
    return "authpriv";
  }
  if facility == 11 {
    return "ftp";
  }
  if facility == 12 {
    return "ntp";
  }
  if facility == 13 {
    return "audit";
  }
  if facility == 14 {
    return "alert";
  }
  if facility == 15 {
    return "clock";
  }
  if facility >= 16 && facility <= 23 {
    return "local" + _int_to_str(facility - 16);
  }
  return "";
}

/// Severity name for code 0..7 (emerg, alert, crit, err, warning, notice,
/// info, debug); "" when `severity` is outside 0..7.
pub fn log_severity_name(severity: Int) -> Str {
  if severity == 0 {
    return "emerg";
  }
  if severity == 1 {
    return "alert";
  }
  if severity == 2 {
    return "crit";
  }
  if severity == 3 {
    return "err";
  }
  if severity == 4 {
    return "warning";
  }
  if severity == 5 {
    return "notice";
  }
  if severity == 6 {
    return "info";
  }
  if severity == 7 {
    return "debug";
  }
  return "";
}

/// Facility code for a name from the table of `log_facility_name`.
/// Params: name - matched byte-exactly and case-sensitively ("kern", ...,
/// "local0".."local7"); the empty string is not a name.
/// Returns: Ok(code) with code in 0..23, or
/// Err("logging: unknown facility: <name>").
/// Complexity: O(1) (a fixed 24-way comparison chain).
pub fn log_facility_code(name: Str) -> Result[Int, Str] {
  if compare.str_compare(name, "kern") == 0 {
    return _ok_int(0);
  }
  if compare.str_compare(name, "user") == 0 {
    return _ok_int(1);
  }
  if compare.str_compare(name, "mail") == 0 {
    return _ok_int(2);
  }
  if compare.str_compare(name, "daemon") == 0 {
    return _ok_int(3);
  }
  if compare.str_compare(name, "auth") == 0 {
    return _ok_int(4);
  }
  if compare.str_compare(name, "syslog") == 0 {
    return _ok_int(5);
  }
  if compare.str_compare(name, "lpr") == 0 {
    return _ok_int(6);
  }
  if compare.str_compare(name, "news") == 0 {
    return _ok_int(7);
  }
  if compare.str_compare(name, "uucp") == 0 {
    return _ok_int(8);
  }
  if compare.str_compare(name, "cron") == 0 {
    return _ok_int(9);
  }
  if compare.str_compare(name, "authpriv") == 0 {
    return _ok_int(10);
  }
  if compare.str_compare(name, "ftp") == 0 {
    return _ok_int(11);
  }
  if compare.str_compare(name, "ntp") == 0 {
    return _ok_int(12);
  }
  if compare.str_compare(name, "audit") == 0 {
    return _ok_int(13);
  }
  if compare.str_compare(name, "alert") == 0 {
    return _ok_int(14);
  }
  if compare.str_compare(name, "clock") == 0 {
    return _ok_int(15);
  }
  if compare.str_compare(name, "local0") == 0 {
    return _ok_int(16);
  }
  if compare.str_compare(name, "local1") == 0 {
    return _ok_int(17);
  }
  if compare.str_compare(name, "local2") == 0 {
    return _ok_int(18);
  }
  if compare.str_compare(name, "local3") == 0 {
    return _ok_int(19);
  }
  if compare.str_compare(name, "local4") == 0 {
    return _ok_int(20);
  }
  if compare.str_compare(name, "local5") == 0 {
    return _ok_int(21);
  }
  if compare.str_compare(name, "local6") == 0 {
    return _ok_int(22);
  }
  if compare.str_compare(name, "local7") == 0 {
    return _ok_int(23);
  }
  return _err_int("logging: unknown facility: " + name);
}

/// Severity code for a name from the table of `log_severity_name`.
/// Params: name - matched byte-exactly and case-sensitively ("emerg", ...,
/// "debug").
/// Returns: Ok(code) with code in 0..7, or
/// Err("logging: unknown severity: <name>").
/// Complexity: O(1) (a fixed 8-way comparison chain).
pub fn log_severity_code(name: Str) -> Result[Int, Str] {
  if compare.str_compare(name, "emerg") == 0 {
    return _ok_int(0);
  }
  if compare.str_compare(name, "alert") == 0 {
    return _ok_int(1);
  }
  if compare.str_compare(name, "crit") == 0 {
    return _ok_int(2);
  }
  if compare.str_compare(name, "err") == 0 {
    return _ok_int(3);
  }
  if compare.str_compare(name, "warning") == 0 {
    return _ok_int(4);
  }
  if compare.str_compare(name, "notice") == 0 {
    return _ok_int(5);
  }
  if compare.str_compare(name, "info") == 0 {
    return _ok_int(6);
  }
  if compare.str_compare(name, "debug") == 0 {
    return _ok_int(7);
  }
  return _err_int("logging: unknown severity: " + name);
}

/// Numeric PRI from a facility and a severity: facility * 8 + severity.
/// Params: facility 0..23; severity 0..7.
/// Returns: Ok(pri) with pri in 0..191, or
/// Err("logging: facility out of range: <facility>") /
/// Err("logging: severity out of range: <severity>").
/// Complexity: O(1).
pub fn log_pri_make(facility: Int, severity: Int) -> Result[Int, Str] {
  if facility < 0 || facility > 23 {
    return _err_int("logging: facility out of range: " + _int_to_str(facility));
  }
  if severity < 0 || severity > 7 {
    return _err_int("logging: severity out of range: " + _int_to_str(severity));
  }
  return _ok_int(facility * 8 + severity);
}

/// True when `pri` is a valid RFC 5424 PRI value (0..191).
pub fn log_pri_valid(pri: Int) -> Bool {
  return pri >= 0 && pri <= 191;
}

/// Facility code of a numeric PRI: pri / 8 for 0..191, else -1.
pub fn log_pri_facility(pri: Int) -> Int {
  if pri < 0 || pri > 191 {
    return -1;
  }
  return pri / 8;
}

/// Severity code of a numeric PRI: pri % 8 for 0..191, else -1.
pub fn log_pri_severity(pri: Int) -> Int {
  if pri < 0 || pri > 191 {
    return -1;
  }
  return pri % 8;
}

// --------------------------------------------------
//  Format auto-detection
// --------------------------------------------------

/// Detect the message format from the byte after the PRI field: a version
/// digit run ending in SP means RFC 5424 ("rfc5424"), an ASCII letter (the
/// month name of "Mmm dd hh:mm:ss") means RFC 3164 ("rfc3164").
/// Params: text - the message text.
/// Returns: "rfc5424", "rfc3164", or "" when the PRI is malformed or the
/// byte after it is neither shape. Detection is shape-only: it does not
/// validate the full message, so a detected text may still fail its parser.
/// Error case: none ("" reports no detection).
/// Complexity: O(len(text)) in the worst case, O(1) for well-formed PRI.
pub fn log_detect(text: Str) -> Str {
  let n = text.len();
  if n < 3 {
    return "";
  }
  if string.byte_at(text, 0) != _LOG_LT {
    return "";
  }
  var i = 1;
  var digits = 0;
  while i < n && digits < 3 && _is_digit(string.byte_at(text, i)) {
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 {
    return "";
  }
  if i < n && _is_digit(string.byte_at(text, i)) {
    return "";
  }
  if i >= n || string.byte_at(text, i) != _LOG_GT {
    return "";
  }
  let j = i + 1;
  if j >= n {
    return "";
  }
  let b = string.byte_at(text, j);
  if _is_digit(b) {
    var k = j;
    var vd = 0;
    while k < n && vd < 3 && _is_digit(string.byte_at(text, k)) {
      vd = vd + 1;
      k = k + 1;
    }
    if vd == 0 {
      return "";
    }
    if k < n && _is_digit(string.byte_at(text, k)) {
      return "";
    }
    if k < n && string.byte_at(text, k) == _LOG_SP {
      return "rfc5424";
    }
    return "";
  }
  if _is_alpha(b) {
    return "rfc3164";
  }
  return "";
}

// --------------------------------------------------
//  RFC 3164
// --------------------------------------------------

/// Parse one RFC 3164 (BSD syslog) message.
/// Params: text - one message, optionally followed by a line break. The
/// walk stops at the first CR or LF, so bytes after the first line break
/// are ignored (a buffer can be walked with `consumed`).
/// Grammar: PRI TIMESTAMP SP HOSTNAME SP TAG [ "[" pid "]" ] ":" [ SP ]
/// CONTENT, with TIMESTAMP = "Mmm dd hh:mm:ss" (exactly 15 bytes, canonical
/// month names, space-padded or zero-padded day, no year), TAG = 1..32
/// alphanumeric bytes, pid = 1..10 digits, HOSTNAME = 1..255 PRINTUSASCII
/// bytes. The PRI decodes to facility (pri / 8) and severity (pri % 8).
/// Returns: Ok(Log3164) with the raw timestamp text, the parsed date/time
/// fields, the field byte offsets and `consumed` (the byte length of the
/// message up to the first line break).
/// Error case: Err("logging: ... at <offset>") with one of the exact
/// reasons catalogued in SPEC.md: missing/bad PRI, PRI out of range, bad
/// TIMESTAMP, missing HOSTNAME / HOSTNAME too long / bad HOSTNAME, missing
/// TAG / bad TAG / TAG too long, bad pid.
/// Complexity: O(len(text)).
pub fn log3164_parse(text: Str) -> Result[Log3164, Str] {
  var m = Log3164{
    facility: 0;
    severity: 0;
    month: 0;
    day: 0;
    hour: 0;
    minute: 0;
    second: 0;
    timestamp: "";
    hostname: "";
    tag: "";
    pid: "";
    has_pid: false;
    content: "";
    has_content: false;
    consumed: 0;
    ts_at: 0;
    host_at: 0;
    tag_at: 0;
    content_at: 0;
  };
  let n = _line_end(text);
  let pr = _scan_pri(text);
  if pr.err.len() > 0 {
    return _err_3164(_err_at(pr.err, pr.pos));
  }
  m.facility = pr.value / 8;
  m.severity = pr.value % 8;
  var i = pr.next;
  // TIMESTAMP: exactly 15 bytes "Mmm dd hh:mm:ss".
  if i + 15 > n {
    return _err_3164(_err_at("bad TIMESTAMP", n));
  }
  let mon = _month_from_name(string.str_slice(text, i, i + 3));
  if mon < 1 {
    return _err_3164(_err_at("bad TIMESTAMP", i));
  }
  if string.byte_at(text, i + 3) != _LOG_SP {
    return _err_3164(_err_at("bad TIMESTAMP", i + 3));
  }
  let d0 = string.byte_at(text, i + 4);
  let d1 = string.byte_at(text, i + 5);
  var day = -1;
  if d0 == _LOG_SP {
    if _is_digit(d1) {
      day = (d1 as Int) - 48;
    }
  } elif _is_digit(d0) && _is_digit(d1) {
    day = ((d0 as Int) - 48) * 10 + ((d1 as Int) - 48);
  }
  if day < 1 || day > 31 {
    return _err_3164(_err_at("bad TIMESTAMP", i + 4));
  }
  if string.byte_at(text, i + 6) != _LOG_SP {
    return _err_3164(_err_at("bad TIMESTAMP", i + 6));
  }
  let hh = _digits2(text, i + 7);
  if hh < 0 || hh > 23 {
    return _err_3164(_err_at("bad TIMESTAMP", i + 7));
  }
  if string.byte_at(text, i + 9) != _LOG_COLON {
    return _err_3164(_err_at("bad TIMESTAMP", i + 9));
  }
  let mm = _digits2(text, i + 10);
  if mm < 0 || mm > 59 {
    return _err_3164(_err_at("bad TIMESTAMP", i + 10));
  }
  if string.byte_at(text, i + 12) != _LOG_COLON {
    return _err_3164(_err_at("bad TIMESTAMP", i + 12));
  }
  let ss = _digits2(text, i + 13);
  if ss < 0 || ss > 59 {
    return _err_3164(_err_at("bad TIMESTAMP", i + 13));
  }
  m.ts_at = i;
  m.timestamp = string.str_slice(text, i, i + 15);
  m.month = mon;
  m.day = day;
  m.hour = hh;
  m.minute = mm;
  m.second = ss;
  i = i + 15;
  // SP HOSTNAME
  if i >= n || string.byte_at(text, i) != _LOG_SP {
    return _err_3164(_err_at("missing HOSTNAME", i));
  }
  i = i + 1;
  let host_at = i;
  while i < n && string.byte_at(text, i) != _LOG_SP {
    i = i + 1;
  }
  let host = string.str_slice(text, host_at, i);
  if host.len() == 0 {
    return _err_3164(_err_at("missing HOSTNAME", host_at));
  }
  if host.len() > _LOG_HOSTNAME_MAX {
    return _err_3164(_err_at("HOSTNAME too long", host_at));
  }
  if !_print_ascii_ok(host) {
    return _err_3164(_err_at("bad HOSTNAME", host_at));
  }
  m.host_at = host_at;
  m.hostname = host;
  // SP TAG [ "[" pid "]" ] ":"
  if i >= n || string.byte_at(text, i) != _LOG_SP {
    return _err_3164(_err_at("missing TAG", i));
  }
  i = i + 1;
  let tag_at = i;
  while i < n && _is_alnum(string.byte_at(text, i)) {
    i = i + 1;
  }
  let tag_len = i - tag_at;
  if tag_len == 0 {
    return _err_3164(_err_at("bad TAG", tag_at));
  }
  if tag_len > _LOG_TAG_MAX {
    return _err_3164(_err_at("TAG too long", tag_at));
  }
  m.tag_at = tag_at;
  m.tag = string.str_slice(text, tag_at, i);
  if i < n && string.byte_at(text, i) == _LOG_LBRACKET {
    i = i + 1;
    let pid_at = i;
    var pd = 0;
    while i < n && _is_digit(string.byte_at(text, i)) && pd < _LOG_PID_MAX + 1 {
      pd = pd + 1;
      i = i + 1;
    }
    if pd == 0 {
      return _err_3164(_err_at("bad pid", pid_at));
    }
    if pd > _LOG_PID_MAX {
      return _err_3164(_err_at("bad pid", pid_at));
    }
    if i >= n || string.byte_at(text, i) != _LOG_RBRACKET {
      return _err_3164(_err_at("bad pid", i));
    }
    m.pid = string.str_slice(text, pid_at, i);
    m.has_pid = true;
    i = i + 1;
  }
  if i >= n || string.byte_at(text, i) != _LOG_COLON {
    return _err_3164(_err_at("bad TAG", i));
  }
  i = i + 1;
  // CONTENT: one optional SP is the separator; the rest (up to the line
  // break) is the content, kept byte-exact.
  if i < n && string.byte_at(text, i) == _LOG_SP {
    i = i + 1;
  }
  m.content_at = i;
  if i < n {
    m.has_content = true;
    m.content = string.str_slice(text, i, n);
  }
  m.consumed = n;
  return _ok_3164(m);
}

/// True when `text` parses as a well-formed RFC 3164 message.
pub fn log3164_ok(text: Str) -> Bool {
  let r = log3164_parse(text);
  if r.is_ok {
    return true;
  }
  return false;
}

/// PRI value of a parsed 3164 message: facility * 8 + severity (0..191).
pub fn log3164_pri(m: &Log3164) -> Int {
  return m.facility * 8 + m.severity;
}

/// Facility code (0..23) of a parsed 3164 message.
pub fn log3164_facility(m: &Log3164) -> Int {
  return m.facility;
}

/// Severity code (0..7) of a parsed 3164 message.
pub fn log3164_severity(m: &Log3164) -> Int {
  return m.severity;
}

/// Month number (1..12) of a parsed 3164 message.
pub fn log3164_month(m: &Log3164) -> Int {
  return m.month;
}

/// Day of month (1..31) of a parsed 3164 message.
pub fn log3164_day(m: &Log3164) -> Int {
  return m.day;
}

/// Hour (0..23) of a parsed 3164 message.
pub fn log3164_hour(m: &Log3164) -> Int {
  return m.hour;
}

/// Minute (0..59) of a parsed 3164 message.
pub fn log3164_minute(m: &Log3164) -> Int {
  return m.minute;
}

/// Second (0..59) of a parsed 3164 message.
pub fn log3164_second(m: &Log3164) -> Int {
  return m.second;
}

/// Raw TIMESTAMP text of a parsed 3164 message ("Mmm dd hh:mm:ss").
pub fn log3164_timestamp(m: &Log3164) -> Str {
  return m.timestamp;
}

/// HOSTNAME of a parsed 3164 message.
pub fn log3164_hostname(m: &Log3164) -> Str {
  return m.hostname;
}

/// TAG of a parsed 3164 message, without the optional "[pid]" part.
pub fn log3164_tag(m: &Log3164) -> Str {
  return m.tag;
}

/// Process id text of a parsed 3164 message; "" when no "[pid]" was present.
pub fn log3164_pid(m: &Log3164) -> Str {
  return m.pid;
}

/// True when the 3164 TAG carried an explicit "[pid]".
pub fn log3164_has_pid(m: &Log3164) -> Bool {
  return m.has_pid;
}

/// CONTENT of a parsed 3164 message; "" when absent or empty.
pub fn log3164_content(m: &Log3164) -> Str {
  return m.content;
}

/// True when CONTENT bytes followed "TAG:" (even when they are empty).
pub fn log3164_has_content(m: &Log3164) -> Bool {
  return m.has_content;
}

/// Number of bytes consumed by the 3164 message walk: the byte length of the
/// message up to (not including) the first CR/LF.
pub fn log3164_consumed(m: &Log3164) -> Int {
  return m.consumed;
}

// --------------------------------------------------
//  RFC 5424
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
/// Returns: true for a conforming timestamp, false otherwise.
/// Error case: none.
/// Complexity: O(len(s)).
pub fn log5424_timestamp_valid(s: Str) -> Bool {
  let sc = _ts_scan(s, 0);
  return sc.ok;
}

/// Parse an RFC 5424 TIMESTAMP string into its fields.
/// Params: s - the timestamp text alone; the same grammar as
/// log5424_timestamp_valid.
/// Returns: Ok(LogTimestamp) with year/month/day/hour/minute/second,
/// `frac` = fractional-second digits without the dot ("" when absent) and
/// `offset_min` = signed UTC offset in minutes (0 for "Z" and "-00:00");
/// `present` is true.
/// Error case: Err("logging: bad TIMESTAMP at <offset>") where the offset
/// is relative to `s` and points at the offending byte.
/// Complexity: O(len(s)).
pub fn log5424_timestamp_parse(s: Str) -> Result[LogTimestamp, Str] {
  let sc = _ts_scan(s, 0);
  if !sc.ok {
    return _err_ts(_err_at("bad TIMESTAMP", sc.err_pos));
  }
  return _ok_ts(sc.ts);
}

/// Parse one RFC 5424 syslog message.
/// Params: text - the complete message; no transport framing is removed, so
/// a trailing LF/CRLF is MSG content when a MSG part is present and is
/// rejected as trailing junk otherwise.
/// Grammar: PRI VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME SP PROCID
/// SP MSGID SP STRUCTURED-DATA [ SP MSG ], with PRI 0..191, VERSION 1..999,
/// NILVALUE "-" for the timestamp and header fields (stored as ""),
/// STRUCTURED-DATA = "-" or one or more "[SD-ID *(SP PARAM-NAME "=" DQUOTE
/// PARAM-VALUE DQUOTE)]" elements, and an optional UTF-8 BOM before MSG.
/// Parameter escapes \" \\ \] are decoded; unescaped values are stored in
/// `sd_param_values` and the raw wire span in `sd_param_val_at` /
/// `sd_param_val_len`.
/// Returns: Ok(Log5424) for a well-formed message.
/// Error case: Err("logging: ... at <offset>") with one of the exact
/// reasons catalogued in SPEC.md (missing/bad PRI, PRI out of range, bad
/// version, missing field, bad TIMESTAMP, field too long / bad field,
/// truncation and the structured-data errors).
/// Complexity: O(len(text)).
pub fn log5424_parse(text: Str) -> Result[Log5424, Str] {
  var m = Log5424{
    facility: 0;
    severity: 0;
    version: 1;
    timestamp: "";
    ts_present: false;
    ts_year: 0;
    ts_month: 0;
    ts_day: 0;
    ts_hour: 0;
    ts_minute: 0;
    ts_second: 0;
    ts_frac: "";
    ts_offset_min: 0;
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
    sd_param_val_at: Vec[Int].new();
    sd_param_val_len: Vec[Int].new();
  };
  let n = text.len();
  let pr = _scan_pri(text);
  if pr.err.len() > 0 {
    return _err_5424(_err_at(pr.err, pr.pos));
  }
  m.facility = pr.value / 8;
  m.severity = pr.value % 8;
  var i = pr.next;
  // VERSION
  let sp_ver = _find_sp(text, i);
  var ver_end = n;
  if sp_ver >= 0 {
    ver_end = sp_ver;
  }
  let ver_text = string.str_slice(text, i, ver_end);
  if !_version_ok(ver_text) {
    return _err_5424(_err_at("bad version", i));
  }
  m.version = _digits_value(ver_text, 0, ver_text.len());
  if sp_ver < 0 {
    return _err_5424(_err_at("missing TIMESTAMP", n));
  }
  i = sp_ver + 1;
  // TIMESTAMP
  let sp_ts = _find_sp(text, i);
  if sp_ts < 0 {
    return _err_5424(_err_at("missing TIMESTAMP", n));
  }
  let ts_text = string.str_slice(text, i, sp_ts);
  if ts_text.len() == 0 {
    return _err_5424(_err_at("missing TIMESTAMP", i));
  }
  if ts_text.len() == 1 && string.byte_at(ts_text, 0) == _LOG_DASH {
    m.ts_present = false;
    m.timestamp = "";
  } else {
    let sc = _ts_scan(ts_text, i);
    if !sc.ok {
      return _err_5424(_err_at("bad TIMESTAMP", sc.err_pos));
    }
    m.timestamp = ts_text;
    m.ts_present = true;
    m.ts_year = sc.ts.year;
    m.ts_month = sc.ts.month;
    m.ts_day = sc.ts.day;
    m.ts_hour = sc.ts.hour;
    m.ts_minute = sc.ts.minute;
    m.ts_second = sc.ts.second;
    m.ts_frac = sc.ts.frac;
    m.ts_offset_min = sc.ts.offset_min;
  }
  i = sp_ts + 1;
  // HOSTNAME
  let f_hn = _scan_field(text, i, "HOSTNAME", _LOG_HOSTNAME_MAX);
  if f_hn.err.len() > 0 {
    return _err_5424(_err_at(f_hn.err, f_hn.pos));
  }
  if !f_hn.sep {
    return _err_5424(_err_at("missing HOSTNAME", n));
  }
  m.hostname = f_hn.text;
  i = f_hn.next + 1;
  // APP-NAME
  let f_ap = _scan_field(text, i, "APP-NAME", _LOG_APP_NAME_MAX);
  if f_ap.err.len() > 0 {
    return _err_5424(_err_at(f_ap.err, f_ap.pos));
  }
  if !f_ap.sep {
    return _err_5424(_err_at("missing APP-NAME", n));
  }
  m.app_name = f_ap.text;
  i = f_ap.next + 1;
  // PROCID
  let f_pr = _scan_field(text, i, "PROCID", _LOG_PROCID_MAX);
  if f_pr.err.len() > 0 {
    return _err_5424(_err_at(f_pr.err, f_pr.pos));
  }
  if !f_pr.sep {
    return _err_5424(_err_at("missing PROCID", n));
  }
  m.procid = f_pr.text;
  i = f_pr.next + 1;
  // MSGID
  let f_mid = _scan_field(text, i, "MSGID", _LOG_MSGID_MAX);
  if f_mid.err.len() > 0 {
    return _err_5424(_err_at(f_mid.err, f_mid.pos));
  }
  if !f_mid.sep {
    return _err_5424(_err_at("truncated message", n));
  }
  m.msgid = f_mid.text;
  i = f_mid.next + 1;
  // STRUCTURED-DATA
  if i >= n {
    return _err_5424(_err_at("truncated message", n));
  }
  let sd_first = string.byte_at(text, i);
  if sd_first == _LOG_DASH {
    i = i + 1;
    if i < n && string.byte_at(text, i) != _LOG_SP {
      return _err_5424(_err_at("bad structured data", i));
    }
  } elif sd_first == _LOG_LBRACKET {
    while i < n && string.byte_at(text, i) == _LOG_LBRACKET {
      i = i + 1;
      let id_start = i;
      while i < n {
        let b = string.byte_at(text, i);
        if b == _LOG_SP || b == _LOG_RBRACKET {
          break;
        }
        i = i + 1;
      }
      let sd_id = string.str_slice(text, id_start, i);
      if !_sd_name_ok(sd_id) {
        return _err_5424(_err_at("bad SD-ID", id_start));
      }
      m.sd_ids.push(sd_id);
      let elem = m.sd_ids.len() - 1;
      while i < n && string.byte_at(text, i) == _LOG_SP {
        i = i + 1;
        let pn_start = i;
        while i < n && string.byte_at(text, i) != _LOG_EQ {
          let pb = string.byte_at(text, i);
          if pb == _LOG_SP || pb == _LOG_RBRACKET {
            break;
          }
          i = i + 1;
        }
        let pn_text = string.str_slice(text, pn_start, i);
        if i >= n || string.byte_at(text, i) != _LOG_EQ {
          return _err_5424(_err_at("bad param name", pn_start));
        }
        if !_sd_name_ok(pn_text) {
          return _err_5424(_err_at("bad param name", pn_start));
        }
        i = i + 1;
        if i >= n || string.byte_at(text, i) != _LOG_DQUOTE {
          return _err_5424(_err_at("bad param quote", i));
        }
        i = i + 1;
        let val_at = i;
        var val = Vec[UInt8].new();
        var closed = false;
        while i < n {
          let vb = string.byte_at(text, i);
          if vb == _LOG_BACKSLASH {
            if i + 1 >= n {
              return _err_5424(_err_at("bad param escape", i));
            }
            let eb = string.byte_at(text, i + 1);
            if eb == _LOG_DQUOTE || eb == _LOG_BACKSLASH || eb == _LOG_RBRACKET {
              val.push(eb);
              i = i + 2;
            } else {
              return _err_5424(_err_at("bad param escape", i));
            }
          } elif vb == _LOG_DQUOTE {
            closed = true;
            i = i + 1;
            break;
          } elif vb == _LOG_RBRACKET {
            return _err_5424(_err_at("bad param value", i));
          } else {
            val.push(vb);
            i = i + 1;
          }
        }
        if !closed {
          return _err_5424(_err_at("bad param quote", i));
        }
        let val_len = i - 1 - val_at;
        if i < n && string.byte_at(text, i) != _LOG_SP && string.byte_at(text, i) != _LOG_RBRACKET {
          return _err_5424(_err_at("bad structured data", i));
        }
        let unescaped = builder.sb_to_str(&val);
        m.sd_param_elem.push(elem);
        m.sd_param_names.push(pn_text);
        m.sd_param_values.push(unescaped);
        m.sd_param_val_at.push(val_at);
        m.sd_param_val_len.push(val_len);
      }
      if i >= n {
        return _err_5424(_err_at("unterminated structured data", i));
      }
      if string.byte_at(text, i) != _LOG_RBRACKET {
        return _err_5424(_err_at("unterminated structured data", i));
      }
      i = i + 1;
    }
  } else {
    return _err_5424(_err_at("bad structured data", i));
  }
  if i < n && string.byte_at(text, i) != _LOG_SP {
    return _err_5424(_err_at("bad structured data", i));
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
  return _ok_5424(m);
}

/// True when `text` parses as a well-formed RFC 5424 message.
pub fn log5424_ok(text: Str) -> Bool {
  let r = log5424_parse(text);
  if r.is_ok {
    return true;
  }
  return false;
}

/// PRI value of a parsed 5424 message: facility * 8 + severity (0..191).
pub fn log5424_pri(m: &Log5424) -> Int {
  return m.facility * 8 + m.severity;
}

/// Facility code (0..23) of a parsed 5424 message.
pub fn log5424_facility(m: &Log5424) -> Int {
  return m.facility;
}

/// Severity code (0..7) of a parsed 5424 message.
pub fn log5424_severity(m: &Log5424) -> Int {
  return m.severity;
}

/// VERSION of a parsed 5424 message (1..999).
pub fn log5424_version(m: &Log5424) -> Int {
  return m.version;
}

/// Raw TIMESTAMP text of a parsed 5424 message; "" for the NILVALUE "-".
pub fn log5424_timestamp_text(m: &Log5424) -> Str {
  return m.timestamp;
}

/// Structured TIMESTAMP fields of a parsed 5424 message; all-zero fields
/// with `present == false` for the NILVALUE "-".
pub fn log5424_timestamp(m: &Log5424) -> LogTimestamp {
  return LogTimestamp{
    year: m.ts_year;
    month: m.ts_month;
    day: m.ts_day;
    hour: m.ts_hour;
    minute: m.ts_minute;
    second: m.ts_second;
    frac: m.ts_frac;
    offset_min: m.ts_offset_min;
    present: m.ts_present;
  };
}

/// True when the 5424 message carried a non-NILVALUE TIMESTAMP.
pub fn log5424_has_timestamp(m: &Log5424) -> Bool {
  return m.ts_present;
}

/// HOSTNAME of a parsed 5424 message; "" for the NILVALUE "-".
pub fn log5424_hostname(m: &Log5424) -> Str {
  return m.hostname;
}

/// APP-NAME of a parsed 5424 message; "" for the NILVALUE "-".
pub fn log5424_app_name(m: &Log5424) -> Str {
  return m.app_name;
}

/// PROCID of a parsed 5424 message; "" for the NILVALUE "-".
pub fn log5424_procid(m: &Log5424) -> Str {
  return m.procid;
}

/// MSGID of a parsed 5424 message; "" for the NILVALUE "-".
pub fn log5424_msgid(m: &Log5424) -> Str {
  return m.msgid;
}

/// MSG text of a parsed 5424 message, without a leading UTF-8 BOM; "" when
/// the message carried no MSG part or an empty one.
pub fn log5424_msg(m: &Log5424) -> Str {
  return m.msg;
}

/// True when MSG began with a UTF-8 BOM (stripped from log5424_msg).
pub fn log5424_has_bom(m: &Log5424) -> Bool {
  return m.bom;
}

/// True when the wire message carried the optional SP MSG part (even when
/// MSG is empty); false when it ended at the structured-data section.
pub fn log5424_has_msg(m: &Log5424) -> Bool {
  return m.has_msg;
}

/// Number of structured-data elements (0 for the NILVALUE section).
pub fn log5424_sd_count(m: &Log5424) -> Int {
  return m.sd_ids.len();
}

/// SD-ID of element `i`; "" when `i` is out of range.
pub fn log5424_sd_id(m: &Log5424, i: Int) -> Str {
  if i < 0 || i >= m.sd_ids.len() {
    return "";
  }
  let v: Str = m.sd_ids[i];
  return v;
}

// Flat parameter slot of the `i`-th parameter of element `elem`, or -1.
fn _param_slot(m: &Log5424, elem: Int, i: Int) -> Int {
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
pub fn log5424_sd_param_count(m: &Log5424, elem: Int) -> Int {
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
pub fn log5424_sd_param_name(m: &Log5424, elem: Int, i: Int) -> Str {
  let at = _param_slot(m, elem, i);
  if at < 0 {
    return "";
  }
  let v: Str = m.sd_param_names[at];
  return v;
}

/// Unescaped value of the `i`-th parameter (0-based) of element `elem`;
/// "" when the element or parameter index is out of range.
pub fn log5424_sd_param_value(m: &Log5424, elem: Int, i: Int) -> Str {
  let at = _param_slot(m, elem, i);
  if at < 0 {
    return "";
  }
  let v: Str = m.sd_param_values[at];
  return v;
}

/// Byte offset of the raw (still escaped) wire value of the `i`-th
/// parameter of element `elem`; -1 when the index is out of range.
pub fn log5424_sd_param_value_at(m: &Log5424, elem: Int, i: Int) -> Int {
  let at = _param_slot(m, elem, i);
  if at < 0 {
    return -1;
  }
  let v: Int = m.sd_param_val_at[at];
  return v;
}

/// Byte length of the raw (still escaped) wire value of the `i`-th
/// parameter of element `elem`; -1 when the index is out of range.
pub fn log5424_sd_param_value_len(m: &Log5424, elem: Int, i: Int) -> Int {
  let at = _param_slot(m, elem, i);
  if at < 0 {
    return -1;
  }
  let v: Int = m.sd_param_val_len[at];
  return v;
}

/// Byte-exact wire text of the `i`-th parameter value of element `elem`,
/// sliced out of the original `text` with the stored span (escapes intact);
/// "" when the index is out of range.
pub fn log5424_sd_param_value_wire(m: &Log5424, text: Str, elem: Int, i: Int) -> Str {
  let at = _param_slot(m, elem, i);
  if at < 0 {
    return "";
  }
  let start: Int = m.sd_param_val_at[at];
  let len: Int = m.sd_param_val_len[at];
  return string.str_slice(text, start, start + len);
}

/// First parameter named `name` of element `elem`; None when the element is
/// out of range or no parameter has that exact name (names are matched
/// byte-exactly and are case-sensitive per RFC 5424).
pub fn log5424_sd_param(m: &Log5424, elem: Int, name: Str) -> Option[Str] {
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
