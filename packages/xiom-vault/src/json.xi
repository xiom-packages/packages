// XIOM -- xiom.vault.json: bounded flat-JSON scanner for vault API payloads
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, total JSON scanner used to read fields out of vault API request
// bodies and responses WITHOUT a general JSON library:
//
//   * `vault_json_lookup` finds a TOP-LEVEL member of a flat JSON object and
//     returns its raw byte span (strings include their quotes) plus a kind:
//     string / number / literal / object / array. The first match wins.
//   * typed getters decode that span: `vault_json_get_str` (escapes applied),
//     `vault_json_get_raw` (verbatim slice), `vault_json_get_int`
//     (decimal integer only), `vault_json_get_bool` (true / false) and
//     `vault_json_get_strs` (array of strings, for vault `policies` lists).
//   * nested values are validated and skipped by a balanced scanner with a
//     depth cap; string escapes support " \ / b f n r t and \uXXXX with
//     code points up to U+FFFF (surrogate pairs are rejected, documented).
//
// Deliberately NOT implemented: a DOM, duplicate-key policies, surrogate
// pairs, big-number arithmetic, floats, streaming and serialization beyond
// the flat builder in `xiom.vault.client`. NUL escapes are rejected so no
// Str is ever built from bytes containing 0x00 (the sb_to_str contract).
//
// v0.62.2 notes: free functions only; Ok/Err only in the `_ok_*`/`_err_*`
// leaves; bytes widened with `(x as Int) & 0xFF`; Str equality through
// core.vault_str_eq (never `==`); no recursion beyond the depth-capped
// value scanner; all loops are bounded by the input length.

module xiom.vault.json

use xiom.vault.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// JSON value kind: string (0).
pub const VAULT_JSON_STRING: Int = 0;

/// JSON value kind: number (1).
pub const VAULT_JSON_NUMBER: Int = 1;

/// JSON value kind: literal true / false / null (2).
pub const VAULT_JSON_LITERAL: Int = 2;

/// JSON value kind: object (3).
pub const VAULT_JSON_OBJECT: Int = 3;

/// JSON value kind: array (4).
pub const VAULT_JSON_ARRAY: Int = 4;

/// Maximum nesting depth accepted by the scanner (16).
pub const VAULT_JSON_MAX_DEPTH: Int = 16;

/// Maximum number of elements returned by vault_json_get_strs (256).
pub const VAULT_JSON_MAX_ELEMENTS: Int = 256;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// One scanned JSON value. The raw span [start, end) covers the whole value
/// (string quotes and object/array delimiters included); `next` equals `end`
/// and is also the offset just past the value.
pub type VaultJsonHit = {
  start: Int;
  end: Int;
  kind: Int;
  next: Int;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_hit(v: VaultJsonHit) -> Result[VaultJsonHit, Str] {
  return Ok(v);
}

fn _err_hit(m: Str) -> Result[VaultJsonHit, Str] {
  return Err(m);
}

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

fn _ok_strs(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

fn _err_strs(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Scanner internals
// --------------------------------------------------

// Skip JSON whitespace (SP, HTAB, LF, CR) at or after `pos`.
fn _ws(text: Str, pos: Int) -> Int {
  let n = text.len();
  var i = pos;
  while i < n {
    let c = core.vault_byte(text, i);
    if c == 32 || c == 9 || c == 10 || c == 13 {
      i = i + 1;
    } else {
      return i;
    }
  }
  return i;
}

// Hex digit value of a byte (0..15), or -1.
fn _hexval(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 97 && b <= 102 {
    return b - 97 + 10;
  }
  if b >= 65 && b <= 70 {
    return b - 65 + 10;
  }
  return -1;
}

// Append the UTF-8 encoding of code point `cp` (cp >= 1) to `out`.
fn _utf8_push(out: &mut Vec[UInt8], cp: Int) {
  if cp < 128 {
    out.push(cp as UInt8);
  } elif cp < 2048 {
    out.push((192 + cp / 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
  } elif cp < 65536 {
    out.push((224 + cp / 4096) as UInt8);
    out.push((128 + (cp / 64) % 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
  } else {
    out.push((240 + cp / 262144) as UInt8);
    out.push((128 + (cp / 4096) % 64) as UInt8);
    out.push((128 + (cp / 64) % 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
  }
}

// Scan one JSON string starting at the opening quote `pos`; the hit span is
// [pos, i) where i is the offset of the closing quote, `next` is i + 1.
fn _scan_string(text: Str, pos: Int) -> Result[VaultJsonHit, Str] {
  let n = text.len();
  if pos >= n || core.vault_byte(text, pos) != 34 {
    return _err_hit(core.vault_err_at("json expected string", pos));
  }
  var i = pos + 1;
  var done = false;
  while !done {
    if i >= n {
      return _err_hit(core.vault_err_at("json unterminated string", pos));
    }
    let c = core.vault_byte(text, i);
    if c == 34 {
      done = true;
      i = i + 1;
    } elif c == 92 {
      if i + 1 >= n {
        return _err_hit(core.vault_err_at("json unterminated escape", i));
      }
      i = i + 2;
    } elif c < 32 {
      return _err_hit(core.vault_err_at("json control byte in string", i));
    } else {
      i = i + 1;
    }
  }
  return _ok_hit(VaultJsonHit{ start: pos; end: i; kind: VAULT_JSON_STRING; next: i });
}

// Scan one JSON number at `pos` (JSON grammar, no leading '+' or zero).
fn _scan_number(text: Str, pos: Int) -> Result[VaultJsonHit, Str] {
  let n = text.len();
  var i = pos;
  if i < n && core.vault_byte(text, i) == 45 {
    i = i + 1;
  }
  if i >= n {
    return _err_hit(core.vault_err_at("json invalid number", pos));
  }
  let d0 = core.vault_byte(text, i);
  if d0 == 48 {
    i = i + 1;
  } elif d0 >= 49 && d0 <= 57 {
    while i < n && core.vault_byte(text, i) >= 48 && core.vault_byte(text, i) <= 57 {
      i = i + 1;
    }
  } else {
    return _err_hit(core.vault_err_at("json invalid number", pos));
  }
  if i < n && core.vault_byte(text, i) == 46 {
    i = i + 1;
    var frac = 0;
    while i < n && core.vault_byte(text, i) >= 48 && core.vault_byte(text, i) <= 57 {
      i = i + 1;
      frac = frac + 1;
    }
    if frac == 0 {
      return _err_hit(core.vault_err_at("json invalid number", pos));
    }
  }
  if i < n {
    let ex = core.vault_byte(text, i);
    if ex == 101 || ex == 69 {
      i = i + 1;
      if i < n && (core.vault_byte(text, i) == 43 || core.vault_byte(text, i) == 45) {
        i = i + 1;
      }
      var digits = 0;
      while i < n && core.vault_byte(text, i) >= 48 && core.vault_byte(text, i) <= 57 {
        i = i + 1;
        digits = digits + 1;
      }
      if digits == 0 {
        return _err_hit(core.vault_err_at("json invalid number", pos));
      }
    }
  }
  return _ok_hit(VaultJsonHit{ start: pos; end: i; kind: VAULT_JSON_NUMBER; next: i });
}

// Scan a true / false / null literal at `pos`.
fn _scan_literal(text: Str, pos: Int) -> Result[VaultJsonHit, Str] {
  let n = text.len();
  if pos + 4 <= n && core.vault_byte(text, pos + 1) == 114 && core.vault_byte(text, pos + 2) == 117 && core.vault_byte(text, pos + 3) == 101 {
    return _ok_hit(VaultJsonHit{ start: pos; end: pos + 4; kind: VAULT_JSON_LITERAL; next: pos + 4 });
  }
  if pos + 5 <= n && core.vault_byte(text, pos + 1) == 97 && core.vault_byte(text, pos + 2) == 108 && core.vault_byte(text, pos + 3) == 115 && core.vault_byte(text, pos + 4) == 101 {
    return _ok_hit(VaultJsonHit{ start: pos; end: pos + 5; kind: VAULT_JSON_LITERAL; next: pos + 5 });
  }
  if pos + 4 <= n && core.vault_byte(text, pos + 1) == 117 && core.vault_byte(text, pos + 2) == 108 && core.vault_byte(text, pos + 3) == 108 {
    return _ok_hit(VaultJsonHit{ start: pos; end: pos + 4; kind: VAULT_JSON_LITERAL; next: pos + 4 });
  }
  return _err_hit(core.vault_err_at("json invalid literal", pos));
}

// Scan a full JSON value at `pos` (whitespace skipped), bounded by `depth`.
fn _scan_value(text: Str, pos: Int, depth: Int) -> Result[VaultJsonHit, Str] {
  if depth > VAULT_JSON_MAX_DEPTH {
    return _err_hit(core.vault_err_at("json nesting too deep", pos));
  }
  let n = text.len();
  var i = _ws(text, pos);
  if i >= n {
    return _err_hit(core.vault_err_at("json expected value", i));
  }
  let c = core.vault_byte(text, i);
  if c == 34 {
    return _scan_string(text, i);
  }
  if c == 123 {
    var j = _ws(text, i + 1);
    if j < n && core.vault_byte(text, j) == 125 {
      return _ok_hit(VaultJsonHit{ start: i; end: j + 1; kind: VAULT_JSON_OBJECT; next: j + 1 });
    }
    var done = false;
    while !done {
      let nr = _scan_string(text, j);
      if !nr.is_ok {
        return _err_hit(nr.error);
      }
      let nh: VaultJsonHit = nr.value;
      j = _ws(text, nh.next);
      if j >= n || core.vault_byte(text, j) != 58 {
        return _err_hit(core.vault_err_at("json expected ':'", j));
      }
      let vr = _scan_value(text, j + 1, depth + 1);
      if !vr.is_ok {
        return _err_hit(vr.error);
      }
      let vh: VaultJsonHit = vr.value;
      j = _ws(text, vh.next);
      if j >= n {
        return _err_hit(core.vault_err_at("json unterminated object", i));
      }
      let c2 = core.vault_byte(text, j);
      if c2 == 44 {
        j = _ws(text, j + 1);
      } elif c2 == 125 {
        j = j + 1;
        done = true;
      } else {
        return _err_hit(core.vault_err_at("json expected ',' or '}'", j));
      }
    }
    return _ok_hit(VaultJsonHit{ start: i; end: j; kind: VAULT_JSON_OBJECT; next: j });
  }
  if c == 91 {
    var j = _ws(text, i + 1);
    if j < n && core.vault_byte(text, j) == 93 {
      return _ok_hit(VaultJsonHit{ start: i; end: j + 1; kind: VAULT_JSON_ARRAY; next: j + 1 });
    }
    var done = false;
    while !done {
      let vr = _scan_value(text, j, depth + 1);
      if !vr.is_ok {
        return _err_hit(vr.error);
      }
      let vh: VaultJsonHit = vr.value;
      j = _ws(text, vh.next);
      if j >= n {
        return _err_hit(core.vault_err_at("json unterminated array", i));
      }
      let c2 = core.vault_byte(text, j);
      if c2 == 44 {
        j = _ws(text, j + 1);
      } elif c2 == 93 {
        j = j + 1;
        done = true;
      } else {
        return _err_hit(core.vault_err_at("json expected ',' or ']'", j));
      }
    }
    return _ok_hit(VaultJsonHit{ start: i; end: j; kind: VAULT_JSON_ARRAY; next: j });
  }
  if c == 116 || c == 102 || c == 110 {
    return _scan_literal(text, i);
  }
  if c == 45 || (c >= 48 && c <= 57) {
    return _scan_number(text, i);
  }
  return _err_hit(core.vault_err_at("json invalid value", i));
}

// Decode the string content [start, end) of `text` (quotes excluded) into a
// Str, applying the JSON escapes. NUL, surrogates and malformed escapes are
// rejected.
fn _decode_range(text: Str, start: Int, end: Int) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    let c = core.vault_byte(text, i);
    if c == 92 {
      if i + 1 >= end {
        return _err_str(core.vault_err_at("json truncated escape", i));
      }
      let e = core.vault_byte(text, i + 1);
      if e == 34 {
        out.push(34 as UInt8);
        i = i + 2;
      } elif e == 92 {
        out.push(92 as UInt8);
        i = i + 2;
      } elif e == 47 {
        out.push(47 as UInt8);
        i = i + 2;
      } elif e == 98 {
        out.push(8 as UInt8);
        i = i + 2;
      } elif e == 102 {
        out.push(12 as UInt8);
        i = i + 2;
      } elif e == 110 {
        out.push(10 as UInt8);
        i = i + 2;
      } elif e == 114 {
        out.push(13 as UInt8);
        i = i + 2;
      } elif e == 116 {
        out.push(9 as UInt8);
        i = i + 2;
      } elif e == 117 {
        if i + 6 > end {
          return _err_str(core.vault_err_at("json truncated unicode escape", i));
        }
        var cp = 0;
        var k = 0;
        while k < 4 {
          let h = _hexval(core.vault_byte(text, i + 2 + k));
          if h < 0 {
            return _err_str(core.vault_err_at("json invalid unicode escape", i));
          }
          cp = cp * 16 + h;
          k = k + 1;
        }
        if cp == 0 {
          return _err_str(core.vault_err_at("json NUL escape", i));
        }
        if cp >= 55296 && cp <= 57343 {
          return _err_str(core.vault_err_at("json surrogate escape unsupported", i));
        }
        _utf8_push(&mut out, cp);
        i = i + 6;
      } else {
        return _err_str(core.vault_err_at("json invalid escape", i));
      }
    } else {
      if c < 32 {
        return _err_str(core.vault_err_at("json control byte in string", i));
      }
      out.push(string.byte_at(text, i));
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Find a top-level member of a flat JSON object. The returned span is the
/// raw value: strings include both quotes and objects/arrays include their
/// delimiters; `next` equals `end`.
/// Params: text - a JSON object; key - the member name (case-sensitive).
/// Returns: Ok(hit) for the first matching member.
/// Error case: Err("vault: json expected object at offset N"),
/// Err("vault: json expected ':' at offset N"), Err("vault: json expected ','
/// or '}' at offset N"), Err("vault: json unterminated object at offset N"),
/// the string/number/literal catalogs, and Err("vault: json key not found:
/// <key>") when no member matches.
/// Complexity: O(text.len()).
pub fn vault_json_lookup(text: Str, key: Str) -> Result[VaultJsonHit, Str] {
  let n = text.len();
  var pos = _ws(text, 0);
  if pos >= n || core.vault_byte(text, pos) != 123 {
    return _err_hit(core.vault_err_at("json expected object", pos));
  }
  pos = _ws(text, pos + 1);
  if pos < n && core.vault_byte(text, pos) == 125 {
    return _err_hit("vault: json key not found: " + key);
  }
  var done = false;
  while !done {
    let nr = _scan_string(text, pos);
    if !nr.is_ok {
      return _err_hit(nr.error);
    }
    let nh: VaultJsonHit = nr.value;
    let dv = _decode_range(text, nh.start + 1, nh.end - 1);
    if !dv.is_ok {
      return _err_hit(dv.error);
    }
    let name: Str = dv.value;
    pos = _ws(text, nh.next);
    if pos >= n || core.vault_byte(text, pos) != 58 {
      return _err_hit(core.vault_err_at("json expected ':'", pos));
    }
    pos = _ws(text, pos + 1);
    let vr = _scan_value(text, pos, 0);
    if !vr.is_ok {
      return _err_hit(vr.error);
    }
    let vh: VaultJsonHit = vr.value;
    if core.vault_str_eq(name, key) {
      return _ok_hit(vh);
    }
    pos = _ws(text, vh.next);
    if pos >= n {
      return _err_hit(core.vault_err_at("json unterminated object", pos));
    }
    let c = core.vault_byte(text, pos);
    if c == 44 {
      pos = _ws(text, pos + 1);
    } elif c == 125 {
      done = true;
    } else {
      return _err_hit(core.vault_err_at("json expected ',' or '}'", pos));
    }
  }
  return _err_hit("vault: json key not found: " + key);
}

/// Raw text of a top-level member (for strings this includes the quotes).
/// Params: text - a JSON object; key - the member name.
/// Returns: Ok(raw slice). Error case: the vault_json_lookup catalog.
/// Complexity: O(text.len()).
pub fn vault_json_get_raw(text: Str, key: Str) -> Result[Str, Str] {
  let r = vault_json_lookup(text, key);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let h: VaultJsonHit = r.value;
  return _ok_str(string.str_slice(text, h.start, h.end));
}

/// Decode a top-level string member (escapes applied).
/// Params: text - a JSON object; key - the member name.
/// Returns: Ok(decoded string).
/// Error case: the vault_json_lookup catalog plus Err("vault: json value is
/// not a string").
/// Complexity: O(text.len()).
pub fn vault_json_get_str(text: Str, key: Str) -> Result[Str, Str] {
  let r = vault_json_lookup(text, key);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let h: VaultJsonHit = r.value;
  if h.kind != VAULT_JSON_STRING {
    return _err_str("vault: json value is not a string");
  }
  return _decode_range(text, h.start + 1, h.end - 1);
}

/// Decode a top-level decimal-integer member (no fraction or exponent).
/// Params: text - a JSON object; key - the member name.
/// Returns: Ok(integer).
/// Error case: the vault_json_lookup catalog plus Err("vault: json value is
/// not an integer") for other kinds, fractions, exponents and overflow.
/// Complexity: O(text.len()).
pub fn vault_json_get_int(text: Str, key: Str) -> Result[Int, Str] {
  let r = vault_json_lookup(text, key);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let h: VaultJsonHit = r.value;
  if h.kind != VAULT_JSON_NUMBER {
    return _err_int("vault: json value is not an integer");
  }
  let raw = string.str_slice(text, h.start, h.end);
  var i = 0;
  if i < raw.len() && core.vault_byte(raw, 0) == 45 {
    i = 1;
  }
  if i >= raw.len() {
    return _err_int("vault: json value is not an integer");
  }
  while i < raw.len() {
    let d = core.vault_byte(raw, i);
    if d < 48 || d > 57 {
      return _err_int("vault: json value is not an integer");
    }
    i = i + 1;
  }
  let pr = string.str_to_int(raw);
  if !pr.is_ok {
    return _err_int("vault: json value is not an integer");
  }
  let v: Int = pr.value;
  return _ok_int(v);
}

/// Decode a top-level boolean member (exactly true / false).
/// Params: text - a JSON object; key - the member name.
/// Returns: Ok(value).
/// Error case: the vault_json_lookup catalog plus Err("vault: json value is
/// not a boolean").
/// Complexity: O(text.len()).
pub fn vault_json_get_bool(text: Str, key: Str) -> Result[Bool, Str] {
  let r = vault_json_lookup(text, key);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let h: VaultJsonHit = r.value;
  if h.kind != VAULT_JSON_LITERAL {
    return _err_bool("vault: json value is not a boolean");
  }
  let raw = string.str_slice(text, h.start, h.end);
  if core.vault_str_eq(raw, "true") {
    return _ok_bool(true);
  }
  if core.vault_str_eq(raw, "false") {
    return _ok_bool(false);
  }
  return _err_bool("vault: json value is not a boolean");
}

/// Decode the string elements of an array hit (up to 256 elements);
/// non-string elements are rejected.
/// Params: text - a JSON object; hit - an array hit from vault_json_lookup.
/// Returns: Ok(vector of decoded strings).
/// Error case: Err("vault: json value is not an array"),
/// Err("vault: json array element is not a string"), the string catalog and
/// Err("vault: json array is too long").
/// Complexity: O(array text).
pub fn vault_json_strs_at(text: Str, hit: &VaultJsonHit) -> Result[Vec[Str], Str] {
  let n = text.len();
  var out = Vec[Str].new();
  if hit.kind != VAULT_JSON_ARRAY {
    return _err_strs("vault: json value is not an array");
  }
  var pos = _ws(text, hit.start + 1);
  if pos < n && core.vault_byte(text, pos) == 93 {
    return _ok_strs(out);
  }
  var done = false;
  while !done {
    let sr = _scan_string(text, pos);
    if !sr.is_ok {
      return _err_strs("vault: json array element is not a string");
    }
    let sh: VaultJsonHit = sr.value;
    let dv = _decode_range(text, sh.start + 1, sh.end - 1);
    if !dv.is_ok {
      return _err_strs(dv.error);
    }
    if out.len() >= VAULT_JSON_MAX_ELEMENTS {
      return _err_strs("vault: json array is too long");
    }
    let sv: Str = dv.value;
    out.push(sv);
    pos = _ws(text, sh.next);
    if pos >= n {
      return _err_strs(core.vault_err_at("json unterminated array", hit.start));
    }
    let c = core.vault_byte(text, pos);
    if c == 44 {
      pos = _ws(text, pos + 1);
    } elif c == 93 {
      done = true;
    } else {
      return _err_strs(core.vault_err_at("json expected ',' or ']'", pos));
    }
  }
  return _ok_strs(out);
}

/// Decode a top-level array-of-strings member (vault `policies` style).
/// Params: text - a JSON object; key - the member name.
/// Returns: Ok(vector of decoded strings).
/// Error case: the vault_json_lookup catalog plus the vault_json_strs_at
/// catalog.
/// Complexity: O(text.len()).
pub fn vault_json_get_strs(text: Str, key: Str) -> Result[Vec[Str], Str] {
  let r = vault_json_lookup(text, key);
  if !r.is_ok {
    return _err_strs(r.error);
  }
  let h: VaultJsonHit = r.value;
  return vault_json_strs_at(text, &h);
}
