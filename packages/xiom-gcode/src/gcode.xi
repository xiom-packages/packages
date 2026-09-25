// XIOM -- xiom.gcode: G-code parsing and canonical emission
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM codec for a documented subset of RS-274-style G-code:
//
//   * one optional line number word `Nnn` per line (first word only),
//   * a command word (first word after the line number) and zero or more
//     parameter words, each a letter (case-insensitive, normalized to
//     uppercase) immediately followed by a decimal number,
//   * `;` end-of-line comments and `( ... )` comments anywhere between words,
//   * an optional checksum suffix `*hh` validated as the XOR of every byte
//     that precedes the `*` (comments included),
//   * whitespace (space, tab, CR, LF) tolerated between tokens.
//
// Parsing is byte-oriented and deterministic. Numbers are kept twice: the
// verbatim text is preserved, and the accessors expose a signed 64-bit
// scaled integer plus the number of decimal fraction digits (scale). See
// SPEC.md for the exact grammar, the checksum rule, the scaling contract and
// the error catalog.
//
// Language notes (XIOM v0.61.3): free functions only -- no self methods, no
// lambdas, no Vec[StructType] (the program is a struct of parallel Vecs), no
// Vec[Float64]; Str values read from Vec[Str] elements are never compared
// with `==` (BUG 17 lowers that to a pointer comparison), element reads are
// bound with typed `let`s, and Ok/Err are constructed only in the tiny leaf
// helpers below because constructing a Result inside a larger function
// miscompiles.

module xiom.gcode

use xiom.string;
use xiom.math;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _GC_TAB: UInt8 = 9u8;
const _GC_LF: UInt8 = 10u8;
const _GC_CR: UInt8 = 13u8;
const _GC_LPAREN: UInt8 = 40u8;
const _GC_RPAREN: UInt8 = 41u8;
const _GC_STAR: UInt8 = 42u8;
const _GC_PLUS: UInt8 = 43u8;
const _GC_MINUS: UInt8 = 45u8;
const _GC_DOT: UInt8 = 46u8;
const _GC_SPACE: UInt8 = 32u8;
const _GC_ZERO: UInt8 = 48u8;
const _GC_NINE: UInt8 = 57u8;
const _GC_SEMI: UInt8 = 59u8;
const _GC_CAP_A: UInt8 = 65u8;
const _GC_CAP_F: UInt8 = 70u8;
const _GC_CAP_N: UInt8 = 78u8;
const _GC_CAP_Z: UInt8 = 90u8;
const _GC_LOWER_A: UInt8 = 97u8;
const _GC_LOWER_F: UInt8 = 102u8;
const _GC_LOWER_Z: UInt8 = 122u8;
const _GC_INT_MAX_DIV10: Int = 922337203685477580;
const _GC_INT_MAX_LAST_DIGIT: Int = 7;
const _GC_INT_MAX: Int = 9223372036854775807;
const _GC_MAX_SCALE: Int = 18;

// ---------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------

// One parsed command word: its letter (uppercase), the verbatim number text,
// the signed scaled integer and the scale (number of decimal fraction digits,
// 0-18). "X10.5" yields text "10.5", value 105, scale 1. Internal only.
type GcodeNum = {
  value: Int;
  scale: Int;
  int_digits: Int;
  had_sign: Bool;
  had_dot: Bool;
}

// One parsed physical line. `blank` lines carry no command and are skipped by
// gcode_parse. Parameter words are stored in four parallel Vecs; parameter j
// is addressed with gcode_param_* accessors.
pub type GcodeLine = {
  blank: Bool;
  line_number: Int;
  command_letter: Str;
  command_text: Str;
  command_value: Int;
  command_scale: Int;
  param_letters: Vec[Str];
  param_texts: Vec[Str];
  param_values: Vec[Int];
  param_scales: Vec[Int];
}

// A parsed document: one entry per non-blank physical line (the command
// stream) plus the flat parameter stream, because XIOM v0.61.3 cannot hold a
// Vec[StructType]. For line i, parameters occupy
// [param_start[i], param_start[i] + param_count[i]).
pub type GcodeProgram = {
  line_numbers: Vec[Int];
  letters: Vec[Str];
  texts: Vec[Str];
  values: Vec[Int];
  scales: Vec[Int];
  param_start: Vec[Int];
  param_count: Vec[Int];
  param_letters: Vec[Str];
  param_texts: Vec[Str];
  param_values: Vec[Int];
  param_scales: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (see the module header)
// ---------------------------------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[GcodeNum, Str].
fn _ok_num(v: GcodeNum) -> Result[GcodeNum, Str] {
  return Ok(v);
}

// Err(m) for Result[GcodeNum, Str]; `m` is a bare detail (no package prefix).
fn _err_num(m: Str) -> Result[GcodeNum, Str] {
  return Err(m);
}

// Ok(v) for Result[GcodeLine, Str].
fn _ok_line(v: GcodeLine) -> Result[GcodeLine, Str] {
  return Ok(v);
}

// Err(m) for Result[GcodeLine, Str]; `m` is a bare detail (no package prefix).
fn _err_line(m: Str) -> Result[GcodeLine, Str] {
  return Err(m);
}

// Ok(v) for Result[GcodeProgram, Str].
fn _ok_program(v: GcodeProgram) -> Result[GcodeProgram, Str] {
  return Ok(v);
}

// Err(m) for Result[GcodeProgram, Str]; `m` is a complete message.
fn _err_program(m: Str) -> Result[GcodeProgram, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

// ASCII whitespace byte: space, tab, LF or CR.
fn _is_space_byte(b: UInt8) -> Bool {
  return b == _GC_SPACE || b == _GC_TAB || b == _GC_LF || b == _GC_CR;
}

// ASCII digit byte: 0-9.
fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= _GC_ZERO && b <= _GC_NINE;
}

// ASCII letter byte: A-Z or a-z.
fn _is_letter_byte(b: UInt8) -> Bool {
  if b >= _GC_CAP_A && b <= _GC_CAP_Z { return true; }
  return b >= _GC_LOWER_A && b <= _GC_LOWER_Z;
}

// Uppercase ASCII letter; any other byte is returned unchanged.
fn _upper_byte(b: UInt8) -> UInt8 {
  if b >= _GC_LOWER_A && b <= _GC_LOWER_Z { return b - 32u8; }
  return b;
}

// Hex digit value 0-15 (either case), or -1 when `b` is not a hex digit.
fn _hex_val(b: UInt8) -> Int {
  if b >= _GC_ZERO && b <= _GC_NINE { return ((b as Int) & 0xFF) - 48; }
  if b >= _GC_CAP_A && b <= _GC_CAP_F { return ((b as Int) & 0xFF) - 55; }
  if b >= _GC_LOWER_A && b <= _GC_LOWER_F { return ((b as Int) & 0xFF) - 87; }
  return -1;
}

// Index just past the ')' that closes the '(' at `open`, or -1 when the
// parenthesized comment is unterminated. Parentheses do not nest.
fn _skip_paren(s: Str, open: Int) -> Int {
  var i = open + 1;
  while i < s.len() {
    if string.byte_at(s, i) == _GC_RPAREN { return i + 1; }
    i = i + 1;
  }
  return -1;
}

// Index just past the offending word that starts at `from`: the run of bytes
// up to the next whitespace byte, '(', ';' or '*'. Always > `from` because
// the caller only invokes it at a non-delimiter byte.
fn _word_end(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if _is_space_byte(b) || b == _GC_LPAREN || b == _GC_SEMI || b == _GC_STAR {
      return i;
    }
    i = i + 1;
  }
  return i;
}

// XOR of the bytes of s[0, upto), each widened to Int; 0 for an empty prefix.
fn _xor_prefix(s: Str, upto: Int) -> Int {
  var acc = 0;
  var i = 0;
  while i < upto {
    acc = math.bit_xor(acc, ((string.byte_at(s, i) as Int) & 0xFF));
    i = i + 1;
  }
  return acc;
}

// 10^k for 0 <= k <= 18 (10^18 fits the signed 64-bit range).
fn _pow10(k: Int) -> Int {
  var p = 1;
  var i = 0;
  while i < k {
    p = p * 10;
    i = i + 1;
  }
  return p;
}

// ---------------------------------------------------------------------------
// Number parsing
// ---------------------------------------------------------------------------

// Parse the number that starts at `from` inside `word`; word[0] is the
// leading letter and is used only for error text. Grammar:
//   number := ('+' | '-')? ( digits ( '.' digits* )? | '.' digits+ )
// The signed magnitude accumulates every digit (integer and fraction alike)
// into one 64-bit integer, so value = magnitude * 10^scale exactly, and the
// magnitude is capped at the signed 64-bit maximum. Errors are bare details:
// "bad number: <word>", "number too large: <word>" or
// "too many fraction digits: <word>".
fn _parse_number(word: Str, from: Int) -> Result[GcodeNum, Str] {
  let n = word.len();
  var k = from;
  var neg = false;
  var had_sign = false;
  if k < n {
    let c = string.byte_at(word, k);
    if c == _GC_PLUS {
      had_sign = true;
      k = k + 1;
    } elif c == _GC_MINUS {
      had_sign = true;
      neg = true;
      k = k + 1;
    }
  }
  var mag = 0;
  var scale = 0;
  var int_digits = 0;
  var had_dot = false;
  while k < n {
    let c = string.byte_at(word, k);
    if _is_digit_byte(c) {
      let d = ((c as Int) & 0xFF) - 48;
      if mag > _GC_INT_MAX_DIV10 { return _err_num("number too large: " + word); }
      if mag == _GC_INT_MAX_DIV10 && d > _GC_INT_MAX_LAST_DIGIT {
        return _err_num("number too large: " + word);
      }
      mag = mag * 10 + d;
      if had_dot {
        scale = scale + 1;
        if scale > _GC_MAX_SCALE { return _err_num("too many fraction digits: " + word); }
      } else {
        int_digits = int_digits + 1;
      }
      k = k + 1;
    } elif c == _GC_DOT {
      if had_dot { return _err_num("bad number: " + word); }
      had_dot = true;
      k = k + 1;
    } else {
      return _err_num("bad number: " + word);
    }
  }
  if int_digits + scale == 0 { return _err_num("bad number: " + word); }
  var value = mag;
  if neg { value = 0 - mag; }
  return _ok_num(GcodeNum{
    value: value;
    scale: scale;
    int_digits: int_digits;
    had_sign: had_sign;
    had_dot: had_dot;
  });
}

// ---------------------------------------------------------------------------
// Line scanning
// ---------------------------------------------------------------------------

// A blank line: no command, no parameters, no checksum.
fn _empty_line() -> GcodeLine {
  return GcodeLine{
    blank: true;
    line_number: -1;
    command_letter: "";
    command_text: "";
    command_value: 0;
    command_scale: 0;
    param_letters: Vec[Str].new();
    param_texts: Vec[Str].new();
    param_values: Vec[Int].new();
    param_scales: Vec[Int].new();
  };
}

// Parse one physical line into its command/parameter stream. Errors are bare
// details; gcode_parse_line adds the "gcode: " prefix and gcode_parse adds
// the "gcode: line <n>: " prefix.
fn _scan_line(text: Str) -> Result[GcodeLine, Str] {
  let n = text.len();
  var i = 0;
  var line_number = -1;
  var has_command = false;
  var saw_word = false;
  var saw_star = false;
  var cmd_letter = "";
  var cmd_text = "";
  var cmd_value = 0;
  var cmd_scale = 0;
  var param_letters = Vec[Str].new();
  var param_texts = Vec[Str].new();
  var param_values = Vec[Int].new();
  var param_scales = Vec[Int].new();
  while i < n {
    let b = string.byte_at(text, i);
    if _is_space_byte(b) {
      i = i + 1;
    } elif b == _GC_SEMI {
      i = n;
    } elif b == _GC_LPAREN {
      let e = _skip_paren(text, i);
      if e < 0 { return _err_line("unterminated paren comment"); }
      i = e;
    } elif b == _GC_STAR {
      if i + 2 >= n { return _err_line("bad checksum"); }
      let hi = _hex_val(string.byte_at(text, i + 1));
      let lo = _hex_val(string.byte_at(text, i + 2));
      if hi < 0 || lo < 0 { return _err_line("bad checksum"); }
      var j = i + 3;
      while j < n {
        let c = string.byte_at(text, j);
        if _is_space_byte(c) {
          j = j + 1;
        } elif c == _GC_SEMI {
          j = n;
        } elif c == _GC_LPAREN {
          let e = _skip_paren(text, j);
          if e < 0 { return _err_line("unterminated paren comment"); }
          j = e;
        } else {
          return _err_line("trailing garbage");
        }
      }
      let computed = _xor_prefix(text, i);
      if hi * 16 + lo != computed {
        return _err_line("checksum mismatch: " + string.str_slice(text, i + 1, i + 3));
      }
      saw_star = true;
      i = n;
    } elif _is_letter_byte(b) {
      let letter = _upper_byte(b);
      var k = i + 1;
      while k < n {
        let c = string.byte_at(text, k);
        if _is_digit_byte(c) || c == _GC_DOT || c == _GC_PLUS || c == _GC_MINUS {
          k = k + 1;
        } else {
          break;
        }
      }
      if !saw_word && letter == _GC_CAP_N {
        var num_ok = false;
        if k > i + 1 {
          let word = string.str_slice(text, i, k);
          let pr = _parse_number(word, 1);
          if pr.is_ok {
            let num: GcodeNum = pr.value;
            if !num.had_sign && !num.had_dot && num.int_digits > 0 {
              line_number = num.value;
              num_ok = true;
            }
          }
        }
        if !num_ok { return _err_line("bad line number"); }
        saw_word = true;
        i = k;
      } elif k == i + 1 {
        let e = _word_end(text, i);
        return _err_line("bad number: " + string.str_slice(text, i, e));
      } else {
        let word = string.str_slice(text, i, k);
        let pr = _parse_number(word, 1);
        if !pr.is_ok { return _err_line(pr.error); }
        let num: GcodeNum = pr.value;
        let num_text = string.str_slice(text, i + 1, k);
        let letter_text = string.str_upper(string.str_slice(text, i, i + 1));
        if !has_command {
          cmd_letter = letter_text;
          cmd_text = num_text;
          cmd_value = num.value;
          cmd_scale = num.scale;
          has_command = true;
        } else {
          param_letters.push(letter_text);
          param_texts.push(num_text);
          param_values.push(num.value);
          param_scales.push(num.scale);
        }
        saw_word = true;
        i = k;
      }
    } elif _is_digit_byte(b) || b == _GC_DOT || b == _GC_PLUS || b == _GC_MINUS {
      let e = _word_end(text, i);
      return _err_line("bad number: " + string.str_slice(text, i, e));
    } else {
      return _err_line("unexpected character at " + int_to_string(i));
    }
  }
  if !has_command {
    if line_number < 0 && !saw_word && !saw_star {
      return _ok_line(_empty_line());
    }
    return _err_line("missing command");
  }
  return _ok_line(GcodeLine{
    blank: false;
    line_number: line_number;
    command_letter: cmd_letter;
    command_text: cmd_text;
    command_value: cmd_value;
    command_scale: cmd_scale;
    param_letters: param_letters;
    param_texts: param_texts;
    param_values: param_values;
    param_scales: param_scales;
  });
}

// ---------------------------------------------------------------------------
// Public parsing API
// ---------------------------------------------------------------------------

/// Parse one physical line of G-code.
/// Params: text - the line text, without its terminator (a trailing CR is
/// tolerated as whitespace).
/// Grammar: see SPEC.md section 3; an optional leading `Nnn` line number, a
/// command word, parameter words, `;` and `( ... )` comments wherever
/// whitespace is allowed, and an optional `*hh` checksum at the end.
/// Returns: Ok(GcodeLine) with uppercase letters, verbatim number texts and
/// scaled integer values; a line with no words and no checksum is Ok with
/// `blank = true`.
/// Error case: Err("gcode: bad line number"), Err("gcode: bad number: <word>"),
/// Err("gcode: number too large: <word>"), Err("gcode: too many fraction
/// digits: <word>"), Err("gcode: bad checksum"),
/// Err("gcode: checksum mismatch: <hh>"), Err("gcode: unterminated paren
/// comment"), Err("gcode: trailing garbage"),
/// Err("gcode: unexpected character at <pos>"), Err("gcode: missing command").
/// Complexity: O(len(text)).
pub fn gcode_parse_line(text: Str) -> Result[GcodeLine, Str] {
  let r = _scan_line(text);
  if r.is_ok { return _ok_line(r.value); }
  let e: Str = r.error;
  return _err_line("gcode: " + e);
}

/// Parse a whole G-code text into a command/parameter stream.
/// Params: text - the document text; physical lines are separated by LF and a
/// CR before the LF is treated as whitespace.
/// Grammar: each physical line is parsed as by gcode_parse_line; lines that
/// parse as blank (only whitespace and comments) are skipped and consume no
/// entry in the program, but they still count for error positions.
/// Returns: Ok(GcodeProgram) whose command i is physical parsed line i
/// (0-based) with its line number, command word and parameter range.
/// Error case: Err("gcode: line <n>: <detail>") where <n> is the 1-based
/// physical line number and <detail> is one of the gcode_parse_line details.
/// Complexity: O(len(text)).
pub fn gcode_parse(text: Str) -> Result[GcodeProgram, Str] {
  var line_numbers = Vec[Int].new();
  var letters = Vec[Str].new();
  var texts = Vec[Str].new();
  var values = Vec[Int].new();
  var scales = Vec[Int].new();
  var param_start = Vec[Int].new();
  var param_count = Vec[Int].new();
  var param_letters = Vec[Str].new();
  var param_texts = Vec[Str].new();
  var param_values = Vec[Int].new();
  var param_scales = Vec[Int].new();
  let n = text.len();
  var line_start = 0;
  var line_no = 1;
  var done = false;
  while !done {
    var line_end = line_start;
    while line_end < n {
      if string.byte_at(text, line_end) == _GC_LF { break; }
      line_end = line_end + 1;
    }
    let raw = string.str_slice(text, line_start, line_end);
    let r = _scan_line(raw);
    if !r.is_ok {
      return _err_program("gcode: line " + int_to_string(line_no) + ": " + r.error);
    }
    let l: GcodeLine = r.value;
    if !l.blank {
      line_numbers.push(l.line_number);
      letters.push(l.command_letter);
      texts.push(l.command_text);
      values.push(l.command_value);
      scales.push(l.command_scale);
      param_start.push(param_letters.len());
      param_count.push(l.param_letters.len());
      var j = 0;
      while j < l.param_letters.len() {
        let ltr: Str = l.param_letters[j];
        let txt: Str = l.param_texts[j];
        let val: Int = l.param_values[j];
        let scl: Int = l.param_scales[j];
        param_letters.push(ltr);
        param_texts.push(txt);
        param_values.push(val);
        param_scales.push(scl);
        j = j + 1;
      }
    }
    if line_end >= n {
      done = true;
    } else {
      line_start = line_end + 1;
      line_no = line_no + 1;
    }
  }
  return _ok_program(GcodeProgram{
    line_numbers: line_numbers;
    letters: letters;
    texts: texts;
    values: values;
    scales: scales;
    param_start: param_start;
    param_count: param_count;
    param_letters: param_letters;
    param_texts: param_texts;
    param_values: param_values;
    param_scales: param_scales;
  });
}

// ---------------------------------------------------------------------------
// Emission
// ---------------------------------------------------------------------------

// Canonical decimal text for a scaled value: no leading zeros, no '+', no
// trailing '.', fraction digits preserved exactly (scale 0 -> integer text),
// negative zero normalized to 0. Exact for the full signed 64-bit range:
// the sign is stripped from int_to_string instead of negating the value.
fn _format_number(value: Int, scale: Int) -> Str {
  if scale <= 0 { return int_to_string(value); }
  let full = int_to_string(value);
  var digits = full;
  var neg = false;
  if value < 0 {
    neg = true;
    digits = string.str_slice(full, 1, full.len());
  }
  var ip = "0";
  var frac = digits;
  if digits.len() > scale {
    let cut = digits.len() - scale;
    ip = string.str_slice(digits, 0, cut);
    frac = string.str_slice(digits, cut, digits.len());
  } else {
    while frac.len() < scale {
      frac = "0" + frac;
    }
  }
  var out = ip + "." + frac;
  if neg { out = "-" + out; }
  return out;
}

/// Emit one parsed line in canonical form.
/// Params: line - a line produced by gcode_parse_line or gcode_program_line.
/// Grammar: `N<line number> ` when the line number is >= 0, then the command
/// letter and canonical number, then one space-separated parameter per word.
/// Letters are uppercase, numbers are re-rendered from value/scale (no '+',
/// no leading zeros, no trailing '.', fraction digits kept), and comments and
/// checksums are not emitted. A blank line emits "".
/// Returns: the canonical text, without a newline.
/// Error case: none (the line must come from the parser, or a hand-built line
/// must respect 0 <= scale <= 18; values are exact across the full signed
/// 64-bit range).
/// Complexity: O(len(result)).
pub fn gcode_emit(line: &GcodeLine) -> Str {
  if line.blank { return ""; }
  var out = "";
  if line.line_number >= 0 {
    out = out + "N" + int_to_string(line.line_number) + " ";
  }
  out = out + line.command_letter + _format_number(line.command_value, line.command_scale);
  var j = 0;
  while j < line.param_letters.len() {
    let ltr: Str = line.param_letters[j];
    let val: Int = line.param_values[j];
    let scl: Int = line.param_scales[j];
    out = out + " " + ltr + _format_number(val, scl);
    j = j + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Scaling accessor
// ---------------------------------------------------------------------------

/// Convert a parsed (value, scale) pair to millionths (1e-6 units).
/// Params: value - the scaled integer; scale - its fraction digit count
/// (0-18, as produced by the parser).
/// Rule: numeric value = value / 10^scale. The result is
/// value * 10^(6-scale) for scale <= 6, else value / 10^(scale-6) with the
/// division truncating toward zero; the sign is applied to the magnitude, so
/// negative values truncate toward zero too. Examples: (105, 1) -> 10500000
/// (10.5); (12345, 7) -> 1234 (0.0012345); (-3, 0) -> -3000000.
/// Returns: Ok(micro) -- the exact value when scale <= 6, otherwise the
/// truncated value.
/// Error case: Err("gcode: bad scale") when scale is outside 0-18;
/// Err("gcode: value out of range") when value is below the signed 64-bit
/// minimum plus one, or when the multiplication for scale <= 6 would
/// overflow the signed 64-bit range.
/// Complexity: O(1).
pub fn gcode_micro(value: Int, scale: Int) -> Result[Int, Str] {
  if scale < 0 || scale > _GC_MAX_SCALE { return _err_int("gcode: bad scale"); }
  if value < 0 - _GC_INT_MAX { return _err_int("gcode: value out of range"); }
  var mag = value;
  var neg = false;
  if mag < 0 {
    neg = true;
    mag = 0 - mag;
  }
  if scale <= 6 {
    let p = _pow10(6 - scale);
    if mag > _GC_INT_MAX / p { return _err_int("gcode: value out of range"); }
    mag = mag * p;
  } else {
    mag = mag / _pow10(scale - 6);
  }
  if neg { mag = 0 - mag; }
  return _ok_int(mag);
}

// ---------------------------------------------------------------------------
// Line accessors
// ---------------------------------------------------------------------------

/// Whether the line carried no command and no parameters (it is skipped by
/// gcode_parse). Params: line - the parsed line. Returns: the flag.
/// Error case: none. Complexity: O(1).
pub fn gcode_line_is_blank(line: &GcodeLine) -> Bool {
  return line.blank;
}

/// Line number. Params: line - the parsed line. Returns: the `N` value; -1
/// when the line has no line number (including every blank line).
/// Error case: none. Complexity: O(1).
pub fn gcode_line_number(line: &GcodeLine) -> Int {
  return line.line_number;
}

/// Command letter. Params: line - the parsed line. Returns: the uppercase
/// letter of the first word; "" for a blank line.
/// Error case: none. Complexity: O(1).
pub fn gcode_command_letter(line: &GcodeLine) -> Str {
  return line.command_letter;
}

/// Command number text. Params: line - the parsed line. Returns: the verbatim
/// number text of the command word (without the letter), e.g. "10.50" for
/// `X10.50`; "" for a blank line.
/// Error case: none. Complexity: O(1).
pub fn gcode_command_text(line: &GcodeLine) -> Str {
  return line.command_text;
}

/// Command value. Params: line - the parsed line. Returns: the signed scaled
/// integer of the command word; 0 for a blank line.
/// Error case: none. Complexity: O(1).
pub fn gcode_command_value(line: &GcodeLine) -> Int {
  return line.command_value;
}

/// Command scale. Params: line - the parsed line. Returns: the number of
/// decimal fraction digits of the command number (0-18); 0 for a blank line.
/// Error case: none. Complexity: O(1).
pub fn gcode_command_scale(line: &GcodeLine) -> Int {
  return line.command_scale;
}

/// Parameter count. Params: line - the parsed line. Returns: the number of
/// parameter words after the command; 0 for a blank line.
/// Error case: none. Complexity: O(1).
pub fn gcode_param_count(line: &GcodeLine) -> Int {
  return line.param_letters.len();
}

/// Parameter letter. Params: line - the parsed line; j - the 0-based
/// parameter index. Returns: the uppercase letter; "" when j is negative or
/// past the last parameter.
/// Error case: none. Complexity: O(1).
pub fn gcode_param_letter(line: &GcodeLine, j: Int) -> Str {
  if j < 0 || j >= line.param_letters.len() { return ""; }
  let v: Str = line.param_letters[j];
  return v;
}

/// Parameter number text. Params: line - the parsed line; j - the 0-based
/// parameter index. Returns: the verbatim number text (without the letter);
/// "" when j is out of range.
/// Error case: none. Complexity: O(1).
pub fn gcode_param_text(line: &GcodeLine, j: Int) -> Str {
  if j < 0 || j >= line.param_texts.len() { return ""; }
  let v: Str = line.param_texts[j];
  return v;
}

/// Parameter value. Params: line - the parsed line; j - the 0-based parameter
/// index. Returns: the signed scaled integer; 0 when j is out of range.
/// Error case: none. Complexity: O(1).
pub fn gcode_param_value(line: &GcodeLine, j: Int) -> Int {
  if j < 0 || j >= line.param_values.len() { return 0; }
  let v: Int = line.param_values[j];
  return v;
}

/// Parameter scale. Params: line - the parsed line; j - the 0-based parameter
/// index. Returns: the fraction digit count (0-18); 0 when j is out of range.
/// Error case: none. Complexity: O(1).
pub fn gcode_param_scale(line: &GcodeLine, j: Int) -> Int {
  if j < 0 || j >= line.param_scales.len() { return 0; }
  let v: Int = line.param_scales[j];
  return v;
}

// ---------------------------------------------------------------------------
// Program accessors
// ---------------------------------------------------------------------------

/// Command count. Params: program - the parsed document. Returns: the number
/// of non-blank lines (commands); 0 for a text with no commands.
/// Error case: none. Complexity: O(1).
pub fn gcode_command_count(program: &GcodeProgram) -> Int {
  return program.letters.len();
}

/// Flat parameter count. Params: program - the parsed document. Returns: the
/// total number of parameter words across all commands.
/// Error case: none. Complexity: O(1).
pub fn gcode_program_param_count(program: &GcodeProgram) -> Int {
  return program.param_letters.len();
}

/// Rebuild command `i` of a parsed document as a GcodeLine.
/// Params: program - the parsed document; i - the 0-based command index
/// (blank physical lines are not indexed).
/// Returns: a GcodeLine equivalent to parsing that line on its own; a blank
/// line value when i is negative or past the last command.
/// Error case: none. Complexity: O(parameters of command i).
pub fn gcode_program_line(program: &GcodeProgram, i: Int) -> GcodeLine {
  if i < 0 || i >= program.letters.len() { return _empty_line(); }
  let ln: Int = program.line_numbers[i];
  let lt: Str = program.letters[i];
  let tx: Str = program.texts[i];
  let vl: Int = program.values[i];
  let sc: Int = program.scales[i];
  let st: Int = program.param_start[i];
  let ct: Int = program.param_count[i];
  var pl = Vec[Str].new();
  var pt = Vec[Str].new();
  var pv = Vec[Int].new();
  var ps = Vec[Int].new();
  var j = 0;
  while j < ct {
    let a: Str = program.param_letters[st + j];
    let b: Str = program.param_texts[st + j];
    let c: Int = program.param_values[st + j];
    let d: Int = program.param_scales[st + j];
    pl.push(a);
    pt.push(b);
    pv.push(c);
    ps.push(d);
    j = j + 1;
  }
  return GcodeLine{
    blank: false;
    line_number: ln;
    command_letter: lt;
    command_text: tx;
    command_value: vl;
    command_scale: sc;
    param_letters: pl;
    param_texts: pt;
    param_values: pv;
    param_scales: ps;
  };
}
