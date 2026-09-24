// XIOM -- xiom.pagination: page/offset math and opaque cursor tokens
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. The module has two independent halves:
//   * page math over 1-based pages and half-open item windows:
//     page_offset, page_count, page_bounds, page_has_next, page_has_prev,
//     page_last and page_clamp;
//   * opaque cursor tokens: base64url (RFC 4648 section 5, '-' and '_', no
//     '=') of the ASCII text "<offset>:<limit>". base64url is implemented
//     locally so the package has no sibling-package dependency; the only
//     imports are xiom.string, xiom.string.builder and xiom.convert from
//     xiom.std.
//
// Cursors are OPAQUE and UNSIGNED: they carry no integrity guarantee, so a
// client can forge or edit one. cursor_decode only proves that a token is a
// well-formed (offset, limit) pair; authorization and range checks against
// the underlying data remain the caller's job.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     xiom.string.byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF`
//     before any comparison or arithmetic (a raw UInt8 compared against a
//     constant >= 128 miscompiles).
//   * Ok/Err for cursor_decode are constructed only in the tiny leaf helpers
//     (_cursor_ok/_cursor_err); constructing a Result inside a function that
//     also returns a tuple miscompiles.
//   * Vec reads are assigned to explicit typed locals (`let v0: Int = ...`)
//     and decoded bytes are collected in a Vec[UInt8] materialized once with
//     xiom.string.builder.sb_to_str.
//   * this module never compares Str values (no `==` on Str); callers/tests
//     use xiom.string.compare.str_compare.
//   * all arithmetic is overflow-checked: page_offset clamps to the 64-bit
//     maximum instead of wrapping and page_count divides before adding.
//
// See SPEC.md for the exact clamping rules, the token grammar, the error
// catalog and the test plan.

module xiom.pagination

use xiom.string;
use xiom.string.builder;
use xiom.convert;

// 64-bit signed limits (Int is i64 on the pinned toolchain).
const _MAX_INT: Int = 9223372036854775807;
const _MAX_INT_DIV10: Int = 922337203685477580;
const _MAX_INT_LAST_DIGIT: Int = 7;

// --------------------------------------------------
//  Page math (1-based pages)
// --------------------------------------------------

/// Byte offset of the first item on `page`, zero-based.
/// Params: page - 1-based page number; per_page - items per page.
/// Returns: (page - 1) * per_page. page < 1 or per_page < 1 yields 0.
/// Overflow safety: when the exact product would exceed the 64-bit signed
/// maximum the result is clamped to 9223372036854775807 (never wraps).
/// Examples: (3, 10) -> 20; (0, 10) -> 0; (2, 9223372036854775807) ->
/// 9223372036854775807.
/// Error case: none.
/// Complexity: O(1).
pub fn page_offset(page: Int, per_page: Int) -> Int {
  if page < 1 {
    return 0;
  }
  if per_page < 1 {
    return 0;
  }
  let pages_before = page - 1;
  if pages_before > _MAX_INT / per_page {
    return _MAX_INT;
  }
  return pages_before * per_page;
}

/// Number of pages needed to hold `total` items (ceiling division).
/// Params: total - item count; per_page - items per page.
/// Returns: ceil(total / per_page); 0 when total <= 0 or per_page < 1.
/// Overflow safety: computed as floor(total / per_page) plus a remainder
/// term, so no intermediate addition can overflow.
/// Examples: (100, 10) -> 10; (101, 10) -> 11; (0, 10) -> 0.
/// Error case: none.
/// Complexity: O(1).
pub fn page_count(total: Int, per_page: Int) -> Int {
  if total <= 0 {
    return 0;
  }
  if per_page < 1 {
    return 0;
  }
  let q = total / per_page;
  if total % per_page != 0 {
    return q + 1;
  }
  return q;
}

/// Half-open item window [start, end) of `page`, clamped to total.
/// Params: page - 1-based page number; per_page - items per page; total -
/// item count.
/// Returns: (start, end) with start == page_offset(page, per_page) and
/// end == min(start + per_page, total) for a page in 1..page_last, so end is
/// exclusive and 0 <= start < end <= total. Any page outside that range
/// (page < 1, page > page_last, per_page < 1, total <= 0) yields (0, 0).
/// Overflow safety: the end is clamped by comparison before any addition, so
/// huge per_page values cannot overflow.
/// Examples: (1, 10, 100) -> (0, 10); (10, 10, 95) -> (90, 95);
/// (11, 10, 100) -> (0, 0).
/// Error case: none.
/// Complexity: O(1).
pub fn page_bounds(page: Int, per_page: Int, total: Int) -> (Int, Int) {
  if total <= 0 {
    return (0, 0);
  }
  if per_page < 1 {
    return (0, 0);
  }
  if page < 1 {
    return (0, 0);
  }
  let last = page_count(total, per_page);
  if page > last {
    return (0, 0);
  }
  let start = page_offset(page, per_page);
  var end = start;
  if per_page > total - start {
    end = total;
  } else {
    end = start + per_page;
  }
  return (start, end);
}

/// True when a next page exists after `page`.
/// Params: page - 1-based page number; per_page - items per page; total -
/// item count.
/// Returns: true iff 1 <= page < page_last(total, per_page); false for any
/// invalid page, empty collection or non-positive per_page.
/// Examples: (1, 10, 100) -> true; (10, 10, 100) -> false.
/// Error case: none.
/// Complexity: O(1).
pub fn page_has_next(page: Int, per_page: Int, total: Int) -> Bool {
  if page < 1 {
    return false;
  }
  return page < page_count(total, per_page);
}

/// True when a previous page exists before `page`.
/// Params: page - 1-based page number.
/// Returns: page > 1.
/// Examples: (2) -> true; (1) -> false.
/// Error case: none.
/// Complexity: O(1).
pub fn page_has_prev(page: Int) -> Bool {
  return page > 1;
}

/// Number of the last page, i.e. the largest valid page number.
/// Params: total - item count; per_page - items per page.
/// Returns: page_count(total, per_page); 0 when there are no pages.
/// Examples: (100, 10) -> 10; (0, 10) -> 0.
/// Error case: none.
/// Complexity: O(1).
pub fn page_last(total: Int, per_page: Int) -> Int {
  return page_count(total, per_page);
}

/// Clamp `page` into 1..page_last.
/// Params: page - requested 1-based page number; total - item count;
/// per_page - items per page.
/// Returns: page unchanged when 1 <= page <= page_last; 1 when page < 1; 
/// page_last when page > page_last; 1 when the collection is empty
/// (total <= 0 or per_page < 1), so the result is always a valid 1-based
/// page number under the documented convention that page 1 of an empty
/// collection is "the" page.
/// Examples: (5, 100, 10) -> 5; (0, 100, 10) -> 1; (99, 100, 10) -> 10;
/// (5, 0, 10) -> 1.
/// Error case: none.
/// Complexity: O(1).
pub fn page_clamp(page: Int, total: Int, per_page: Int) -> Int {
  let last = page_count(total, per_page);
  if last < 1 {
    return 1;
  }
  if page < 1 {
    return 1;
  }
  if page > last {
    return last;
  }
  return page;
}

// --------------------------------------------------
//  Base64url (RFC 4648 section 5, no padding)
// --------------------------------------------------

// Base64url value of one byte (A-Z 0-25, a-z 26-51, 0-9 52-61, '-' 62,
// '_' 63). Returns -1 for every other byte: '+' '/' and '=' are deliberately
// rejected because cursor tokens are URL-safe and unpadded.
fn _b64u_value(b: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b - 65;
  }
  if b >= 97 && b <= 122 {
    return b - 71;
  }
  if b >= 48 && b <= 57 {
    return b + 4;
  }
  if b == 45 {
    return 62;
  }
  if b == 95 {
    return 63;
  }
  return -1;
}

// Base64url alphabet byte for a 6-bit value (0..63).
fn _b64u_char(v: Int) -> UInt8 {
  return string.byte_at("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", v);
}

// Encode the bytes of `text` (ASCII by construction) as unpadded base64url.
// A 1-byte tail becomes 2 characters, a 2-byte tail 3 characters.
fn _b64u_encode_str(text: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let b0 = (string.byte_at(text, i) as Int) & 0xFF;
    let have1 = i + 1 < n;
    let have2 = i + 2 < n;
    var b1 = 0;
    var b2 = 0;
    if have1 {
      b1 = (string.byte_at(text, i + 1) as Int) & 0xFF;
    }
    if have2 {
      b2 = (string.byte_at(text, i + 2) as Int) & 0xFF;
    }
    out.push(_b64u_char(b0 >> 2));
    out.push(_b64u_char(((b0 & 3) << 4) | (b1 >> 4)));
    if have1 {
      out.push(_b64u_char(((b1 & 15) << 2) | (b2 >> 6)));
    }
    if have2 {
      out.push(_b64u_char(b2 & 63));
    }
    i = i + 3;
  }
  return builder.sb_to_str(&out);
}

// Decode `token` as strict unpadded base64url, appending the decoded bytes to
// `out`. Trailing bits of a 2- or 3-character tail are ignored (non-canonical
// encodings map to the same bytes, matching xiom.codec's decoder).
// Returns: 0 on success, 1 when a byte is outside the alphabet ('+', '/'
// and '=' included), 2 when the character count is 1 (mod 4).
fn _b64u_decode_str(token: Str, out: &mut Vec[UInt8]) -> Int {
  var vals = Vec[Int].new();
  let n = token.len();
  var i = 0;
  while i < n {
    let b = (string.byte_at(token, i) as Int) & 0xFF;
    let v = _b64u_value(b);
    if v < 0 {
      return 1;
    }
    vals.push(v);
    i = i + 1;
  }
  let core = vals.len();
  if core % 4 == 1 {
    return 2;
  }
  var k = 0;
  while k + 4 <= core {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    let v3: Int = vals[k + 3];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
    out.push(((v1 << 4) | (v2 >> 2)) as UInt8);
    out.push(((v2 << 6) | v3) as UInt8);
    k = k + 4;
  }
  let rem = core - k;
  if rem == 2 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
  } elif rem == 3 {
    let v0: Int = vals[k];
    let v1: Int = vals[k + 1];
    let v2: Int = vals[k + 2];
    out.push(((v0 << 2) | (v1 >> 4)) as UInt8);
    out.push(((v1 << 4) | (v2 >> 2)) as UInt8);
  }
  return 0;
}

// --------------------------------------------------
//  Cursor tokens
// --------------------------------------------------

// Parse exactly `len` ASCII digits at `start` as a non-negative Int.
// Returns: the value, or -1 when a byte is not a digit or the magnitude
// would exceed the 64-bit signed maximum (9223372036854775807).
fn _parse_uint(bytes: &Vec[UInt8], start: Int, len: Int) -> Int {
  var mag = 0;
  var i = 0;
  while i < len {
    let b = (bytes[start + i] as Int) & 0xFF;
    let d = b - 48;
    if d < 0 || d > 9 {
      return -1;
    }
    if mag > _MAX_INT_DIV10 {
      return -1;
    }
    if mag == _MAX_INT_DIV10 && d > _MAX_INT_LAST_DIGIT {
      return -1;
    }
    mag = mag * 10 + d;
    i = i + 1;
  }
  return mag;
}

// Ok((offset, limit)) for Result[(Int, Int), Str].
fn _cursor_ok(offset: Int, limit: Int) -> Result[(Int, Int), Str] {
  return Ok((offset, limit));
}

// Err(m) for Result[(Int, Int), Str].
fn _cursor_err(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

/// Encode an offset/limit pair as an opaque cursor token.
/// Params: offset - zero-based item offset, clamped to >= 0; limit - page
/// size, clamped to >= 1.
/// Returns: the unpadded base64url (RFC 4648 section 5) of the ASCII text
/// "<offset>:<limit>". The token is opaque: callers must not parse it by
/// hand and must not treat it as tamper-proof (it is not signed).
/// Examples: (0, 10) -> "MDoxMA"; (123, 50) -> "MTIzOjUw".
/// Error case: none.
/// Complexity: O(digits).
pub fn cursor_encode(offset: Int, limit: Int) -> Str {
  var off = offset;
  if off < 0 {
    off = 0;
  }
  var lim = limit;
  if lim < 1 {
    lim = 1;
  }
  let text = convert.int_to_string(off) + ":" + convert.int_to_string(lim);
  return _b64u_encode_str(text);
}

/// Decode an opaque cursor token back to (offset, limit).
/// Params: token - an unpadded base64url token previously produced by
/// cursor_encode (or any well-formed token).
/// Returns: Ok((offset, limit)) for a canonical token: strictly the
/// URL-safe alphabet, no '=' padding, no whitespace, exactly one ':' and
/// bare unsigned decimal numbers with no leading zeros ("0" is the only
/// zero form), each fitting the 64-bit signed maximum; limit is >= 1.
/// Error case: Err("pagination: ...") -- empty token, a byte outside the
/// alphabet ("invalid cursor character"), a length of 1 (mod 4) ("invalid
/// cursor length"), a malformed shape including zero limit and leading
/// zeros ("invalid cursor shape" / "non-canonical cursor"), or a value
/// above the 64-bit signed maximum ("cursor value out of range").
/// Examples: "MDoxMA" -> Ok((0, 10)); "YWJj" -> Err; "" -> Err.
/// Complexity: O(token.len()).
pub fn cursor_decode(token: Str) -> Result[(Int, Int), Str] {
  let n = token.len();
  if n == 0 {
    return _cursor_err("pagination: empty cursor");
  }
  var raw = Vec[UInt8].new();
  let code = _b64u_decode_str(token, &mut raw);
  if code == 1 {
    return _cursor_err("pagination: invalid cursor character");
  }
  if code == 2 {
    return _cursor_err("pagination: invalid cursor length");
  }
  let bn = raw.len();
  var colon = -1;
  var i = 0;
  while i < bn {
    let b = (raw[i] as Int) & 0xFF;
    if b == 58 {
      if colon >= 0 {
        return _cursor_err("pagination: invalid cursor shape");
      }
      colon = i;
    } elif b < 48 || b > 57 {
      return _cursor_err("pagination: invalid cursor shape");
    }
    i = i + 1;
  }
  if colon < 0 {
    return _cursor_err("pagination: invalid cursor shape");
  }
  let off_len = colon;
  let lim_len = bn - colon - 1;
  if off_len == 0 || lim_len == 0 {
    return _cursor_err("pagination: invalid cursor shape");
  }
  let off_first = (raw[0] as Int) & 0xFF;
  if off_len > 1 && off_first == 48 {
    return _cursor_err("pagination: non-canonical cursor");
  }
  let lim_first = (raw[colon + 1] as Int) & 0xFF;
  if lim_first == 48 {
    return _cursor_err("pagination: non-canonical cursor");
  }
  let off_mag = _parse_uint(&raw, 0, off_len);
  if off_mag < 0 {
    return _cursor_err("pagination: cursor value out of range");
  }
  let lim_mag = _parse_uint(&raw, colon + 1, lim_len);
  if lim_mag < 0 {
    return _cursor_err("pagination: cursor value out of range");
  }
  if lim_mag < 1 {
    return _cursor_err("pagination: invalid cursor shape");
  }
  return _cursor_ok(off_mag, lim_mag);
}
