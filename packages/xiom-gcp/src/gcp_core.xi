// XIOM -- xiom.gcp.core: shared constants and byte/text helpers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The support layer of the xiom.gcp package: the tiny byte/text helpers every
// sibling module uses, plus the deterministic JSON fragment helpers used by
// the auth model. No composite GCP logic and no dependencies beyond xiom.std.
//
// Sibling layout (all modules under `xiom.gcp.*`; import direction is
// sibling-to-sibling only -- on compiler v0.62.2 a child module cannot import
// its parent):
//
//   * `xiom.gcp`           resource names + service registry + endpoints
//   * `xiom.gcp.core`      this module: constants + helpers
//   * `xiom.gcp.storage`   GCS buckets / objects / generations / ACL
//   * `xiom.gcp.compute`   GCE machine types / instance state machine / metadata
//   * `xiom.gcp.cloudfunctions` Cloud Functions runtime / handler / trigger / invoke
//   * `xiom.gcp.bigquery`  datasets / tables / schemas / jobs / row pages
//   * `xiom.gcp.pubsub`    topics / subscriptions / publish / ack / deadline
//   * `xiom.gcp.auth`      service-account key / OAuth scope / token / JWT claims
//
// v0.62.2 discipline: free functions only; every byte read widened with
// `(x as Int) & 0xFF`; Str equality through xiom.string.compare (never `==`);
// no &mut Int scalar parameters (scalar state travels through returns); all
// loops have a strictly increasing counter.

module xiom.gcp.core

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// The pseudo-location used by global GCP resources (`projects/p/global/...`).
pub const GCP_LOCATION_GLOBAL: Str = "global";

/// Host suffix shared by the per-service GCP JSON APIs.
pub const GCP_API_HOST_SUFFIX: Str = ".googleapis.com";

/// Maximum length of a project id (GCP limit is 30 characters).
pub const GCP_PROJECT_ID_MAX: Int = 30;

/// Minimum length of a project id (GCP limit is 6 characters).
pub const GCP_PROJECT_ID_MIN: Int = 6;

// Lowercase hex alphabet for JSON \u escapes.
const _GCP_HEX_LOWER: Str = "0123456789abcdef";

// --------------------------------------------------
//  Bytes and text
// --------------------------------------------------

/// Byte at `pos` of a Str widened to an Int in 0..255; the caller guarantees
/// the bounds. Params: s - the text; pos - a valid byte index. Complexity O(1).
pub fn gcp_byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

/// True when two Str values are byte-for-byte equal (never `==` on Str).
/// Params: a, b - the values. Complexity O(min(len)).
pub fn gcp_str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

/// Decimal rendering of `v` with no leading zeros. Params: v - the integer.
/// Complexity O(digits).
pub fn gcp_int_str(v: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

/// "gcp: <what>" -- the package's plain error form. Params: what - the
/// description. Complexity O(what.len()).
pub fn gcp_err(what: Str) -> Str {
  return "gcp: " + what;
}

/// True for an ASCII decimal digit. Params: c - a widened byte. Complexity O(1).
pub fn gcp_is_digit(c: Int) -> Bool {
  if c >= 48 && c <= 57 {
    return true;
  }
  return false;
}

/// True for an ASCII lowercase letter. Params: c - a widened byte. O(1).
pub fn gcp_is_lower_alpha(c: Int) -> Bool {
  if c >= 97 && c <= 122 {
    return true;
  }
  return false;
}

/// True for an ASCII uppercase letter. Params: c - a widened byte. O(1).
pub fn gcp_is_upper_alpha(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  return false;
}

/// True for an ASCII letter (either case). Params: c - a widened byte. O(1).
pub fn gcp_is_alpha(c: Int) -> Bool {
  if gcp_is_lower_alpha(c) {
    return true;
  }
  if gcp_is_upper_alpha(c) {
    return true;
  }
  return false;
}

/// True for a lowercase letter or digit. Params: c - a widened byte. O(1).
pub fn gcp_is_alnum_lower(c: Int) -> Bool {
  if gcp_is_lower_alpha(c) {
    return true;
  }
  if gcp_is_digit(c) {
    return true;
  }
  return false;
}

/// True for an ASCII letter or digit (either case). Params: c - a widened
/// byte. Complexity O(1).
pub fn gcp_is_alnum(c: Int) -> Bool {
  if gcp_is_alpha(c) {
    return true;
  }
  if gcp_is_digit(c) {
    return true;
  }
  return false;
}

/// True for a DNS-1035-style label: 1..63 characters, lowercase letter first,
/// lowercase letter or digit last, interior lowercase letters/digits/hyphens.
/// Params: s - the candidate label. Complexity O(s.len()).
pub fn gcp_is_rfc1035_label(s: Str) -> Bool {
  let n = s.len();
  if n < 1 {
    return false;
  }
  if n > 63 {
    return false;
  }
  let first = gcp_byte(s, 0);
  if !gcp_is_lower_alpha(first) {
    return false;
  }
  let last = gcp_byte(s, n - 1);
  if !gcp_is_alnum_lower(last) {
    return false;
  }
  var i = 1;
  while i < n - 1 {
    let c = gcp_byte(s, i);
    if !gcp_is_alnum_lower(c) {
      if c != 45 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// Copy s[from, to) into a fresh Str; the caller guarantees 0 <= from <= to
/// <= s.len(). Params: s - the text; from, to - byte bounds. Complexity O(to-from).
pub fn gcp_substr(s: Str, from: Int, to: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// First index of byte `ch` in s[from, to), or -1 when absent. Params: s - the
/// text; from, to - byte bounds; ch - a widened byte value. Complexity O(to-from).
pub fn gcp_index_of_char(s: Str, from: Int, to: Int, ch: Int) -> Int {
  var i = from;
  while i < to {
    let b = gcp_byte(s, i);
    if b == ch {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// True when `s` begins with `prefix`. Params: s - the text; prefix - the
/// prefix. Complexity O(prefix.len()).
pub fn gcp_starts_with(s: Str, prefix: Str) -> Bool {
  let pn = prefix.len();
  if pn > s.len() {
    return false;
  }
  var i = 0;
  while i < pn {
    let a = gcp_byte(s, i);
    let b = gcp_byte(prefix, i);
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// True when `s` ends with `suffix`. Params: s - the text; suffix - the
/// suffix. Complexity O(suffix.len()).
pub fn gcp_ends_with(s: Str, suffix: Str) -> Bool {
  let sn = suffix.len();
  let n = s.len();
  if sn > n {
    return false;
  }
  var i = 0;
  while i < sn {
    let a = gcp_byte(s, n - sn + i);
    let b = gcp_byte(suffix, i);
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// True when `needle` occurs in `haystack`. The empty needle is false by
/// contract (it also avoids the stdlib empty-needle runtime abort). Params:
/// haystack, needle - the texts. Complexity O(n*m).
pub fn gcp_contains(haystack: Str, needle: Str) -> Bool {
  let nn = needle.len();
  if nn == 0 {
    return false;
  }
  let hn = haystack.len();
  if nn > hn {
    return false;
  }
  var i = 0;
  while i + nn <= hn {
    var j = 0;
    var hit = true;
    while j < nn {
      let a = gcp_byte(haystack, i + j);
      let b = gcp_byte(needle, j);
      if a != b {
        hit = false;
        j = nn;
      } else {
        j = j + 1;
      }
    }
    if hit {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  JSON fragments (used by the auth model)
// --------------------------------------------------

/// JSON-escape `s`: `"` and `\` are backslash-escaped and CTL bytes become
/// `\u00xx` with lowercase hex. Params: s - the text. Complexity O(s.len()).
pub fn gcp_json_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b = gcp_byte(s, i);
    if b == 34 {
      out.push(92 as UInt8);
      out.push(34 as UInt8);
    } else {
      if b == 92 {
        out.push(92 as UInt8);
        out.push(92 as UInt8);
      } else {
        if b < 32 {
          out.push(92 as UInt8);
          out.push(117 as UInt8);
          out.push(48 as UInt8);
          out.push(48 as UInt8);
          out.push(string.byte_at(_GCP_HEX_LOWER, b / 16));
          out.push(string.byte_at(_GCP_HEX_LOWER, b % 16));
        } else {
          out.push(string.byte_at(s, i));
        }
      }
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Append `"<escaped>"` (with the surrounding quotes) to `out`. Params: out -
/// the byte builder; s - the text. Complexity O(s.len()).
pub fn gcp_json_push_quoted(out: &mut Vec[UInt8], s: Str) {
  out.push(34 as UInt8);
  var i = 0;
  while i < s.len() {
    let b = gcp_byte(s, i);
    if b == 34 {
      out.push(92 as UInt8);
      out.push(34 as UInt8);
    } else {
      if b == 92 {
        out.push(92 as UInt8);
        out.push(92 as UInt8);
      } else {
        if b < 32 {
          out.push(92 as UInt8);
          out.push(117 as UInt8);
          out.push(48 as UInt8);
          out.push(48 as UInt8);
          out.push(string.byte_at(_GCP_HEX_LOWER, b / 16));
          out.push(string.byte_at(_GCP_HEX_LOWER, b % 16));
        } else {
          out.push(string.byte_at(s, i));
        }
      }
    }
    i = i + 1;
  }
  out.push(34 as UInt8);
}

/// Append the decimal rendering of `v` to `out`. Params: out - the byte
/// builder; v - the integer. Complexity O(digits).
pub fn gcp_json_push_int(out: &mut Vec[UInt8], v: Int) {
  let s = gcp_int_str(v);
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}
