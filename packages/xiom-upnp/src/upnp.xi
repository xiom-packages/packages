// XIOM -- xiom.upnp: SSDP/UPnP discovery message codec (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) codec for the SSDP messages of UPnP device discovery
// (UPnP Device Architecture 1.0/1.1). Three message forms are recognised:
//
//   * M-SEARCH requests:  "M-SEARCH * HTTP/1.1" plus HOST, MAN, MX, ST and
//     an optional USER-AGENT;
//   * NOTIFY notifications: "NOTIFY * HTTP/1.1" plus HOST, NT, NTS
//     (ssdp:alive / ssdp:byebye / ssdp:update), USN, and for the forms that
//     carry them CACHE-CONTROL, LOCATION, SERVER and the integer headers
//     BOOTID.UPNP.ORG, CONFIGID.UPNP.ORG and SEARCHPORT.UPNP.ORG;
//   * search responses:    "HTTP/1.1 200 OK" plus CACHE-CONTROL, DATE, EXT,
//     LOCATION, ST, USN, an optional SERVER and the same integer headers.
//
// Header names are matched ASCII case-insensitively; every header is kept,
// in wire order, in parallel name/value/offset vectors, and the documented
// fields are also decoded into typed struct fields. LOCATION is validated
// loosely (scheme http/https, non-empty host, port 1..65535); USN and ST/NT
// values are parsed by usn_split / upnp_classify_target. The two required
// serialisers (M-SEARCH and NOTIFY ssdp:alive) write canonical header-name
// casing and CRLF terminators and round-trip through upnp_parse.
//
// Non-goals (see SPEC.md): sockets and multicast, XML device descriptions,
// SOAP control, HTTP bodies, method registries beyond M-SEARCH/NOTIFY/200,
// and full RFC 7230/1123 validation.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType] and no
//     struct fields of struct type -- SsdpMessage, SsdpTarget and UsnSplit
//     are deliberately flat with parallel vectors.
//   * Ok/Err are constructed only in the tiny leaf helpers below
//     (constructing Results directly inside larger functions miscompiles).
//   * Every byte read from Vec[UInt8] or Str is widened with
//     `... as Int) & 0xFF` before any comparison.
//   * Vec[Str] element reads are bound to typed locals and compared only
//     through xiom.string.compare.str_compare (BUG 17).
//   * Vec[Int] element reads are bound to typed locals before use, and the
//     parallel vectors of SsdpMessage are only ever extended together.

module xiom.upnp

use xiom.string;
use xiom.string.compare;
use xiom.convert.int;

// --------------------------------------------------
//  Protocol constants
// --------------------------------------------------

/// The SSDP multicast address (IPv4).
pub const UPNP_SSDP_ADDRESS: Str = "239.255.255.250";

/// The SSDP port.
pub const UPNP_SSDP_PORT: Int = 1900;

/// The canonical SSDP HOST value "239.255.255.250:1900".
pub const UPNP_SSDP_HOST: Str = "239.255.255.250:1900";

/// Largest accepted message, in bytes. SSDP runs over UDP; this cap keeps the
/// parser linear on hostile input. Messages longer than this are rejected
/// before any scanning.
pub const UPNP_MAX_MESSAGE: Int = 8192;

/// Message kind: an M-SEARCH request.
pub const UPNP_KIND_MSEARCH: Int = 0;

/// Message kind: a NOTIFY notification.
pub const UPNP_KIND_NOTIFY: Int = 1;

/// Message kind: an HTTP/1.1 200 search response.
pub const UPNP_KIND_RESPONSE: Int = 2;

/// NTS kind: ssdp:alive.
pub const UPNP_NTS_ALIVE: Int = 0;

/// NTS kind: ssdp:byebye.
pub const UPNP_NTS_BYEBYE: Int = 1;

/// NTS kind: ssdp:update.
pub const UPNP_NTS_UPDATE: Int = 2;

/// Target kind: the ssdp:all search target.
pub const UPNP_TARGET_SSDP_ALL: Int = 0;

/// Target kind: upnp:rootdevice.
pub const UPNP_TARGET_ROOTDEVICE: Int = 1;

/// Target kind: uuid:<device-uuid>.
pub const UPNP_TARGET_UUID: Int = 2;

/// Target kind: urn:<domain>:device:<type>:<ver>.
pub const UPNP_TARGET_DEVICE: Int = 3;

/// Target kind: urn:<domain>:service:<type>:<ver>.
pub const UPNP_TARGET_SERVICE: Int = 4;

/// Target kind: a structurally valid URN that is not a UPnP device/service
/// type.
pub const UPNP_TARGET_OTHER_URN: Int = 5;

/// USN kind: "uuid:<device-uuid>".
pub const UPNP_USN_UUID: Int = 0;

/// USN kind: "uuid:<device-uuid>::urn:...".
pub const UPNP_USN_UUID_URN: Int = 1;

/// USN kind: "uuid:<device-uuid>::upnp:rootdevice".
pub const UPNP_USN_UUID_ROOTDEVICE: Int = 2;

/// USN kind: a bare "urn:...".
pub const UPNP_USN_URN: Int = 3;

// Bytes referenced by the scanners (Int space; see _str_byte/_byte).
const _UPNP_TAB: Int = 9;
const _UPNP_LF: Int = 10;
const _UPNP_CR: Int = 13;
const _UPNP_SP: Int = 32;
const _UPNP_QUOTE: Int = 34;
const _UPNP_COMMA: Int = 44;
const _UPNP_COLON: Int = 58;
const _UPNP_LBRACKET: Int = 91;
const _UPNP_RBRACKET: Int = 93;
const _UPNP_DEL: Int = 127;

// Header value bounds used by the typed extractors.
const _UPNP_MAX_U32: Int = 4294967295;
const _UPNP_MAX_CONFIGID: Int = 16777215;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parse error: a stable message plus the byte offset in the input buffer
/// where the problem was detected. For the standalone classifiers
/// (upnp_classify_target, usn_split) the offset is an index into the target
/// string; for serialiser errors it is -1 (no input buffer exists).
pub type SsdpError = {
  message: Str;
  offset: Int;
}

/// A classified SSDP target (an ST or NT value).
///
/// `kind` is one of UPNP_TARGET_*; `raw` is the input text. For
/// UPNP_TARGET_UUID, `uuid` holds the device UUID (without the "uuid:"
/// prefix). For device/service/other-URN kinds, `domain`, `class_word`,
/// `dev_type` and `version` hold the URN parts ("" when not applicable) and
/// `major`/`minor` the parsed version (`minor` is -1 for "N", otherwise the
/// part after ".").
pub type SsdpTarget = {
  kind: Int;
  raw: Str;
  uuid: Str;
  domain: Str;
  class_word: Str;
  dev_type: Str;
  version: Str;
  major: Int;
  minor: Int;
}

/// A split USN (Unique Service Name).
///
/// `kind` is one of UPNP_USN_*; `uuid` holds the full "uuid:..." token (""),
/// `device_uuid` the bare device UUID (""), `urn` the "urn:..." token ("")
/// and `suffix` the raw text after "::" (""); for UPNP_USN_UUID the suffix is
/// empty and for UPNP_USN_UUID_ROOTDEVICE it is "upnp:rootdevice" (any case).
pub type UsnSplit = {
  kind: Int;
  uuid: Str;
  device_uuid: Str;
  urn: Str;
  suffix: Str;
}

/// A parsed SSDP message.
///
/// `kind` is one of UPNP_KIND_*; `start_line` is the raw first line (without
/// CRLF); `method`, `target`, `version`, `status` and `reason` are its
/// decoded parts (for responses `method` is "HTTP/1.1", `target` is "" and
/// `status` is 200; for requests `status` is -1 and `reason` is "").
///
/// `names`, `values` and `header_offsets` are parallel vectors in wire
/// order: the header name as sent, the value with surrounding whitespace
/// trimmed, and the absolute offset of the header's first byte. The typed
/// fields below are decoded from those headers; absent optional headers use
/// "" or -1. `nts_kind` is one of UPNP_NTS_* or -1. `max_age` is the value
/// of a valid "max-age=N" CACHE-CONTROL directive (-1 when absent).
pub type SsdpMessage = {
  kind: Int;
  start_line: Str;
  method: Str;
  target: Str;
  version: Str;
  status: Int;
  reason: Str;
  names: Vec[Str];
  values: Vec[Str];
  header_offsets: Vec[Int];
  host: Str;
  man: Str;
  mx: Int;
  st: Str;
  user_agent: Str;
  nt: Str;
  nts: Str;
  nts_kind: Int;
  usn: Str;
  location: Str;
  server: Str;
  date: Str;
  ext: Str;
  cache_control: Str;
  max_age: Int;
  bootid: Int;
  configid: Int;
  searchport: Int;
}

// Decoded start line (internal).
type SsdpStart = {
  kind: Int;
  method: Str;
  target: Str;
  version: Str;
  status: Int;
  reason: Str;
}

// Decoded typed header fields (internal).
type SsdpFields = {
  host: Str;
  man: Str;
  mx: Int;
  st: Str;
  user_agent: Str;
  nt: Str;
  nts: Str;
  nts_kind: Int;
  usn: Str;
  location: Str;
  server: Str;
  date: Str;
  ext: Str;
  cache_control: Str;
  max_age: Int;
  bootid: Int;
  configid: Int;
  searchport: Int;
}

// The header block of a message (internal). The three vectors are parallel.
type SsdpHeaderBlock = {
  names: Vec[Str];
  values: Vec[Str];
  offsets: Vec[Int];
  end_offset: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

fn _ok_msg(v: SsdpMessage) -> Result[SsdpMessage, SsdpError] {
  return Ok(v);
}

fn _err_msg(m: Str, off: Int) -> Result[SsdpMessage, SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

fn _ok_start(v: SsdpStart) -> Result[SsdpStart, SsdpError] {
  return Ok(v);
}

fn _err_start(m: Str, off: Int) -> Result[SsdpStart, SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

fn _ok_fields(v: SsdpFields) -> Result[SsdpFields, SsdpError] {
  return Ok(v);
}

fn _err_fields(m: Str, off: Int) -> Result[SsdpFields, SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

fn _ok_target(v: SsdpTarget) -> Result[SsdpTarget, SsdpError] {
  return Ok(v);
}

fn _err_target(m: Str, off: Int) -> Result[SsdpTarget, SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

fn _ok_usn(v: UsnSplit) -> Result[UsnSplit, SsdpError] {
  return Ok(v);
}

fn _err_usn(m: Str, off: Int) -> Result[UsnSplit, SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], SsdpError] {
  return Ok(v);
}

fn _err_bytes(m: Str, off: Int) -> Result[Vec[UInt8], SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

fn _ok_int(v: Int) -> Result[Int, SsdpError] {
  return Ok(v);
}

fn _err_int(m: Str, off: Int) -> Result[Int, SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

fn _ok_block(v: SsdpHeaderBlock) -> Result[SsdpHeaderBlock, SsdpError] {
  return Ok(v);
}

fn _err_block(m: Str, off: Int) -> Result[SsdpHeaderBlock, SsdpError] {
  return Err(SsdpError{ message: m; offset: off; });
}

// --------------------------------------------------
//  Byte and character helpers
// --------------------------------------------------

// Byte at `pos` of a byte buffer widened to Int (0..255). Callers guarantee
// the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Byte at `pos` of a Str widened to Int (0..255). Callers guarantee bounds.
fn _str_byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// ASCII digit.
fn _is_digit(b: Int) -> Bool {
  return b >= 48 && b <= 57;
}

// ASCII letter.
fn _is_alpha(b: Int) -> Bool {
  return (b >= 65 && b <= 90) || (b >= 97 && b <= 122);
}

// ASCII letter or digit.
fn _is_alnum(b: Int) -> Bool {
  return _is_digit(b) || _is_alpha(b);
}

// Hexadecimal digit (either case).
fn _is_hex(b: Int) -> Bool {
  if _is_digit(b) { return true; }
  if b >= 97 && b <= 102 { return true; }
  return b >= 65 && b <= 70;
}

// RFC 7230 token character.
fn _is_tchar(b: Int) -> Bool {
  if _is_alnum(b) { return true; }
  if b == 33 { return true; }
  if b == 35 { return true; }
  if b == 36 { return true; }
  if b == 37 { return true; }
  if b == 38 { return true; }
  if b == 39 { return true; }
  if b == 42 { return true; }
  if b == 43 { return true; }
  if b == 45 { return true; }
  if b == 46 { return true; }
  if b == 94 { return true; }
  if b == 95 { return true; }
  if b == 96 { return true; }
  if b == 124 { return true; }
  return b == 126;
}

// --------------------------------------------------
//  Str helpers
// --------------------------------------------------

// Str equality through str_compare, never `==` (BUG 17).
fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII case-insensitive Str equality.
fn _str_eq_ci(a: Str, b: Str) -> Bool {
  return compare.str_compare_ignore_case(a, b) == 0;
}

// True when `s` starts with `prefix`, ASCII case-insensitively.
fn _starts_ci(s: Str, prefix: Str) -> Bool {
  let pn = string.str_len(prefix);
  if string.str_len(s) < pn { return false; }
  let head = string.str_slice(s, 0, pn);
  return _str_eq_ci(head, prefix);
}

// UTF-8 bytes of a Str (one byte per string byte; no re-encoding).
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  let n = string.str_len(s);
  while i < n {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Copy bytes [from, to) of `data` into a fresh vector.
fn _slice_bytes(data: &Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Bytes [from, to) of `data` as a Str. Callers pass spans of a line that
// already passed _scan_line, so the span cannot contain NUL or control
// bytes; UTF-8 is not validated (the pinned Str::from_utf8 is lenient).
fn _slice_str(data: &Vec[UInt8], from: Int, to: Int) -> Str {
  let v = _slice_bytes(data, from, to);
  return Str::from_utf8(v);
}

// --------------------------------------------------
//  Part splitting (space-separated tokens, colon-separated URN parts)
// --------------------------------------------------

// Number of parts of `s` split at `sep`; 0 when `s` is empty. An empty
// middle part ("a::b" with sep ':') counts as a part (and is "" in _part).
fn _part_count(s: Str, sep: Int) -> Int {
  let n = string.str_len(s);
  if n == 0 { return 0; }
  var count = 1;
  var i = 0;
  while i < n {
    if _str_byte(s, i) == sep { count = count + 1; }
    i = i + 1;
  }
  return count;
}

// Part `idx` of `s` split at `sep`, or "" when out of range.
fn _part(s: Str, sep: Int, idx: Int) -> Str {
  let n = string.str_len(s);
  var seg = 0;
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || _str_byte(s, i) == sep {
      if seg == idx { return string.str_slice(s, start, i); }
      seg = seg + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return "";
}

// Offset of part `idx` of `s`, or -1 when out of range.
fn _part_start(s: Str, sep: Int, idx: Int) -> Int {
  let n = string.str_len(s);
  var seg = 0;
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || _str_byte(s, i) == sep {
      if seg == idx { return start; }
      seg = seg + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return -1;
}

// Value of a nonempty run of at most 10 ASCII digits; -1 when empty, longer
// than 10 bytes, or carrying a non-digit. Leading zeros are accepted.
fn _digits_value(s: Str) -> Int {
  let n = string.str_len(s);
  if n == 0 || n > 10 { return -1; }
  var v = 0;
  var i = 0;
  while i < n {
    let b = _str_byte(s, i);
    if !_is_digit(b) { return -1; }
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  return v;
}

// Split a UPnP version text: "N" (minor = -1) or "N.M" (major, minor).
// Both parts are 1..10 digit runs. The v0.61.3 `&mut Int` calling convention
// miscompiles write-through updates (documented in xiom-optimizer), so this
// returns the parts by value instead of using out-parameters.
type VersionParts = {
  valid: Bool;
  major: Int;
  minor: Int;
}

fn _parse_version_parts(s: Str) -> VersionParts {
  let n = string.str_len(s);
  if n == 0 { return VersionParts{ valid: false; major: -1; minor: -1; }; }
  var dot = -1;
  var i = 0;
  while i < n {
    let b = _str_byte(s, i);
    if b == 46 {
      if dot >= 0 { return VersionParts{ valid: false; major: -1; minor: -1; }; }
      dot = i;
    } elif !_is_digit(b) {
      return VersionParts{ valid: false; major: -1; minor: -1; };
    }
    i = i + 1;
  }
  if dot < 0 {
    let v0 = _digits_value(s);
    if v0 < 0 { return VersionParts{ valid: false; major: -1; minor: -1; }; }
    return VersionParts{ valid: true; major: v0; minor: -1; };
  }
  let a = string.str_slice(s, 0, dot);
  let b2 = string.str_slice(s, dot + 1, n);
  let ma = _digits_value(a);
  let mi = _digits_value(b2);
  if ma < 0 || mi < 0 { return VersionParts{ valid: false; major: -1; minor: -1; }; }
  return VersionParts{ valid: true; major: ma; minor: mi; };
}

// --------------------------------------------------
//  Validators
// --------------------------------------------------

/// True when `s` is a device UUID in the canonical 8-4-4-4-12 hex form
/// (dashes at indexes 8, 13, 18 and 23, hex digits elsewhere, either case).
/// Complexity: O(1).
pub fn upnp_is_device_uuid(s: Str) -> Bool {
  let n = string.str_len(s);
  if n != 36 { return false; }
  var i = 0;
  while i < n {
    let b = _str_byte(s, i);
    if i == 8 || i == 13 || i == 18 || i == 23 {
      if b != 45 { return false; }
    } elif !_is_hex(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// A URN part: nonempty, ASCII alphanumeric plus '-', '.' and '_'.
fn _valid_urn_token(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    let b = _str_byte(s, i);
    if !_is_alnum(b) && b != 45 && b != 46 && b != 95 { return false; }
    i = i + 1;
  }
  return true;
}

// Structural URN check: "urn:<nid>:<nss>" with at least two nonempty
// colon-separated parts after the scheme; every part nonempty.
fn _urn_valid(s: Str) -> Bool {
  if !_starts_ci(s, "urn:") { return false; }
  let rest = string.str_slice(s, 4, string.str_len(s));
  let c = _part_count(rest, _UPNP_COLON);
  if c < 2 { return false; }
  var k = 0;
  while k < c {
    let p = _part(rest, _UPNP_COLON, k);
    if string.str_len(p) == 0 { return false; }
    k = k + 1;
  }
  return true;
}

// Host name: nonempty, ASCII alphanumeric plus '-', '.' and '_' (IPv4
// literals pass as digit/dot runs).
fn _valid_hostname(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    let b = _str_byte(s, i);
    if !_is_alnum(b) && b != 45 && b != 46 && b != 95 { return false; }
    i = i + 1;
  }
  return true;
}

// Port text: 1..5 digits with value 1..65535.
fn _valid_port(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 || n > 5 { return false; }
  var v = 0;
  var i = 0;
  while i < n {
    let b = _str_byte(s, i);
    if !_is_digit(b) { return false; }
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  return v >= 1 && v <= 65535;
}

/// Loose validation of an authority (the HOST header value or the host:port
/// part of a LOCATION). Accepts "host", "host:port", "ipv4:port" and the
/// bracketed IPv6 form "[addr]" / "[addr]:port"; the host must be nonempty
/// and the port, when present, must be 1..65535. Rejects spaces, slashes,
/// empty hosts, unbracketed multiple colons and out-of-range ports.
/// Complexity: O(length).
pub fn upnp_validate_authority(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    let b = _str_byte(s, i);
    let ok = _is_alnum(b) || b == 45 || b == 46 || b == 95 || b == _UPNP_COLON || b == _UPNP_LBRACKET || b == _UPNP_RBRACKET;
    if !ok { return false; }
    i = i + 1;
  }
  if _str_byte(s, 0) == _UPNP_LBRACKET {
    var close = -1;
    var k = 1;
    while k < n {
      if _str_byte(s, k) == _UPNP_RBRACKET {
        close = k;
        break;
      }
      k = k + 1;
    }
    if close < 0 { return false; }
    let inner = string.str_slice(s, 1, close);
    if string.str_len(inner) == 0 { return false; }
    if close == n - 1 { return true; }
    if _str_byte(s, close + 1) != _UPNP_COLON { return false; }
    let p = string.str_slice(s, close + 2, n);
    return _valid_port(p);
  }
  var colons = 0;
  var last = -1;
  var j = 0;
  while j < n {
    if _str_byte(s, j) == _UPNP_COLON {
      colons = colons + 1;
      last = j;
    }
    j = j + 1;
  }
  if colons == 0 { return _valid_hostname(s); }
  if colons > 1 { return false; }
  let host = string.str_slice(s, 0, last);
  let port = string.str_slice(s, last + 1, n);
  if !_valid_hostname(host) { return false; }
  return _valid_port(port);
}

/// Loose validation of a LOCATION URL: scheme http:// or https://
/// (case-insensitive), an authority accepted by upnp_validate_authority,
/// and no ASCII space or control byte anywhere. The path is not validated
/// beyond that. Complexity: O(length).
pub fn upnp_validate_location(s: Str) -> Bool {
  let n = string.str_len(s);
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    if _str_byte(s, i) <= _UPNP_SP { return false; }
    i = i + 1;
  }
  let low = string.str_lower(s);
  var start = -1;
  if string.str_starts_with(low, "http://") {
    start = 7;
  } elif string.str_starts_with(low, "https://") {
    start = 8;
  } else {
    return false;
  }
  if start >= n { return false; }
  var end = n;
  var j = start;
  while j < n {
    let b = _str_byte(s, j);
    if b == 47 || b == 63 || b == 35 {
      end = j;
      break;
    }
    j = j + 1;
  }
  let authority = string.str_slice(s, start, end);
  return upnp_validate_authority(authority);
}

// Loose RFC 1123 date check for the DATE header: at least 20 bytes, a comma
// at index 3, a space at index 4, and ending in " GMT".
fn _valid_date(s: Str) -> Bool {
  let n = string.str_len(s);
  if n < 20 { return false; }
  if !string.str_ends_with(s, " GMT") { return false; }
  if _str_byte(s, 3) != _UPNP_COMMA { return false; }
  return _str_byte(s, 4) == _UPNP_SP;
}

// NTS kind of `s` (case-insensitive), or -1 when unrecognised.
fn _nts_kind_of(s: Str) -> Int {
  if _str_eq_ci(s, "ssdp:alive") { return UPNP_NTS_ALIVE; }
  if _str_eq_ci(s, "ssdp:byebye") { return UPNP_NTS_BYEBYE; }
  if _str_eq_ci(s, "ssdp:update") { return UPNP_NTS_UPDATE; }
  return -1;
}

// Strip one pair of surrounding double quotes, when present.
fn _strip_quotes(s: Str) -> Str {
  let n = string.str_len(s);
  if n >= 2 {
    if _str_byte(s, 0) == _UPNP_QUOTE && _str_byte(s, n - 1) == _UPNP_QUOTE {
      return string.str_slice(s, 1, n - 1);
    }
  }
  return s;
}

// --------------------------------------------------
//  Target and USN classification
// --------------------------------------------------

/// Classify an SSDP ST or NT value.
///
/// Recognised (case-insensitively): "ssdp:all", "upnp:rootdevice",
/// "uuid:<device-uuid>" and the UPnP URN forms
/// "urn:<domain>:device:<type>:<ver>" / "urn:<domain>:service:<type>:<ver>"
/// with a structural version (digits, optionally ".digits"). Other
/// structurally valid URNs classify as UPNP_TARGET_OTHER_URN. Anything else
/// is Err with the offset of the offending part. Complexity: O(length).
pub fn upnp_classify_target(s: Str) -> Result[SsdpTarget, SsdpError] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_target("upnp: empty target", 0);
  }
  if _str_eq_ci(s, "ssdp:all") {
    return _ok_target(SsdpTarget{ kind: UPNP_TARGET_SSDP_ALL; raw: s; uuid: ""; domain: ""; class_word: ""; dev_type: ""; version: ""; major: -1; minor: -1; });
  }
  if _str_eq_ci(s, "upnp:rootdevice") {
    return _ok_target(SsdpTarget{ kind: UPNP_TARGET_ROOTDEVICE; raw: s; uuid: ""; domain: ""; class_word: ""; dev_type: ""; version: ""; major: -1; minor: -1; });
  }
  if _starts_ci(s, "uuid:") {
    let id = string.str_slice(s, 5, n);
    if !upnp_is_device_uuid(id) {
      return _err_target("upnp: bad uuid in target", 5);
    }
    return _ok_target(SsdpTarget{ kind: UPNP_TARGET_UUID; raw: s; uuid: id; domain: ""; class_word: ""; dev_type: ""; version: ""; major: -1; minor: -1; });
  }
  if _starts_ci(s, "urn:") {
    let rest = string.str_slice(s, 4, n);
    let c = _part_count(rest, _UPNP_COLON);
    if c < 2 {
      return _err_target("upnp: bad urn in target", 4);
    }
    let domain = _part(rest, _UPNP_COLON, 0);
    let word = _part(rest, _UPNP_COLON, 1);
    if !_valid_urn_token(domain) {
      return _err_target("upnp: bad urn in target", 4);
    }
    if _str_eq_ci(word, "device") || _str_eq_ci(word, "service") {
      if c != 4 {
        return _err_target("upnp: bad urn in target", 4);
      }
      let dt = _part(rest, _UPNP_COLON, 2);
      if !_valid_urn_token(dt) {
        return _err_target("upnp: bad type in target", 4 + _part_start(rest, _UPNP_COLON, 2));
      }
      let ver = _part(rest, _UPNP_COLON, 3);
      let vp = _parse_version_parts(ver);
      if !vp.valid {
        return _err_target("upnp: bad version in target", 4 + _part_start(rest, _UPNP_COLON, 3));
      }
      var kind = UPNP_TARGET_DEVICE;
      if _str_eq_ci(word, "service") { kind = UPNP_TARGET_SERVICE; }
      return _ok_target(SsdpTarget{ kind: kind; raw: s; uuid: ""; domain: domain; class_word: word; dev_type: dt; version: ver; major: vp.major; minor: vp.minor; });
    }
    var k = 0;
    while k < c {
      let p = _part(rest, _UPNP_COLON, k);
      if string.str_len(p) == 0 {
        return _err_target("upnp: bad urn in target", 4);
      }
      k = k + 1;
    }
    return _ok_target(SsdpTarget{ kind: UPNP_TARGET_OTHER_URN; raw: s; uuid: ""; domain: domain; class_word: word; dev_type: ""; version: ""; major: -1; minor: -1; });
  }
  return _err_target("upnp: bad target", 0);
}

/// Split a USN (Unique Service Name).
///
/// Recognised forms (left/right of an optional single "::"):
/// "uuid:<id>", "uuid:<id>::urn:...", "uuid:<id>::upnp:rootdevice" and a
/// bare "urn:...". The device UUID must be in 8-4-4-4-12 hex form and the
/// URNs must pass the structural urn check. More than one "::" and every
/// other shape are Err with the offset of the offending part.
/// Complexity: O(length).
pub fn usn_split(usn: Str) -> Result[UsnSplit, SsdpError] {
  let n = string.str_len(usn);
  if n == 0 {
    return _err_usn("upnp: empty USN", 0);
  }
  var sep = -1;
  var second = -1;
  var q = 0;
  while q + 1 < n {
    if _str_byte(usn, q) == _UPNP_COLON && _str_byte(usn, q + 1) == _UPNP_COLON {
      if sep < 0 {
        sep = q;
      } else {
        second = q;
      }
    }
    q = q + 1;
  }
  if second >= 0 {
    return _err_usn("upnp: bad USN", second);
  }
  var left = usn;
  var right = "";
  if sep >= 0 {
    left = string.str_slice(usn, 0, sep);
    right = string.str_slice(usn, sep + 2, n);
  }
  let left_is_uuid = _starts_ci(left, "uuid:");
  let left_is_urn = _starts_ci(left, "urn:");
  if left_is_uuid {
    let id = string.str_slice(left, 5, string.str_len(left));
    if !upnp_is_device_uuid(id) {
      return _err_usn("upnp: bad uuid in USN", 5);
    }
  }
  if !left_is_uuid && !left_is_urn {
    return _err_usn("upnp: bad USN", 0);
  }
  if string.str_len(right) == 0 {
    if left_is_uuid {
      let id2 = string.str_slice(left, 5, string.str_len(left));
      return _ok_usn(UsnSplit{ kind: UPNP_USN_UUID; uuid: left; device_uuid: id2; urn: ""; suffix: ""; });
    }
    if !_urn_valid(left) {
      return _err_usn("upnp: bad urn in USN", 0);
    }
    return _ok_usn(UsnSplit{ kind: UPNP_USN_URN; uuid: ""; device_uuid: ""; urn: left; suffix: ""; });
  }
  if !left_is_uuid {
    return _err_usn("upnp: bad USN", 0);
  }
  let id3 = string.str_slice(left, 5, string.str_len(left));
  if _str_eq_ci(right, "upnp:rootdevice") {
    return _ok_usn(UsnSplit{ kind: UPNP_USN_UUID_ROOTDEVICE; uuid: left; device_uuid: id3; urn: ""; suffix: right; });
  }
  if !_starts_ci(right, "urn:") {
    return _err_usn("upnp: bad USN", sep + 2);
  }
  if !_urn_valid(right) {
    return _err_usn("upnp: bad urn in USN", sep + 2);
  }
  return _ok_usn(UsnSplit{ kind: UPNP_USN_UUID_URN; uuid: left; device_uuid: id3; urn: right; suffix: right; });
}

// --------------------------------------------------
//  Line scanning and header block
// --------------------------------------------------

// Scan one line beginning at `pos`. Returns the index of the first CR of its
// terminating CRLF; when the line runs to the end of the buffer without a
// CRLF, returns data.len() (the final line of a datagram may be
// unterminated). Rejects bare CR, bare LF, NUL, other C0 control bytes and
// DEL, reporting the offending offset.
fn _scan_line(data: &Vec[UInt8], pos: Int) -> Result[Int, SsdpError] {
  let len = data.len();
  var p = pos;
  while p < len {
    let b = _byte(data, p);
    if b == _UPNP_CR {
      if p + 1 < len {
        if _byte(data, p + 1) == _UPNP_LF {
          return _ok_int(p);
        }
      }
      return _err_int("upnp: bare CR", p);
    }
    if b == _UPNP_LF {
      return _err_int("upnp: bare LF", p);
    }
    if b == _UPNP_DEL {
      return _err_int("upnp: control character", p);
    }
    if b < _UPNP_SP && b != _UPNP_TAB {
      return _err_int("upnp: control character", p);
    }
    p = p + 1;
  }
  return _ok_int(len);
}

// Parse the header block starting at `pos_in` and ending at the first empty
// line or the end of the buffer. The three parallel vectors are extended in
// lockstep, one iteration per header line.
fn _parse_header_block(data: &Vec[UInt8], pos_in: Int) -> Result[SsdpHeaderBlock, SsdpError] {
  let len = data.len();
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var offsets = Vec[Int].new();
  var pos = pos_in;
  var end_offset = len;
  var done = false;
  while !done && pos < len {
    let lr = _scan_line(data, pos);
    if !lr.is_ok {
      let e: SsdpError = lr.error;
      return _err_block(e.message, e.offset);
    }
    let le: Int = lr.value;
    if le == pos {
      end_offset = pos;
      done = true;
    } else {
      let line = _slice_str(data, pos, le);
      let ln = string.str_len(line);
      var colon = -1;
      var q = 0;
      while q < ln {
        if _str_byte(line, q) == _UPNP_COLON {
          colon = q;
          break;
        }
        q = q + 1;
      }
      if colon < 0 {
        return _err_block("upnp: missing colon in header", pos + ln);
      }
      if colon == 0 {
        return _err_block("upnp: empty header name", pos);
      }
      var k = 0;
      while k < colon {
        let b = _str_byte(line, k);
        if !_is_tchar(b) {
          return _err_block("upnp: bad header name", pos + k);
        }
        k = k + 1;
      }
      let name = string.str_slice(line, 0, colon);
      let value = string.str_trim(string.str_slice(line, colon + 1, ln));
      names.push(name);
      values.push(value);
      offsets.push(pos);
      if le + 2 <= len {
        pos = le + 2;
      } else {
        pos = len;
      }
    }
  }
  return _ok_block(SsdpHeaderBlock{ names: names; values: values; offsets: offsets; end_offset: end_offset; });
}

// Index of the first header whose name equals `name` case-insensitively, or
// -1 when absent (including a malformed block whose vectors drifted apart).
fn _block_index(block: &SsdpHeaderBlock, name: Str) -> Int {
  if block.values.len() != block.names.len() { return -1; }
  var i = 0;
  while i < block.names.len() {
    let n: Str = block.names[i];
    if compare.str_compare_ignore_case(n, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Value of header `idx`, or "" when out of range.
fn _block_value(block: &SsdpHeaderBlock, idx: Int) -> Str {
  if idx < 0 { return ""; }
  if idx >= block.names.len() { return ""; }
  if block.values.len() != block.names.len() { return ""; }
  let v: Str = block.values[idx];
  return v;
}

// Source offset of header `idx`, or -1 when out of range.
fn _block_offset(block: &SsdpHeaderBlock, idx: Int) -> Int {
  if idx < 0 { return -1; }
  if idx >= block.offsets.len() { return -1; }
  let v: Int = block.offsets[idx];
  return v;
}

// Require a header by name: the index on success, otherwise
// "upnp: missing required header <what>" at the end-of-headers offset.
fn _require_block(block: &SsdpHeaderBlock, name: Str, what: Str, eoh: Int) -> Result[Int, SsdpError] {
  let idx = _block_index(block, name);
  if idx < 0 {
    return _err_int("upnp: missing required header " + what, eoh);
  }
  return _ok_int(idx);
}

// Optional integer header: -1 when absent; "upnp: bad <name>" at the header
// offset when present but empty/malformed/above `max`.
fn _optional_uint(block: &SsdpHeaderBlock, name: Str, idx: Int, max: Int) -> Result[Int, SsdpError] {
  if idx < 0 { return _ok_int(-1); }
  let s: Str = _block_value(block, idx);
  let v = _digits_value(s);
  if v < 0 || v > max {
    return _err_int("upnp: bad " + name, _block_offset(block, idx));
  }
  return _ok_int(v);
}

// Required integer header: the value, or the missing-header error, or
// "upnp: bad <name>" at the header offset.
fn _require_uint(block: &SsdpHeaderBlock, name: Str, what: Str, max: Int, eoh: Int) -> Result[Int, SsdpError] {
  let ir = _require_block(block, name, what, eoh);
  if !ir.is_ok {
    let e: SsdpError = ir.error;
    return _err_int(e.message, e.offset);
  }
  let idx: Int = ir.value;
  let s: Str = _block_value(block, idx);
  let v = _digits_value(s);
  if v < 0 || v > max {
    return _err_int("upnp: bad " + name, _block_offset(block, idx));
  }
  return _ok_int(v);
}

// Value of a "max-age=N" CACHE-CONTROL directive (case-insensitive prefix,
// optional ", ..." tail, trimmed); -1 when malformed or absent.
fn _max_age_of(cc: Str) -> Int {
  let low = string.str_lower(string.str_trim(cc));
  if !string.str_starts_with(low, "max-age=") { return -1; }
  let v = string.str_slice(low, 8, string.str_len(low));
  let only = _part(v, _UPNP_COMMA, 0);
  return _digits_value(string.str_trim(only));
}

// --------------------------------------------------
//  Typed extraction
// --------------------------------------------------

// M-SEARCH: HOST, MAN ("ssdp:discover"), MX (1..5) and ST are required;
// USER-AGENT is optional.
fn _extract_msearch(block: &SsdpHeaderBlock, eoh: Int) -> Result[SsdpFields, SsdpError] {
  let hr = _require_block(block, "HOST", "HOST", eoh);
  if !hr.is_ok {
    let e: SsdpError = hr.error;
    return _err_fields(e.message, e.offset);
  }
  let host_i: Int = hr.value;
  let mr = _require_block(block, "MAN", "MAN", eoh);
  if !mr.is_ok {
    let e: SsdpError = mr.error;
    return _err_fields(e.message, e.offset);
  }
  let man_i: Int = mr.value;
  let xr = _require_block(block, "MX", "MX", eoh);
  if !xr.is_ok {
    let e: SsdpError = xr.error;
    return _err_fields(e.message, e.offset);
  }
  let mx_i: Int = xr.value;
  let sr = _require_block(block, "ST", "ST", eoh);
  if !sr.is_ok {
    let e: SsdpError = sr.error;
    return _err_fields(e.message, e.offset);
  }
  let st_i: Int = sr.value;

  let host: Str = _block_value(block, host_i);
  if string.str_len(host) == 0 {
    return _err_fields("upnp: empty HOST", _block_offset(block, host_i));
  }
  if !upnp_validate_authority(host) {
    return _err_fields("upnp: bad HOST", _block_offset(block, host_i));
  }
  let man_raw: Str = _block_value(block, man_i);
  let man = _strip_quotes(man_raw);
  if !_str_eq_ci(man, "ssdp:discover") {
    return _err_fields("upnp: bad MAN", _block_offset(block, man_i));
  }
  let mx_s: Str = _block_value(block, mx_i);
  let mx = _digits_value(mx_s);
  if mx < 1 || mx > 5 {
    return _err_fields("upnp: bad MX", _block_offset(block, mx_i));
  }
  let st: Str = _block_value(block, st_i);
  if string.str_len(st) == 0 {
    return _err_fields("upnp: empty ST", _block_offset(block, st_i));
  }
  let ctr = upnp_classify_target(st);
  if !ctr.is_ok {
    return _err_fields("upnp: bad ST", _block_offset(block, st_i));
  }
  let ua_i = _block_index(block, "USER-AGENT");
  let ua: Str = _block_value(block, ua_i);

  return _ok_fields(SsdpFields{
    host: host;
    man: man_raw;
    mx: mx;
    st: st;
    user_agent: ua;
    nt: "";
    nts: "";
    nts_kind: -1;
    usn: "";
    location: "";
    server: "";
    date: "";
    ext: "";
    cache_control: "";
    max_age: -1;
    bootid: -1;
    configid: -1;
    searchport: -1;
  });
}

// NOTIFY: HOST, NT, NTS and USN are always required; ssdp:alive additionally
// requires CACHE-CONTROL (max-age >= 1) and LOCATION; ssdp:update requires
// BOOTID.UPNP.ORG.
fn _extract_notify(block: &SsdpHeaderBlock, eoh: Int) -> Result[SsdpFields, SsdpError] {
  let hr = _require_block(block, "HOST", "HOST", eoh);
  if !hr.is_ok {
    let e: SsdpError = hr.error;
    return _err_fields(e.message, e.offset);
  }
  let host_i: Int = hr.value;
  let nr = _require_block(block, "NT", "NT", eoh);
  if !nr.is_ok {
    let e: SsdpError = nr.error;
    return _err_fields(e.message, e.offset);
  }
  let nt_i: Int = nr.value;
  let tr = _require_block(block, "NTS", "NTS", eoh);
  if !tr.is_ok {
    let e: SsdpError = tr.error;
    return _err_fields(e.message, e.offset);
  }
  let nts_i: Int = tr.value;
  let ur = _require_block(block, "USN", "USN", eoh);
  if !ur.is_ok {
    let e: SsdpError = ur.error;
    return _err_fields(e.message, e.offset);
  }
  let usn_i: Int = ur.value;

  let host: Str = _block_value(block, host_i);
  if string.str_len(host) == 0 {
    return _err_fields("upnp: empty HOST", _block_offset(block, host_i));
  }
  if !upnp_validate_authority(host) {
    return _err_fields("upnp: bad HOST", _block_offset(block, host_i));
  }
  let nt: Str = _block_value(block, nt_i);
  if string.str_len(nt) == 0 {
    return _err_fields("upnp: empty NT", _block_offset(block, nt_i));
  }
  let ntr = upnp_classify_target(nt);
  if !ntr.is_ok {
    return _err_fields("upnp: bad NT", _block_offset(block, nt_i));
  }
  let nts: Str = _block_value(block, nts_i);
  let nts_kind = _nts_kind_of(nts);
  if nts_kind < 0 {
    return _err_fields("upnp: bad NTS", _block_offset(block, nts_i));
  }
  let usn: Str = _block_value(block, usn_i);
  let usr = usn_split(usn);
  if !usr.is_ok {
    return _err_fields("upnp: bad USN", _block_offset(block, usn_i));
  }

  let cc_i = _block_index(block, "CACHE-CONTROL");
  var cache_control = "";
  var max_age = -1;
  if cc_i >= 0 {
    cache_control = _block_value(block, cc_i);
    max_age = _max_age_of(cache_control);
    if max_age < 0 {
      return _err_fields("upnp: bad CACHE-CONTROL", _block_offset(block, cc_i));
    }
  }
  let lo_i = _block_index(block, "LOCATION");
  var location = "";
  if lo_i >= 0 {
    location = _block_value(block, lo_i);
    if string.str_len(location) > 0 {
      if !upnp_validate_location(location) {
        return _err_fields("upnp: bad LOCATION", _block_offset(block, lo_i));
      }
    }
  }
  let sv_i = _block_index(block, "SERVER");
  let server: Str = _block_value(block, sv_i);

  let bo_i = _block_index(block, "BOOTID.UPNP.ORG");
  let bor = _optional_uint(block, "BOOTID.UPNP.ORG", bo_i, _UPNP_MAX_U32);
  if !bor.is_ok {
    let e: SsdpError = bor.error;
    return _err_fields(e.message, e.offset);
  }
  let bootid: Int = bor.value;
  let co_i = _block_index(block, "CONFIGID.UPNP.ORG");
  let cor = _optional_uint(block, "CONFIGID.UPNP.ORG", co_i, _UPNP_MAX_CONFIGID);
  if !cor.is_ok {
    let e: SsdpError = cor.error;
    return _err_fields(e.message, e.offset);
  }
  let configid: Int = cor.value;
  let sp_i = _block_index(block, "SEARCHPORT.UPNP.ORG");
  let spr = _optional_uint(block, "SEARCHPORT.UPNP.ORG", sp_i, 65535);
  if !spr.is_ok {
    let e: SsdpError = spr.error;
    return _err_fields(e.message, e.offset);
  }
  let searchport: Int = spr.value;
  if sp_i >= 0 && searchport < 1 {
    return _err_fields("upnp: bad SEARCHPORT.UPNP.ORG", _block_offset(block, sp_i));
  }

  if nts_kind == UPNP_NTS_ALIVE {
    if cc_i < 0 {
      return _err_fields("upnp: missing required header CACHE-CONTROL", eoh);
    }
    if max_age < 1 {
      return _err_fields("upnp: bad CACHE-CONTROL", _block_offset(block, cc_i));
    }
    if lo_i < 0 {
      return _err_fields("upnp: missing required header LOCATION", eoh);
    }
    if string.str_len(location) == 0 {
      return _err_fields("upnp: bad LOCATION", _block_offset(block, lo_i));
    }
  }
  if nts_kind == UPNP_NTS_UPDATE {
    if bo_i < 0 {
      return _err_fields("upnp: missing required header BOOTID.UPNP.ORG", eoh);
    }
  }

  return _ok_fields(SsdpFields{
    host: host;
    man: "";
    mx: -1;
    st: "";
    user_agent: "";
    nt: nt;
    nts: nts;
    nts_kind: nts_kind;
    usn: usn;
    location: location;
    server: server;
    date: "";
    ext: "";
    cache_control: cache_control;
    max_age: max_age;
    bootid: bootid;
    configid: configid;
    searchport: searchport;
  });
}

// 200 response: CACHE-CONTROL (max-age >= 1), DATE, EXT, LOCATION, ST and
// USN are required; SERVER and the integer headers are optional.
fn _extract_response(block: &SsdpHeaderBlock, eoh: Int) -> Result[SsdpFields, SsdpError] {
  let cr = _require_block(block, "CACHE-CONTROL", "CACHE-CONTROL", eoh);
  if !cr.is_ok {
    let e: SsdpError = cr.error;
    return _err_fields(e.message, e.offset);
  }
  let cc_i: Int = cr.value;
  let dr = _require_block(block, "DATE", "DATE", eoh);
  if !dr.is_ok {
    let e: SsdpError = dr.error;
    return _err_fields(e.message, e.offset);
  }
  let date_i: Int = dr.value;
  let er = _require_block(block, "EXT", "EXT", eoh);
  if !er.is_ok {
    let e: SsdpError = er.error;
    return _err_fields(e.message, e.offset);
  }
  let ext_i: Int = er.value;
  let lr = _require_block(block, "LOCATION", "LOCATION", eoh);
  if !lr.is_ok {
    let e: SsdpError = lr.error;
    return _err_fields(e.message, e.offset);
  }
  let lo_i: Int = lr.value;
  let sr = _require_block(block, "ST", "ST", eoh);
  if !sr.is_ok {
    let e: SsdpError = sr.error;
    return _err_fields(e.message, e.offset);
  }
  let st_i: Int = sr.value;
  let ur = _require_block(block, "USN", "USN", eoh);
  if !ur.is_ok {
    let e: SsdpError = ur.error;
    return _err_fields(e.message, e.offset);
  }
  let usn_i: Int = ur.value;

  let cache_control: Str = _block_value(block, cc_i);
  let max_age = _max_age_of(cache_control);
  if max_age < 1 {
    return _err_fields("upnp: bad CACHE-CONTROL", _block_offset(block, cc_i));
  }
  let date: Str = _block_value(block, date_i);
  if !_valid_date(date) {
    return _err_fields("upnp: bad DATE", _block_offset(block, date_i));
  }
  let ext: Str = _block_value(block, ext_i);
  let location: Str = _block_value(block, lo_i);
  if !upnp_validate_location(location) {
    return _err_fields("upnp: bad LOCATION", _block_offset(block, lo_i));
  }
  let st: Str = _block_value(block, st_i);
  if string.str_len(st) == 0 {
    return _err_fields("upnp: empty ST", _block_offset(block, st_i));
  }
  let ctr = upnp_classify_target(st);
  if !ctr.is_ok {
    return _err_fields("upnp: bad ST", _block_offset(block, st_i));
  }
  let usn: Str = _block_value(block, usn_i);
  let usr = usn_split(usn);
  if !usr.is_ok {
    return _err_fields("upnp: bad USN", _block_offset(block, usn_i));
  }

  let sv_i = _block_index(block, "SERVER");
  let server: Str = _block_value(block, sv_i);
  let bo_i = _block_index(block, "BOOTID.UPNP.ORG");
  let bor = _optional_uint(block, "BOOTID.UPNP.ORG", bo_i, _UPNP_MAX_U32);
  if !bor.is_ok {
    let e: SsdpError = bor.error;
    return _err_fields(e.message, e.offset);
  }
  let bootid: Int = bor.value;
  let co_i = _block_index(block, "CONFIGID.UPNP.ORG");
  let cor = _optional_uint(block, "CONFIGID.UPNP.ORG", co_i, _UPNP_MAX_CONFIGID);
  if !cor.is_ok {
    let e: SsdpError = cor.error;
    return _err_fields(e.message, e.offset);
  }
  let configid: Int = cor.value;
  let sp_i = _block_index(block, "SEARCHPORT.UPNP.ORG");
  let spr = _optional_uint(block, "SEARCHPORT.UPNP.ORG", sp_i, 65535);
  if !spr.is_ok {
    let e: SsdpError = spr.error;
    return _err_fields(e.message, e.offset);
  }
  let searchport: Int = spr.value;
  if sp_i >= 0 && searchport < 1 {
    return _err_fields("upnp: bad SEARCHPORT.UPNP.ORG", _block_offset(block, sp_i));
  }

  return _ok_fields(SsdpFields{
    host: "";
    man: "";
    mx: -1;
    st: st;
    user_agent: "";
    nt: "";
    nts: "";
    nts_kind: -1;
    usn: usn;
    location: location;
    server: server;
    date: date;
    ext: ext;
    cache_control: cache_control;
    max_age: max_age;
    bootid: bootid;
    configid: configid;
    searchport: searchport;
  });
}

// --------------------------------------------------
//  Start line
// --------------------------------------------------

// Decode the start line: "M-SEARCH * HTTP/1.1", "NOTIFY * HTTP/1.1" or
// "HTTP/1.1 200 [reason]". Methods, the "*" target, the version and the
// status are matched exactly (request methods and HTTP versions are
// case-sensitive); the reason phrase may be empty or contain spaces.
fn _parse_start_line(line: Str, line_off: Int) -> Result[SsdpStart, SsdpError] {
  let n = string.str_len(line);
  if n == 0 {
    return _err_start("upnp: empty start line", line_off);
  }
  let t0 = _part(line, _UPNP_SP, 0);
  if _str_eq(t0, "M-SEARCH") || _str_eq(t0, "NOTIFY") {
    let segs = _part_count(line, _UPNP_SP);
    if segs != 3 {
      return _err_start("upnp: bad start line", line_off);
    }
    let target = _part(line, _UPNP_SP, 1);
    if !_str_eq(target, "*") {
      return _err_start("upnp: bad target", line_off + _part_start(line, _UPNP_SP, 1));
    }
    let version = _part(line, _UPNP_SP, 2);
    if !_str_eq(version, "HTTP/1.1") {
      return _err_start("upnp: bad version", line_off + _part_start(line, _UPNP_SP, 2));
    }
    var kind = UPNP_KIND_MSEARCH;
    if _str_eq(t0, "NOTIFY") { kind = UPNP_KIND_NOTIFY; }
    return _ok_start(SsdpStart{ kind: kind; method: t0; target: "*"; version: "HTTP/1.1"; status: -1; reason: ""; });
  }
  if _str_eq(t0, "HTTP/1.1") {
    let segs2 = _part_count(line, _UPNP_SP);
    if segs2 < 2 {
      return _err_start("upnp: bad start line", line_off);
    }
    let status_s = _part(line, _UPNP_SP, 1);
    let status = _digits_value(status_s);
    if string.str_len(status_s) != 3 || status != 200 {
      return _err_start("upnp: bad status", line_off + _part_start(line, _UPNP_SP, 1));
    }
    var reason = "";
    if segs2 >= 3 {
      reason = string.str_trim(string.str_slice(line, _part_start(line, _UPNP_SP, 2), n));
    }
    return _ok_start(SsdpStart{ kind: UPNP_KIND_RESPONSE; method: "HTTP/1.1"; target: ""; version: "HTTP/1.1"; status: 200; reason: reason; });
  }
  return _err_start("upnp: bad start line", line_off);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one SSDP message from a datagram buffer.
///
/// Checks, in order: a nonempty message of at most UPNP_MAX_MESSAGE bytes;
/// a well-formed CRLF-terminated start line (bare CR/LF, NUL and other
/// control bytes are rejected with their offset); a header block of
/// "Name: value" lines terminated by a blank line or the end of the buffer;
/// then the typed extraction for the message kind. Header names are matched
/// case-insensitively and kept verbatim in `names`; bytes after the
/// end-of-headers blank line are ignored.
///
/// Errors (stable message, offset in the input):
///   * "upnp: empty message", "upnp: message too large";
///   * "upnp: bare CR", "upnp: bare LF", "upnp: control character";
///   * "upnp: empty start line", "upnp: bad start line", "upnp: bad target",
///     "upnp: bad version", "upnp: bad status";
///   * "upnp: missing colon in header", "upnp: empty header name",
///     "upnp: bad header name";
///   * "upnp: missing required header <name>";
///   * "upnp: empty HOST", "upnp: bad HOST", "upnp: bad MAN", "upnp: bad MX",
///     "upnp: empty ST", "upnp: bad ST", "upnp: empty NT", "upnp: bad NT",
///     "upnp: bad NTS", "upnp: bad USN", "upnp: bad CACHE-CONTROL",
///     "upnp: bad LOCATION", "upnp: bad DATE", "upnp: bad BOOTID.UPNP.ORG",
///     "upnp: bad CONFIGID.UPNP.ORG", "upnp: bad SEARCHPORT.UPNP.ORG".
/// Complexity: O(message length).
pub fn upnp_parse(data: &Vec[UInt8]) -> Result[SsdpMessage, SsdpError] {
  let len = data.len();
  if len == 0 {
    return _err_msg("upnp: empty message", 0);
  }
  if len > UPNP_MAX_MESSAGE {
    return _err_msg("upnp: message too large", len);
  }
  let lr = _scan_line(data, 0);
  if !lr.is_ok {
    let e: SsdpError = lr.error;
    return _err_msg(e.message, e.offset);
  }
  let le: Int = lr.value;
  let start_line = _slice_str(data, 0, le);
  let sr = _parse_start_line(start_line, 0);
  if !sr.is_ok {
    let e: SsdpError = sr.error;
    return _err_msg(e.message, e.offset);
  }
  let st: SsdpStart = sr.value;
  var pos = len;
  if le + 2 <= len {
    pos = le + 2;
  }
  let block_r = _parse_header_block(data, pos);
  if !block_r.is_ok {
    let e: SsdpError = block_r.error;
    return _err_msg(e.message, e.offset);
  }
  let block: SsdpHeaderBlock = block_r.value;
  var fields_r = _extract_msearch(&block, block.end_offset);
  if st.kind == UPNP_KIND_NOTIFY {
    fields_r = _extract_notify(&block, block.end_offset);
  }
  if st.kind == UPNP_KIND_RESPONSE {
    fields_r = _extract_response(&block, block.end_offset);
  }
  if !fields_r.is_ok {
    let e: SsdpError = fields_r.error;
    return _err_msg(e.message, e.offset);
  }
  let f: SsdpFields = fields_r.value;
  let m = SsdpMessage{
    kind: st.kind;
    start_line: start_line;
    method: st.method;
    target: st.target;
    version: st.version;
    status: st.status;
    reason: st.reason;
    names: block.names;
    values: block.values;
    header_offsets: block.offsets;
    host: f.host;
    man: f.man;
    mx: f.mx;
    st: f.st;
    user_agent: f.user_agent;
    nt: f.nt;
    nts: f.nts;
    nts_kind: f.nts_kind;
    usn: f.usn;
    location: f.location;
    server: f.server;
    date: f.date;
    ext: f.ext;
    cache_control: f.cache_control;
    max_age: f.max_age;
    bootid: f.bootid;
    configid: f.configid;
    searchport: f.searchport;
  };
  return _ok_msg(m);
}

/// Parse an SSDP message held in a Str. The bytes are taken verbatim (one
/// byte per string byte) and handed to upnp_parse. Complexity: O(length).
pub fn upnp_parse_text(s: Str) -> Result[SsdpMessage, SsdpError] {
  let data: Vec[UInt8] = _str_bytes(s);
  return upnp_parse(&data);
}

// --------------------------------------------------
//  Header access
// --------------------------------------------------

/// Number of headers in the message. Complexity: O(1).
pub fn upnp_header_count(m: &SsdpMessage) -> Int {
  return m.names.len();
}

// Index of the first header named `name` (case-insensitive), or -1.
fn _header_index(m: &SsdpMessage, name: Str) -> Int {
  if m.values.len() != m.names.len() { return -1; }
  var i = 0;
  while i < m.names.len() {
    let n: Str = m.names[i];
    if compare.str_compare_ignore_case(n, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Value of the first header named `name` (case-insensitive), with
/// surrounding whitespace already trimmed; "" when absent. Complexity:
/// O(headers).
pub fn upnp_header(m: &SsdpMessage, name: Str) -> Str {
  let i = _header_index(m, name);
  if i < 0 { return ""; }
  let v: Str = m.values[i];
  return v;
}

/// True when a header named `name` (case-insensitive) is present.
/// Complexity: O(headers).
pub fn upnp_has_header(m: &SsdpMessage, name: Str) -> Bool {
  return _header_index(m, name) >= 0;
}

/// Name of header `i` exactly as sent, or "" when out of range.
/// Complexity: O(1).
pub fn upnp_header_name(m: &SsdpMessage, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= m.names.len() { return ""; }
  let n: Str = m.names[i];
  return n;
}

/// Trimmed value of header `i`, or "" when out of range. Complexity: O(1).
pub fn upnp_header_value(m: &SsdpMessage, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= m.values.len() { return ""; }
  let v: Str = m.values[i];
  return v;
}

/// Absolute offset of header `i`'s first byte, or -1 when out of range.
/// Complexity: O(1).
pub fn upnp_header_offset(m: &SsdpMessage, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= m.header_offsets.len() { return -1; }
  let v: Int = m.header_offsets[i];
  return v;
}

// --------------------------------------------------
//  Serialisation
// --------------------------------------------------

// Append one canonical "Name: value\r\n" line to a Str.
fn _append_header(out: Str, name: Str, value: Str) -> Str {
  return out + name + ": " + value + "\r\n";
}

/// Serialise an M-SEARCH request with canonical header names and CRLF line
/// endings:
///
///   M-SEARCH * HTTP/1.1 CRLF
///   HOST: <host> CRLF
///   MAN: "ssdp:discover" CRLF
///   MX: <mx> CRLF
///   ST: <st> CRLF
///   [USER-AGENT: <user_agent> CRLF]
///   CRLF
///
/// `host` must pass upnp_validate_authority, `mx` must be 1..5, `st` must
/// classify (upnp_classify_target) and `user_agent` may be empty (the header
/// is then omitted). Errors carry offset -1. Complexity: O(length).
pub fn upnp_build_msearch(host: Str, mx: Int, st: Str, user_agent: Str) -> Result[Vec[UInt8], SsdpError] {
  if string.str_len(host) == 0 {
    return _err_bytes("upnp: empty HOST", -1);
  }
  if !upnp_validate_authority(host) {
    return _err_bytes("upnp: bad HOST", -1);
  }
  if mx < 1 || mx > 5 {
    return _err_bytes("upnp: bad MX", -1);
  }
  if string.str_len(st) == 0 {
    return _err_bytes("upnp: empty ST", -1);
  }
  let ctr = upnp_classify_target(st);
  if !ctr.is_ok {
    return _err_bytes("upnp: bad ST", -1);
  }
  var out = "M-SEARCH * HTTP/1.1\r\n";
  out = _append_header(out, "HOST", host);
  out = _append_header(out, "MAN", "\"ssdp:discover\"");
  out = _append_header(out, "MX", int_to_string(mx));
  out = _append_header(out, "ST", st);
  if string.str_len(user_agent) > 0 {
    out = _append_header(out, "USER-AGENT", user_agent);
  }
  out = out + "\r\n";
  let bytes: Vec[UInt8] = _str_bytes(out);
  return _ok_bytes(bytes);
}

/// Serialise a NOTIFY ssdp:alive notification with canonical header names
/// and CRLF line endings:
///
///   NOTIFY * HTTP/1.1 CRLF
///   HOST: <host> CRLF
///   CACHE-CONTROL: max-age=<max_age> CRLF
///   LOCATION: <location> CRLF
///   NT: <nt> CRLF
///   NTS: ssdp:alive CRLF
///   [SERVER: <server> CRLF]
///   USN: <usn> CRLF
///   [BOOTID.UPNP.ORG: <bootid> CRLF]
///   [CONFIGID.UPNP.ORG: <configid> CRLF]
///   CRLF
///
/// `host` must pass upnp_validate_authority, `max_age` must be 1..2^31-1,
/// `location` must pass upnp_validate_location, `nt` must classify, `usn`
/// must pass usn_split, `server` may be empty (header omitted) and a
/// negative `bootid` or `configid` omits that header (otherwise the value
/// must fit the UDA bounds: BOOTID 32-bit, CONFIGID 24-bit). Errors carry
/// offset -1. Complexity: O(length).
pub fn upnp_build_notify_alive(host: Str, max_age: Int, location: Str, nt: Str, usn: Str, server: Str, bootid: Int, configid: Int) -> Result[Vec[UInt8], SsdpError] {
  if string.str_len(host) == 0 {
    return _err_bytes("upnp: empty HOST", -1);
  }
  if !upnp_validate_authority(host) {
    return _err_bytes("upnp: bad HOST", -1);
  }
  if max_age < 1 || max_age > 2147483647 {
    return _err_bytes("upnp: bad CACHE-CONTROL", -1);
  }
  if !upnp_validate_location(location) {
    return _err_bytes("upnp: bad LOCATION", -1);
  }
  if string.str_len(nt) == 0 {
    return _err_bytes("upnp: empty NT", -1);
  }
  let ntr = upnp_classify_target(nt);
  if !ntr.is_ok {
    return _err_bytes("upnp: bad NT", -1);
  }
  if string.str_len(usn) == 0 {
    return _err_bytes("upnp: empty USN", -1);
  }
  let usr = usn_split(usn);
  if !usr.is_ok {
    return _err_bytes("upnp: bad USN", -1);
  }
  if bootid > _UPNP_MAX_U32 {
    return _err_bytes("upnp: bad BOOTID.UPNP.ORG", -1);
  }
  if configid > _UPNP_MAX_CONFIGID {
    return _err_bytes("upnp: bad CONFIGID.UPNP.ORG", -1);
  }
  var out = "NOTIFY * HTTP/1.1\r\n";
  out = _append_header(out, "HOST", host);
  out = _append_header(out, "CACHE-CONTROL", "max-age=" + int_to_string(max_age));
  out = _append_header(out, "LOCATION", location);
  out = _append_header(out, "NT", nt);
  out = _append_header(out, "NTS", "ssdp:alive");
  if string.str_len(server) > 0 {
    out = _append_header(out, "SERVER", server);
  }
  out = _append_header(out, "USN", usn);
  if bootid >= 0 {
    out = _append_header(out, "BOOTID.UPNP.ORG", int_to_string(bootid));
  }
  if configid >= 0 {
    out = _append_header(out, "CONFIGID.UPNP.ORG", int_to_string(configid));
  }
  out = out + "\r\n";
  let bytes: Vec[UInt8] = _str_bytes(out);
  return _ok_bytes(bytes);
}

// --------------------------------------------------
//  Name helpers
// --------------------------------------------------

/// Name of a message kind: "m-search", "notify", "response" or "unknown".
/// Complexity: O(1).
pub fn upnp_msg_kind_name(kind: Int) -> Str {
  if kind == UPNP_KIND_MSEARCH { return "m-search"; }
  if kind == UPNP_KIND_NOTIFY { return "notify"; }
  if kind == UPNP_KIND_RESPONSE { return "response"; }
  return "unknown";
}

/// Name of an NTS kind: "ssdp:alive", "ssdp:byebye", "ssdp:update" or
/// "unknown". Complexity: O(1).
pub fn upnp_nts_name(kind: Int) -> Str {
  if kind == UPNP_NTS_ALIVE { return "ssdp:alive"; }
  if kind == UPNP_NTS_BYEBYE { return "ssdp:byebye"; }
  if kind == UPNP_NTS_UPDATE { return "ssdp:update"; }
  return "unknown";
}

/// Name of a target kind: "ssdp:all", "upnp:rootdevice", "uuid", "device",
/// "service", "urn" or "unknown". Complexity: O(1).
pub fn upnp_target_name(kind: Int) -> Str {
  if kind == UPNP_TARGET_SSDP_ALL { return "ssdp:all"; }
  if kind == UPNP_TARGET_ROOTDEVICE { return "upnp:rootdevice"; }
  if kind == UPNP_TARGET_UUID { return "uuid"; }
  if kind == UPNP_TARGET_DEVICE { return "device"; }
  if kind == UPNP_TARGET_SERVICE { return "service"; }
  if kind == UPNP_TARGET_OTHER_URN { return "urn"; }
  return "unknown";
}

/// Name of a USN kind: "uuid", "uuid+urn", "uuid+rootdevice", "urn" or
/// "unknown". Complexity: O(1).
pub fn upnp_usn_kind_name(kind: Int) -> Str {
  if kind == UPNP_USN_UUID { return "uuid"; }
  if kind == UPNP_USN_UUID_URN { return "uuid+urn"; }
  if kind == UPNP_USN_UUID_ROOTDEVICE { return "uuid+rootdevice"; }
  if kind == UPNP_USN_URN { return "urn"; }
  return "unknown";
}

/// Canonical header-name casing for the SSDP headers this package knows
/// ("host" -> "HOST", "bootid.upnp.org" -> "BOOTID.UPNP.ORG", ...). Unknown
/// names are returned unchanged, so serialisers can preserve caller casing.
/// Complexity: O(1).
pub fn upnp_canonical_header_name(name: Str) -> Str {
  if _str_eq_ci(name, "host") { return "HOST"; }
  if _str_eq_ci(name, "man") { return "MAN"; }
  if _str_eq_ci(name, "mx") { return "MX"; }
  if _str_eq_ci(name, "st") { return "ST"; }
  if _str_eq_ci(name, "user-agent") { return "USER-AGENT"; }
  if _str_eq_ci(name, "cache-control") { return "CACHE-CONTROL"; }
  if _str_eq_ci(name, "date") { return "DATE"; }
  if _str_eq_ci(name, "ext") { return "EXT"; }
  if _str_eq_ci(name, "location") { return "LOCATION"; }
  if _str_eq_ci(name, "nt") { return "NT"; }
  if _str_eq_ci(name, "nts") { return "NTS"; }
  if _str_eq_ci(name, "server") { return "SERVER"; }
  if _str_eq_ci(name, "usn") { return "USN"; }
  if _str_eq_ci(name, "bootid.upnp.org") { return "BOOTID.UPNP.ORG"; }
  if _str_eq_ci(name, "configid.upnp.org") { return "CONFIGID.UPNP.ORG"; }
  if _str_eq_ci(name, "searchport.upnp.org") { return "SEARCHPORT.UPNP.ORG"; }
  return name;
}
