module xiom.json

use xiom.string;
use xiom.convert;
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
// PARSER INTERNALS
// ============================================================

fn JsonParser.new(input: Str) -> JsonParser {
  return JsonParser{
    input: input,
    pos: 0,
    len: xiom.string.str_len(input),
    line: 1,
    col: 1,
  };
}

fn JsonParser.eof() -> Bool {
  return pos >= len;
}

fn JsonParser.peek() -> Int {
  if pos >= len { return -1; }
  match xiom.string.char_at(input, pos) {
    Some(ch) => xiom.convert.char_to_int(ch),
    None => -1,
  }
}

fn JsonParser.peek_ahead(offset: Int) -> Int {
  var idx = pos + offset;
  if idx >= len { return -1; }
  match xiom.string.char_at(input, idx) {
    Some(ch) => xiom.convert.char_to_int(ch),
    None => -1,
  }
}

fn JsonParser.advance() {
  match xiom.string.char_at(input, pos) {
    Some(ch) => {
      if xiom.convert.char_to_int(ch) == BYTE_NEWLINE() {
        line = line + 1;
        col = 1;
      } else {
        col = col + 1;
      }
    }
    None => {},
  }
  pos = pos + 1;
}

fn JsonParser.skip_ws() {
  while pos < len {
    match xiom.string.char_at(input, pos) {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte != BYTE_SPACE() && byte != BYTE_TAB() && byte != BYTE_NEWLINE() && byte != BYTE_CR() {
          return;
        }
        if byte == BYTE_NEWLINE() {
          line = line + 1;
          col = 1;
        } else {
          col = col + 1;
        }
      }
      None => return,
    }
    pos = pos + 1;
  }
}

fn JsonParser.make_error(msg: Str) -> ParseError {
  return ParseError{ message: msg, line: line, column: col };
}

fn JsonParser.match_literal(lit: Str) -> Bool {
  var i: Int = 0;
  while i < xiom.string.str_len(lit) {
    if pos + i >= len { return false; }
    match xiom.string.char_at(input, pos + i) {
      Some(ich) => {
        match xiom.string.char_at(lit, i) {
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
    i = i + 1;
  }
  return true;
}

fn JsonParser.consume_literal(lit: Str, advance_count: Int) {
  var i: Int = 0;
  while i < advance_count {
    advance();
    i = i + 1;
  }
}

fn JsonParser.parse_value() -> Result[JsonValue, ParseError] {
  skip_ws();
  if eof() {
    return Err(make_error("unexpected end of input"));
  }
  var ch = peek();
  if ch == BYTE_OPEN_BRACE() { return parse_object(); }
  if ch == BYTE_OPEN_BRACKET() { return parse_array(); }
  if ch == BYTE_QUOTE() { return parse_string_as_value(); }
  if ch == BYTE_MINUS() || (ch >= BYTE_ZERO() && ch <= BYTE_NINE()) { return parse_number_value(); }
  if ch == BYTE_LOWER_T() || ch == BYTE_LOWER_F() { return parse_bool_value(); }
  if ch == BYTE_LOWER_N() { return parse_null_value(); }
  return Err(make_error("unexpected character"));
}

fn JsonParser.parse_object() -> Result[JsonValue, ParseError] {
  advance();
  skip_ws();
  var entries = Vec[JsonEntry].new();
  if peek() != BYTE_CLOSE_BRACE() {
    var first = parse_entry();
    if first.is_err() { return Err(first.err_value()); }
    entries.push(first.ok_value());
    skip_ws();
    while peek() == BYTE_COMMA() {
      advance();
      skip_ws();
      var next = parse_entry();
      if next.is_err() { return Err(next.err_value()); }
      entries.push(next.ok_value());
      skip_ws();
    }
  }
  if peek() != BYTE_CLOSE_BRACE() {
    return Err(make_error("expected '}'"));
  }
  advance();
  return Ok(JsonValue.Object(entries));
}

fn JsonParser.parse_entry() -> Result[JsonEntry, ParseError] {
  skip_ws();
  if peek() != BYTE_QUOTE() { return Err(make_error("expected key string")); }
  var key_res = parse_string();
  if key_res.is_err() { return Err(key_res.err_value()); }
  skip_ws();
  if peek() != BYTE_COLON() { return Err(make_error("expected ':'")); }
  advance();
  var val_res = parse_value();
  if val_res.is_err() { return Err(val_res.err_value()); }
  return Ok(JsonEntry{ key: key_res.ok_value(), value: val_res.ok_value() });
}

fn JsonParser.parse_array() -> Result[JsonValue, ParseError] {
  advance();
  skip_ws();
  var items = Vec[JsonValue].new();
  if peek() != BYTE_CLOSE_BRACKET() {
    var first = parse_value();
    if first.is_err() { return Err(first.err_value()); }
    items.push(first.ok_value());
    skip_ws();
    while peek() == BYTE_COMMA() {
      advance();
      skip_ws();
      var next = parse_value();
      if next.is_err() { return Err(next.err_value()); }
      items.push(next.ok_value());
      skip_ws();
    }
  }
  if peek() != BYTE_CLOSE_BRACKET() {
    return Err(make_error("expected ']'"));
  }
  advance();
  return Ok(JsonValue.Array(items));
}

fn JsonParser.parse_string_as_value() -> Result[JsonValue, ParseError] {
  var s = parse_string();
  if s.is_err() { return Err(s.err_value()); }
  return Ok(JsonValue.String(s.ok_value()));
}

fn JsonParser.parse_string() -> Result[Str, ParseError] {
  advance();
  var result = "";
  while pos < len {
    match xiom.string.char_at(input, pos) {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte == BYTE_QUOTE() {
          advance();
          return Ok(result);
        }
        if byte == BYTE_BACKSLASH() {
          advance();
          if eof() { return Err(make_error("unexpected end of input in string escape")); }
          match xiom.string.char_at(input, pos) {
            Some(esc) => {
              var esc_byte = xiom.convert.char_to_int(esc);
              advance();
              if esc_byte == BYTE_QUOTE() {
                result = xiom.string.str_concat(result, "\"");
              } elif esc_byte == BYTE_BACKSLASH() {
                result = xiom.string.str_concat(result, "\\");
              } elif esc_byte == BYTE_SLASH() {
                result = xiom.string.str_concat(result, "/");
              } elif esc_byte == BYTE_LOWER_B() {
                result = xiom.string.str_concat(result, "\b");
              } elif esc_byte == BYTE_LOWER_F() {
                result = xiom.string.str_concat(result, "\f");
              } elif esc_byte == BYTE_LOWER_N() {
                result = xiom.string.str_concat(result, "\n");
              } elif esc_byte == BYTE_LOWER_R() {
                result = xiom.string.str_concat(result, "\r");
              } elif esc_byte == BYTE_LOWER_T() {
                result = xiom.string.str_concat(result, "\t");
              } elif esc_byte == BYTE_LOWER_U() {
                if pos + 4 > len { return Err(make_error("unexpected end of input in unicode escape")); }
                pos = pos + 4;
                result = xiom.string.str_concat(result, "\u0000");
              } else {
                return Err(make_error("invalid escape character"));
              }
            }
            None => return Err(make_error("unexpected end of input in string escape")),
          }
        } else {
          if byte < 32 {
            return Err(make_error("unescaped control character in string"));
          }
          var single = chr_byte(byte);
          result = xiom.string.str_concat(result, single);
          advance();
        }
      }
      None => return Err(make_error("unterminated string")),
    }
  }
  return Err(make_error("unterminated string"));
}

fn JsonParser.parse_number_value() -> Result[JsonValue, ParseError] {
  var num = parse_number();
  if num.is_err() { return Err(num.err_value()); }
  return Ok(JsonValue.Number(num.ok_value()));
}

fn JsonParser.read_digits() -> Int {
  var value: Int = 0;
  while pos < len {
    match xiom.string.char_at(input, pos) {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte < BYTE_ZERO() || byte > BYTE_NINE() { return value; }
        value = value * 10 + (byte - BYTE_ZERO());
        advance();
      }
      None => return value,
    }
  }
  return value;
}

fn JsonParser.parse_number() -> Result[Float64, ParseError] {
  var start = pos;
  var is_neg = false;
  if peek() == BYTE_MINUS() {
    is_neg = true;
    advance();
  }
  var int_val: Int = 0;
  if peek() == BYTE_ZERO() {
    advance();
  } elif peek() >= BYTE_ZERO() && peek() <= BYTE_NINE() {
    int_val = read_digits();
  } else {
    return Err(make_error("expected digit in number"));
  }
  var frac_val: Float64 = 0.0;
  if pos < len {
    match xiom.string.char_at(input, pos) {
      Some(ch) => {
        if xiom.convert.char_to_int(ch) == BYTE_DOT() {
          advance();
          if pos >= len {
            return Err(make_error("expected digit after decimal point"));
          }
          match xiom.string.char_at(input, pos) {
            Some(nch) => {
              var nbyte = xiom.convert.char_to_int(nch);
              if nbyte < BYTE_ZERO() || nbyte > BYTE_NINE() {
                return Err(make_error("expected digit after decimal point"));
              }
            }
            None => return Err(make_error("expected digit after decimal point")),
          }
          var frac_digits = read_digits();
          var fd: Float64 = xiom.convert.int_to_float(frac_digits);
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
  if pos < len {
    match xiom.string.char_at(input, pos) {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte == BYTE_LOWER_E() || byte == BYTE_UPPER_E() {
          advance();
          if pos < len {
            match xiom.string.char_at(input, pos) {
              Some(ech) => {
                var ebyte = xiom.convert.char_to_int(ech);
                if ebyte == BYTE_MINUS() {
                  exp_neg = true;
                  advance();
                } elif ebyte == BYTE_PLUS() {
                  advance();
                }
              }
              None => {},
            }
          }
          if pos >= len {
            return Err(make_error("expected digit in exponent"));
          }
          match xiom.string.char_at(input, pos) {
            Some(dch) => {
              var dbyte = xiom.convert.char_to_int(dch);
              if dbyte < BYTE_ZERO() || dbyte > BYTE_NINE() {
                return Err(make_error("expected digit in exponent"));
              }
            }
            None => return Err(make_error("expected digit in exponent")),
          }
          exp_val = read_digits();
        }
      }
      None => {},
    }
  }
  if start == pos {
    return Err(make_error("empty number"));
  }
  if is_neg && start + 1 == pos {
    return Err(make_error("incomplete negative number"));
  }
  var result: Float64 = xiom.convert.int_to_float(int_val) + frac_val;
  if exp_val > 0 {
    var mult: Float64 = 1.0;
    var ei: Int = 0;
    while ei < exp_val {
      if exp_neg { mult = mult / 10.0; }
      else { mult = mult * 10.0; }
      ei = ei + 1;
    }
    result = result * mult;
  }
  if is_neg { result = -result; }
  return Ok(result);
}

fn JsonParser.parse_bool_value() -> Result[JsonValue, ParseError] {
  if match_literal("true") {
    consume_literal("true", 4);
    return Ok(JsonValue.Bool(true));
  }
  if match_literal("false") {
    consume_literal("false", 5);
    return Ok(JsonValue.Bool(false));
  }
  return Err(make_error("expected 'true' or 'false'"));
}

fn JsonParser.parse_null_value() -> Result[JsonValue, ParseError] {
  if match_literal("null") {
    consume_literal("null", 4);
    return Ok(JsonValue.Null);
  }
  return Err(make_error("expected 'null'"));
}

// ============================================================
// SINGLE-CHARACTER STRING HELPER
// ============================================================

fn chr_byte(b: Int) -> Str {
  if b == 0 { return "\0"; }
  if b == 8 { return "\b"; }
  if b == 9 { return "\t"; }
  if b == 10 { return "\n"; }
  if b == 12 { return "\f"; }
  if b == 13 { return "\r"; }
  if b == 34 { return "\""; }
  if b == 92 { return "\\"; }
  if b == 39 { return "'"; }
  var result = " ";
  return result;
}

// ============================================================
// PUBLIC PARSE / VALIDATE
// ============================================================

pub fn json_parse(input: Str) -> Result[JsonValue, ParseError]
  requires: xiom.string.str_len(input) > 0
{
  var parser = JsonParser.new(input);
  var value = parser.parse_value();
  if value.is_err() { return value; }
  parser.skip_ws();
  if !parser.eof() {
    return Err(parser.make_error("trailing data after root value"));
  }
  return value;
}

pub fn json_validate(input: Str) -> Result[Bool, ParseError]
  requires: xiom.string.str_len(input) > 0
{
  var parser = JsonParser.new(input);
  var value = parser.parse_value();
  if value.is_err() { return Err(value.err_value()); }
  parser.skip_ws();
  if !parser.eof() {
    return Err(parser.make_error("trailing data after root value"));
  }
  return Ok(true);
}

// ============================================================
// JSON STRINGIFY — INTERNALS
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

fn stringify_string(s: Str) -> Str {
  var result = "\"";
  var i: Int = 0;
  while i < xiom.string.str_len(s) {
    match xiom.string.char_at(s, i) {
      Some(ch) => {
        var byte = xiom.convert.char_to_int(ch);
        if byte == 34 || byte == 92 || byte < 32 {
          result = xiom.string.str_concat(result, escape_char(byte));
        } else {
          result = xiom.string.str_concat(result, chr_byte(byte));
        }
      }
      None => {},
    }
    i = i + 1;
  }
  result = xiom.string.str_concat(result, "\"");
  return result;
}

fn stringify_number(v: Float64) -> Str {
  if v == 0.0 { return "0"; }
  var result = "";
  var num = v;
  if num < 0.0 {
    result = "-";
    num = -num;
  }
  if num >= 1000000000000000.0 {
    result = xiom.string.str_concat(result, "0");
    return result;
  }
  var int_part: Int = xiom.convert.float_to_int(num);
  var int_str = xiom.convert.int_to_string(int_part);
  result = xiom.string.str_concat(result, int_str);
  var frac = num - xiom.convert.int_to_float(int_part);
  if frac > 0.0000000001 {
    result = xiom.string.str_concat(result, ".");
    var digits: Int = 0;
    while frac > 0.0000000001 && digits < 15 {
      frac = frac * 10.0;
      var d: Int = xiom.convert.float_to_int(frac);
      result = xiom.string.str_concat(result, xiom.convert.int_to_char(d));
      frac = frac - xiom.convert.int_to_float(d);
      digits = digits + 1;
    }
  }
  return result;
}

fn stringify_indent(depth: Int, config: &JsonPrettyConfig) -> Str {
  var result = "\n";
  var total_spaces = depth * config.indent;
  var i: Int = 0;
  while i < total_spaces {
    result = xiom.string.str_concat(result, " ");
    i = i + 1;
  }
  return result;
}

fn stringify_value_rec(value: &JsonValue, depth: Int, config: &JsonPrettyConfig, is_pretty: Bool) -> Str {
  match value {
    Null => "null",
    Bool(v) => {
      if v { return "true"; }
      return "false";
    }
    Number(v) => stringify_number(v),
    String(v) => stringify_string(v),
    Array(items) => {
      if items.is_empty() { return "[]"; }
      var result = "[";
      if is_pretty {
        var i: Int = 0;
        while i < items.len() {
          result = xiom.string.str_concat(result, stringify_indent(depth + 1, config));
          result = xiom.string.str_concat(result, stringify_value_rec(&items[i], depth + 1, config, is_pretty));
          if i < items.len() - 1 {
            result = xiom.string.str_concat(result, ",");
          }
          i = i + 1;
        }
        result = xiom.string.str_concat(result, stringify_indent(depth, config));
        result = xiom.string.str_concat(result, "]");
      } else {
        var i: Int = 0;
        while i < items.len() {
          result = xiom.string.str_concat(result, stringify_value_rec(&items[i], depth + 1, config, is_pretty));
          if i < items.len() - 1 {
            result = xiom.string.str_concat(result, ",");
          }
          i = i + 1;
        }
        result = xiom.string.str_concat(result, "]");
      }
      return result;
    }
    Object(entries) => {
      if entries.is_empty() { return "{}"; }
      var sorted = Vec[JsonEntry].new();
      var k: Int = 0;
      while k < entries.len() {
        sorted.push(JsonEntry{ key: entries[k].key, value: entries[k].value.clone() });
        k = k + 1;
      }
      if config.sort_keys {
        sorted = sort_entries(sorted);
      }
      var result = "{";
      var i: Int = 0;
      while i < sorted.len() {
        if is_pretty {
          result = xiom.string.str_concat(result, stringify_indent(depth + 1, config));
        }
        result = xiom.string.str_concat(result, stringify_string(sorted[i].key));
        if is_pretty {
          result = xiom.string.str_concat(result, ": ");
        } else {
          result = xiom.string.str_concat(result, ":");
        }
        result = xiom.string.str_concat(result, stringify_value_rec(&sorted[i].value, depth + 1, config, is_pretty));
        if i < sorted.len() - 1 {
          result = xiom.string.str_concat(result, ",");
        }
        i = i + 1;
      }
      if is_pretty {
        result = xiom.string.str_concat(result, stringify_indent(depth, config));
      }
      result = xiom.string.str_concat(result, "}");
      return result;
    }
  }
}

fn sort_entries(entries: Vec[JsonEntry]) -> Vec[JsonEntry] {
  if entries.len() <= 1 { return entries; }
  var pivot = entries[entries.len() / 2];
  var less = Vec[JsonEntry].new();
  var greater = Vec[JsonEntry].new();
  var equal = Vec[JsonEntry].new();
  var i: Int = 0;
  while i < entries.len() {
    if entries[i].key < pivot.key {
      less.push(entries[i]);
    } elif entries[i].key > pivot.key {
      greater.push(entries[i]);
    } else {
      equal.push(entries[i]);
    }
    i = i + 1;
  }
  var sorted_less = sort_entries(less);
  var sorted_greater = sort_entries(greater);
  var result = Vec[JsonEntry].new();
  i = 0;
  while i < sorted_less.len() { result.push(sorted_less[i]); i = i + 1; }
  i = 0;
  while i < equal.len() { result.push(equal[i]); i = i + 1; }
  i = 0;
  while i < sorted_greater.len() { result.push(sorted_greater[i]); i = i + 1; }
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
        i = i + 1;
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
      JsonPathSegment.Key(k) => {
        var found = json_get(&current, k);
        if found.is_none() { return None; }
        current = found.ok_value();
      }
      JsonPathSegment.Index(idx) => {
        match current {
          Array(items) => {
            if idx < 0 || idx >= items.len() { return None; }
            current = items[idx].clone();
          }
          _ => return None,
        }
      }
    }
    i = i + 1;
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
        i = i + 1;
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
  var current = root;
  var i: Int = 0;
  while i < path.segments.len() - 1 {
    var seg = &path.segments[i];
    match seg {
      JsonPathSegment.Key(k) => {
        match current {
          Object(entries) => {
            var found_entry: Int = -1;
            var j: Int = 0;
            while j < entries.len() {
              if entries[j].key == k {
                found_entry = j;
              }
              j = j + 1;
            }
            if found_entry == -1 {
              entries.push(JsonEntry{ key: k, value: JsonValue.Null });
              found_entry = entries.len() - 1;
            }
            current = &mut entries[found_entry].value;
          }
          _ => return false,
        }
      }
      JsonPathSegment.Index(idx) => {
        match current {
          Array(items) => {
            if idx < 0 || idx >= items.len() { return false; }
            current = &mut items[idx];
          }
          _ => return false,
        }
      }
    }
    i = i + 1;
  }
  var last_seg = &path.segments[path.segments.len() - 1];
  match last_seg {
    JsonPathSegment.Key(k) => {
      return json_set(current, k, value);
    }
    JsonPathSegment.Index(idx) => {
      match current {
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
            j = j + 1;
          }
          entries = new_entries;
          return true;
        }
        i = i + 1;
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
        i = i + 1;
      }
      return false;
    }
    _ => false,
  }
}

pub fn json_is_type(value: &JsonValue, expected: JsonType) -> Bool {
  match value {
    Null => expected == JsonType.NullType,
    Bool(_) => expected == JsonType.BoolType,
    Number(_) => expected == JsonType.NumberType,
    String(_) => expected == JsonType.StringType,
    Array(_) => expected == JsonType.ArrayType,
    Object(_) => expected == JsonType.ObjectType,
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
              j = j + 1;
            }
            if found_idx != -1 {
              var ov = &overlay_entries[i].value;
              match ov {
                Object(_) => {
                  var r = json_merge(&mut base_entries[found_idx].value, ov);
                  if !r { return false; }
                }
                _ => {
                  base_entries[found_idx].value = ov.clone();
                }
              }
            } else {
              base_entries.push(JsonEntry{
                key: overlay_entries[i].key,
                value: overlay_entries[i].value.clone(),
              });
            }
            i = i + 1;
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
  if type_field.is_some() {
    var type_val = type_field.ok_value();
    var ok = schema_check_type(value, &type_val);
    if !ok { return Err("type mismatch"); }
  }
  var enum_field = json_get(schema, "enum");
  if enum_field.is_some() {
    var enum_vals = enum_field.ok_value();
    match enum_vals {
      Array(allowed) => {
        var found = false;
        var i: Int = 0;
        while i < allowed.len() {
          if json_values_equal(value, &allowed[i]) { found = true; }
          i = i + 1;
        }
        if !found { return Err("value not in enum"); }
      }
      _ => return Err("schema enum must be array"),
    }
  }
  var props_field = json_get(schema, "properties");
  if props_field.is_some() {
    match value {
      Object(_) => {},
      _ => return Err("properties constraint requires object value"),
    }
    match props_field.ok_value() {
      Object(prop_schemas) => {
        var i: Int = 0;
        while i < prop_schemas.len() {
          var prop_val = json_get(value, prop_schemas[i].key);
          if prop_val.is_some() {
            var r = json_schema_validate(&prop_val.ok_value(), &prop_schemas[i].value);
            if r.is_err() {
              var err_msg = xiom.string.str_concat("property '", prop_schemas[i].key);
              err_msg = xiom.string.str_concat(err_msg, "': ");
              err_msg = xiom.string.str_concat(err_msg, r.err_value());
              return Err(err_msg);
            }
          }
          i = i + 1;
        }
      }
      _ => return Err("schema properties must be object"),
    }
  }
  var required_field = json_get(schema, "required");
  if required_field.is_some() {
    match value {
      Object(_) => {},
      _ => return Err("required constraint requires object value"),
    }
    match required_field.ok_value() {
      Array(required_keys) => {
        var i: Int = 0;
        while i < required_keys.len() {
          match required_keys[i] {
            String(rk) => {
              if !json_has_key(value, rk) { return Err("missing required key"); }
            }
            _ => {},
          }
          i = i + 1;
        }
      }
      _ => return Err("schema required must be array"),
    }
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
        i = i + 1;
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
            i = i + 1;
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
            if bv.is_none() { return false; }
            if !json_values_equal(&aentries[i].value, &bv.ok_value()) { return false; }
            i = i + 1;
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
        i = i + 1;
      }
      entries.push(JsonEntry{ key: key, value: value });
    }
    _ => {},
  }
}

// ============================================================
// JSONPATH CONSTRUCTOR HELPERS
// ============================================================

pub fn JsonPath.new() -> JsonPath {
  return JsonPath{ segments: Vec[JsonPathSegment].new() };
}

pub fn JsonPath.push_key(key: Str)
  requires: xiom.string.str_len(key) > 0
{
  segments.push(JsonPathSegment.Key(key));
}

pub fn JsonPath.push_index(index: Int) {
  segments.push(JsonPathSegment.Index(index));
}

pub fn JsonPath.parse(path_str: Str) -> Result[JsonPath, Str]
  requires: xiom.string.str_len(path_str) > 0
{
  var result = JsonPath{ segments: Vec[JsonPathSegment].new() };
  var str_len = xiom.string.str_len(path_str);
  if str_len == 0 { return Ok(result); }
  var i: Int = 0;
  if path_byte(path_str, i) == 36 {
    i = i + 1;
  }
  while i < str_len {
    var b = path_byte(path_str, i);
    if b == 46 {
      i = i + 1;
      var start = i;
      var scanning = true;
      while i < str_len && scanning {
        var cb = path_byte(path_str, i);
        if cb == 46 || cb == 91 { scanning = false; }
        else { i = i + 1; }
      }
      if i > start {
        var key = "";
        var j = start;
        while j < i {
          key = xiom.string.str_concat(key, chr_byte(path_byte(path_str, j)));
          j = j + 1;
        }
        result.segments.push(JsonPathSegment.Key(key));
      }
    } elif b == 91 {
      i = i + 1;
      if i < str_len && path_byte(path_str, i) == 39 {
        i = i + 1;
        var start = i;
        var scanning = true;
        while i < str_len && scanning {
          if path_byte(path_str, i) == 39 { scanning = false; }
          else { i = i + 1; }
        }
        if i >= str_len { return Err("unterminated bracket key"); }
        var key = "";
        var j = start;
        while j < i {
          key = xiom.string.str_concat(key, chr_byte(path_byte(path_str, j)));
          j = j + 1;
        }
        result.segments.push(JsonPathSegment.Key(key));
        i = i + 1;
        if i < str_len && path_byte(path_str, i) == 93 {
          i = i + 1;
        } else {
          return Err("expected ']'");
        }
      } else {
        var start = i;
        var scanning = true;
        while i < str_len && scanning {
          var nb = path_byte(path_str, i);
          if nb >= 48 && nb <= 57 { i = i + 1; }
          else { scanning = false; }
        }
        if i > start {
          var idx: Int = 0;
          var j = start;
          while j < i {
            idx = idx * 10 + (path_byte(path_str, j) - 48);
            j = j + 1;
          }
          result.segments.push(JsonPathSegment.Index(idx));
        }
        if i < str_len && path_byte(path_str, i) == 93 {
          i = i + 1;
        } else {
          return Err("expected ']'");
        }
      }
    } else {
      return Err("unexpected character in path");
    }
  }
  return Ok(result);
}

fn path_byte(s: Str, i: Int) -> Int {
  match xiom.string.char_at(s, i) {
    Some(ch) => xiom.convert.char_to_int(ch),
    None => -1,
  }
}

// ============================================================
// JSONPRETTYCONFIG CONSTRUCTOR
// ============================================================

pub fn JsonPrettyConfig.compact() -> JsonPrettyConfig {
  return JsonPrettyConfig{ indent: 0, sort_keys: false };
}

pub fn JsonPrettyConfig.default() -> JsonPrettyConfig {
  return JsonPrettyConfig{ indent: 2, sort_keys: false };
}

pub fn JsonPrettyConfig.sorted() -> JsonPrettyConfig {
  return JsonPrettyConfig{ indent: 2, sort_keys: true };
}
