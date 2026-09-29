// XIOM -- xiom.linter: line-oriented lint engine (rule registry, diagnostic
// bag, built-in source rules, key = value config, deterministic reports).
// Port task: replace the xiom.linter placeholder with a pure-XIOM module
// (no FFI, no file I/O: the input is a Str).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Layout model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - Rules live in parallel Vec fields (RuleRegistry: ids/severities/enabled);
//   Vec[StructType] is unsupported on the pinned compiler, so every list in
//   this module is a struct of mirrored Vecs (trap 10/16). A Diagnostic is a
//   value, but a DiagnosticBag stores many diagnostics in five mirrored Vec
//   fields (severities/rules/lines/cols/messages).
// - Rule ids are stable lowercase snake_case strings; severities are Ints:
//   0 = info, 1 = warning, 2 = error.
// - Lines and columns are 1-based byte positions (ASCII model; see SPEC.md).
// - The six built-in rules are line-oriented only: the engine never parses
//   the source, it classifies byte ranges. Rule application order in lint_run
//   is fixed: trailing_whitespace, tab_indent, line_length, todo_marker,
//   mixed_line_endings, missing_final_newline.
// - Str equality always goes through xiom.string.str_compare (trap 1: `==`
//   on Str values read from Vec[Str] elements compares pointers).
// - Ok/Err are constructed only in the leaf helpers _ok_*/_err_* (trap 6).
// - Every Vec element read is bound to a typed local (trap 2); byte compares
//   stay under 128 or go through the widened-and-masked `as Int` path
//   (trap 3).
// - Free functions only (no methods), explicit `&`/`&mut` at call sites, no
//   function named `log`, no `Vec[Float64]`.

module xiom.linter

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Severity codes used by rules, diagnostics and reports.
const _LINT_SEV_INFO: Int = 0;
const _LINT_SEV_WARNING: Int = 1;
const _LINT_SEV_ERROR: Int = 2;

// Built-in rule ids (registry keys).
const _LINT_RULE_TRAILING_WS: Str = "trailing_whitespace";
const _LINT_RULE_TAB_INDENT: Str = "tab_indent";
const _LINT_RULE_LINE_LENGTH: Str = "line_length";
const _LINT_RULE_TODO_MARKER: Str = "todo_marker";
const _LINT_RULE_MIXED_EOL: Str = "mixed_line_endings";
const _LINT_RULE_MISSING_FINAL: Str = "missing_final_newline";

// The meta rule id used by lint_run for configuration errors. It is not a
// source rule and is never part of the registry.
const _LINT_RULE_CONFIG: Str = "config";

// Config keys.
const _LINT_KEY_LINE_LENGTH: Str = "line_length_max";

// Default line length limit used when the config does not override it.
const _LINT_DEFAULT_LINE_LENGTH: Int = 80;

// Line terminator codes recorded per line by _split_source.
const _LINT_EOL_NONE: Int = 0;
const _LINT_EOL_LF: Int = 1;
const _LINT_EOL_CRLF: Int = 2;
const _LINT_EOL_CR: Int = 3;

// Byte constants.
const _LINT_TAB: UInt8 = 9u8;
const _LINT_LF: UInt8 = 10u8;
const _LINT_CR: UInt8 = 13u8;
const _LINT_SPACE: UInt8 = 32u8;
const _LINT_HASH: UInt8 = 35u8;
const _LINT_SEMI: UInt8 = 59u8;
const _LINT_EQ: Int = 61;

// ---------------------------------------------------------------------------
// Result constructors (see the module header: leaf helpers only)
// ---------------------------------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(r) for Result[RuleRegistry, Str].
fn _ok_registry(r: RuleRegistry) -> Result[RuleRegistry, Str] {
  return Ok(r);
}

// Err(m) for Result[RuleRegistry, Str].
fn _err_registry(m: Str) -> Result[RuleRegistry, Str] {
  return Err(m);
}

// Ok(c) for Result[LintConfig, Str].
fn _ok_config(c: LintConfig) -> Result[LintConfig, Str] {
  return Ok(c);
}

// Err(m) for Result[LintConfig, Str].
fn _err_config(m: Str) -> Result[LintConfig, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A registry of lint rules in parallel Vec fields: ids[i] has severity
/// severities[i] (0 = info, 1 = warning, 2 = error) and is enabled exactly
/// when enabled[i] == 1. Build one with linter_registry_new and add rules
/// with linter_register; the six built-in rules come from
/// linter_registry_default.
pub type RuleRegistry = {
  ids: Vec[Str];
  severities: Vec[Int];
  enabled: Vec[Int];
}

/// One diagnostic. severity is 0 = info, 1 = warning, 2 = error; rule is the
/// rule id; line and column are 1-based byte positions (0 means "not tied to
/// a source position", used by config errors); message is the human text.
pub type Diagnostic = {
  severity: Int;
  rule: Str;
  line: Int;
  column: Int;
  message: Str;
}

/// A collection of diagnostics in five parallel Vec fields, index-aligned:
/// severities[i], rules[i], lines[i], cols[i], messages[i]. Use the accessors
/// (linter_bag_get, linter_bag_line, ...) and the mutators (linter_bag_add,
/// linter_bag_merge, linter_bag_sort_by_line).
pub type DiagnosticBag = {
  severities: Vec[Int];
  rules: Vec[Str];
  lines: Vec[Int];
  cols: Vec[Int];
  messages: Vec[Str];
}

/// A parsed settings document: keys and values are index-aligned parallel Vec
/// fields. Duplicate keys keep their first position and the last value wins.
pub type LintConfig = {
  keys: Vec[Str];
  values: Vec[Str];
}

/// The internal line model produced by scanning a source Str: lines[i] is the
/// content of line i+1 without its terminator, and eols[i] is that line's
/// terminator code (0 = none, 1 = LF, 2 = CRLF, 3 = CR). A trailing LF/CR
/// does not produce an extra empty line; a final line without a terminator
/// still appears, with eol code 0.
pub type LintSource = {
  lines: Vec[Str];
  eols: Vec[Int];
}

// ---------------------------------------------------------------------------
// Small string/byte helpers
// ---------------------------------------------------------------------------

// Byte-exact Str equality via str_compare (trap 1).
fn _str_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

// True for the two bytes trimmed by _trim_ascii and recognized as trailing
// whitespace by the trailing_whitespace rule.
fn _is_space_or_tab(b: UInt8) -> Bool {
  return b == _LINT_SPACE || b == _LINT_TAB;
}

// Copy of s without leading/trailing ASCII spaces and tabs.
fn _trim_ascii(s: Str) -> Str {
  var start = 0;
  var end = s.len();
  while start < end {
    let b: UInt8 = string.byte_at(s, start);
    if !_is_space_or_tab(b) {
      break;
    }
    start = start + 1;
  }
  while end > start {
    let b: UInt8 = string.byte_at(s, end - 1);
    if !_is_space_or_tab(b) {
      break;
    }
    end = end - 1;
  }
  if start == 0 && end == s.len() {
    return s;
  }
  return string.str_slice(s, start, end);
}

// First index of byte `want` (an Int value 0..255) at or after `from`, or -1.
// The byte read is widened and masked (trap 3).
fn _find_byte(s: Str, want: Int, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == want {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when needle occurs in hay exactly at byte offset pos. Both bytes are
// widened and masked before comparing (trap 3).
fn _matches_at(hay: Str, pos: Int, needle: Str) -> Bool {
  let nl = needle.len();
  if pos + nl > hay.len() {
    return false;
  }
  var j = 0;
  while j < nl {
    let hb: Int = (string.byte_at(hay, pos + j) as Int) & 0xFF;
    let nb: Int = (string.byte_at(needle, j) as Int) & 0xFF;
    if hb != nb {
      return false;
    }
    j = j + 1;
  }
  return true;
}

// Parse an unsigned decimal string to an Int in 0..=1000000; -1 for an empty
// string, a non-digit byte, or a value above 1000000.
fn _parse_uint(s: Str) -> Int {
  let n = s.len();
  if n == 0 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 48 || b > 57 {
      return -1;
    }
    v = v * 10 + (b - 48);
    if v > 1000000 {
      return -1;
    }
    i = i + 1;
  }
  return v;
}

// Parse a config boolean: 1 for true/yes/1, 0 for false/no/0, -1 otherwise.
// The accepted spellings are lower-case and exact.
fn _parse_bool(v: Str) -> Int {
  if _str_eq(v, "true") {
    return 1;
  }
  if _str_eq(v, "yes") {
    return 1;
  }
  if _str_eq(v, "1") {
    return 1;
  }
  if _str_eq(v, "false") {
    return 0;
  }
  if _str_eq(v, "no") {
    return 0;
  }
  if _str_eq(v, "0") {
    return 0;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Rule registry
// ---------------------------------------------------------------------------

/// A fresh, empty rule registry.
pub fn linter_registry_new() -> RuleRegistry {
  return RuleRegistry{ ids: Vec[Str].new(); severities: Vec[Int].new(); enabled: Vec[Int].new(); };
}

// Append a rule without duplicate/validity checks (used by the built-in
// default registry; public callers go through linter_register).
fn _push_rule(reg: &mut RuleRegistry, id: Str, sev: Int, enabled: Bool) {
  reg.ids.push(id);
  reg.severities.push(sev);
  var flag = 0;
  if enabled {
    flag = 1;
  }
  reg.enabled.push(flag);
}

// Index of `id` in reg.ids, or -1 when absent. Str comparisons go through
// str_compare and every element read is typed (traps 1/2).
fn _rule_index(reg: &RuleRegistry, id: Str) -> Int {
  var i = 0;
  while i < reg.ids.len() {
    let k: Str = reg.ids[i];
    if _str_eq(k, id) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of a built-in rule id in linter_registry_default(), or -1. Used by
// config validation before a registry exists.
fn _builtin_rule_index(id: Str) -> Int {
  if _str_eq(id, _LINT_RULE_TRAILING_WS) {
    return 0;
  }
  if _str_eq(id, _LINT_RULE_TAB_INDENT) {
    return 1;
  }
  if _str_eq(id, _LINT_RULE_LINE_LENGTH) {
    return 2;
  }
  if _str_eq(id, _LINT_RULE_TODO_MARKER) {
    return 3;
  }
  if _str_eq(id, _LINT_RULE_MIXED_EOL) {
    return 4;
  }
  if _str_eq(id, _LINT_RULE_MISSING_FINAL) {
    return 5;
  }
  return -1;
}

/// The default registry: the six built-in rules, all enabled, with default
/// severities. Register order (and therefore index order):
/// 0 trailing_whitespace warning; 1 tab_indent warning; 2 line_length
/// warning; 3 todo_marker info; 4 mixed_line_endings warning;
/// 5 missing_final_newline warning.
pub fn linter_registry_default() -> RuleRegistry {
  var reg = linter_registry_new();
  _push_rule(&mut reg, _LINT_RULE_TRAILING_WS, _LINT_SEV_WARNING, true);
  _push_rule(&mut reg, _LINT_RULE_TAB_INDENT, _LINT_SEV_WARNING, true);
  _push_rule(&mut reg, _LINT_RULE_LINE_LENGTH, _LINT_SEV_WARNING, true);
  _push_rule(&mut reg, _LINT_RULE_TODO_MARKER, _LINT_SEV_INFO, true);
  _push_rule(&mut reg, _LINT_RULE_MIXED_EOL, _LINT_SEV_WARNING, true);
  _push_rule(&mut reg, _LINT_RULE_MISSING_FINAL, _LINT_SEV_WARNING, true);
  return reg;
}

/// Register a rule by id.
/// Params: reg - the registry to mutate; id - a non-empty rule id; severity -
/// 0 (info), 1 (warning) or 2 (error); enabled - the initial enabled flag.
/// Returns: Ok(index) with the new rule's index, or Err with
/// "linter: rule id must not be empty" (empty id),
/// "linter: severity must be 0, 1 or 2" (severity out of range), or
/// "linter: duplicate rule id: <id>" (id already registered).
/// Error case: see above; nothing is appended on error.
/// Complexity: O(rules * id length) for the duplicate scan.
pub fn linter_register(reg: &mut RuleRegistry, id: Str, severity: Int, enabled: Bool) -> Result[Int, Str] {
  if id.len() == 0 {
    return _err_int("linter: rule id must not be empty");
  }
  if severity < 0 || severity > 2 {
    return _err_int("linter: severity must be 0, 1 or 2");
  }
  if _rule_index(reg, id) >= 0 {
    return _err_int("linter: duplicate rule id: " + id);
  }
  _push_rule(reg, id, severity, enabled);
  return _ok_int(reg.ids.len() - 1);
}

/// Number of registered rules.
pub fn linter_rule_count(reg: &RuleRegistry) -> Int {
  return reg.ids.len();
}

/// Index of the rule with id `id`, or -1 when it is not registered.
/// Complexity: O(rules * id length).
pub fn linter_rule_index(reg: &RuleRegistry, id: Str) -> Int {
  return _rule_index(reg, id);
}

/// Rule id at index i; "" when i is out of range.
pub fn linter_rule_id(reg: &RuleRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.ids.len() {
    return "";
  }
  let id: Str = reg.ids[i];
  return id;
}

/// Severity of the rule at index i; -1 when i is out of range.
pub fn linter_rule_severity_at(reg: &RuleRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.severities.len() {
    return -1;
  }
  let s: Int = reg.severities[i];
  return s;
}

/// Enabled flag of the rule at index i; false when i is out of range.
pub fn linter_rule_enabled_at(reg: &RuleRegistry, i: Int) -> Bool {
  if i < 0 || i >= reg.enabled.len() {
    return false;
  }
  let e: Int = reg.enabled[i];
  return e != 0;
}

/// Severity of the rule with id `id`; -1 when the rule is not registered.
pub fn linter_rule_severity(reg: &RuleRegistry, id: Str) -> Int {
  let i = _rule_index(reg, id);
  if i < 0 {
    return -1;
  }
  let s: Int = reg.severities[i];
  return s;
}

/// True only when the rule with id `id` is registered and enabled.
pub fn linter_rule_enabled(reg: &RuleRegistry, id: Str) -> Bool {
  let i = _rule_index(reg, id);
  if i < 0 {
    return false;
  }
  let e: Int = reg.enabled[i];
  return e != 0;
}

/// Enable the rule with id `id`.
/// Returns: Ok(index) or Err("linter: unknown rule id: <id>").
/// Error case: unknown id; the registry is unchanged.
/// Complexity: O(rules * id length).
pub fn linter_enable(reg: &mut RuleRegistry, id: Str) -> Result[Int, Str] {
  let i = _rule_index(reg, id);
  if i < 0 {
    return _err_int("linter: unknown rule id: " + id);
  }
  reg.enabled[i] = 1;
  return _ok_int(i);
}

/// Disable the rule with id `id`.
/// Returns: Ok(index) or Err("linter: unknown rule id: <id>").
/// Error case: unknown id; the registry is unchanged.
/// Complexity: O(rules * id length).
pub fn linter_disable(reg: &mut RuleRegistry, id: Str) -> Result[Int, Str] {
  let i = _rule_index(reg, id);
  if i < 0 {
    return _err_int("linter: unknown rule id: " + id);
  }
  reg.enabled[i] = 0;
  return _ok_int(i);
}

// Severity of `id` in reg, or `fallback` when the id is not registered.
fn _sev_of(reg: &RuleRegistry, id: Str, fallback: Int) -> Int {
  let s = linter_rule_severity(reg, id);
  if s < 0 {
    return fallback;
  }
  return s;
}

// ---------------------------------------------------------------------------
// Diagnostic bag
// ---------------------------------------------------------------------------

/// A fresh, empty diagnostic bag.
pub fn linter_bag_new() -> DiagnosticBag {
  return DiagnosticBag{
    severities: Vec[Int].new();
    rules: Vec[Str].new();
    lines: Vec[Int].new();
    cols: Vec[Int].new();
    messages: Vec[Str].new();
  };
}

/// Append one diagnostic; all five parallel Vec fields are pushed together
/// (trap 16). No validation is performed: callers pass well-formed values.
/// Complexity: O(rule length + message length).
pub fn linter_bag_add(bag: &mut DiagnosticBag, severity: Int, rule: Str, line: Int, column: Int, message: Str) {
  bag.severities.push(severity);
  bag.rules.push(rule);
  bag.lines.push(line);
  bag.cols.push(column);
  bag.messages.push(message);
}

/// Number of diagnostics in the bag.
pub fn linter_bag_count(bag: &DiagnosticBag) -> Int {
  return bag.severities.len();
}

/// Severity of diagnostic i; -1 when out of range.
pub fn linter_bag_severity(bag: &DiagnosticBag, i: Int) -> Int {
  if i < 0 || i >= bag.severities.len() {
    return -1;
  }
  let s: Int = bag.severities[i];
  return s;
}

/// Rule id of diagnostic i; "" when out of range.
pub fn linter_bag_rule(bag: &DiagnosticBag, i: Int) -> Str {
  if i < 0 || i >= bag.rules.len() {
    return "";
  }
  let r: Str = bag.rules[i];
  return r;
}

/// Line of diagnostic i; 0 when out of range.
pub fn linter_bag_line(bag: &DiagnosticBag, i: Int) -> Int {
  if i < 0 || i >= bag.lines.len() {
    return 0;
  }
  let l: Int = bag.lines[i];
  return l;
}

/// Column of diagnostic i; 0 when out of range.
pub fn linter_bag_column(bag: &DiagnosticBag, i: Int) -> Int {
  if i < 0 || i >= bag.cols.len() {
    return 0;
  }
  let c: Int = bag.cols[i];
  return c;
}

/// Message of diagnostic i; "" when out of range.
pub fn linter_bag_message(bag: &DiagnosticBag, i: Int) -> Str {
  if i < 0 || i >= bag.messages.len() {
    return "";
  }
  let m: Str = bag.messages[i];
  return m;
}

/// Diagnostic i as a value; a zero diagnostic (severity info, empty rule and
/// message, line 0, column 0) when i is out of range.
pub fn linter_bag_get(bag: &DiagnosticBag, i: Int) -> Diagnostic {
  if i < 0 || i >= bag.severities.len() {
    return Diagnostic{ severity: _LINT_SEV_INFO; rule: ""; line: 0; column: 0; message: ""; };
  }
  let sev: Int = bag.severities[i];
  let rule: Str = bag.rules[i];
  let ln: Int = bag.lines[i];
  let col: Int = bag.cols[i];
  let msg: Str = bag.messages[i];
  return Diagnostic{ severity: sev; rule: rule; line: ln; column: col; message: msg; };
}

// Push diagnostic i of src into dst, mirroring all five fields (trap 16).
fn _bag_push_all(dst: &mut DiagnosticBag, src: &DiagnosticBag, i: Int) {
  let sev: Int = src.severities[i];
  let rule: Str = src.rules[i];
  let ln: Int = src.lines[i];
  let col: Int = src.cols[i];
  let msg: Str = src.messages[i];
  dst.severities.push(sev);
  dst.rules.push(rule);
  dst.lines.push(ln);
  dst.cols.push(col);
  dst.messages.push(msg);
}

/// A new bag with the diagnostics of `bag` whose severity is exactly
/// `severity`, in their original relative order. The input bag is unchanged.
/// Complexity: O(diagnostics).
pub fn linter_bag_filter_severity(bag: &DiagnosticBag, severity: Int) -> DiagnosticBag {
  var out = linter_bag_new();
  var i = 0;
  while i < bag.severities.len() {
    let sev: Int = bag.severities[i];
    if sev == severity {
      _bag_push_all(&mut out, bag, i);
    }
    i = i + 1;
  }
  return out;
}

/// Stable in-place sort of the bag by line only (equal lines keep their
/// insertion order); columns are not considered. Insertion sort: the bag has
/// at most a handful of diagnostics in practice.
/// Complexity: O(n^2) worst case, O(n) for already sorted input.
pub fn linter_bag_sort_by_line(bag: &mut DiagnosticBag) {
  var i = 1;
  while i < bag.lines.len() {
    let key_line: Int = bag.lines[i];
    let key_sev: Int = bag.severities[i];
    let key_rule: Str = bag.rules[i];
    let key_col: Int = bag.cols[i];
    let key_msg: Str = bag.messages[i];
    var j = i - 1;
    while j >= 0 {
      let jl: Int = bag.lines[j];
      if jl > key_line {
        let mv_sev: Int = bag.severities[j];
        let mv_rule: Str = bag.rules[j];
        let mv_col: Int = bag.cols[j];
        let mv_msg: Str = bag.messages[j];
        bag.lines[j + 1] = jl;
        bag.severities[j + 1] = mv_sev;
        bag.rules[j + 1] = mv_rule;
        bag.cols[j + 1] = mv_col;
        bag.messages[j + 1] = mv_msg;
        j = j - 1;
      } else {
        break;
      }
    }
    bag.lines[j + 1] = key_line;
    bag.severities[j + 1] = key_sev;
    bag.rules[j + 1] = key_rule;
    bag.cols[j + 1] = key_col;
    bag.messages[j + 1] = key_msg;
    i = i + 1;
  }
}

/// Append every diagnostic of `src` to `dst` in order; `src` is unchanged.
/// Complexity: O(src diagnostics).
pub fn linter_bag_merge(dst: &mut DiagnosticBag, src: &DiagnosticBag) {
  var i = 0;
  while i < src.severities.len() {
    _bag_push_all(dst, src, i);
    i = i + 1;
  }
}

/// The lowercase name of a severity code: "info" (0), "warning" (1), "error"
/// (2), "unknown" for any other value.
pub fn linter_severity_name(severity: Int) -> Str {
  if severity == _LINT_SEV_INFO {
    return "info";
  }
  if severity == _LINT_SEV_WARNING {
    return "warning";
  }
  if severity == _LINT_SEV_ERROR {
    return "error";
  }
  return "unknown";
}

// ---------------------------------------------------------------------------
// Source scanning
// ---------------------------------------------------------------------------

/// Split a source Str into the line model: LF, CRLF and a lone CR each
/// terminate a line; a final line without a terminator still appears (with
/// eol code 0) and a trailing terminator does not create an extra empty line.
/// An empty source yields an empty model.
/// Complexity: O(source length).
pub fn linter_scan(source: Str) -> LintSource {
  var lines = Vec[Str].new();
  var eols = Vec[Int].new();
  let n = source.len();
  var start = 0;
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(source, i);
    if b == _LINT_LF {
      lines.push(string.str_slice(source, start, i));
      eols.push(_LINT_EOL_LF);
      i = i + 1;
      start = i;
    } elif b == _LINT_CR {
      var crlf = false;
      if i + 1 < n {
        let nb: UInt8 = string.byte_at(source, i + 1);
        if nb == _LINT_LF {
          crlf = true;
        }
      }
      lines.push(string.str_slice(source, start, i));
      if crlf {
        eols.push(_LINT_EOL_CRLF);
        i = i + 2;
      } else {
        eols.push(_LINT_EOL_CR);
        i = i + 1;
      }
      start = i;
    } else {
      i = i + 1;
    }
  }
  if start < n {
    lines.push(string.str_slice(source, start, n));
    eols.push(_LINT_EOL_NONE);
  }
  return LintSource{ lines: lines; eols: eols; };
}

// Index of the first byte of the trailing run of spaces/tabs on `line`, or -1
// when the line does not end with space or tab. An all-whitespace line
// returns 0.
fn _first_trailing_ws(line: Str) -> Int {
  let n = line.len();
  if n == 0 {
    return -1;
  }
  let last: UInt8 = string.byte_at(line, n - 1);
  if !_is_space_or_tab(last) {
    return -1;
  }
  var j = n - 1;
  while j > 0 {
    let b: UInt8 = string.byte_at(line, j - 1);
    if !_is_space_or_tab(b) {
      break;
    }
    j = j - 1;
  }
  return j;
}

// Index of the first tab inside the leading run of spaces/tabs on `line`, or
// -1 when the leading run contains no tab. The leading run is every byte
// before the first byte that is neither space nor tab (for an all-whitespace
// line, the whole line).
fn _first_leading_tab(line: Str) -> Int {
  var i = 0;
  while i < line.len() {
    let b: UInt8 = string.byte_at(line, i);
    if b == _LINT_TAB {
      return i;
    }
    if b != _LINT_SPACE {
      return -1;
    }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Built-in rules (collectors)
// ---------------------------------------------------------------------------

// trailing_whitespace: one diagnostic per line whose last byte is space or
// tab, at the first byte of the trailing run.
fn _collect_trailing(src: &LintSource, sev: Int, bag: &mut DiagnosticBag) {
  var i = 0;
  while i < src.lines.len() {
    let line: Str = src.lines[i];
    let col = _first_trailing_ws(line);
    if col >= 0 {
      linter_bag_add(bag, sev, _LINT_RULE_TRAILING_WS, i + 1, col + 1, "trailing whitespace");
    }
    i = i + 1;
  }
}

// tab_indent: one diagnostic per line whose leading whitespace run contains a
// tab, at the first tab.
fn _collect_tab_indent(src: &LintSource, sev: Int, bag: &mut DiagnosticBag) {
  var i = 0;
  while i < src.lines.len() {
    let line: Str = src.lines[i];
    let col = _first_leading_tab(line);
    if col >= 0 {
      linter_bag_add(bag, sev, _LINT_RULE_TAB_INDENT, i + 1, col + 1, "tab indentation");
    }
    i = i + 1;
  }
}

// line_length: one diagnostic per line longer than `limit` bytes (excluding
// the terminator), at column limit + 1. limit < 1 disables the rule.
fn _collect_line_length(src: &LintSource, limit: Int, sev: Int, bag: &mut DiagnosticBag) {
  if limit < 1 {
    return;
  }
  var i = 0;
  while i < src.lines.len() {
    let line: Str = src.lines[i];
    let n = line.len();
    if n > limit {
      linter_bag_add(bag, sev, _LINT_RULE_LINE_LENGTH, i + 1, limit + 1, "line length " + convert.int_to_string(n) + " exceeds " + convert.int_to_string(limit));
    }
    i = i + 1;
  }
}

// todo_marker: one diagnostic per non-overlapping occurrence of the exact
// upper-case needles TODO (4 bytes) and FIXME (5 bytes), left to right; TODO
// wins when both could match at the same position.
fn _collect_todo(src: &LintSource, sev: Int, bag: &mut DiagnosticBag) {
  var i = 0;
  while i < src.lines.len() {
    let line: Str = src.lines[i];
    let n = line.len();
    var p = 0;
    while p < n {
      if _matches_at(line, p, "TODO") {
        linter_bag_add(bag, sev, _LINT_RULE_TODO_MARKER, i + 1, p + 1, "TODO marker");
        p = p + 4;
      } elif _matches_at(line, p, "FIXME") {
        linter_bag_add(bag, sev, _LINT_RULE_TODO_MARKER, i + 1, p + 1, "FIXME marker");
        p = p + 5;
      } else {
        p = p + 1;
      }
    }
    i = i + 1;
  }
}

// mixed_line_endings: when at least two distinct terminator codes occur among
// the actual terminators, one diagnostic at column 1 of the first line whose
// terminator differs from the first terminator in the file. A missing final
// terminator is not a terminator and never triggers this rule.
fn _collect_mixed(src: &LintSource, sev: Int, bag: &mut DiagnosticBag) {
  var baseline = _LINT_EOL_NONE;
  var i = 0;
  while i < src.eols.len() {
    let code: Int = src.eols[i];
    if code != _LINT_EOL_NONE {
      if baseline == _LINT_EOL_NONE {
        baseline = code;
      } elif code != baseline {
        linter_bag_add(bag, sev, _LINT_RULE_MIXED_EOL, i + 1, 1, "mixed line endings");
        return;
      }
    }
    i = i + 1;
  }
}

// missing_final_newline: when the source is non-empty and its final line has
// no terminator, one diagnostic at the last line, column last_len + 1.
fn _collect_missing_final(src: &LintSource, sev: Int, bag: &mut DiagnosticBag) {
  let n = src.lines.len();
  if n == 0 {
    return;
  }
  let code: Int = src.eols[n - 1];
  if code == _LINT_EOL_NONE {
    let last: Str = src.lines[n - 1];
    linter_bag_add(bag, sev, _LINT_RULE_MISSING_FINAL, n, last.len() + 1, "missing final newline");
  }
}

// ---------------------------------------------------------------------------
// Per-rule public entry points (default severities, no config)
// ---------------------------------------------------------------------------

/// Scan for trailing whitespace.
/// Params: source - the text to scan.
/// Returns: one diagnostic per line ending in space or tab, at the 1-based
/// byte column of the first trailing whitespace byte; severity warning.
/// An all-whitespace line is flagged at column 1.
/// Complexity: O(source length).
pub fn lint_trailing_whitespace(source: Str) -> DiagnosticBag {
  var bag = linter_bag_new();
  let src = linter_scan(source);
  _collect_trailing(&src, _LINT_SEV_WARNING, &mut bag);
  return bag;
}

/// Scan for tab indentation.
/// Params: source - the text to scan.
/// Returns: one diagnostic per line whose leading run of spaces/tabs contains
/// a tab, at the 1-based byte column of the first tab; severity warning.
/// Complexity: O(source length).
pub fn lint_tab_indent(source: Str) -> DiagnosticBag {
  var bag = linter_bag_new();
  let src = linter_scan(source);
  _collect_tab_indent(&src, _LINT_SEV_WARNING, &mut bag);
  return bag;
}

/// Scan for lines longer than `limit` bytes.
/// Params: source - the text to scan; limit - the maximum allowed line length
/// in bytes (limit < 1 disables the rule and returns an empty bag).
/// Returns: one diagnostic per over-long line at column limit + 1 with
/// message "line length <n> exceeds <limit>"; severity warning.
/// Complexity: O(source length).
pub fn lint_line_length(source: Str, limit: Int) -> DiagnosticBag {
  var bag = linter_bag_new();
  let src = linter_scan(source);
  _collect_line_length(&src, limit, _LINT_SEV_WARNING, &mut bag);
  return bag;
}

/// Scan for TODO/FIXME markers.
/// Params: source - the text to scan.
/// Returns: one diagnostic per non-overlapping exact upper-case occurrence of
/// "TODO" or "FIXME", at the marker's 1-based byte column, with message
/// "TODO marker" or "FIXME marker"; severity info.
/// Complexity: O(source length).
pub fn lint_todo_markers(source: Str) -> DiagnosticBag {
  var bag = linter_bag_new();
  let src = linter_scan(source);
  _collect_todo(&src, _LINT_SEV_INFO, &mut bag);
  return bag;
}

/// Scan for mixed line endings.
/// Params: source - the text to scan.
/// Returns: one diagnostic (at line N, column 1) where N is the first line
/// whose terminator kind differs from the file's first terminator; severity
/// warning. Files with zero or one terminator kind produce no diagnostics.
/// Complexity: O(source length).
pub fn lint_mixed_line_endings(source: Str) -> DiagnosticBag {
  var bag = linter_bag_new();
  let src = linter_scan(source);
  _collect_mixed(&src, _LINT_SEV_WARNING, &mut bag);
  return bag;
}

/// Scan for a missing final newline.
/// Params: source - the text to scan.
/// Returns: one diagnostic at the last line, column last_len + 1, when the
/// source is non-empty and does not end with LF or CR; severity warning.
/// An empty source is clean.
/// Complexity: O(source length).
pub fn lint_missing_final_newline(source: Str) -> DiagnosticBag {
  var bag = linter_bag_new();
  let src = linter_scan(source);
  _collect_missing_final(&src, _LINT_SEV_WARNING, &mut bag);
  return bag;
}

/// The default line length limit (80) used when the config does not set
/// line_length_max.
pub fn linter_default_line_length() -> Int {
  return _LINT_DEFAULT_LINE_LENGTH;
}

/// Version marker of this module; stable for the package's 0.1.0 line.
pub fn linter_version() -> Str {
  return "xiom.linter 0.1.0";
}

// ---------------------------------------------------------------------------
// Config: parsing and application
// ---------------------------------------------------------------------------

/// A fresh, empty config (no overrides).
pub fn linter_config_new() -> LintConfig {
  return LintConfig{ keys: Vec[Str].new(); values: Vec[Str].new(); };
}

// Index of `key` in cfg.keys, or -1; Str comparisons via str_compare.
fn _config_index(cfg: &LintConfig, key: Str) -> Int {
  var i = 0;
  while i < cfg.keys.len() {
    let k: Str = cfg.keys[i];
    if _str_eq(k, key) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Set `key` to `value`: an existing key keeps its position and gets the new
/// value (last assignment wins), a new key is appended.
/// Complexity: O(keys).
pub fn linter_config_set(cfg: &mut LintConfig, key: Str, value: Str) {
  let i = _config_index(cfg, key);
  if i >= 0 {
    cfg.values[i] = value;
    return;
  }
  cfg.keys.push(key);
  cfg.values.push(value);
}

/// Number of settings in the config.
pub fn linter_config_count(cfg: &LintConfig) -> Int {
  return cfg.keys.len();
}

/// Key at index i; "" when out of range.
pub fn linter_config_key(cfg: &LintConfig, i: Int) -> Str {
  if i < 0 || i >= cfg.keys.len() {
    return "";
  }
  let k: Str = cfg.keys[i];
  return k;
}

/// Value at index i; "" when out of range.
pub fn linter_config_value(cfg: &LintConfig, i: Int) -> Str {
  if i < 0 || i >= cfg.values.len() {
    return "";
  }
  let v: Str = cfg.values[i];
  return v;
}

/// Value of `key`; None when the key is absent.
pub fn linter_config_get(cfg: &LintConfig, key: Str) -> Option[Str] {
  let i = _config_index(cfg, key);
  if i < 0 {
    return None;
  }
  let v: Str = cfg.values[i];
  return Some(v);
}

// True when key has the shape rule.<id>.enabled with a non-empty id.
fn _is_rule_enabled_key(key: Str) -> Bool {
  if !string.str_starts_with(key, "rule.") {
    return false;
  }
  if !string.str_ends_with(key, ".enabled") {
    return false;
  }
  return key.len() >= 14;
}

// Extract <id> from rule.<id>.enabled (caller guarantees the shape).
fn _rule_id_from_key(key: Str) -> Str {
  return string.str_slice(key, 5, key.len() - 8);
}

/// Parse a settings document.
/// Grammar (exact; see SPEC.md):
///   line   = ws* ( "" / ( "#" / ";" ) bytes* / key ws* "=" ws* value ) ws*
///   key    = "line_length_max" / "rule." id ".enabled"
///   value  = for line_length_max: decimal digits, 1..1000000;
///            for rule.<id>.enabled: true/false/1/0/yes/no (lower-case).
/// Returns: Ok(config) with duplicate keys resolved last-wins-in-place, or
/// Err with a "linter: config line <n>: ..." message on a malformed line,
/// an empty key, an unknown key, or a bad value.
/// Error case: none of the checks escape; every failure is an Err.
/// Complexity: O(config length).
pub fn linter_config_parse(text: Str) -> Result[LintConfig, Str] {
  var cfg = linter_config_new();
  let src = linter_scan(text);
  var i = 0;
  while i < src.lines.len() {
    let raw: Str = src.lines[i];
    let line_no = i + 1;
    let t = _trim_ascii(raw);
    let tlen = t.len();
    if tlen == 0 {
      i = i + 1;
      continue;
    }
    let b0: UInt8 = string.byte_at(t, 0);
    if b0 == _LINT_HASH || b0 == _LINT_SEMI {
      i = i + 1;
      continue;
    }
    let eq = _find_byte(t, _LINT_EQ, 0);
    if eq < 0 {
      return _err_config("linter: config line " + convert.int_to_string(line_no) + ": expected key = value");
    }
    let key = _trim_ascii(string.str_slice(t, 0, eq));
    let value = _trim_ascii(string.str_slice(t, eq + 1, tlen));
    if key.len() == 0 {
      return _err_config("linter: config line " + convert.int_to_string(line_no) + ": empty key");
    }
    if _str_eq(key, _LINT_KEY_LINE_LENGTH) {
      if _parse_uint(value) < 1 {
        return _err_config("linter: config line " + convert.int_to_string(line_no) + ": line_length_max must be a positive integer: " + value);
      }
    } elif _is_rule_enabled_key(key) {
      if _parse_bool(value) < 0 {
        return _err_config("linter: config line " + convert.int_to_string(line_no) + ": enabled must be true, false, 1, 0, yes or no: " + value);
      }
    } else {
      return _err_config("linter: config line " + convert.int_to_string(line_no) + ": unknown key: " + key);
    }
    linter_config_set(&mut cfg, key, value);
    i = i + 1;
  }
  return _ok_config(cfg);
}

// First configuration error of a parsed/hand-built config, or "" when valid.
fn _config_error(cfg: &LintConfig) -> Str {
  var i = 0;
  while i < cfg.keys.len() {
    let key: Str = cfg.keys[i];
    let value: Str = cfg.values[i];
    if _str_eq(key, _LINT_KEY_LINE_LENGTH) {
      if _parse_uint(value) < 1 {
        return "linter: config: line_length_max must be a positive integer: " + value;
      }
    } elif _is_rule_enabled_key(key) {
      let id = _rule_id_from_key(key);
      if _builtin_rule_index(id) < 0 {
        return "linter: config: unknown rule id: " + id;
      }
      if _parse_bool(value) < 0 {
        return "linter: config: enabled must be true, false, 1, 0, yes or no: " + value;
      }
    } else {
      return "linter: config: unknown key: " + key;
    }
    i = i + 1;
  }
  return "";
}

/// Build the effective registry: linter_registry_default() with every
/// rule.<id>.enabled setting applied. line_length_max entries are accepted
/// and ignored here (they belong to linter_config_line_length).
/// Returns: Ok(registry), or Err with "linter: config: unknown rule id: <id>"
/// / "linter: config: unknown key: <key>" / a bad-value message.
/// Complexity: O(settings * rule count).
pub fn linter_registry_from_config(cfg: &LintConfig) -> Result[RuleRegistry, Str] {
  var reg = linter_registry_default();
  var i = 0;
  while i < cfg.keys.len() {
    let key: Str = cfg.keys[i];
    let value: Str = cfg.values[i];
    if _str_eq(key, _LINT_KEY_LINE_LENGTH) {
      if _parse_uint(value) < 1 {
        return _err_registry("linter: config: line_length_max must be a positive integer: " + value);
      }
    } elif _is_rule_enabled_key(key) {
      let id = _rule_id_from_key(key);
      let idx = _rule_index(&reg, id);
      if idx < 0 {
        return _err_registry("linter: config: unknown rule id: " + id);
      }
      let b = _parse_bool(value);
      if b < 0 {
        return _err_registry("linter: config: enabled must be true, false, 1, 0, yes or no: " + value);
      }
      reg.enabled[idx] = b;
    } else {
      return _err_registry("linter: config: unknown key: " + key);
    }
    i = i + 1;
  }
  return _ok_registry(reg);
}

/// The effective line length limit of a config: the parsed line_length_max
/// value when present and valid, otherwise the default (80). Use
/// linter_config_parse first when an invalid value must be an error.
pub fn linter_config_line_length(cfg: &LintConfig) -> Result[Int, Str] {
  let i = _config_index(cfg, _LINT_KEY_LINE_LENGTH);
  if i < 0 {
    return _ok_int(_LINT_DEFAULT_LINE_LENGTH);
  }
  let value: Str = cfg.values[i];
  let v = _parse_uint(value);
  if v < 1 {
    return _err_int("linter: config: line_length_max must be a positive integer: " + value);
  }
  return _ok_int(v);
}

// Effective limit without error reporting (the config was validated).
fn _effective_limit(cfg: &LintConfig) -> Int {
  let i = _config_index(cfg, _LINT_KEY_LINE_LENGTH);
  if i < 0 {
    return _LINT_DEFAULT_LINE_LENGTH;
  }
  let value: Str = cfg.values[i];
  let v = _parse_uint(value);
  if v < 1 {
    return _LINT_DEFAULT_LINE_LENGTH;
  }
  return v;
}

// ---------------------------------------------------------------------------
// lint_run
// ---------------------------------------------------------------------------

// Run every enabled rule of `reg` over `source`, appending to `bag`, in the
// documented fixed order.
fn _lint_with_registry(source: Str, reg: &RuleRegistry, limit: Int, bag: &mut DiagnosticBag) {
  let src = linter_scan(source);
  if linter_rule_enabled(reg, _LINT_RULE_TRAILING_WS) {
    _collect_trailing(&src, _sev_of(reg, _LINT_RULE_TRAILING_WS, _LINT_SEV_WARNING), bag);
  }
  if linter_rule_enabled(reg, _LINT_RULE_TAB_INDENT) {
    _collect_tab_indent(&src, _sev_of(reg, _LINT_RULE_TAB_INDENT, _LINT_SEV_WARNING), bag);
  }
  if linter_rule_enabled(reg, _LINT_RULE_LINE_LENGTH) {
    _collect_line_length(&src, limit, _sev_of(reg, _LINT_RULE_LINE_LENGTH, _LINT_SEV_WARNING), bag);
  }
  if linter_rule_enabled(reg, _LINT_RULE_TODO_MARKER) {
    _collect_todo(&src, _sev_of(reg, _LINT_RULE_TODO_MARKER, _LINT_SEV_INFO), bag);
  }
  if linter_rule_enabled(reg, _LINT_RULE_MIXED_EOL) {
    _collect_mixed(&src, _sev_of(reg, _LINT_RULE_MIXED_EOL, _LINT_SEV_WARNING), bag);
  }
  if linter_rule_enabled(reg, _LINT_RULE_MISSING_FINAL) {
    _collect_missing_final(&src, _sev_of(reg, _LINT_RULE_MISSING_FINAL, _LINT_SEV_WARNING), bag);
  }
}

// Build the effective registry from a validated config and run the rules.
fn _lint_all(source: Str, cfg: &LintConfig, bag: &mut DiagnosticBag) {
  let limit = _effective_limit(cfg);
  let regr = linter_registry_from_config(cfg);
  match regr {
    Ok(reg) => { _lint_with_registry(source, &reg, limit, bag); },
    Err(_) => { return; },
  }
}

/// Lint a source Str with a settings Str: the one-call convenience.
/// Params: source - the text to lint; config - the "key = value" settings
/// document ("" means defaults).
/// Returns: a DiagnosticBag. On success the bag holds the diagnostics of
/// every enabled rule in registry order. On any config parse or validation
/// error the bag holds exactly one diagnostic: severity error, rule id
/// "config", line 0, column 0, message the exact error text; the source is
/// not linted (fail closed).
/// Error case: none escapes; configuration failures become diagnostics.
/// Complexity: O(config length + source length).
pub fn lint_run(source: Str, config: Str) -> DiagnosticBag {
  var bag = linter_bag_new();
  let parsed = linter_config_parse(config);
  match parsed {
    Ok(cfg) => {
      let err = _config_error(&cfg);
      if err.len() > 0 {
        linter_bag_add(&mut bag, _LINT_SEV_ERROR, _LINT_RULE_CONFIG, 0, 0, err);
      } else {
        _lint_all(source, &cfg, &mut bag);
      }
    },
    Err(e) => {
      linter_bag_add(&mut bag, _LINT_SEV_ERROR, _LINT_RULE_CONFIG, 0, 0, e);
    },
  }
  return bag;
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

// CSV-quote one field: fields containing a comma, a double quote, LF or CR
// are wrapped in double quotes with inner quotes doubled. Other fields are
// returned unchanged.
fn _csv_field(s: Str) -> Str {
  let n = s.len();
  var need = false;
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if b == 44u8 || b == 34u8 || b == _LINT_LF || b == _LINT_CR {
      need = true;
    }
    i = i + 1;
  }
  if !need {
    return s;
  }
  var out = "\"";
  i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if b == 34u8 {
      out = out + "\"\"";
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out + "\"";
}

/// Render the human text report: one line per diagnostic in bag order,
/// exactly "<line>:<col>: <severity> <rule>: <message>", joined with LF and
/// with no trailing newline; an empty bag renders as "".
/// Example: "3:12: warning trailing_whitespace: trailing whitespace".
/// Complexity: O(total output length).
pub fn linter_report_text(bag: &DiagnosticBag) -> Str {
  var out = "";
  var i = 0;
  while i < bag.severities.len() {
    let sev: Int = bag.severities[i];
    let rule: Str = bag.rules[i];
    let ln: Int = bag.lines[i];
    let col: Int = bag.cols[i];
    let msg: Str = bag.messages[i];
    if i > 0 {
      out = out + "\n";
    }
    out = out + convert.int_to_string(ln) + ":" + convert.int_to_string(col) + ": " + linter_severity_name(sev) + " " + rule + ": " + msg;
    i = i + 1;
  }
  return out;
}

/// Render the machine-readable CSV-like report: one line per diagnostic in
/// bag order, exactly "<severity-number>,<rule>,<line>,<column>,<message>",
/// joined with LF and with no trailing newline; an empty bag renders as "".
/// A field containing a comma, a double quote, LF or CR is double-quoted and
/// inner quotes are doubled (RFC-4180 style); severity is never quoted.
/// Example: "1,trailing_whitespace,3,12,trailing whitespace".
/// Complexity: O(total output length).
pub fn linter_report_csv(bag: &DiagnosticBag) -> Str {
  var out = "";
  var i = 0;
  while i < bag.severities.len() {
    let sev: Int = bag.severities[i];
    let rule: Str = bag.rules[i];
    let ln: Int = bag.lines[i];
    let col: Int = bag.cols[i];
    let msg: Str = bag.messages[i];
    if i > 0 {
      out = out + "\n";
    }
    out = out + convert.int_to_string(sev) + "," + _csv_field(rule) + "," + convert.int_to_string(ln) + "," + convert.int_to_string(col) + "," + _csv_field(msg);
    i = i + 1;
  }
  return out;
}
