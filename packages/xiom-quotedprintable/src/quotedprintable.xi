// XIOM -- xiom.quotedprintable: RFC 2045 quoted-printable encoding and decoding
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) quoted-printable codec for the RFC 2045 section 6.7
// transfer encoding:
//   * qp_encode: printable ASCII (0x21..0x7E) except '=' (0x3D) is copied
//     literally; every other byte becomes '=' + two UPPERCASE hex digits.
//     TAB (0x09) and space (0x20) are literal only while another character
//     follows on the same encoded line; a line-final TAB/space is escaped.
//   * Soft line breaks: long input wraps with '=' + CRLF so that no physical
//     line exceeds 76 characters excluding the trailing CRLF. The marker '='
//     is the 76th character, so a line carries at most 75 payload characters.
//     The final line has no trailing CRLF.
//   * Binary-safe: the encoder emits no hard line break; input CR/LF bytes
//     are escaped as =0D/=0A, so every byte round-trips.
//   * qp_decode is strict: '=' must start either a two-hex-digit escape or a
//     CRLF soft break; a raw CRLF hard break decodes to CR LF. See SPEC.md
//     for the exact error catalog.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType],
//     no Vec[fn] dispatch, no `match` in the library (if/elif chains).
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     _ok_bytes/_err_bytes/_ok_str/_err_str (constructing Results directly
//     inside larger functions miscompiles in this compiler).
//   * Every Vec[UInt8] element read is widened once with
//     (data[i] as Int) & 0xFF before comparison or arithmetic.
//   * The library compares no Str values; callers and tests use
//     xiom.string.compare.str_compare (BUG 17).

module xiom.quotedprintable

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

// TAB (0x09): literal only while not last on an encoded line.
const _QP_TAB: Int = 9;

// CR (0x0D) and LF (0x0A): line-break bytes, escaped by the encoder.
const _QP_LF: Int = 10;
const _QP_CR: Int = 13;

// Space (0x20): literal only while not last on an encoded line.
const _QP_SPACE: Int = 32;

// '=' (0x3D): the escape and soft-break marker.
const _QP_EQUALS: Int = 61;

// Documented encoded-line limit in characters, excluding the trailing CRLF
// (RFC 2045 section 6.7 rule #4).
const _QP_LINE_LIMIT: Int = 76;

// Payload capacity of a line: the 76-character limit minus the soft-break
// '=' marker. A line is flushed only when another token would not fit, so a
// physical line never exceeds _QP_LINE_LIMIT characters.
const _QP_PAYLOAD_LIMIT: Int = 75;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// True for a byte the encoder may write literally: printable ASCII
// (0x21..0x7E) except '=' (0x3D), which always starts an escape.
fn _qp_literal(b: Int) -> Bool {
  if b < 33 || b > 126 {
    return false;
  }
  if b == _QP_EQUALS {
    return false;
  }
  return true;
}

// True for TAB (0x09) and space (0x20): literal only when not line-final.
fn _qp_ws(b: Int) -> Bool {
  if b == _QP_TAB || b == _QP_SPACE {
    return true;
  }
  return false;
}

// Uppercase hex digit byte for a nibble value (0..15).
fn _qp_hex_upper(n: Int) -> UInt8 {
  if n < 10 {
    return (48 + n) as UInt8;
  }
  return (55 + n) as UInt8;
}

// Numeric value of a hex digit byte (0-9, A-F, a-f); -1 for any other byte.
// Uppercase is the canonical encoder output; lowercase is accepted here so
// decoding is tolerant while encoding stays canonical.
fn _qp_hex_value(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 65 && b <= 70 {
    return b - 55;
  }
  if b >= 97 && b <= 102 {
    return b - 87;
  }
  return -1;
}

// Raw bytes of a Str (one byte per index; embedded bytes pass through).
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Encoding
// --------------------------------------------------

/// Encode `data` as quoted-printable bytes (RFC 2045 section 6.7).
/// Params: data - the raw bytes to encode; any byte value is accepted.
/// Returns: printable ASCII 0x21..0x7E except '=' (0x3D) copied literally;
/// '=' and every other byte written as '=' + two uppercase hex digits
/// (0x00 -> "=00", 0x0D -> "=0D", 0xFF -> "=FF"). TAB (0x09) and space
/// (0x20) are literal except when they would be the last character of an
/// encoded line or the last byte of the input, where they are written as
/// "=09"/"=20". Long input is wrapped with soft line breaks ('=' + CRLF) so
/// that no line exceeds 76 characters excluding the trailing CRLF; the
/// marker '=' is the 76th character, so each line carries at most 75 payload
/// characters. The final line has no trailing CRLF. Empty input yields
/// empty output.
/// Error case: none (total).
/// Complexity: O(data.len()).
pub fn qp_encode(data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = data.len();
  var line_len = 0;
  var i = 0;
  while i < n {
    let b = (data[i] as Int) & 0xFF;
    var literal = false;
    var size = 3;
    if _qp_literal(b) {
      literal = true;
      size = 1;
    } elif _qp_ws(b) {
      // A TAB/space may be literal only when the line still has room for at
      // least one more token (an escape needs at most 3 characters), so the
      // whitespace byte can never end up as the last character of a line.
      if i + 1 < n && line_len + 4 <= _QP_PAYLOAD_LIMIT {
        literal = true;
        size = 1;
      }
    }
    if line_len + size > _QP_PAYLOAD_LIMIT {
      out.push(61u8);
      out.push(13u8);
      out.push(10u8);
      line_len = 0;
    }
    if literal {
      out.push(data[i]);
      line_len = line_len + 1;
    } else {
      out.push(61u8);
      out.push(_qp_hex_upper(b >> 4));
      out.push(_qp_hex_upper(b & 15));
      line_len = line_len + 3;
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Decoding
// --------------------------------------------------

/// Decode quoted-printable bytes to the bytes they represent.
/// Params: data - the encoded bytes.
/// Returns: Ok(bytes) for well-formed input. "=XX" (two hex digits,
/// case-insensitive; uppercase is canonical) decodes to the byte 0xXX; "="
/// followed by CRLF is a soft line break and yields nothing; a raw CRLF hard
/// break decodes to CR LF; every other byte is copied literally, including
/// spaces and TABs (no trailing-whitespace stripping is performed). Empty
/// input yields Ok(empty).
/// Error case: Err("quotedprintable: ...") on the first violation; the
/// catalog is: "quotedprintable: stray equals" ('=' followed by a byte that
/// cannot begin an escape and is not CR/LF), "quotedprintable: invalid hex
/// digit" (the second character of an escape is not a hex digit),
/// "quotedprintable: truncated escape at EOF" (input ends after '=' or after
/// '=' plus one hex digit), "quotedprintable: invalid line break" (raw LF,
/// raw CR without LF, '=' + LF, '=' + CR not followed by LF).
/// Complexity: O(data.len()).
pub fn qp_decode(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = data.len();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b = (data[i] as Int) & 0xFF;
    if b == _QP_EQUALS {
      if i + 1 >= n {
        return _err_bytes("quotedprintable: truncated escape at EOF");
      }
      let c = (data[i + 1] as Int) & 0xFF;
      if c == _QP_CR {
        if i + 2 >= n {
          return _err_bytes("quotedprintable: invalid line break");
        }
        let d = (data[i + 2] as Int) & 0xFF;
        if d != _QP_LF {
          return _err_bytes("quotedprintable: invalid line break");
        }
        i = i + 3;
      } elif c == _QP_LF {
        return _err_bytes("quotedprintable: invalid line break");
      } else {
        let hi = _qp_hex_value(c);
        if hi < 0 {
          return _err_bytes("quotedprintable: stray equals");
        }
        if i + 2 >= n {
          return _err_bytes("quotedprintable: truncated escape at EOF");
        }
        let lo = _qp_hex_value((data[i + 2] as Int) & 0xFF);
        if lo < 0 {
          return _err_bytes("quotedprintable: invalid hex digit");
        }
        out.push(((hi << 4) | lo) as UInt8);
        i = i + 3;
      }
    } elif b == _QP_CR {
      if i + 1 >= n {
        return _err_bytes("quotedprintable: invalid line break");
      }
      let c = (data[i + 1] as Int) & 0xFF;
      if c != _QP_LF {
        return _err_bytes("quotedprintable: invalid line break");
      }
      out.push(13u8);
      out.push(10u8);
      i = i + 2;
    } elif b == _QP_LF {
      return _err_bytes("quotedprintable: invalid line break");
    } else {
      out.push(data[i]);
      i = i + 1;
    }
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Text convenience wrappers
// --------------------------------------------------

/// Encode the raw UTF-8 bytes of a Str as quoted-printable text.
/// Params: s - any Str; its UTF-8 bytes are treated as opaque bytes.
/// Returns: the quoted-printable encoding of those bytes as a Str; empty
/// input yields "". See qp_encode for the encoding rules.
/// Error case: none (total).
/// Complexity: O(s.len()).
pub fn qp_encode_str(s: Str) -> Str {
  let data = _str_bytes(s);
  let enc = qp_encode(&data);
  return builder.sb_to_str(&enc);
}

/// Decode quoted-printable text to a Str over the decoded bytes.
/// Params: s - the encoded text.
/// Returns: Ok(text) built from the decoded bytes; empty input yields Ok("").
/// Error case: the qp_decode catalog applies unchanged; Err(...) carries the
/// same message.
/// Complexity: O(s.len()).
pub fn qp_decode_str(s: Str) -> Result[Str, Str] {
  let data = _str_bytes(s);
  let dec = qp_decode(&data);
  if !dec.is_ok {
    return _err_str(dec.error);
  }
  // v0.61.3 quirk: a Result field passed straight into a &Vec[UInt8]
  // parameter reads as an empty vector, so bind it to a local first (the
  // same workaround xiom.base58 documents).
  let raw = dec.value;
  return _ok_str(builder.sb_to_str(&raw));
}

// --------------------------------------------------
//  Validation and constants
// --------------------------------------------------

/// True when `data` is well-formed quoted-printable.
/// Params: data - the candidate encoded bytes.
/// Returns: true when qp_decode(data) would return Ok; true for empty input.
/// Error case: none.
/// Complexity: O(data.len()).
pub fn qp_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = qp_decode(data);
  if r.is_ok {
    return true;
  }
  return false;
}

/// The documented encoded-line limit in characters, excluding the trailing
/// CRLF: 76 (RFC 2045 section 6.7 rule #4).
/// Params: none.
/// Returns: 76.
/// Error case: none.
/// Complexity: O(1).
pub fn qp_line_limit() -> Int {
  return _QP_LINE_LIMIT;
}
