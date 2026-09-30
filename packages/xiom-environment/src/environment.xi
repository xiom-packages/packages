// XIOM -- xiom.environment: deterministic environment-variable expansion
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure, deterministic `${VAR}` expansion engine. The variable table is
// caller-supplied (parallel name/value vectors, or "NAME=VALUE" entries built
// with env_vars_from_pairs); the module never reads or writes the process
// environment, so every result is a pure function of its inputs.
//
// Recognized syntax (full grammar, semantics and error catalog in SPEC.md):
//   ${NAME}          value of NAME; strict mode rejects an unset NAME
//   ${NAME:-default} default when NAME is unset OR empty
//   ${NAME-default}  default when NAME is unset (set-but-empty keeps "")
//   ${NAME:+alt}     alt when NAME is set AND non-empty, else ""
//   ${NAME:?message} value when set and non-empty, else Err with the message
//   $$               one literal "$"
//   '...'            literal span (no expansion; the quotes are removed)
//   "..."            expanding span (references expand; the quotes are removed)
// Operator operand text is itself expanded (nested references allowed up to
// _ENV_MAX_NEST levels); expansion is single-pass, so substituted values are
// copied verbatim and never re-scanned.
//
// v0.62.2 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * byte_at returns UInt8, so bytes compare directly (no widen+mask idiom).
//   * Every loop either advances its index or returns, and every branch of the
//     expander consumes at least one byte, so expansion always terminates.
//   * Ok/Err for the struct payloads (Expansion) are constructed only in the
//     leaf helpers _env_ok_exp/_env_err_exp.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17);
//     Vec[Str] elements are read into typed locals before any use.
//   * Helper names carry the _env_ prefix because short C-runtime names such
//     as _close collide with the platform linker.

module xiom.environment

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A caller-supplied variable table: `names` and `values` are index-aligned.
/// Lookups are byte-exact and case-sensitive; the first entry whose name
/// matches and that has a parallel value wins, so duplicate names resolve to
/// the first occurrence. A name beyond the end of `values` is treated as
/// unset (the shorter vector bounds every lookup).
pub type EnvVars = {
  names: Vec[Str];
  values: Vec[Str];
}

/// The result of a successful expansion: `text` is the expanded output and
/// `names` lists the distinct variable names that were looked up, in
/// first-lookup order. Names inside skipped operator operands, inside
/// single-quoted spans, and names never reached because of an error, are not
/// reported.
pub type Expansion = {
  text: Str;
  names: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(0) for the internal Result[Int, Str] step protocol.
fn _env_ok_step() -> Result[Int, Str] {
  return Ok(0);
}

// Err(m) for the internal Result[Int, Str] step protocol.
fn _env_err_step(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(Expansion) for Result[Expansion, Str].
fn _env_ok_exp(text: Str, names: Vec[Str]) -> Result[Expansion, Str] {
  return Ok(Expansion{ text: text; names: names });
}

// Err(m) for Result[Expansion, Str].
fn _env_err_exp(m: Str) -> Result[Expansion, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _ENV_DOLLAR: UInt8 = 36u8;
const _ENV_SQUOTE: UInt8 = 39u8;
const _ENV_DQUOTE: UInt8 = 34u8;
const _ENV_DASH: UInt8 = 45u8;
const _ENV_PLUS: UInt8 = 43u8;
const _ENV_COLON: UInt8 = 58u8;
const _ENV_EQ: UInt8 = 61u8;
const _ENV_QUESTION: UInt8 = 63u8;
const _ENV_LBRACE: UInt8 = 123u8;
const _ENV_RBRACE: UInt8 = 125u8;

// Depth cap: operator operands are expanded recursively; top-level text runs
// at depth 0, so at most eight nested operand levels are allowed.
const _ENV_MAX_NEST: Int = 8;

// --------------------------------------------------
//  Byte predicates
// --------------------------------------------------

// True for a NAME start byte: A-Z a-z _.
fn _env_is_name_start(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 {
    return true;
  }
  if b >= 97u8 && b <= 122u8 {
    return true;
  }
  return b == 95u8;
}

// True for a NAME continuation byte: A-Z a-z 0-9 _.
fn _env_is_name_char(b: UInt8) -> Bool {
  if _env_is_name_start(b) {
    return true;
  }
  return b >= 48u8 && b <= 57u8;
}

// --------------------------------------------------
//  Scanning helpers (every loop advances or returns)
// --------------------------------------------------

// Index of the first `want` byte in s[from, to), or -1.
fn _env_find_byte(s: Str, from: Int, to: Int, want: UInt8) -> Int {
  var i = from;
  while i < to {
    if string.byte_at(s, i) == want {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the `}` that matches the reference whose content starts at `from`,
// or -1 when there is none before `to`. A "$" followed by "{" opens one
// nesting level and a "}" closes the innermost one; every other byte,
// including a "$" in any other position, is skipped. Quoting does not shield
// braces here -- an operand cannot contain an unbalanced "}" (SPEC section 3).
fn _env_find_close(s: Str, from: Int, to: Int) -> Int {
  var i = from;
  var nest = 0;
  while i < to {
    let b: UInt8 = string.byte_at(s, i);
    if b == _ENV_DOLLAR && i + 1 < to && string.byte_at(s, i + 1) == _ENV_LBRACE {
      nest = nest + 1;
      i = i + 2;
    } elif b == _ENV_RBRACE {
      if nest == 0 {
        return i;
      }
      nest = nest - 1;
      i = i + 1;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Index just past the NAME prefix of s[start, to). Returns `start` when the
// first byte is not a NAME start byte (an empty name).
fn _env_scan_name(s: Str, start: Int, to: Int) -> Int {
  if start >= to {
    return start;
  }
  if !_env_is_name_start(string.byte_at(s, start)) {
    return start;
  }
  var i = start + 1;
  while i < to && _env_is_name_char(string.byte_at(s, i)) {
    i = i + 1;
  }
  return i;
}

// --------------------------------------------------
//  Table helpers
// --------------------------------------------------

// Index of the first entry in `vars` whose name equals `name` and that has a
// parallel value, or -1. Comparisons go through str_compare (BUG 17).
fn _env_lookup(vars: &EnvVars, name: Str) -> Int {
  var lim = vars.names.len();
  if vars.values.len() < lim {
    lim = vars.values.len();
  }
  var i = 0;
  while i < lim {
    let n: Str = vars.names[i];
    if compare.str_compare(n, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Value paired with index `idx` (callers pass an index from _env_lookup).
fn _env_value(vars: &EnvVars, idx: Int) -> Str {
  let v: Str = vars.values[idx];
  return v;
}

// True when `items` already holds `name` (str_compare, never `==`).
fn _env_contains(items: &Vec[Str], name: Str) -> Bool {
  var i = 0;
  while i < items.len() {
    let item: Str = items[i];
    if compare.str_compare(item, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Record one name in the referenced-variable list (distinct, first-seen).
fn _env_seen_add(seen: &mut Vec[Str], name: Str) {
  if !_env_contains(seen, name) {
    seen.push(name);
  }
}

// --------------------------------------------------
//  Output helpers
// --------------------------------------------------

// Append s[from, to) to the output buffer verbatim.
fn _env_push_range(out: &mut Vec[UInt8], s: Str, from: Int, to: Int) {
  if to <= from {
    return;
  }
  builder.sb_push_str(out, string.str_slice(s, from, to));
}

// --------------------------------------------------
//  Reference expansion
// --------------------------------------------------

// `${NAME}` in the current strictness: value, or Err when unset and strict,
// or "" when unset and lenient. The name is always recorded as referenced.
fn _env_plain(name: Str, vars: &EnvVars, strict: Bool, out: &mut Vec[UInt8], seen: &mut Vec[Str]) -> Result[Int, Str] {
  _env_seen_add(seen, name);
  let idx = _env_lookup(vars, name);
  if idx >= 0 {
    let v: Str = _env_value(vars, idx);
    builder.sb_push_str(out, v);
    return _env_ok_step();
  }
  if strict {
    return _env_err_step("environment: undefined variable: " + name);
  }
  return _env_ok_step();
}

// `${NAME:-word}` (colon_form true) selects `word` when NAME is unset OR
// empty; `${NAME-word}` (colon_form false) selects it only when NAME is
// unset. A selected word is expanded recursively; otherwise the value is
// emitted verbatim.
fn _env_default(name: Str, text: Str, word_from: Int, close: Int, colon_form: Bool, vars: &EnvVars, strict: Bool, depth: Int, out: &mut Vec[UInt8], seen: &mut Vec[Str]) -> Result[Int, Str] {
  _env_seen_add(seen, name);
  let idx = _env_lookup(vars, name);
  var use_word = false;
  if idx < 0 {
    use_word = true;
  } elif colon_form {
    let v: Str = _env_value(vars, idx);
    if v.len() == 0 {
      use_word = true;
    }
  }
  if use_word {
    return _env_expand_range(text, word_from, close, vars, strict, depth + 1, false, out, seen);
  }
  let v2: Str = _env_value(vars, idx);
  builder.sb_push_str(out, v2);
  return _env_ok_step();
}

// `${NAME:+word}`: expand `word` when NAME is set AND non-empty; otherwise
// emit nothing. The value of NAME is never emitted.
fn _env_alt(name: Str, text: Str, word_from: Int, close: Int, vars: &EnvVars, strict: Bool, depth: Int, out: &mut Vec[UInt8], seen: &mut Vec[Str]) -> Result[Int, Str] {
  _env_seen_add(seen, name);
  let idx = _env_lookup(vars, name);
  if idx < 0 {
    return _env_ok_step();
  }
  let v: Str = _env_value(vars, idx);
  if v.len() == 0 {
    return _env_ok_step();
  }
  return _env_expand_range(text, word_from, close, vars, strict, depth + 1, false, out, seen);
}

// `${NAME:?message}`: emit the value when NAME is set and non-empty;
// otherwise fail with "environment: NAME: <message>" where <message> is the
// expanded operand (and "environment: NAME: unset or empty" when the operand
// expands to the empty string). An error raised while expanding the message
// propagates unchanged.
fn _env_require(name: Str, text: Str, word_from: Int, close: Int, vars: &EnvVars, strict: Bool, depth: Int, out: &mut Vec[UInt8], seen: &mut Vec[Str]) -> Result[Int, Str] {
  _env_seen_add(seen, name);
  let idx = _env_lookup(vars, name);
  if idx >= 0 {
    let v: Str = _env_value(vars, idx);
    if v.len() > 0 {
      builder.sb_push_str(out, v);
      return _env_ok_step();
    }
  }
  var msg_out = builder.sb_new();
  var msg_seen = Vec[Str].new();
  let mr = _env_expand_range(text, word_from, close, vars, strict, depth + 1, false, &mut msg_out, &mut msg_seen);
  match mr {
    Ok(_) => {},
    Err(m) => { return _env_err_step(m); },
  }
  let msg = builder.sb_to_str(&msg_out);
  if msg.len() == 0 {
    return _env_err_step("environment: " + name + ": unset or empty");
  }
  return _env_err_step("environment: " + name + ": " + msg);
}

// Dispatch one reference whose brace content is text[start, close): parse
// NAME, then the optional operator, and delegate. Errors are raised in the
// documented precedence order: invalid name, then unsupported operator.
fn _env_expand_ref(text: Str, start: Int, close: Int, vars: &EnvVars, strict: Bool, depth: Int, out: &mut Vec[UInt8], seen: &mut Vec[Str]) -> Result[Int, Str] {
  let name_end = _env_scan_name(text, start, close);
  if name_end == start {
    return _env_err_step("environment: invalid variable name");
  }
  let name = string.str_slice(text, start, name_end);
  if name_end == close {
    return _env_plain(name, vars, strict, out, seen);
  }
  let c1: UInt8 = string.byte_at(text, name_end);
  if c1 == _ENV_COLON {
    let op_end = name_end + 2;
    if op_end > close {
      return _env_err_step("environment: unsupported operator: " + string.str_slice(text, name_end, close));
    }
    let c2: UInt8 = string.byte_at(text, name_end + 1);
    if c2 == _ENV_DASH {
      return _env_default(name, text, op_end, close, true, vars, strict, depth, out, seen);
    } elif c2 == _ENV_PLUS {
      return _env_alt(name, text, op_end, close, vars, strict, depth, out, seen);
    } elif c2 == _ENV_QUESTION {
      return _env_require(name, text, op_end, close, vars, strict, depth, out, seen);
    }
    return _env_err_step("environment: unsupported operator: " + string.str_slice(text, name_end, op_end));
  }
  if c1 == _ENV_DASH {
    return _env_default(name, text, name_end + 1, close, false, vars, strict, depth, out, seen);
  }
  return _env_err_step("environment: unsupported operator: " + string.str_slice(text, name_end, name_end + 1));
}

// --------------------------------------------------
//  The expander
// --------------------------------------------------

// Expand text[from, to) into `out`, recording looked-up names in `seen`.
// Depth counts nested operand expansions: the entry point uses 0 and each
// selected operand adds one, up to _ENV_MAX_NEST. in_dquote marks a scan
// inside a double-quoted span; every branch consumes a byte, so it progresses.
fn _env_expand_range(text: Str, from: Int, to: Int, vars: &EnvVars, strict: Bool, depth: Int, in_dquote: Bool, out: &mut Vec[UInt8], seen: &mut Vec[Str]) -> Result[Int, Str] {
  if depth > _ENV_MAX_NEST {
    return _env_err_step("environment: nesting too deep");
  }
  var i = from;
  while i < to {
    let b: UInt8 = string.byte_at(text, i);
    if b == _ENV_DOLLAR && i + 1 < to && string.byte_at(text, i + 1) == _ENV_DOLLAR {
      out.push(_ENV_DOLLAR);
      i = i + 2;
    } elif b == _ENV_DOLLAR && i + 1 < to && string.byte_at(text, i + 1) == _ENV_LBRACE {
      let close = _env_find_close(text, i + 2, to);
      if close < 0 {
        return _env_err_step("environment: unterminated reference");
      }
      let r = _env_expand_ref(text, i + 2, close, vars, strict, depth, out, seen);
      match r {
        Ok(_) => {},
        Err(m) => { return _env_err_step(m); },
      }
      i = close + 1;
    } elif b == _ENV_SQUOTE && !in_dquote {
      let qend = _env_find_byte(text, i + 1, to, _ENV_SQUOTE);
      if qend < 0 {
        return _env_err_step("environment: unterminated single quote");
      }
      _env_push_range(out, text, i + 1, qend);
      i = qend + 1;
    } elif b == _ENV_DQUOTE && !in_dquote {
      let qend = _env_find_byte(text, i + 1, to, _ENV_DQUOTE);
      if qend < 0 {
        return _env_err_step("environment: unterminated double quote");
      }
      let r = _env_expand_range(text, i + 1, qend, vars, strict, depth, true, out, seen);
      match r {
        Ok(_) => {},
        Err(m) => { return _env_err_step(m); },
      }
      i = qend + 1;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return _env_ok_step();
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Expand every `${...}` reference in `src` from the caller-supplied table.
/// Params: src - the source text; vars - the index-aligned name/value table
/// (first matching name with a parallel value wins); strict - when true, a
/// plain `${NAME}` with an unset NAME is an error, when false it expands to
/// "".
/// Returns: Ok(Expansion) with the expanded text and the distinct referenced
/// names in first-lookup order. `$$` is one literal "$"; `'...'` is a literal
/// span; `"..."` is an expanding span; substituted values are copied verbatim
/// and never re-scanned.
/// Error case: Err("environment: ...") - see the error catalog in SPEC.md.
/// Complexity: O(output length + references * table length), with nested
/// operands expanded recursively up to the depth cap.
pub fn env_expand(src: Str, vars: &EnvVars, strict: Bool) -> Result[Expansion, Str] {
  var out = builder.sb_new();
  var seen = Vec[Str].new();
  let r = _env_expand_range(src, 0, src.len(), vars, strict, 0, false, &mut out, &mut seen);
  var failed = false;
  var err_msg = "";
  match r {
    Ok(_) => {},
    Err(m) => { failed = true; err_msg = m; },
  }
  if failed {
    return _env_err_exp(err_msg);
  }
  return _env_ok_exp(builder.sb_to_str(&out), seen);
}

/// Build an `EnvVars` table from "NAME=VALUE" entries: each entry is split at
/// its first "="; the key part is everything before it (stored verbatim) and
/// the value part everything after. An entry without "=" or with an empty key
/// part is skipped (malformed entries are ignored, never an error). Entries
/// keep their order, so a repeated name resolves to the first occurrence.
/// Params: pairs - the entries.
/// Returns: a fresh table (names and values pushed in mirror).
/// Error case: none.
/// Complexity: O(total entry bytes).
pub fn env_vars_from_pairs(pairs: &Vec[Str]) -> EnvVars {
  var vars = EnvVars{ names: Vec[Str].new(); values: Vec[Str].new() };
  var i = 0;
  while i < pairs.len() {
    let p: Str = pairs[i];
    let eq = _env_find_byte(p, 0, p.len(), _ENV_EQ);
    if eq > 0 {
      vars.names.push(string.str_slice(p, 0, eq));
      vars.values.push(string.str_slice(p, eq + 1, p.len()));
    }
    i = i + 1;
  }
  return vars;
}

/// Expand `src` from "NAME=VALUE" entries (env_vars_from_pairs then
/// env_expand). Params: src, pairs, strict as above.
/// Returns: Ok(Expansion) with the same semantics as env_expand.
/// Error case: same as env_expand.
/// Complexity: O(src + entry bytes + references * table length).
pub fn env_expand_pairs(src: Str, pairs: &Vec[Str], strict: Bool) -> Result[Expansion, Str] {
  let vars = env_vars_from_pairs(pairs);
  return env_expand(src, &vars, strict);
}
