// XIOM -- xiom.escape: string escaping and unescaping for JSON, HTML and URL
// Port task: replace the xiom.escape placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact per-function mapping, the error
// catalog and the test plan):
//   * JSON strings: RFC 8259 escapes for " \ and the C0 controls; \uXXXX
//     decoding is BMP-only and encodes to UTF-8.
//   * HTML text/attribute values: the five named entities &amp; &lt; &gt;
//     &quot; &apos; plus numeric references &#NN; and &#xHH; (decimal/hex).
//   * URL components: RFC 3986 percent-encoding; only the unreserved set
//     [A-Za-z0-9-_.~] passes through, space becomes %20.
//   * POSIX shell double-quoted contexts: backslash-escape \ " $ `.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (one allocation per result Str).
//   * Ok/Err for Result[Str, Str] are constructed only in the tiny leaf
//     helpers _ok_str/_err_str (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).
//
// Infallible by design: escape_* always succeeds; only the unescape_*
// functions that must report malformed input return Result (HTML unescaping is
// deliberately lenient and infallible, matching the xiom.xml entity decoder).

module xiom.escape

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

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

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _ESC_TAB: UInt8 = 9u8;
const _ESC_LF: UInt8 = 10u8;
const _ESC_FF: UInt8 = 12u8;
const _ESC_CR: UInt8 = 13u8;
const _ESC_BS: UInt8 = 8u8;
const _ESC_SPACE: UInt8 = 32u8;
const _ESC_DQUOTE: UInt8 = 34u8;
const _ESC_HASH: UInt8 = 35u8;
const _ESC_DOLLAR: UInt8 = 36u8;
const _ESC_PCT: UInt8 = 37u8;
const _ESC_AMP: UInt8 = 38u8;
const _ESC_SQUOTE: UInt8 = 39u8;
const _ESC_SLASH: UInt8 = 47u8;
const _ESC_SEMI: UInt8 = 59u8;
const _ESC_LT: UInt8 = 60u8;
const _ESC_GT: UInt8 = 62u8;
const _ESC_BACKSLASH: UInt8 = 92u8;
const _ESC_BACKTICK: UInt8 = 96u8;
const _ESC_LOWER_B: UInt8 = 98u8;
const _ESC_LOWER_F: UInt8 = 102u8;
const _ESC_LOWER_N: UInt8 = 110u8;
const _ESC_LOWER_R: UInt8 = 114u8;
const _ESC_LOWER_T: UInt8 = 116u8;
const _ESC_LOWER_U: UInt8 = 117u8;
const _ESC_LOWER_X: UInt8 = 120u8;
const _ESC_UPPER_X: UInt8 = 88u8;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Uppercase hex digit byte for a nibble value (0-15).
fn _hex_upper(n: Int) -> UInt8 {
  if n < 10 {
    return (48 + n) as UInt8;
  }
  return (55 + n) as UInt8;
}

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 for any other byte.
fn _hex_value(b: UInt8) -> Int {
  let c = (b as Int) & 0xFF;
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  if c >= 97 && c <= 102 {
    return c - 87;
  }
  if c >= 65 && c <= 70 {
    return c - 55;
  }
  return -1;
}

// Append the UTF-8 encoding of `code` (1..0x10FFFF) to `out`.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push(code as UInt8);
    return;
  }
  if code <= 2047 {
    out.push((192 + code / 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push((224 + code / 4096) as UInt8);
    out.push((128 + (code / 64) % 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  out.push((240 + code / 262144) as UInt8);
  out.push((128 + (code / 4096) % 64) as UInt8);
  out.push((128 + (code / 64) % 64) as UInt8);
  out.push((128 + code % 64) as UInt8);
}

// --------------------------------------------------
//  JSON
// --------------------------------------------------

/// Escape a string for embedding in a JSON string literal (RFC 8259).
/// Params: s - the raw text; UTF-8 bytes above the control range pass through.
/// Returns: s with `"` -> `\"`, `\` -> `\\`, backspace -> `\b`, form feed ->
/// `\f`, LF -> `\n`, CR -> `\r`, tab -> `\t`, and every other C0 control byte
/// (0x00-0x1F) -> `\u00XX` with uppercase hex. `/` and DEL are NOT escaped
/// (both are legal raw in JSON).
/// Error case: none.
/// Complexity: O(s.len()).
pub fn escape_json_string(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _ESC_DQUOTE {
      builder.sb_push_str(&mut out, "\\\"");
    } elif b == _ESC_BACKSLASH {
      builder.sb_push_str(&mut out, "\\\\");
    } elif b == _ESC_BS {
      builder.sb_push_str(&mut out, "\\b");
    } elif b == _ESC_FF {
      builder.sb_push_str(&mut out, "\\f");
    } elif b == _ESC_LF {
      builder.sb_push_str(&mut out, "\\n");
    } elif b == _ESC_CR {
      builder.sb_push_str(&mut out, "\\r");
    } elif b == _ESC_TAB {
      builder.sb_push_str(&mut out, "\\t");
    } elif b < _ESC_SPACE {
      builder.sb_push_str(&mut out, "\\u00");
      let v = (b as Int) & 0xFF;
      out.push(_hex_upper(v >> 4));
      out.push(_hex_upper(v & 15));
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Decode a JSON string body (inverse of escape_json_string).
/// Params: s - the JSON string contents without the surrounding quotes.
/// Returns: Ok(text) with `\"` `\\` `\/` `\b` `\f` `\n` `\r` `\t` decoded and
/// `\uXXXX` decoded from four hex digits (case-insensitive letters) into the
/// UTF-8 encoding of the code point. Only the BMP is supported; surrogate
/// code points and U+0000 are rejected.
/// Error case: Err("escape: ...") - trailing backslash, invalid escape
/// sequence, truncated unicode escape, invalid unicode escape, lone
/// surrogate, null escape not supported. See SPEC.md for the catalog.
/// Complexity: O(s.len()).
pub fn unescape_json_string(s: Str) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b != _ESC_BACKSLASH {
      out.push(b);
      i = i + 1;
    } else {
      if i + 1 >= n {
        return _err_str("escape: trailing backslash");
      }
      let e = string.byte_at(s, i + 1);
      if e == _ESC_DQUOTE {
        out.push(_ESC_DQUOTE);
        i = i + 2;
      } elif e == _ESC_BACKSLASH {
        out.push(_ESC_BACKSLASH);
        i = i + 2;
      } elif e == _ESC_SLASH {
        out.push(_ESC_SLASH);
        i = i + 2;
      } elif e == _ESC_LOWER_B {
        out.push(_ESC_BS);
        i = i + 2;
      } elif e == _ESC_LOWER_F {
        out.push(_ESC_FF);
        i = i + 2;
      } elif e == _ESC_LOWER_N {
        out.push(_ESC_LF);
        i = i + 2;
      } elif e == _ESC_LOWER_R {
        out.push(_ESC_CR);
        i = i + 2;
      } elif e == _ESC_LOWER_T {
        out.push(_ESC_TAB);
        i = i + 2;
      } elif e == _ESC_LOWER_U {
        if i + 5 >= n {
          return _err_str("escape: truncated unicode escape");
        }
        let h0 = _hex_value(string.byte_at(s, i + 2));
        let h1 = _hex_value(string.byte_at(s, i + 3));
        let h2 = _hex_value(string.byte_at(s, i + 4));
        let h3 = _hex_value(string.byte_at(s, i + 5));
        if h0 < 0 || h1 < 0 || h2 < 0 || h3 < 0 {
          return _err_str("escape: invalid unicode escape");
        }
        let code = (h0 << 12) | (h1 << 8) | (h2 << 4) | h3;
        if code == 0 {
          return _err_str("escape: null escape not supported");
        }
        if code >= 0xD800 && code <= 0xDFFF {
          return _err_str("escape: lone surrogate");
        }
        _push_utf8(&mut out, code);
        i = i + 6;
      } else {
        return _err_str("escape: invalid escape sequence");
      }
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  HTML
// --------------------------------------------------

/// Escape the five HTML metacharacters as named entities.
/// Params: s - the text to escape.
/// Returns: s with `&` -> `&amp;`, `<` -> `&lt;`, `>` -> `&gt;`, `"` ->
/// `&quot;` and `'` -> `&apos;`; every other byte (including UTF-8 sequences)
/// passes through.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn escape_html(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _ESC_AMP {
      builder.sb_push_str(&mut out, "&amp;");
    } elif b == _ESC_LT {
      builder.sb_push_str(&mut out, "&lt;");
    } elif b == _ESC_GT {
      builder.sb_push_str(&mut out, "&gt;");
    } elif b == _ESC_DQUOTE {
      builder.sb_push_str(&mut out, "&quot;");
    } elif b == _ESC_SQUOTE {
      builder.sb_push_str(&mut out, "&apos;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Codepoint of a "#NN" or "#xHH" numeric reference body, -1 when malformed,
// out of range (> U+10FFFF), NUL or a surrogate code point.
fn _numeric_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 {
    return -1;
  }
  if string.byte_at(body, 0) != _ESC_HASH {
    return -1;
  }
  var i = 1;
  var base = 10;
  let mark = string.byte_at(body, i);
  if mark == _ESC_LOWER_X || mark == _ESC_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n {
    return -1;
  }
  var v = 0;
  while i < n {
    let b = string.byte_at(body, i);
    var d = -1;
    if b >= 48u8 && b <= 57u8 {
      d = (b as Int) - 48;
    } elif base == 16 && b >= 97u8 && b <= 102u8 {
      d = (b as Int) - 87;
    } elif base == 16 && b >= 65u8 && b <= 70u8 {
      d = (b as Int) - 55;
    } else {
      return -1;
    }
    if d >= base {
      return -1;
    }
    v = v * base + d;
    if v > 1114111 {
      return -1;
    }
    i = i + 1;
  }
  if v == 0 {
    return -1;
  }
  if v >= 0xD800 && v <= 0xDFFF {
    return -1;
  }
  return v;
}

/// Decode named entities and numeric references in HTML text or attribute
/// values (inverse of most of escape_html).
/// Params: s - the text to decode.
/// Returns: s with `&amp;` `&lt;` `&gt;` `&quot;` `&apos;`, `&#NN;` (decimal)
/// and `&#xHH;` (hex, either case for the marker and digits) decoded; unknown
/// or malformed references (including bare `&`) pass through verbatim, one
/// byte at a time, so `&amp;lt;` decodes to `&lt;` and not to `<`.
/// Error case: none (lenient by design; see SPEC.md).
/// Complexity: O(s.len()).
pub fn unescape_html(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b != _ESC_AMP {
      out.push(b);
      i = i + 1;
    } else {
      var limit = i + 11;
      if limit > n {
        limit = n;
      }
      var semi = -1;
      var j = i + 1;
      while j < limit {
        if string.byte_at(s, j) == _ESC_SEMI {
          semi = j;
          break;
        }
        j = j + 1;
      }
      if semi < 0 {
        out.push(_ESC_AMP);
        i = i + 1;
      } else {
        let body = string.str_slice(s, i + 1, semi);
        var matched = false;
        if compare.str_compare(body, "amp") == 0 {
          out.push(_ESC_AMP);
          matched = true;
        } elif compare.str_compare(body, "lt") == 0 {
          out.push(_ESC_LT);
          matched = true;
        } elif compare.str_compare(body, "gt") == 0 {
          out.push(_ESC_GT);
          matched = true;
        } elif compare.str_compare(body, "quot") == 0 {
          out.push(_ESC_DQUOTE);
          matched = true;
        } elif compare.str_compare(body, "apos") == 0 {
          out.push(_ESC_SQUOTE);
          matched = true;
        }
        if matched {
          i = semi + 1;
        } else {
          let code = _numeric_code(body);
          if code > 0 {
            _push_utf8(&mut out, code);
            i = semi + 1;
          } else {
            out.push(_ESC_AMP);
            i = i + 1;
          }
        }
      }
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  URL
// --------------------------------------------------

// True for an RFC 3986 unreserved byte: A-Z a-z 0-9 - _ . ~.
fn _is_unreserved(b: Int) -> Bool {
  if b >= 65 && b <= 90 {
    return true;
  }
  if b >= 97 && b <= 122 {
    return true;
  }
  if b >= 48 && b <= 57 {
    return true;
  }
  if b == 45 || b == 95 || b == 46 || b == 126 {
    return true;
  }
  return false;
}

/// Percent-encode one URL component (RFC 3986).
/// Params: s - the raw component text.
/// Returns: s with every byte outside the unreserved set
/// [A-Za-z0-9-_.~] written as `%XX` with uppercase hex; space becomes `%20`.
/// Non-ASCII text is encoded per UTF-8 byte (e.g. "é" -> "%C3%A9").
/// Error case: none.
/// Complexity: O(s.len()).
pub fn escape_url_component(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v = (b as Int) & 0xFF;
    if _is_unreserved(v) {
      out.push(b);
    } else {
      out.push(_ESC_PCT);
      out.push(_hex_upper(v >> 4));
      out.push(_hex_upper(v & 15));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Decode percent-escapes in one URL component (inverse of
/// escape_url_component).
/// Params: s - the encoded component text.
/// Returns: Ok(text) with every `%XX` (hex digits case-insensitive) replaced
/// by the byte it denotes; `+` is NOT a space and passes through literally.
/// Error case: Err("escape: ...") - truncated percent escape (fewer than two
/// bytes after `%`), invalid percent escape (non-hex digit). See SPEC.md.
/// Complexity: O(s.len()).
pub fn unescape_url_component(s: Str) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b != _ESC_PCT {
      out.push(b);
      i = i + 1;
    } else {
      if i + 2 >= n {
        return _err_str("escape: truncated percent escape");
      }
      let hi = _hex_value(string.byte_at(s, i + 1));
      let lo = _hex_value(string.byte_at(s, i + 2));
      if hi < 0 || lo < 0 {
        return _err_str("escape: invalid percent escape");
      }
      out.push(((hi << 4) | lo) as UInt8);
      i = i + 3;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Shell
// --------------------------------------------------

/// Escape text for a POSIX shell double-quoted context.
/// Params: s - the raw text.
/// Returns: s with `\`, `"`, `$` and `` ` `` each prefixed by a backslash;
/// every other byte passes through unchanged.
/// Error case: none. The result is only safe inside double quotes; single
/// quotes, `!` history expansion and newline handling are out of scope
/// (see SPEC.md).
/// Complexity: O(s.len()).
pub fn escape_shell_double(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _ESC_BACKSLASH || b == _ESC_DQUOTE || b == _ESC_DOLLAR || b == _ESC_BACKTICK {
      out.push(_ESC_BACKSLASH);
    }
    out.push(b);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
