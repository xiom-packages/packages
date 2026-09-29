// XIOM -- xiom.sectest: HTTP security-header verification
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no network.
//
// A header-block parser and a deterministic checker for the documented
// security-header policy in SPEC.md. It reads a block of "Name: value" lines
// (an HTTP response header section), stores it as flat parallel vectors, and
// reports findings with a rule id, a severity ("high", "medium", "low",
// "info") and a stable message, in a fixed rule order.
//
// The package never sends a request, never follows redirects and never
// validates certificates: it verifies headers a caller already captured.
// Only the `headers` branch of the placeholder inventory is implemented;
// fuzzing, TLS scanning and payload generation are explicit non-goals.
//
// Language notes (XIOM v0.61.3): free functions only; flat parallel Vecs
// instead of Vec[StructType]; Str equality goes through
// xiom.string.compare.str_compare; every element read is bound to a typed
// local first; Ok/Err are constructed only in the leaf helpers
// _ok_headers/_err_headers.

module xiom.sectest

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(h) for Result[HeaderSet, Str].
fn _ok_headers(h: HeaderSet) -> Result[HeaderSet, Str] {
  return Ok(h);
}

// Err(m) for Result[HeaderSet, Str].
fn _err_headers(m: Str) -> Result[HeaderSet, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (all ASCII)
// --------------------------------------------------

const _ST_TAB: UInt8 = 9u8;
const _ST_LF: UInt8 = 10u8;
const _ST_CR: UInt8 = 13u8;
const _ST_SPACE: UInt8 = 32u8;
const _ST_COLON: UInt8 = 58u8;
const _ST_DIGIT_0: UInt8 = 48u8;
const _ST_DIGIT_9: UInt8 = 57u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed header block: names and values are index-aligned parallel
/// vectors in document order. Names are stored verbatim (trimmed) and are
/// matched case-insensitively by the lookups; values are trimmed and kept
/// byte-exact otherwise. Duplicate names are preserved: the first occurrence
/// is what the lookups return, and header_count_named reports how many there
/// are.
pub type HeaderSet = {
  names: Vec[Str];
  values: Vec[Str];
}

/// The result of a header policy check: one index-aligned entry per finding,
/// in the fixed rule order documented in SPEC.md. severity is one of "high",
/// "medium", "low" or "info"; rule is a short stable identifier; message is
/// the deterministic human-readable text.
pub type SectestReport = {
  rules: Vec[Str];
  severities: Vec[Str];
  messages: Vec[Str];
}

// --------------------------------------------------
//  Small text helpers
// --------------------------------------------------

// Drop leading and trailing ASCII spaces and tabs from `s`.
fn _trim_ws(s: Str) -> Str {
  var a = 0;
  let n = s.len();
  while a < n {
    let b = string.byte_at(s, a);
    if b != _ST_SPACE && b != _ST_TAB {
      break;
    }
    a = a + 1;
  }
  var e = n;
  while e > a {
    let b = string.byte_at(s, e - 1);
    if b != _ST_SPACE && b != _ST_TAB {
      break;
    }
    e = e - 1;
  }
  return string.str_slice(s, a, e);
}

// Case-insensitive ASCII equality.
fn _eq_ci(a: Str, b: Str) -> Bool {
  return compare.str_compare(string.str_lower(a), string.str_lower(b)) == 0;
}

// Parse a digits-only string into a non-negative Int; -1 when empty, not all
// digits, or above the overflow guard.
fn _parse_uint(s: Str) -> Int {
  let n = s.len();
  if n == 0 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b < _ST_DIGIT_0 || b > _ST_DIGIT_9 {
      return -1;
    }
    v = v * 10 + (((b as Int) & 0xFF) - 48);
    if v > 1000000000 {
      return -1;
    }
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Header parsing
// --------------------------------------------------

/// Parse a header block: one "Name: value" per line, LF or CRLF terminated.
/// Blank lines are skipped, surrounding SP/TAB is trimmed from names and
/// values, and a value may be empty. Obs-fold continuation lines (a line
/// starting with SP/TAB) are rejected, not joined.
/// Params: text - the header block (no status line).
/// Returns: Ok(HeaderSet) in document order; "" yields zero headers.
/// Error case: Err("sectest: malformed header line <n>") when a non-blank
/// line has no colon or an empty name (1-based line number);
/// Err("sectest: folded header line <n>") for a continuation line.
/// Complexity: O(input length).
pub fn sectest_headers_parse(text: Str) -> Result[HeaderSet, Str] {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  let n = text.len();
  var start = 0;
  var line_no = 1;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(text, i) == _ST_LF {
      var line = string.str_slice(text, start, i);
      let raw = line.len();
      if raw > 0 && string.byte_at(line, raw - 1) == _ST_CR {
        line = string.str_slice(line, 0, raw - 1);
      }
      let trimmed = _trim_ws(line);
      if trimmed.len() > 0 {
        let first = string.byte_at(line, 0);
        if first == _ST_SPACE || first == _ST_TAB {
          return _err_headers("sectest: folded header line " + int_to_string(line_no));
        }
        var colon = -1;
        var k = 0;
        while k < trimmed.len() {
          if string.byte_at(trimmed, k) == _ST_COLON {
            colon = k;
            break;
          }
          k = k + 1;
        }
        if colon < 0 {
          return _err_headers("sectest: malformed header line " + int_to_string(line_no));
        }
        let name = _trim_ws(string.str_slice(trimmed, 0, colon));
        if name.len() == 0 {
          return _err_headers("sectest: malformed header line " + int_to_string(line_no));
        }
        let value = _trim_ws(string.str_slice(trimmed, colon + 1, trimmed.len()));
        names.push(name);
        values.push(value);
      }
      start = i + 1;
      line_no = line_no + 1;
    }
    i = i + 1;
  }
  return _ok_headers(HeaderSet{ names: names; values: values; });
}

// Number of index-aligned headers.
fn _header_count(h: &HeaderSet) -> Int {
  var n = h.names.len();
  if h.values.len() < n {
    n = h.values.len();
  }
  return n;
}

/// Number of headers in the block.
/// Params: h - the header set.
/// Returns: the count; 0 for an empty block.
/// Error case: none.
/// Complexity: O(1).
pub fn sectest_header_count(h: &HeaderSet) -> Int {
  return _header_count(h);
}

/// Name of header `i` as stored (trimmed, original case).
/// Params: h - the header set; i - the zero-based index.
/// Returns: the name; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sectest_header_name(h: &HeaderSet, i: Int) -> Str {
  if i < 0 || i >= _header_count(h) {
    return "";
  }
  let v: Str = h.names[i];
  return v;
}

/// Value of header `i` as stored (trimmed; may be empty).
/// Params: h - the header set; i - the zero-based index.
/// Returns: the value; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sectest_header_value(h: &HeaderSet, i: Int) -> Str {
  if i < 0 || i >= _header_count(h) {
    return "";
  }
  let v: Str = h.values[i];
  return v;
}

/// First value of a header name, matched case-insensitively.
/// Params: h - the header set; name - the header name.
/// Returns: the first matching value; "" when the header is absent (an
/// absent header and an empty value are not distinguished by this accessor;
/// use sectest_header_count_named to tell them apart).
/// Error case: none.
/// Complexity: O(headers).
pub fn sectest_header_get(h: &HeaderSet, name: Str) -> Str {
  var i = 0;
  let n = _header_count(h);
  while i < n {
    let cur: Str = h.names[i];
    if _eq_ci(cur, name) {
      let v: Str = h.values[i];
      return v;
    }
    i = i + 1;
  }
  return "";
}

/// Number of headers with the given name, matched case-insensitively.
/// Params: h - the header set; name - the header name.
/// Returns: the count; 0 when absent.
/// Error case: none.
/// Complexity: O(headers).
pub fn sectest_header_count_named(h: &HeaderSet, name: Str) -> Int {
  var c = 0;
  var i = 0;
  let n = _header_count(h);
  while i < n {
    let cur: Str = h.names[i];
    if _eq_ci(cur, name) {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

// --------------------------------------------------
//  Findings
// --------------------------------------------------

// Append one finding to the parallel report vectors.
fn _finding(rules: &mut Vec[Str], severities: &mut Vec[Str], messages: &mut Vec[Str], rule: Str, sev: Str, msg: Str) {
  rules.push(rule);
  severities.push(sev);
  messages.push(msg);
}

// True when `value` contains the case-insensitive token `token`.
fn _has_token_ci(value: Str, token: Str) -> Bool {
  return string.str_contains(string.str_lower(value), token);
}

// max-age value of a Strict-Transport-Security header: >= 0 when present and
// parseable, -1 when the directive is absent, -2 when it is malformed.
fn _hsts_max_age(value: Str) -> Int {
  let lv = string.str_lower(value);
  let n = lv.len();
  var i = 0;
  while i + 7 <= n {
    let piece = string.str_slice(lv, i, i + 7);
    if compare.str_compare(piece, "max-age") == 0 {
      var k = i + 7;
      while k < n {
        let b = string.byte_at(lv, k);
        if b != _ST_SPACE && b != _ST_TAB {
          break;
        }
        k = k + 1;
      }
      if k >= n || string.byte_at(lv, k) != 61u8 {
        return -2;
      }
      k = k + 1;
      while k < n {
        let b = string.byte_at(lv, k);
        if b != _ST_SPACE && b != _ST_TAB {
          break;
        }
        k = k + 1;
      }
      var e = k;
      while e < n {
        let b = string.byte_at(lv, e);
        if b < _ST_DIGIT_0 || b > _ST_DIGIT_9 {
          break;
        }
        e = e + 1;
      }
      if e == k {
        return -2;
      }
      let parsed = _parse_uint(string.str_slice(lv, k, e));
      if parsed < 0 {
        return -2;
      }
      return parsed;
    }
    i = i + 1;
  }
  return -1;
}

// True when a Referrer-Policy value is one of the documented tokens.
fn _referrer_ok(value: Str) -> Bool {
  let lv = string.str_lower(value);
  if compare.str_compare(lv, "no-referrer") == 0 {
    return true;
  }
  if compare.str_compare(lv, "no-referrer-when-downgrade") == 0 {
    return true;
  }
  if compare.str_compare(lv, "origin") == 0 {
    return true;
  }
  if compare.str_compare(lv, "origin-when-cross-origin") == 0 {
    return true;
  }
  if compare.str_compare(lv, "same-origin") == 0 {
    return true;
  }
  if compare.str_compare(lv, "strict-origin") == 0 {
    return true;
  }
  if compare.str_compare(lv, "strict-origin-when-cross-origin") == 0 {
    return true;
  }
  return compare.str_compare(lv, "unsafe-url") == 0;
}

// True when an X-Frame-Options value is DENY or SAMEORIGIN.
fn _xfo_ok(value: Str) -> Bool {
  let uv = string.str_upper(value);
  if compare.str_compare(uv, "DENY") == 0 {
    return true;
  }
  return compare.str_compare(uv, "SAMEORIGIN") == 0;
}

/// Check a header block against the documented security-header policy.
/// Params: h - the header set.
/// Returns: a SectestReport with the findings in the fixed rule order
/// (hsts, csp, x-content-type-options, x-frame-options, referrer-policy,
/// permissions-policy, x-xss-protection, disclosure); an empty report means
/// the block satisfies every documented rule. The exact per-rule conditions
/// and messages are in SPEC.md section 4.
/// Error case: none.
/// Complexity: O(headers * value length).
pub fn sectest_check(h: &HeaderSet) -> SectestReport {
  var rules = Vec[Str].new();
  var severities = Vec[Str].new();
  var messages = Vec[Str].new();

  let hsts = sectest_header_get(h, "Strict-Transport-Security");
  if sectest_header_count_named(h, "Strict-Transport-Security") == 0 {
    _finding(&mut rules, &mut severities, &mut messages, "hsts", "high", "missing Strict-Transport-Security");
  } else {
    let age = _hsts_max_age(hsts);
    if age == -1 {
      _finding(&mut rules, &mut severities, &mut messages, "hsts", "medium", "HSTS without max-age");
    } elif age < 0 {
      _finding(&mut rules, &mut severities, &mut messages, "hsts", "medium", "HSTS max-age is not a number");
    } elif age < 31536000 {
      _finding(&mut rules, &mut severities, &mut messages, "hsts", "medium", "HSTS max-age " + int_to_string(age) + " is below 31536000");
    }
    if !_has_token_ci(hsts, "includesubdomains") {
      _finding(&mut rules, &mut severities, &mut messages, "hsts", "low", "HSTS without includeSubDomains");
    }
  }

  let csp = sectest_header_get(h, "Content-Security-Policy");
  if sectest_header_count_named(h, "Content-Security-Policy") == 0 {
    _finding(&mut rules, &mut severities, &mut messages, "csp", "high", "missing Content-Security-Policy");
  } else {
    if string.str_contains(csp, "'unsafe-inline'") {
      _finding(&mut rules, &mut severities, &mut messages, "csp", "medium", "CSP allows 'unsafe-inline'");
    }
    if string.str_contains(csp, "'unsafe-eval'") {
      _finding(&mut rules, &mut severities, &mut messages, "csp", "medium", "CSP allows 'unsafe-eval'");
    }
  }

  if sectest_header_count_named(h, "X-Content-Type-Options") == 0 {
    _finding(&mut rules, &mut severities, &mut messages, "x-content-type-options", "medium", "missing X-Content-Type-Options");
  } else {
    let xcto = sectest_header_get(h, "X-Content-Type-Options");
    if !_eq_ci(xcto, "nosniff") {
      _finding(&mut rules, &mut severities, &mut messages, "x-content-type-options", "medium", "X-Content-Type-Options is not nosniff");
    }
  }

  if sectest_header_count_named(h, "X-Frame-Options") == 0 {
    _finding(&mut rules, &mut severities, &mut messages, "x-frame-options", "medium", "missing X-Frame-Options");
  } else {
    let xfo = sectest_header_get(h, "X-Frame-Options");
    if !_xfo_ok(xfo) {
      _finding(&mut rules, &mut severities, &mut messages, "x-frame-options", "medium", "X-Frame-Options is not DENY or SAMEORIGIN");
    }
  }

  if sectest_header_count_named(h, "Referrer-Policy") == 0 {
    _finding(&mut rules, &mut severities, &mut messages, "referrer-policy", "low", "missing Referrer-Policy");
  } else {
    let rp = sectest_header_get(h, "Referrer-Policy");
    if !_referrer_ok(rp) {
      _finding(&mut rules, &mut severities, &mut messages, "referrer-policy", "low", "Referrer-Policy value is not recognized");
    }
  }

  if sectest_header_count_named(h, "Permissions-Policy") == 0 {
    _finding(&mut rules, &mut severities, &mut messages, "permissions-policy", "low", "missing Permissions-Policy");
  }

  if sectest_header_count_named(h, "X-XSS-Protection") > 0 {
    _finding(&mut rules, &mut severities, &mut messages, "x-xss-protection", "info", "X-XSS-Protection is deprecated");
  }

  if sectest_header_count_named(h, "Server") > 0 {
    _finding(&mut rules, &mut severities, &mut messages, "disclosure", "low", "information disclosure via Server");
  }
  if sectest_header_count_named(h, "X-Powered-By") > 0 {
    _finding(&mut rules, &mut severities, &mut messages, "disclosure", "low", "information disclosure via X-Powered-By");
  }

  return SectestReport{ rules: rules; severities: severities; messages: messages; };
}

// Number of index-aligned findings.
fn _finding_count(r: &SectestReport) -> Int {
  var n = r.rules.len();
  if r.severities.len() < n {
    n = r.severities.len();
  }
  if r.messages.len() < n {
    n = r.messages.len();
  }
  return n;
}

/// Number of findings in the report.
/// Params: r - the report.
/// Returns: the count; 0 when everything passed.
/// Error case: none.
/// Complexity: O(1).
pub fn sectest_finding_count(r: &SectestReport) -> Int {
  return _finding_count(r);
}

/// Rule id of finding `i`.
/// Params: r - the report; i - the zero-based index.
/// Returns: the rule id; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sectest_finding_rule(r: &SectestReport, i: Int) -> Str {
  if i < 0 || i >= _finding_count(r) {
    return "";
  }
  let v: Str = r.rules[i];
  return v;
}

/// Severity of finding `i`: "high", "medium", "low" or "info".
/// Params: r - the report; i - the zero-based index.
/// Returns: the severity; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sectest_finding_severity(r: &SectestReport, i: Int) -> Str {
  if i < 0 || i >= _finding_count(r) {
    return "";
  }
  let v: Str = r.severities[i];
  return v;
}

/// Message of finding `i`.
/// Params: r - the report; i - the zero-based index.
/// Returns: the message; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn sectest_finding_message(r: &SectestReport, i: Int) -> Str {
  if i < 0 || i >= _finding_count(r) {
    return "";
  }
  let v: Str = r.messages[i];
  return v;
}

/// Number of findings with a given severity.
/// Params: r - the report; severity - "high", "medium", "low" or "info".
/// Returns: the count.
/// Error case: none.
/// Complexity: O(findings).
pub fn sectest_count_severity(r: &SectestReport, severity: Str) -> Int {
  var c = 0;
  var i = 0;
  let n = _finding_count(r);
  while i < n {
    let sev: Str = r.severities[i];
    if _eq_ci(sev, severity) {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// True when the block has no high or medium finding.
/// Params: r - the report.
/// Returns: the flag (low and info findings do not fail the check).
/// Error case: none.
/// Complexity: O(findings).
pub fn sectest_passed(r: &SectestReport) -> Bool {
  return sectest_count_severity(r, "high") == 0 && sectest_count_severity(r, "medium") == 0;
}

/// Deterministic one-line summary of the report.
/// Params: r - the report.
/// Returns: "no findings" for an empty report, else
/// "<n> findings: <high> high, <medium> medium, <low> low, <info> info".
/// Error case: none.
/// Complexity: O(findings).
pub fn sectest_summary(r: &SectestReport) -> Str {
  let n = _finding_count(r);
  if n == 0 {
    return "no findings";
  }
  return int_to_string(n) + " findings: "
    + int_to_string(sectest_count_severity(r, "high")) + " high, "
    + int_to_string(sectest_count_severity(r, "medium")) + " medium, "
    + int_to_string(sectest_count_severity(r, "low")) + " low, "
    + int_to_string(sectest_count_severity(r, "info")) + " info";
}
