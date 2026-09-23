module xiom.json

use xiom.string;
use xiom.convert;
use xiom.convert.tostring;
use xiom.fmt;

pub enum JsonValue {
  Null,
  Bool(value: Bool),
  Number(value: Float64),
  String(value: Str),
  Array(items: Vec[JsonValue]),
  Object(entries: Vec[JsonEntry]),
} derive[Clone]

pub type JsonEntry = {
  key: Str;
  value: JsonValue;
} derive[Clone]

pub type ParseError = {
  message: Str;
  line: Int;
  column: Int;
} derive[Clone]

pub type JsonNumber = {
  int_part: Int;
  frac_part: Int;
  frac_digits: Int;
  is_negative: Bool;
} derive[Clone]

pub enum JsonPathSegment {
  Key(key: Str),
  Index(index: Int),
} derive[Clone]

pub type JsonPath = {
  segments: Vec[JsonPathSegment];
} derive[Clone]

pub type JsonPrettyConfig = {
  indent: Int;
  sort_keys: Bool;
} derive[Clone]

pub enum JsonType {
  NullType,
  BoolType,
  NumberType,
  StringType,
  ArrayType,
  ObjectType,
}

pub type JsonParser = {
  input: Str;
  pos: Int;
  len: Int;
  line: Int;
  col: Int;
} derive[Clone]

// ============================================================
// PARSER BYTE CONSTANTS
// ============================================================

fn BYTE_OPEN_BRACE() -> Int { return 123; }
fn BYTE_CLOSE_BRACE() -> Int { return 125; }
fn BYTE_OPEN_BRACKET() -> Int { return 91; }
fn BYTE_CLOSE_BRACKET() -> Int { return 93; }
fn BYTE_QUOTE() -> Int { return 34; }
fn BYTE_COLON() -> Int { return 58; }
fn BYTE_COMMA() -> Int { return 44; }
fn BYTE_BACKSLASH() -> Int { return 92; }
fn BYTE_SPACE() -> Int { return 32; }
fn BYTE_TAB() -> Int { return 9; }
fn BYTE_NEWLINE() -> Int { return 10; }
fn BYTE_CR() -> Int { return 13; }
fn BYTE_MINUS() -> Int { return 45; }
fn BYTE_DOT() -> Int { return 46; }
fn BYTE_PLUS() -> Int { return 43; }
fn BYTE_SLASH() -> Int { return 47; }
fn BYTE_LOWER_B() -> Int { return 98; }
fn BYTE_LOWER_F() -> Int { return 102; }
fn BYTE_LOWER_N() -> Int { return 110; }
fn BYTE_LOWER_R() -> Int { return 114; }
fn BYTE_LOWER_T() -> Int { return 116; }
fn BYTE_LOWER_U() -> Int { return 117; }
fn BYTE_UPPER_E() -> Int { return 69; }
fn BYTE_LOWER_E() -> Int { return 101; }
fn BYTE_ZERO() -> Int { return 48; }
fn BYTE_NINE() -> Int { return 57; }
fn BYTE_UPPER_A() -> Int { return 65; }
fn BYTE_UPPER_F() -> Int { return 70; }
fn BYTE_LOWER_A() -> Int { return 97; }
fn BYTE_LOWER_X() -> Int { return 120; }

// ============================================================
// SINGLE-CHARACTER STRING HELPER
// ============================================================

fn chr_byte(b: Int) -> Str {
  var ch_opt = xiom.convert.int_to_char(b);
  match ch_opt {
    Some(ch) => return tostring.to_string_char(ch),
    None => return " ",
  }
}

// ============================================================
// PARSER FREE FUNCTIONS (internal, not pub)
// ============================================================

fn parser_advance(p: &mut JsonParser) {
  var ch_opt = xiom.string.char_at(p.input, p.pos);
  match ch_opt {
    Some(ch) => {
      var byte_opt = xiom.convert.int_to_char(BYTE_NEWLINE());
      match byte_opt {
        Some(newline_ch) => {
          if ch == newline_ch {
            p.line = p.line + 1;
            p.col = 1;
          } else {
            p.col = p.col + 1;
          }
        }
        None => { p.col = p.col + 1; }
      }
    }
    None => {},
  }
  var next_pos = p.pos + 1;
  p.pos = next_pos;
}

fn parser_peek(p: &JsonParser) -> Int {
  if p.pos >= p.len { return -1; }
  var ch_opt = xiom.string.char_at(p.input, p.pos);
  match ch_opt {
    Some(ch) => xiom.convert.char_to_int(ch),
    None => -1,
  }
}

fn parser_peek_ahead(p: &JsonParser, offset: Int) -> Int {
  var idx = p.pos + offset;
  if idx >= p.len { return -1; }
  var ch_opt = xiom.string.char_at(p.input, idx);
  match ch_opt {
    Some(ch) => xiom.convert.char_to_int(ch),
    None => -1,
  }
}

fn parser_eof(p: &JsonParser) -> Bool {
  return p.pos >= p.len;
}

fn parser_skip_ws(p: &mut JsonParser) {
  while p.pos < p.len {
    var ch_opt = xiom.string.char_at(p.input, p.pos);
    match ch_opt {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte != BYTE_SPACE() && byte != BYTE_TAB() && byte != BYTE_NEWLINE() && byte != BYTE_CR() {
          return;
        }
        if byte == BYTE_NEWLINE() {
          p.line = p.line + 1;
          p.col = 1;
        } else {
          p.col = p.col + 1;
        }
      }
      None => return,
    }
    var next_pos = p.pos + 1;
    p.pos = next_pos;
  }
}

fn parser_make_error(p: &JsonParser, msg: Str) -> ParseError {
  return ParseError{ message: msg, line: p.line, column: p.col };
}

fn parser_match_literal(p: &JsonParser, lit: Str) -> Bool {
  var idx: Int = 0;
  var lit_len = xiom.string.str_len(lit);
  while idx < lit_len {
    if p.pos + idx >= p.len { return false; }
    var ich_opt = xiom.string.char_at(p.input, p.pos + idx);
    match ich_opt {
      Some(ich) => {
        var lch_opt = xiom.string.char_at(lit, idx + 0);
        match lch_opt {
          Some(lch) => {
            if xiom.convert.char_to_int(ich) != xiom.convert.char_to_int(lch) {
              return false;
            }
          }
          None => return false,
        }
      }
      None => return false,
    }
    var next_idx = idx + 1;
    idx = next_idx;
  }
  return true;
}

fn parser_consume_literal(p: &mut JsonParser, advance_count: Int) {
  var idx = 0;
  while idx < advance_count {
    parser_advance(p);
    var next_idx = idx + 1;
    idx = next_idx;
  }
}

fn parser_read_digits(p: &mut JsonParser) -> Int {
  var value: Int = 0;
  while p.pos < p.len {
    var ch_opt = xiom.string.char_at(p.input, p.pos);
    match ch_opt {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte < BYTE_ZERO() || byte > BYTE_NINE() { return value; }
        value = value * 10 + (byte - BYTE_ZERO());
        parser_advance(p);
      }
      None => return value,
    }
  }
  return value;
}

fn parser_parse_string(p: &mut JsonParser) -> Result[Str, ParseError] {
  parser_advance(p);
  return parser_parse_string_loop(p, "");
}

fn parser_parse_string_loop(p: &mut JsonParser, acc: Str) -> Result[Str, ParseError] {
  if p.pos >= p.len { return Err(parser_make_error(p, "unterminated string")); }
  var ch_opt = xiom.string.char_at(p.input, p.pos);
  match ch_opt {
    Some(ch) => {
      var byte = xiom.convert.char_to_int(ch);
      if byte == BYTE_QUOTE() {
        parser_advance(p);
        return Ok(acc);
      }
      if byte == BYTE_BACKSLASH() {
        parser_advance(p);
        if parser_eof(p) { return Err(parser_make_error(p, "unexpected end of input in string escape")); }
        var esc_opt = xiom.string.char_at(p.input, p.pos);
        match esc_opt {
          Some(esc) => {
            var esc_byte = xiom.convert.char_to_int(esc);
            parser_advance(p);
            if esc_byte == BYTE_QUOTE() {
              var next = xiom.string.str_concat(acc, "\"");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_BACKSLASH() {
              var next = xiom.string.str_concat(acc, "\\");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_SLASH() {
              var next = xiom.string.str_concat(acc, "/");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_LOWER_B() {
              var next = xiom.string.str_concat(acc, "\b");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_LOWER_F() {
              var next = xiom.string.str_concat(acc, "\f");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_LOWER_N() {
              var next = xiom.string.str_concat(acc, "\n");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_LOWER_R() {
              var next = xiom.string.str_concat(acc, "\r");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_LOWER_T() {
              var next = xiom.string.str_concat(acc, "\t");
              return parser_parse_string_loop(p, next);
            } elif esc_byte == BYTE_LOWER_U() {
              if p.pos + 4 > p.len { return Err(parser_make_error(p, "unexpected end of input in unicode escape")); }
              var next_pos = p.pos + 4;
              p.pos = next_pos;
              var next = xiom.string.str_concat(acc, "\u{0000}");
              return parser_parse_string_loop(p, next);
            } else {
              return Err(parser_make_error(p, "invalid escape character"));
            }
          }
          None => return Err(parser_make_error(p, "unexpected end of input in string escape")),
        }
      } else {
        if byte < 32 {
          return Err(parser_make_error(p, "unescaped control character in string"));
        }
        var single = chr_byte(byte);
        var next = xiom.string.str_concat(acc, single);
        parser_advance(p);
        return parser_parse_string_loop(p, next);
      }
    }
    None => return Err(parser_make_error(p, "unterminated string")),
  }
}

fn parser_parse_number(p: &mut JsonParser) -> Result[Float64, ParseError] {
  var start = p.pos;
  var is_neg = false;
  if parser_peek(p) == BYTE_MINUS() {
    is_neg = true;
    parser_advance(p);
  }
  var int_val: Int = 0;
  if parser_peek(p) == BYTE_ZERO() {
    parser_advance(p);
  } elif parser_peek(p) >= BYTE_ZERO() && parser_peek(p) <= BYTE_NINE() {
    int_val = parser_read_digits(p);
  } else {
    return Err(parser_make_error(p, "expected digit in number"));
  }
  var frac_val: Float64 = 0.0;
  if p.pos < p.len {
    var ch_opt = xiom.string.char_at(p.input, p.pos);
    match ch_opt {
      Some(ch) => {
        if xiom.convert.char_to_int(ch) == BYTE_DOT() {
          parser_advance(p);
          if p.pos >= p.len {
            return Err(parser_make_error(p, "expected digit after decimal point"));
          }
          var nch_opt = xiom.string.char_at(p.input, p.pos);
          match nch_opt {
            Some(nch) => {
              var nbyte = xiom.convert.char_to_int(nch);
              if nbyte < BYTE_ZERO() || nbyte > BYTE_NINE() {
                return Err(parser_make_error(p, "expected digit after decimal point"));
              }
            }
            None => return Err(parser_make_error(p, "expected digit after decimal point")),
          }
          var frac_digits = parser_read_digits(p);
          var fd: Float64 = xiom.convert.int_to_float(frac_digits + 0);
          var divisor: Float64 = 1.0;
          var temp = frac_digits;
          while temp > 0 {
            divisor = divisor * 10.0;
            temp = temp / 10;
          }
          frac_val = fd / divisor;
        }
      }
      None => {},
    }
  }
  var exp_val: Int = 0;
  var exp_neg = false;
  if p.pos < p.len {
    var ch_opt = xiom.string.char_at(p.input, p.pos);
    match ch_opt {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte == BYTE_LOWER_E() || byte == BYTE_UPPER_E() {
          parser_advance(p);
          if p.pos < p.len {
            var ech_opt = xiom.string.char_at(p.input, p.pos);
            match ech_opt {
              Some(ech) => {
                var ebyte = xiom.convert.char_to_int(ech);
                if ebyte == BYTE_MINUS() {
                  exp_neg = true;
                  parser_advance(p);
                } elif ebyte == BYTE_PLUS() {
                  parser_advance(p);
                }
              }
              None => {},
            }
          }
          if p.pos >= p.len {
            return Err(parser_make_error(p, "expected digit in exponent"));
          }
          var dch_opt = xiom.string.char_at(p.input, p.pos);
          match dch_opt {
            Some(dch) => {
              var dbyte = xiom.convert.char_to_int(dch);
              if dbyte < BYTE_ZERO() || dbyte > BYTE_NINE() {
                return Err(parser_make_error(p, "expected digit in exponent"));
              }
            }
            None => return Err(parser_make_error(p, "expected digit in exponent")),
          }
          exp_val = parser_read_digits(p);
        }
      }
      None => {},
    }
  }
  if start == p.pos {
    return Err(parser_make_error(p, "empty number"));
  }
  if is_neg && start + 1 == p.pos {
    return Err(parser_make_error(p, "incomplete negative number"));
  }
  var result_val: Float64 = xiom.convert.int_to_float(int_val) + frac_val;
  if exp_val > 0 {
    var mult: Float64 = 1.0;
    var ei: Int = 0;
    while ei < exp_val {
      if exp_neg { mult = mult / 10.0; }
      else { mult = mult * 10.0; }
      var next_ei = ei + 1;
      ei = next_ei;
    }
    result_val = result_val * mult;
  }
  if is_neg { result_val = -result_val; }
  return Ok(result_val);
}

fn parser_parse_value(p: &mut JsonParser) -> Result[JsonValue, ParseError] {
  parser_skip_ws(p);
  if parser_eof(p) {
    return Err(parser_make_error(p, "unexpected end of input"));
  }
  var ch = parser_peek(p);
  if ch == BYTE_OPEN_BRACE() { return parser_parse_object(p); }
  if ch == BYTE_OPEN_BRACKET() { return parser_parse_array(p); }
  if ch == BYTE_QUOTE() { return parser_parse_string_as_value(p); }
  if ch == BYTE_MINUS() || (ch >= BYTE_ZERO() && ch <= BYTE_NINE()) { return parser_parse_number_value(p); }
  if ch == BYTE_LOWER_T() || ch == BYTE_LOWER_F() { return parser_parse_bool_value(p); }
  if ch == BYTE_LOWER_N() { return parser_parse_null_value(p); }
  return Err(parser_make_error(p, "unexpected character"));
}

fn parser_parse_object(p: &mut JsonParser) -> Result[JsonValue, ParseError] {
  parser_advance(p);
  parser_skip_ws(p);
  var entries = Vec[JsonEntry].new();
  if parser_peek(p) != BYTE_CLOSE_BRACE() {
    var first_res = parser_parse_entry(p);
    var first = first_res;
    match first {
      Err(e) => return Err(e),
      Ok(v) => entries.push(v),
    }
    parser_skip_ws(p);
    while parser_peek(p) == BYTE_COMMA() {
      parser_advance(p);
      parser_skip_ws(p);
      var next_res = parser_parse_entry(p);
      match next_res {
        Err(e) => return Err(e),
        Ok(v) => entries.push(v),
      }
      parser_skip_ws(p);
    }
  }
  if parser_peek(p) != BYTE_CLOSE_BRACE() {
    return Err(parser_make_error(p, "expected '}'"));
  }
  parser_advance(p);
  return Ok(JsonValue.Object(entries));
}

fn parser_parse_entry(p: &mut JsonParser) -> Result[JsonEntry, ParseError] {
  parser_skip_ws(p);
  if parser_peek(p) != BYTE_QUOTE() { return Err(parser_make_error(p, "expected key string")); }
  var key = parser_parse_string(p)?;
  parser_skip_ws(p);
  if parser_peek(p) != BYTE_COLON() { return Err(parser_make_error(p, "expected ':'")); }
  parser_advance(p);
  var val = parser_parse_value(p)?;
  return Ok(JsonEntry{ key: key, value: val });
}

fn parser_parse_array(p: &mut JsonParser) -> Result[JsonValue, ParseError] {
  parser_advance(p);
  parser_skip_ws(p);
  var items = Vec[JsonValue].new();
  if parser_peek(p) != BYTE_CLOSE_BRACKET() {
    var first_res = parser_parse_value(p);
    match first_res {
      Err(e) => return Err(e),
      Ok(v) => items.push(v),
    }
    parser_skip_ws(p);
    while parser_peek(p) == BYTE_COMMA() {
      parser_advance(p);
      parser_skip_ws(p);
      var next_res = parser_parse_value(p);
      match next_res {
        Err(e) => return Err(e),
        Ok(v) => items.push(v),
      }
      parser_skip_ws(p);
    }
  }
  if parser_peek(p) != BYTE_CLOSE_BRACKET() {
    return Err(parser_make_error(p, "expected ']'"));
  }
  parser_advance(p);
  return Ok(JsonValue.Array(items));
}

fn parser_parse_string_as_value(p: &mut JsonParser) -> Result[JsonValue, ParseError] {
  var s_res = parser_parse_string(p);
  match s_res {
    Err(e) => return Err(e),
    Ok(s) => return Ok(JsonValue.String(s)),
  }
}

fn parser_parse_number_value(p: &mut JsonParser) -> Result[JsonValue, ParseError] {
  var num_res = parser_parse_number(p);
  match num_res {
    Err(e) => return Err(e),
    Ok(n) => return Ok(JsonValue.Number(n)),
  }
}

fn parser_parse_bool_value(p: &mut JsonParser) -> Result[JsonValue, ParseError] {
  if parser_match_literal(p, "true") {
    parser_consume_literal(p, 4);
    return Ok(JsonValue.Bool(true));
  }
  if parser_match_literal(p, "false") {
    parser_consume_literal(p, 5);
    return Ok(JsonValue.Bool(false));
  }
  return Err(parser_make_error(p, "expected 'true' or 'false'"));
}

fn parser_parse_null_value(p: &mut JsonParser) -> Result[JsonValue, ParseError] {
  if parser_match_literal(p, "null") {
    parser_consume_literal(p, 4);
    return Ok(JsonValue.Null);
  }
  return Err(parser_make_error(p, "expected 'null'"));
}

// ============================================================
// PUBLIC PARSE / VALIDATE
// ============================================================

pub fn json_parse(input: Str) -> Result[JsonValue, ParseError]
  requires: xiom.string.str_len(input) > 0
{
  var parser = JsonParser{
    input: input,
    pos: 0,
    len: xiom.string.str_len(input),
    line: 1,
    col: 1,
  };
  var value = parser_parse_value(&mut parser);
  match value {
    Err(e) => return Err(e),
    Ok(_) => {},
  }
  parser_skip_ws(&mut parser);
  if !parser_eof(&parser) {
    return Err(parser_make_error(&parser, "trailing data after root value"));
  }
  return value;
}

pub fn json_validate(input: Str) -> Result[Bool, ParseError]
  requires: xiom.string.str_len(input) > 0
{
  var parser = JsonParser{
    input: input,
    pos: 0,
    len: xiom.string.str_len(input),
    line: 1,
    col: 1,
  };
  var value = parser_parse_value(&mut parser);
  match value {
    Err(e) => return Err(e),
    Ok(_) => {},
  }
  parser_skip_ws(&mut parser);
  if !parser_eof(&parser) {
    return Err(parser_make_error(&parser, "trailing data after root value"));
  }
  return Ok(true);
}

// ============================================================
// JSON STRINGIFY -- INTERNALS
// ============================================================

fn escape_char(ch: Int) -> Str {
  if ch == 34 { return "\\\""; }
  if ch == 92 { return "\\\\"; }
  if ch == 8 { return "\\b"; }
  if ch == 12 { return "\\f"; }
  if ch == 10 { return "\\n"; }
  if ch == 13 { return "\\r"; }
  if ch == 9 { return "\\t"; }
  if ch < 32 {
    return "\\u0000";
  }
  return chr_byte(ch);
}

fn str_build_loop(acc: Str, suffix: Str, remaining: Int) -> Str {
  if remaining <= 0 { return acc; }
  var next = xiom.string.str_concat(acc, suffix);
  return str_build_loop(next, suffix, remaining - 1);
}

fn stringify_indent(depth: Int, config: &JsonPrettyConfig) -> Str {
  var total_spaces = depth * config.indent;
  var prefix = "\n";
  return str_build_loop(prefix, " ", total_spaces);
}

fn stringify_string(s: Str) -> Str {
  var slen = xiom.string.str_len(s);
  return stringify_string_loop(s, 0, slen, "\"");
}

fn stringify_string_loop(s: Str, pos: Int, slen: Int, acc: Str) -> Str {
  if pos >= slen {
    return xiom.string.str_concat(acc, "\"");
  }
  var ch_opt = xiom.string.char_at(s, pos);
  var char_str = "\"";
  match ch_opt {
    Some(ch) => {
      var byte = xiom.convert.char_to_int(ch);
      var byte_copy = byte + 0;
      if byte_copy == 34 || byte_copy == 92 || byte_copy < 32 {
        char_str = escape_char(byte);
      } else {
        char_str = chr_byte(byte);
      }
    }
    None => {},
  }
  var next_acc = xiom.string.str_concat(acc, char_str);
  var next_pos = pos + 1;
  return stringify_string_loop(s, next_pos, slen, next_acc);
}

fn stringify_number(v: Float64) -> Str {
  if v == 0.0 { return "0"; }
  if v < 0.0 {
    return stringify_number_body("-", -v);
  }
  return stringify_number_body("", v);
}

fn stringify_number_body(prefix: Str, num: Float64) -> Str {
  if num >= 1000000000000000.0 {
    return xiom.string.str_concat(prefix, "0");
  }
  var int_part: Int = xiom.convert.float_to_int(num);
  var int_str = xiom.convert.int_to_string(int_part + 0);
  var s0 = xiom.string.str_concat(prefix, int_str);
  var int_as_float = xiom.convert.int_to_float(int_part + 0);
  var frac = num - int_as_float;
  if frac > 0.0000000001 {
    return stringify_frac(s0, frac, 0);
  } else {
    return s0;
  }
}

fn stringify_frac(acc: Str, frac: Float64, digits: Int) -> Str {
  if frac <= 0.0000000001 || digits >= 15 { return acc; }
  if digits == 0 {
    var s0 = xiom.string.str_concat(acc, ".");
    return stringify_frac(s0, frac, digits);
  }
  var multiplied = frac * 10.0;
  var d_val: Int = xiom.convert.float_to_int(multiplied + 0.0);
  var d_copy = d_val + 0;
  var ch_opt = xiom.convert.int_to_char(d_copy);
  var dstr = "0";
  match ch_opt {
    Some(ch) => {
      dstr = chr_byte(xiom.convert.char_to_int(ch));
    }
    None => {},
  }
  var s1 = xiom.string.str_concat(acc, dstr);
  var d_val2 = d_val + 0;
  var remaining = multiplied - xiom.convert.int_to_float(d_val2);
  var next_digits = digits + 1;
  return stringify_frac(s1, remaining, next_digits);
}

fn stringify_value_rec(value: &JsonValue, depth: Int, config: &JsonPrettyConfig, is_pretty: Bool) -> Str {
  match value {
    Null => return "null",
    Bool(v) => {
      if v { return "true"; }
      return "false";
    }
    Number(v) => return stringify_number(v),
    String(v) => return stringify_string(v),
    Array(items) => {
      if items.len() == 0 { return "[]"; }
      return stringify_array(items, depth, config, is_pretty, 0, "[");
    }
    Object(entries) => {
      if entries.len() == 0 { return "{}"; }
      var sorted = Vec[JsonEntry].new();
      var k: Int = 0;
      while k < entries.len() {
        sorted.push(entries[k]);
        var next_k = k + 1;
        k = next_k;
      }
      if config.sort_keys {
        var srt = sort_entries(sorted);
        return stringify_object(&srt, depth, config, is_pretty, 0, "{");
      } else {
        return stringify_object(&sorted, depth, config, is_pretty, 0, "{");
      }
    }
  }
}

fn stringify_array(items: &Vec[JsonValue], depth: Int, config: &JsonPrettyConfig, is_pretty: Bool, idx: Int, acc: Str) -> Str {
  if idx >= items.len() {
    if is_pretty {
      var a0 = xiom.string.str_concat(acc, stringify_indent(depth, config));
      return xiom.string.str_concat(a0, "]");
    }
    return xiom.string.str_concat(acc, "]");
  }
  if is_pretty {
    var base = xiom.string.str_concat(acc, stringify_indent(depth + 1, config));
    return stringify_array_item(items, depth, config, is_pretty, idx, base);
  }
  return stringify_array_item(items, depth, config, is_pretty, idx, acc);
}

fn stringify_array_item(items: &Vec[JsonValue], depth: Int, config: &JsonPrettyConfig, is_pretty: Bool, idx: Int, base: Str) -> Str {
  var next = idx + 1;
  if idx == items.len() - 1 {
    var val_str = stringify_value_rec(&items[idx], depth + 1, config, is_pretty);
    var a2 = xiom.string.str_concat(base, val_str);
    return stringify_array(items, depth, config, is_pretty, next, a2);
  }
  var val_str = stringify_value_rec(&items[idx], depth + 1, config, is_pretty);
  var a2 = xiom.string.str_concat(base, val_str);
  var a3 = xiom.string.str_concat(a2, ",");
  return stringify_array(items, depth, config, is_pretty, next, a3);
}

fn stringify_object_item(entries: &Vec[JsonEntry], depth: Int, config: &JsonPrettyConfig, is_pretty: Bool, idx: Int, base: Str) -> Str {
  var key_str = stringify_string(entries[idx].key);
  var a2 = xiom.string.str_concat(base, key_str);
  var next = idx + 1;
  if is_pretty {
    if idx == entries.len() - 1 {
      var a3 = xiom.string.str_concat(a2, ": ");
      var val_str = stringify_value_rec(&entries[idx].value, depth + 1, config, is_pretty);
      var a4 = xiom.string.str_concat(a3, val_str);
      return stringify_object(entries, depth, config, is_pretty, next, a4);
    }
    var a3 = xiom.string.str_concat(a2, ": ");
    var val_str = stringify_value_rec(&entries[idx].value, depth + 1, config, is_pretty);
    var a4 = xiom.string.str_concat(a3, val_str);
    var a5 = xiom.string.str_concat(a4, ",");
    return stringify_object(entries, depth, config, is_pretty, next, a5);
  }
  if idx == entries.len() - 1 {
    var a3 = xiom.string.str_concat(a2, ":");
    var val_str = stringify_value_rec(&entries[idx].value, depth + 1, config, is_pretty);
    var a4 = xiom.string.str_concat(a3, val_str);
    return stringify_object(entries, depth, config, is_pretty, next, a4);
  }
  var a3 = xiom.string.str_concat(a2, ":");
  var val_str = stringify_value_rec(&entries[idx].value, depth + 1, config, is_pretty);
  var a4 = xiom.string.str_concat(a3, val_str);
  var a5 = xiom.string.str_concat(a4, ",");
  return stringify_object(entries, depth, config, is_pretty, next, a5);
}

fn stringify_object(entries: &Vec[JsonEntry], depth: Int, config: &JsonPrettyConfig, is_pretty: Bool, idx: Int, acc: Str) -> Str {
  if idx >= entries.len() {
    if is_pretty {
      var a0 = xiom.string.str_concat(acc, stringify_indent(depth, config));
      return xiom.string.str_concat(a0, "}");
    }
    return xiom.string.str_concat(acc, "}");
  }
  if is_pretty {
    var base = xiom.string.str_concat(acc, stringify_indent(depth + 1, config));
    return stringify_object_item(entries, depth, config, is_pretty, idx, base);
  }
  return stringify_object_item(entries, depth, config, is_pretty, idx, acc);
}

fn stringify_object_item(entries: &Vec[JsonEntry], depth: Int, config: &JsonPrettyConfig, is_pretty: Bool, idx: Int, base: Str) -> Str {
  var key_str = stringify_string(entries[idx].key);
  var a2 = xiom.string.str_concat(base, key_str);
  if is_pretty {
    var a3 = xiom.string.str_concat(a2, ": ");
    var next = idx + 1;
    var val_str = stringify_value_rec(&entries[idx].value, depth + 1, config, is_pretty);
    if idx == entries.len() - 1 {
      var a4 = xiom.string.str_concat(a3, val_str);
      return stringify_object(entries, depth, config, is_pretty, next, a4);
    }
    var a4 = xiom.string.str_concat(a3, val_str);
    var a5 = xiom.string.str_concat(a4, ",");
    return stringify_object(entries, depth, config, is_pretty, next, a5);
  } else {
    var a3 = xiom.string.str_concat(a2, ":");
    var next = idx + 1;
    var val_str = stringify_value_rec(&entries[idx].value, depth + 1, config, is_pretty);
    if idx == entries.len() - 1 {
      var a4 = xiom.string.str_concat(a3, val_str);
      return stringify_object(entries, depth, config, is_pretty, next, a4);
    }
    var a4 = xiom.string.str_concat(a3, val_str);
    var a5 = xiom.string.str_concat(a4, ",");
    return stringify_object(entries, depth, config, is_pretty, next, a5);
  }
}

fn sort_entries(entries: Vec[JsonEntry]) -> Vec[JsonEntry] {
  if entries.len() <= 1 { return entries; }
  var pivot = entries[entries.len() / 2];
  var less = Vec[JsonEntry].new();
  var greater = Vec[JsonEntry].new();
  var equal = Vec[JsonEntry].new();
  var idx = 0;
  while idx < entries.len() {
    var next_idx = idx + 1;
    if entries[idx].key < pivot.key {
      less.push(entries[idx]);
    } elif entries[idx].key > pivot.key {
      greater.push(entries[idx]);
    } else {
      equal.push(entries[idx]);
    }
    idx = next_idx;
  }
  var sorted_less = sort_entries(less);
  var sorted_greater = sort_entries(greater);
  var result = Vec[JsonEntry].new();
  idx = 0;
  while idx < sorted_less.len() {
    result.push(sorted_less[idx]);
    var next_idx = idx + 1;
    idx = next_idx;
  }
  idx = 0;
  while idx < equal.len() {
    result.push(equal[idx]);
    var next_idx = idx + 1;
    idx = next_idx;
  }
  idx = 0;
  while idx < sorted_greater.len() {
    result.push(sorted_greater[idx]);
    var next_idx = idx + 1;
    idx = next_idx;
  }
  return result;
}

// ============================================================
// PUBLIC STRINGIFY
// ============================================================

pub fn json_stringify(value: &JsonValue) -> Str {
  var config = JsonPrettyConfig{ indent: 2, sort_keys: false };
  return stringify_value_rec(value, 0, &config, false);
}

pub fn json_stringify_pretty(value: &JsonValue, config: &JsonPrettyConfig) -> Str {
  return stringify_value_rec(value, 0, config, true);
}

// ============================================================
// JSON MANIPULATION API
// ============================================================

pub fn json_get(obj: &JsonValue, key: Str) -> Option[JsonValue]
  requires: xiom.string.str_len(key) > 0
{
  match obj {
    Object(entries) => {
      var i: Int = 0;
      while i < entries.len() {
        if entries[i].key == key {
          return Some(entries[i].value.clone());
        }
        var next_i = i + 1;
        i = next_i;
      }
      return None;
    }
    _ => None,
  }
}

pub fn json_get_path(root: &JsonValue, path: &JsonPath) -> Option[JsonValue]
  requires: path.segments.len() > 0
{
  var current = root.clone();
  var i: Int = 0;
  while i < path.segments.len() {
    var seg = &path.segments[i];
    match seg {
      Key(k) => {
        var found = json_get(&current, k);
        match found {
          Some(v) => { current = v; }
          None => return None,
        }
      }
      Index(idx) => {
        match current {
          Array(items) => {
            if idx < 0 || idx >= items.len() { return None; }
            current = items[idx].clone();
          }
          _ => return None,
        }
      }
    }
    var next_i = i + 1;
    i = next_i;
  }
  return Some(current);
}

pub fn json_set(obj: &mut JsonValue, key: Str, value: JsonValue) -> Bool
  requires: xiom.string.str_len(key) > 0
{
  match obj {
    Object(entries) => {
      var i: Int = 0;
      while i < entries.len() {
        if entries[i].key == key {
          entries[i].value = value;
          return true;
        }
        var next_i = i + 1;
        i = next_i;
      }
      entries.push(JsonEntry{ key: key, value: value });
      return true;
    }
    _ => false,
  }
}

pub fn json_set_path(root: &mut JsonValue, path: &JsonPath, value: JsonValue) -> Bool
  requires: path.segments.len() > 0
{
  if path.segments.is_empty() { return false; }
  var i: Int = 0;
  while i < path.segments.len() - 1 {
    var seg = &path.segments[i];
    match seg {
      Key(k) => {
        match root {
          Object(entries) => {
            var found_entry: Int = -1;
            var j: Int = 0;
            while j < entries.len() {
              if entries[j].key == k {
                found_entry = j;
              }
              var next_j = j + 1;
              j = next_j;
            }
            if found_entry == -1 {
              entries.push(JsonEntry{ key: k, value: JsonValue.Null });
              found_entry = entries.len() - 1;
            }
            root = &mut entries[found_entry].value;
          }
          _ => return false,
        }
      }
      Index(idx) => {
        match root {
          Array(items) => {
            if idx < 0 || idx >= items.len() { return false; }
            root = &mut items[idx];
          }
          _ => return false,
        }
      }
    }
    var next_i = i + 1;
    i = next_i;
  }
  var last_seg = &path.segments[path.segments.len() - 1];
  match last_seg {
    Key(k) => {
      return json_set(root, k, value);
    }
    Index(idx) => {
      match root {
        Array(items) => {
          if idx < 0 || idx >= items.len() { return false; }
          items[idx] = value;
          return true;
        }
        _ => return false,
      }
    }
  }
}

pub fn json_remove(obj: &mut JsonValue, key: Str) -> Bool
  requires: xiom.string.str_len(key) > 0
{
  match obj {
    Object(entries) => {
      var i: Int = 0;
      while i < entries.len() {
        if entries[i].key == key {
          var new_entries = Vec[JsonEntry].new();
          var j: Int = 0;
          while j < entries.len() {
            if j != i {
              new_entries.push(entries[j]);
            }
            var j_copy = j + 0;
            var next_j = j_copy + 1;
            j = next_j;
          }
          entries = new_entries;
          return true;
        }
        var next_i = i + 1;
        i = next_i;
      }
      return false;
    }
    _ => false,
  }
}

pub fn json_has_key(obj: &JsonValue, key: Str) -> Bool
  requires: xiom.string.str_len(key) > 0
{
  match obj {
    Object(entries) => {
      var i: Int = 0;
      while i < entries.len() {
        if entries[i].key == key { return true; }
        var next_i = i + 1;
        i = next_i;
      }
      return false;
    }
    _ => false,
  }
}

pub fn json_is_type(value: &JsonValue, expected: JsonType) -> Bool {
  match value {
    Null => return expected == JsonType.NullType,
    Bool(_) => return expected == JsonType.BoolType,
    Number(_) => return expected == JsonType.NumberType,
    String(_) => return expected == JsonType.StringType,
    Array(_) => return expected == JsonType.ArrayType,
    Object(_) => return expected == JsonType.ObjectType,
  }
}

pub fn json_merge(base: &mut JsonValue, overlay: &JsonValue) -> Bool {
  match base {
    Object(base_entries) => {
      match overlay {
        Object(overlay_entries) => {
          var i: Int = 0;
          while i < overlay_entries.len() {
            var found_idx: Int = -1;
            var j: Int = 0;
            while j < base_entries.len() {
              if base_entries[j].key == overlay_entries[i].key {
                found_idx = j;
              }
              var next_j = j + 1;
              j = next_j;
            }
            if found_idx != -1 {
              match overlay_entries[i].value {
                Object(_) => {
                  var r = json_merge(&mut base_entries[found_idx].value, &overlay_entries[i].value);
                  if !r { return false; }
                }
                _ => {
                  base_entries[found_idx].value = overlay_entries[i].value.clone();
                }
              }
            } else {
              base_entries.push(JsonEntry{
                key: overlay_entries[i].key,
                value: overlay_entries[i].value.clone(),
              });
            }
            var next_i = i + 1;
            i = next_i;
          }
          return true;
        }
        _ => return false,
      }
    }
    _ => false,
  }
}

// ============================================================
// JSON SCHEMA VALIDATION
// ============================================================

pub fn json_schema_validate(value: &JsonValue, schema: &JsonValue) -> Result[Bool, Str] {
  var type_field = json_get(schema, "type");
  match type_field {
    Some(tv) => {
      var ok = schema_check_type(value, &tv);
      if !ok { return Err("type mismatch"); }
    }
    None => {},
  }
  var enum_field = json_get(schema, "enum");
  match enum_field {
    Some(ev) => {
      match ev {
        Array(allowed) => {
          var found = false;
          var i: Int = 0;
          while i < allowed.len() {
            if json_values_equal(value, &allowed[i]) { found = true; }
            var next_i = i + 1;
            i = next_i;
          }
          if !found { return Err("value not in enum"); }
        }
        _ => return Err("schema enum must be array"),
      }
    }
    None => {},
  }
  var props_field = json_get(schema, "properties");
  match props_field {
    Some(pv) => {
      match value {
        Object(_) => {},
        _ => return Err("properties constraint requires object value"),
      }
      match pv {
        Object(prop_schemas) => {
          var i: Int = 0;
          while i < prop_schemas.len() {
            var prop_val = json_get(value, prop_schemas[i].key);
            match prop_val {
              Some(pvv) => {
                var r = json_schema_validate(&pvv, &prop_schemas[i].value);
                match r {
                  Err(emsg) => {
                    var em0 = xiom.string.str_concat("property '", prop_schemas[i].key);
                    var em1 = xiom.string.str_concat(em0, "': ");
                    var em2 = xiom.string.str_concat(em1, emsg);
                    return Err(em2);
                  }
                  Ok(_) => {},
                }
              }
              None => {},
            }
            var next_i = i + 1;
            i = next_i;
          }
        }
        _ => return Err("schema properties must be object"),
      }
    }
    None => {},
  }
  var required_field = json_get(schema, "required");
  match required_field {
    Some(rv) => {
      match value {
        Object(_) => {},
        _ => return Err("required constraint requires object value"),
      }
      match rv {
        Array(required_keys) => {
          var i: Int = 0;
          while i < required_keys.len() {
            match required_keys[i] {
              String(rk) => {
                if !json_has_key(value, rk) { return Err("missing required key"); }
              }
              _ => {},
            }
            var next_i = i + 1;
            i = next_i;
          }
        }
        _ => return Err("schema required must be array"),
      }
    }
    None => {},
  }
  return Ok(true);
}

fn schema_check_type(value: &JsonValue, type_val: &JsonValue) -> Bool {
  match type_val {
    String(t) => {
      if t == "null" {
        match value { Null => true, _ => false }
      } elif t == "boolean" {
        match value { Bool(_) => true, _ => false }
      } elif t == "number" {
        match value { Number(_) => true, _ => false }
      } elif t == "string" {
        match value { String(_) => true, _ => false }
      } elif t == "array" {
        match value { Array(_) => true, _ => false }
      } elif t == "object" {
        match value { Object(_) => true, _ => false }
      } else {
        false
      }
    }
    Array(types) => {
      var i: Int = 0;
      while i < types.len() {
        if schema_check_type(value, &types[i]) { return true; }
        var next_i = i + 1;
        i = next_i;
      }
      return false;
    }
    _ => false,
  }
}

fn json_values_equal(a: &JsonValue, b: &JsonValue) -> Bool {
  match a {
    Null => {
      match b { Null => true, _ => false }
    }
    Bool(av) => {
      match b { Bool(bv) => av == bv, _ => false }
    }
    Number(av) => {
      match b { Number(bv) => av == bv, _ => false }
    }
    String(av) => {
      match b { String(bv) => av == bv, _ => false }
    }
    Array(aitems) => {
      match b {
        Array(bitems) => {
          if aitems.len() != bitems.len() { return false; }
          var i: Int = 0;
          while i < aitems.len() {
            if !json_values_equal(&aitems[i], &bitems[i]) { return false; }
            var next_i = i + 1;
            i = next_i;
          }
          return true;
        }
        _ => false,
      }
    }
    Object(aentries) => {
      match b {
        Object(bentries) => {
          if aentries.len() != bentries.len() { return false; }
          var i: Int = 0;
          while i < aentries.len() {
            var bv = json_get(b, aentries[i].key);
            match bv {
              Some(bvv) => {
                if !json_values_equal(&aentries[i].value, &bvv) { return false; }
              }
              None => return false,
            }
            var next_i = i + 1;
            i = next_i;
          }
          return true;
        }
        _ => false,
      }
    }
  }
}

// ============================================================
// CONVENIENCE CONSTRUCTORS
// ============================================================

pub fn json_null() -> JsonValue {
  return JsonValue.Null;
}

pub fn json_bool(v: Bool) -> JsonValue {
  return JsonValue.Bool(v);
}

pub fn json_number(v: Float64) -> JsonValue {
  return JsonValue.Number(v);
}

pub fn json_string(v: Str) -> JsonValue {
  return JsonValue.String(v);
}

pub fn json_array() -> JsonValue {
  return JsonValue.Array(Vec[JsonValue].new());
}

pub fn json_object() -> JsonValue {
  return JsonValue.Object(Vec[JsonEntry].new());
}

pub fn json_array_push(arr: &mut JsonValue, value: JsonValue) {
  match arr {
    Array(items) => {
      items.push(value);
    }
    _ => {},
  }
}

pub fn json_object_put(obj: &mut JsonValue, key: Str, value: JsonValue)
  requires: xiom.string.str_len(key) > 0
{
  match obj {
    Object(entries) => {
      var i: Int = 0;
      while i < entries.len() {
        if entries[i].key == key {
          entries[i].value = value;
          return;
        }
        var next_i = i + 1;
        i = next_i;
      }
      entries.push(JsonEntry{ key: key, value: value });
    }
    _ => {},
  }
}

// ============================================================
// JSONPATH CONSTRUCTOR HELPERS
// ============================================================

pub fn json_path_new() -> JsonPath {
  return JsonPath{ segments: Vec[JsonPathSegment].new() };
}

pub fn json_path_push_key(path: &mut JsonPath, key: Str)
  requires: xiom.string.str_len(key) > 0
{
  path.segments.push(JsonPathSegment.Key(key));
}

pub fn json_path_push_index(path: &mut JsonPath, index: Int) {
  path.segments.push(JsonPathSegment.Index(index));
}

fn json_path_parse_segments(path_str: Str, str_len: Int, i: Int, result: JsonPath) -> Result[JsonPath, Str] {
  if i >= str_len { return Ok(result); }
  var b0 = json_path_byte(path_str, i + 0);
  if b0 == 46 {
    var next_i = i + 1;
    return json_path_parse_dot(path_str, str_len, next_i, result);
  }
  if b0 == 91 {
    var next_i = i + 1;
    return json_path_parse_bracket(path_str, str_len, next_i, result);
  }
  return Err("unexpected character in path");
}

fn json_path_parse_dot(path_str: Str, str_len: Int, i: Int, result: JsonPath) -> Result[JsonPath, Str] {
  return json_path_parse_dot_scan(path_str, str_len, i, i, result);
}

fn json_path_parse_dot_scan(path_str: Str, str_len: Int, i: Int, start: Int, result: JsonPath) -> Result[JsonPath, Str] {
  if i >= str_len {
    if i > start {
      return json_path_parse_key_build(path_str, str_len, i, start, "", result);
    }
    return json_path_parse_segments(path_str, str_len, i, result);
  }
  var cb0 = json_path_byte(path_str, i + 0);
  if cb0 == 46 || cb0 == 91 {
    if i > start {
      return json_path_parse_key_build(path_str, str_len, i, start, "", result);
    }
    return json_path_parse_segments(path_str, str_len, i, result);
  }
  var next_i = i + 1;
  return json_path_parse_dot_scan(path_str, str_len, next_i, start, result);
}

fn json_path_parse_key_build(path_str: Str, str_len: Int, end_i: Int, j: Int, acc: Str, result: JsonPath) -> Result[JsonPath, Str] {
  if j >= end_i {
    result.segments.push(JsonPathSegment.Key(acc));
    return json_path_parse_segments(path_str, str_len, end_i, result);
  }
  var ch_byte = json_path_byte(path_str, j + 0);
  var ch_str = chr_byte(ch_byte);
  var new_acc = xiom.string.str_concat(acc, ch_str);
  var next_j = j + 1;
  return json_path_parse_key_build(path_str, str_len, end_i, next_j, new_acc, result);
}

fn json_path_parse_bracket(path_str: Str, str_len: Int, i: Int, result: JsonPath) -> Result[JsonPath, Str] {
  if i >= str_len { return Err("unterminated bracket segment"); }
  var b0 = json_path_byte(path_str, i + 0);
  if b0 == 39 {
    var start = i + 1;
    return json_path_parse_bracket_key_scan(path_str, str_len, start, start, result);
  }
  return json_path_parse_bracket_idx_scan(path_str, str_len, i, i, result);
}

fn json_path_parse_bracket_key_scan(path_str: Str, str_len: Int, i: Int, start: Int, result: JsonPath) -> Result[JsonPath, Str] {
  if i >= str_len { return Err("unterminated bracket key"); }
  var b0 = json_path_byte(path_str, i + 0);
  if b0 == 39 {
    return json_path_parse_bracket_key_build_and_close(path_str, str_len, i, start, "", result);
  }
  var next_i = i + 1;
  return json_path_parse_bracket_key_scan(path_str, str_len, next_i, start, result);
}

fn json_path_parse_expect_close_bracket(path_str: Str, str_len: Int, i: Int, result: JsonPath) -> Result[JsonPath, Str] {
  if i < str_len {
    var b0 = json_path_byte(path_str, i + 0);
    if b0 == 93 {
      var next_i = i + 1;
      return json_path_parse_segments(path_str, str_len, next_i, result);
    }
  }
  return Err("expected ']'");
}

fn json_path_parse_bracket_key_build_and_close(path_str: Str, str_len: Int, quote_end: Int, j: Int, acc: Str, result: JsonPath) -> Result[JsonPath, Str] {
  if j >= quote_end {
    result.segments.push(JsonPathSegment.Key(acc));
    var next_i = quote_end + 1;
    return json_path_parse_expect_close_bracket(path_str, str_len, next_i, result);
  }
  var ch_byte = json_path_byte(path_str, j + 0);
  var ch_str = chr_byte(ch_byte);
  var new_acc = xiom.string.str_concat(acc, ch_str);
  var next_j = j + 1;
  return json_path_parse_bracket_key_build_and_close(path_str, str_len, quote_end, next_j, new_acc, result);
}

fn json_path_parse_bracket_idx_scan(path_str: Str, str_len: Int, i: Int, start: Int, result: JsonPath) -> Result[JsonPath, Str] {
  if i >= str_len { return Err("expected ']'"); }
  var b0 = json_path_byte(path_str, i + 0);
  if b0 >= 48 && b0 <= 57 {
    var next_i = i + 1;
    return json_path_parse_bracket_idx_scan(path_str, str_len, next_i, start, result);
  }
  if b0 == 93 {
    if i > start {
      return json_path_parse_idx_build(path_str, str_len, i, start, 0, result);
    }
    var next_i = i + 1;
    return json_path_parse_segments(path_str, str_len, next_i, result);
  }
  return Err("expected ']' or digit");
}

fn json_path_parse_idx_build(path_str: Str, str_len: Int, end_i: Int, j: Int, acc: Int, result: JsonPath) -> Result[JsonPath, Str] {
  if j >= end_i {
    result.segments.push(JsonPathSegment.Index(acc));
    var next_i = end_i + 1;
    return json_path_parse_segments(path_str, str_len, next_i, result);
  }
  var digit = json_path_byte(path_str, j + 0) - 48;
  var new_acc = acc * 10 + digit;
  var next_j = j + 1;
  return json_path_parse_idx_build(path_str, str_len, end_i, next_j, new_acc, result);
}

pub fn json_path_parse(path_str: Str) -> Result[JsonPath, Str]
  requires: xiom.string.str_len(path_str) > 0
{
  var result = JsonPath{ segments: Vec[JsonPathSegment].new() };
  var str_len = xiom.string.str_len(path_str);
  if str_len == 0 { return Ok(result); }
  var i0: Int = 0;
  var b0 = json_path_byte(path_str, i0 + 0);
  if b0 == 36 {
    var next_i = i0 + 1;
    return json_path_parse_segments(path_str, str_len, next_i, result);
  }
  return json_path_parse_segments(path_str, str_len, i0, result);
}

fn json_path_byte(s: Str, i: Int) -> Int {
  var ch_opt = xiom.string.char_at(s, i);
  match ch_opt {
    Some(ch) => xiom.convert.char_to_int(ch),
    None => -1,
  }
}

// ============================================================
// JSONPRETTYCONFIG CONSTRUCTOR
// ============================================================

pub fn json_pretty_config_compact() -> JsonPrettyConfig {
  return JsonPrettyConfig{ indent: 0, sort_keys: false };
}

pub fn json_pretty_config_default() -> JsonPrettyConfig {
  return JsonPrettyConfig{ indent: 2, sort_keys: false };
}

pub fn json_pretty_config_sorted() -> JsonPrettyConfig {
  return JsonPrettyConfig{ indent: 2, sort_keys: true };
}
