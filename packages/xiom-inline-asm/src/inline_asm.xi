// XIOM -- xiom.inline-asm: inline-assembly template parser and clobber lists
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no codegen.
//
// A parser and canonical formatter for inline-assembly templates in the
// dialect-neutral syntax documented in SPEC.md:
//   template = *( literal / "$$" / operand )
//   operand  = "$" digits / "${" digits [ ":" constraint ] "}"
// Template text is opaque otherwise: this package never lowers, never
// resolves registers and never touches a target backend. It answers the
// structural questions a front end needs: which operands a template
// references, in which order, with which constraint strings, and what a
// clobber list contains.
//
// Model: one parsed template is an AsmTemplate with flat, index-aligned
// parallel vectors because XIOM v0.61.3 cannot hold Vec[StructType]. Chunk i
// is kinds[i] ("lit" or "op"), texts[i] (the literal text, with "$$" already
// decoded to "$", or the operand constraint) and indexes[i] (the operand
// index for "op", -1 for "lit").
//
// Language notes (XIOM v0.61.3): free functions only; Str equality goes
// through xiom.string.compare.str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison); every element read
// is bound to a typed local first; Ok/Err are constructed only in the leaf
// helpers _ok_template/_err_template and _ok_names/_err_names.

module xiom.inline.asm

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(t) for Result[AsmTemplate, Str].
fn _ok_template(t: AsmTemplate) -> Result[AsmTemplate, Str] {
  return Ok(t);
}

// Err(m) for Result[AsmTemplate, Str].
fn _err_template(m: Str) -> Result[AsmTemplate, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _ok_names(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_names(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (all ASCII)
// --------------------------------------------------

const _ASM_TAB: UInt8 = 9u8;
const _ASM_SPACE: UInt8 = 32u8;
const _ASM_BANG: UInt8 = 33u8;
const _ASM_HASH: UInt8 = 35u8;
const _ASM_DOLLAR: UInt8 = 36u8;
const _ASM_PERCENT: UInt8 = 37u8;
const _ASM_AMP: UInt8 = 38u8;
const _ASM_STAR: UInt8 = 42u8;
const _ASM_PLUS: UInt8 = 43u8;
const _ASM_COMMA: UInt8 = 44u8;
const _ASM_MINUS: UInt8 = 45u8;
const _ASM_DOT: UInt8 = 46u8;
const _ASM_DIGIT_0: UInt8 = 48u8;
const _ASM_DIGIT_9: UInt8 = 57u8;
const _ASM_COLON: UInt8 = 58u8;
const _ASM_LT: UInt8 = 60u8;
const _ASM_EQ: UInt8 = 61u8;
const _ASM_GT: UInt8 = 62u8;
const _ASM_UNDERSCORE: UInt8 = 95u8;
const _ASM_CARET: UInt8 = 94u8;
const _ASM_LBRACE: UInt8 = 123u8;
const _ASM_RBRACE: UInt8 = 125u8;
const _ASM_TILDE: UInt8 = 126u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed inline-assembly template, stored flat.
/// Chunk i (0-based, in source order) is kinds[i] ("lit" or "op"),
/// texts[i] (the literal bytes with "$$" decoded to "$", or the operand
/// constraint string) and indexes[i] (the operand index for "op", -1 for
/// "lit"). operand_count is one more than the highest referenced operand
/// (0 when the template references none). The three parallel vectors are
/// index-aligned; accessors operate on their shortest length.
pub type AsmTemplate = {
  kinds: Vec[Str];
  texts: Vec[Str];
  indexes: Vec[Int];
  operand_count: Int;
}

// --------------------------------------------------
//  Character predicates and small helpers
// --------------------------------------------------

// ASCII digit byte: 0-9.
fn _is_digit(b: UInt8) -> Bool {
  return b >= _ASM_DIGIT_0 && b <= _ASM_DIGIT_9;
}

// ASCII letter byte: A-Z or a-z.
fn _is_letter(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 {
    return true;
  }
  return b >= 97u8 && b <= 122u8;
}

// Constraint byte: ASCII letter, ASCII digit, or one of the documented
// modifier/class punctuation bytes = + & * % ! ~ ^ , . - < >.
fn _is_constraint_char(b: UInt8) -> Bool {
  if _is_letter(b) || _is_digit(b) {
    return true;
  }
  if b == _ASM_EQ || b == _ASM_PLUS || b == _ASM_AMP || b == _ASM_STAR {
    return true;
  }
  if b == _ASM_PERCENT || b == _ASM_BANG || b == _ASM_TILDE || b == _ASM_CARET {
    return true;
  }
  if b == _ASM_COMMA || b == _ASM_DOT || b == _ASM_MINUS || b == _ASM_LT {
    return true;
  }
  return b == _ASM_GT;
}

// Clobber-name byte: ASCII letter, ASCII digit, "_" or ".".
fn _is_clobber_char(b: UInt8) -> Bool {
  if _is_letter(b) || _is_digit(b) {
    return true;
  }
  return b == _ASM_UNDERSCORE || b == _ASM_DOT;
}

// ASCII space or tab.
fn _is_space(b: UInt8) -> Bool {
  return b == _ASM_SPACE || b == _ASM_TAB;
}

// Parse the ASCII digit run s[from..to) into a non-negative Int.
// Returns: the value; -1 when the run is empty, carries a non-digit byte, or
// would exceed 1000000000 (overflow guard).
fn _parse_digits(s: Str, from: Int, to: Int) -> Int {
  if from >= to {
    return -1;
  }
  var v = 0;
  var i = from;
  while i < to {
    let b = string.byte_at(s, i);
    if b < _ASM_DIGIT_0 || b > _ASM_DIGIT_9 {
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
//  Template construction
// --------------------------------------------------

/// A fresh, empty template: no chunks and no operands.
/// Params: none.
/// Returns: an empty AsmTemplate.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_new() -> AsmTemplate {
  return AsmTemplate{
    kinds: Vec[Str].new();
    texts: Vec[Str].new();
    indexes: Vec[Int].new();
    operand_count: 0;
  };
}

/// Append one literal chunk. An empty text is ignored. The text is stored
/// verbatim (a "$" in it is a literal and is escaped by asm_template_emit).
/// Params: t - the template to mutate; text - the literal bytes.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_push_literal(t: &mut AsmTemplate, text: Str) {
  if text.len() == 0 {
    return;
  }
  t.kinds.push("lit");
  t.texts.push(text);
  t.indexes.push(-1);
}

/// Append one operand reference. A negative index is ignored. The constraint
/// is stored verbatim (empty means "no constraint"); operand_count grows to
/// index + 1. No validation is performed: a negative or oversized index, or
/// a constraint outside the documented alphabet, is written as given and the
/// emitted text may not re-parse.
/// Params: t - the template to mutate; index - the operand index; constraint
/// - the constraint string ("" when none).
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_push_operand(t: &mut AsmTemplate, index: Int, constraint: Str) {
  if index < 0 {
    return;
  }
  t.kinds.push("op");
  t.texts.push(constraint);
  t.indexes.push(index);
  if index + 1 > t.operand_count {
    t.operand_count = index + 1;
  }
}

// --------------------------------------------------
//  Template parsing
// --------------------------------------------------

/// Parse an inline-assembly template.
/// Params: text - the template text: literals (any bytes except "$") mixed
/// with "$<n>" and "${<n>}" / "${<n>:<constraint>}" operand references.
/// Inside a literal, "$$" decodes to one "$"; "}" outside an operand is a
/// literal byte. Digits may have leading zeros.
/// Returns: Ok(AsmTemplate) with one chunk per maximal literal run and one
/// chunk per operand; "" parses to an empty template.
/// Error case: Err("asm: ...") for a dangling "$", a missing or overflowing
/// operand index, a missing ":" or "}" after the index, an empty or invalid
/// constraint, or an unterminated operand. Operand errors carry the byte
/// offset of the operand's "$", except "bad constraint character", which
/// carries the offset of that character.
/// Complexity: O(input length).
pub fn asm_template_parse(text: Str) -> Result[AsmTemplate, Str] {
  var kinds = Vec[Str].new();
  var texts = Vec[Str].new();
  var indexes = Vec[Int].new();
  var operand_count = 0;
  var lit = Vec[UInt8].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(text, i);
    if b != _ASM_DOLLAR {
      lit.push(b);
      i = i + 1;
    } elif i + 1 >= n {
      return _err_template("asm: dangling '$' at " + int_to_string(i));
    } else {
      let b2 = string.byte_at(text, i + 1);
      if b2 == _ASM_DOLLAR {
        lit.push(_ASM_DOLLAR);
        i = i + 2;
      } else {
        var index = -1;
        var constraint = "";
        var after = 0;
        if b2 == _ASM_LBRACE {
          var j = i + 2;
          var d = j;
          while d < n {
            let c = string.byte_at(text, d);
            if !_is_digit(c) {
              break;
            }
            d = d + 1;
          }
          if d == j {
            return _err_template("asm: bad operand index at " + int_to_string(i));
          }
          index = _parse_digits(text, j, d);
          if index < 0 {
            return _err_template("asm: operand index overflow at " + int_to_string(i));
          }
          var k = d;
          if k < n && string.byte_at(text, k) == _ASM_COLON {
            var c = k + 1;
            var e = c;
            while e < n {
              let ch = string.byte_at(text, e);
              if !_is_constraint_char(ch) {
                break;
              }
              e = e + 1;
            }
            if e == c {
              if c >= n {
                return _err_template("asm: unterminated operand at " + int_to_string(i));
              }
              if string.byte_at(text, c) == _ASM_RBRACE {
                return _err_template("asm: empty constraint at " + int_to_string(i));
              }
              return _err_template("asm: bad constraint character at " + int_to_string(c));
            }
            constraint = string.str_slice(text, c, e);
            k = e;
          }
          if k >= n {
            return _err_template("asm: unterminated operand at " + int_to_string(i));
          }
          if string.byte_at(text, k) != _ASM_RBRACE {
            return _err_template("asm: bad constraint character at " + int_to_string(k));
          }
          after = k + 1;
        } else {
          if !_is_digit(b2) {
            return _err_template("asm: bad operand index at " + int_to_string(i));
          }
          var j = i + 1;
          var d = j;
          while d < n {
            let c = string.byte_at(text, d);
            if !_is_digit(c) {
              break;
            }
            d = d + 1;
          }
          index = _parse_digits(text, j, d);
          if index < 0 {
            return _err_template("asm: operand index overflow at " + int_to_string(i));
          }
          after = d;
        }
        if lit.len() > 0 {
          kinds.push("lit");
          texts.push(Str::from_utf8(lit));
          indexes.push(-1);
          lit = Vec[UInt8].new();
        }
        kinds.push("op");
        texts.push(constraint);
        indexes.push(index);
        if index + 1 > operand_count {
          operand_count = index + 1;
        }
        i = after;
      }
    }
  }
  if lit.len() > 0 {
    kinds.push("lit");
    texts.push(Str::from_utf8(lit));
    indexes.push(-1);
  }
  return _ok_template(AsmTemplate{
    kinds: kinds;
    texts: texts;
    indexes: indexes;
    operand_count: operand_count;
  });
}

// --------------------------------------------------
//  Template accessors
// --------------------------------------------------

// Number of index-aligned chunks: the shortest of the three parallel arrays.
fn _chunk_count(t: &AsmTemplate) -> Int {
  var n = t.kinds.len();
  if t.texts.len() < n {
    n = t.texts.len();
  }
  if t.indexes.len() < n {
    n = t.indexes.len();
  }
  return n;
}

/// Number of chunks (literal runs and operands) in `t`.
/// Params: t - the template.
/// Returns: the chunk count; 0 for an empty template.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_chunk_count(t: &AsmTemplate) -> Int {
  return _chunk_count(t);
}

/// Number of distinct operands the template references: one more than the
/// highest index (0 when none). For a hand-built template this is the value
/// maintained by asm_template_push_operand.
/// Params: t - the template.
/// Returns: the operand count; never negative.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_operand_count(t: &AsmTemplate) -> Int {
  let v: Int = t.operand_count;
  if v < 0 {
    return 0;
  }
  return v;
}

/// Kind of chunk `i`.
/// Params: t - the template; i - the zero-based chunk index.
/// Returns: "lit" or "op"; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_kind(t: &AsmTemplate, i: Int) -> Str {
  if i < 0 || i >= _chunk_count(t) {
    return "";
  }
  let v: Str = t.kinds[i];
  return v;
}

/// Text of chunk `i`: the literal bytes (with "$$" decoded) or the operand
/// constraint string.
/// Params: t - the template; i - the zero-based chunk index.
/// Returns: the text; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_text(t: &AsmTemplate, i: Int) -> Str {
  if i < 0 || i >= _chunk_count(t) {
    return "";
  }
  let v: Str = t.texts[i];
  return v;
}

/// Operand index of chunk `i`.
/// Params: t - the template; i - the zero-based chunk index.
/// Returns: the operand index for an "op" chunk; -1 for a "lit" chunk and
/// for any out-of-range `i`.
/// Error case: none.
/// Complexity: O(1).
pub fn asm_template_index(t: &AsmTemplate, i: Int) -> Int {
  if i < 0 || i >= _chunk_count(t) {
    return -1;
  }
  let v: Int = t.indexes[i];
  return v;
}

/// Number of operand chunks referencing operand `index`.
/// Params: t - the template; index - the operand index.
/// Returns: the reference count; 0 for a negative index.
/// Error case: none.
/// Complexity: O(chunks).
pub fn asm_template_uses(t: &AsmTemplate, index: Int) -> Int {
  if index < 0 {
    return 0;
  }
  var c = 0;
  var i = 0;
  let n = _chunk_count(t);
  while i < n {
    let v: Int = t.indexes[i];
    if v == index {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Highest operand index referenced by the template.
/// Params: t - the template.
/// Returns: the maximum operand index; -1 when no operand is referenced.
/// Error case: none.
/// Complexity: O(chunks).
pub fn asm_template_max_operand(t: &AsmTemplate) -> Int {
  var best = -1;
  var i = 0;
  let n = _chunk_count(t);
  while i < n {
    let v: Int = t.indexes[i];
    if v > best {
      best = v;
    }
    i = i + 1;
  }
  return best;
}

// Double every "$" in `text` so it survives a re-parse as literal text.
fn _escape_dollars(text: Str) -> Str {
  var out = "";
  var i = 0;
  let n = text.len();
  while i < n {
    let b = string.byte_at(text, i);
    if b == _ASM_DOLLAR {
      out = out + "$$";
    } else {
      out = out + string.str_slice(text, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

/// Canonical emission of a template: literal chunks verbatim with every "$"
/// escaped as "$$", operand chunks as "${<n>}" or "${<n>:<constraint>}"
/// (always braced, so an operand followed by literal digits cannot merge).
/// Adjacent literal chunks are emitted contiguously and re-parse as one
/// chunk; unknown chunk kinds are emitted as literals.
/// Params: t - the template to serialize.
/// Returns: the canonical template text; "" for an empty template.
/// Error case: none. Mismatched parallel arrays are clamped to their
/// shortest length; a hand-built negative or oversized operand index is
/// emitted as given and may not re-parse.
/// Complexity: O(total output length).
pub fn asm_template_emit(t: &AsmTemplate) -> Str {
  var out = "";
  var i = 0;
  let n = _chunk_count(t);
  while i < n {
    let kind: Str = t.kinds[i];
    let text: Str = t.texts[i];
    if compare.str_compare(kind, "op") == 0 {
      let index: Int = t.indexes[i];
      out = out + "${" + int_to_string(index);
      if text.len() > 0 {
        out = out + ":" + text;
      }
      out = out + "}";
    } else {
      out = out + _escape_dollars(text);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Operand constraints
// --------------------------------------------------

/// Classification of an operand constraint string.
/// Params: c - the constraint text ("" allowed).
/// Returns: "none" for "", "register" for r, "memory" for m,
/// "offset_memory" for o, "immediate" for i, "immediate_integer" for n,
/// "general" for g, "xmm_register" for x, "register_or_memory" for rm, and
/// "unknown" otherwise. Leading output modifiers "=", "+" and "&" are
/// stripped before the table lookup, so "=r" is "register".
/// Error case: none.
/// Complexity: O(len(c)).
pub fn asm_constraint_class(c: Str) -> Str {
  var i = 0;
  let n = c.len();
  while i < n {
    let b = string.byte_at(c, i);
    if b != _ASM_EQ && b != _ASM_PLUS && b != _ASM_AMP {
      break;
    }
    i = i + 1;
  }
  let core = string.str_slice(c, i, n);
  if core.len() == 0 {
    return "none";
  }
  if compare.str_compare(core, "r") == 0 {
    return "register";
  }
  if compare.str_compare(core, "m") == 0 {
    return "memory";
  }
  if compare.str_compare(core, "o") == 0 {
    return "offset_memory";
  }
  if compare.str_compare(core, "i") == 0 {
    return "immediate";
  }
  if compare.str_compare(core, "n") == 0 {
    return "immediate_integer";
  }
  if compare.str_compare(core, "g") == 0 {
    return "general";
  }
  if compare.str_compare(core, "x") == 0 {
    return "xmm_register";
  }
  if compare.str_compare(core, "rm") == 0 {
    return "register_or_memory";
  }
  return "unknown";
}

/// True when the constraint starts with an output modifier: "=" (write-only)
/// or "+" (read-write).
/// Params: c - the constraint text.
/// Returns: the flag; false for "".
/// Error case: none.
/// Complexity: O(1).
pub fn asm_constraint_is_output(c: Str) -> Bool {
  if c.len() == 0 {
    return false;
  }
  let b = string.byte_at(c, 0);
  return b == _ASM_EQ || b == _ASM_PLUS;
}

/// True when `c` is a non-empty constraint string over the documented
/// alphabet (ASCII letters, ASCII digits, and = + & * % ! ~ ^ , . - < >).
/// Params: c - the constraint text.
/// Returns: the flag; false for "" and for any out-of-alphabet byte.
/// Error case: none.
/// Complexity: O(len(c)).
pub fn asm_constraint_is_valid(c: Str) -> Bool {
  if c.len() == 0 {
    return false;
  }
  var i = 0;
  while i < c.len() {
    if !_is_constraint_char(string.byte_at(c, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Clobber lists
// --------------------------------------------------

/// Parse a clobber list: comma-separated names, each over ASCII letters,
/// digits, "_" and ".". Surrounding SPACE/TAB is trimmed; the empty list is
/// valid and yields zero names. Names are case-sensitive and must be unique.
/// Params: text - the clobber list text.
/// Returns: Ok(Vec[Str]) with the names in order (a fresh vector).
/// Error case: Err("asm: empty clobber at <pos>") for an empty entry,
/// Err("asm: bad clobber character at <pos>") for a byte outside the
/// alphabet, Err("asm: duplicate clobber at <pos>") for a repeated name.
/// Positions are byte offsets of the offending entry or byte.
/// Complexity: O(input length * entries).
pub fn asm_clobbers_parse(text: Str) -> Result[Vec[Str], Str] {
  var names = Vec[Str].new();
  let n = text.len();
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(text, i) == _ASM_COMMA {
      var es = start;
      while es < i {
        if !_is_space(string.byte_at(text, es)) {
          break;
        }
        es = es + 1;
      }
      var ee = i;
      while ee > es {
        if !_is_space(string.byte_at(text, ee - 1)) {
          break;
        }
        ee = ee - 1;
      }
      if es == ee {
        if names.len() == 0 && start == 0 && i == n {
          return _ok_names(names);
        }
        return _err_names("asm: empty clobber at " + int_to_string(es));
      }
      var k = es;
      while k < ee {
        if !_is_clobber_char(string.byte_at(text, k)) {
          return _err_names("asm: bad clobber character at " + int_to_string(k));
        }
        k = k + 1;
      }
      let name = string.str_slice(text, es, ee);
      var d = 0;
      while d < names.len() {
        let prev: Str = names[d];
        if compare.str_compare(prev, name) == 0 {
          return _err_names("asm: duplicate clobber at " + int_to_string(es));
        }
        d = d + 1;
      }
      names.push(name);
      start = i + 1;
    }
    i = i + 1;
  }
  return _ok_names(names);
}

/// Canonical emission of a clobber list: names joined with ", " in order.
/// Params: names - the clobber names.
/// Returns: the joined text; "" for an empty list.
/// Error case: none.
/// Complexity: O(total name length).
pub fn asm_clobbers_emit(names: &Vec[Str]) -> Str {
  var out = "";
  var i = 0;
  while i < names.len() {
    if i > 0 {
      out = out + ", ";
    }
    let name: Str = names[i];
    out = out + name;
    i = i + 1;
  }
  return out;
}
