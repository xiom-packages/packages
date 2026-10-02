// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.salt: pure Salt remote-execution / configuration model
// Port task: promote the xiom.salt placeholder to a real, tested, pure-XIOM
// package: Salt-style state declarations (ids / state functions / names) with
// require / watch / onchanges ordering (and the `_in` inverses), pillar data
// with top-file targeting and layered merge precedence, minion targeting
// (glob, a documented regex-like subset, grain matches and compound
// expressions with and / or / not), typed grains with precedence and
// aggregation, and an event bus with tags, deterministic payload framing and
// glob-matched reactor rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: MODEL ONLY. There is no network, no socket, no shell-out, no FFI and
// no file I/O. A "run" is a pure function of the declared SLS, the declared
// grain facts and the host-supplied per-state outcome: the same inputs always
// produce the same execution order, the same report and the same event
// sequence. A host that actually executes states supplies each state's
// outcome (whether it failed and how many changes it reported) and uses the
// run report to drive real execution modules.
//
// Model (Vec[StructType] is unsupported in this compiler, so every collection
// is a set of index-aligned parallel vectors):
//   GrainSet   typed facts (str/int/bool) with a precedence level per row:
//              core (0) < config (1) < custom (2). Higher level wins; at
//              equal level the later write wins; a key keeps the position of
//              its first insertion.
//   Top        top-file rows: a target expression plus the SLS names it
//              applies to, in declaration order.
//   Pillar     pillar key/value rows with a precedence level (base < env <
//              override) and an origin (source) string per row.
//   SLS        state declarations (id / state function / name) plus
//              host-supplied outcomes (result, changes) and requisite rows
//              (require / watch / onchanges / *_in).
//   RunReport  execution counters (applied / noop / failed / skipped /
//              watches / onchanges / changes) plus the ordered event log.
//   EventBuf   published events: one tag per event plus index-aligned payload
//              key/value rows, framed as "<tag>|k=v;k=v".
//   Reactor    glob tag patterns plus one action string per rule, in rule
//              order.
//
// State execution model (deterministic, bounded; see SPEC.md section 7):
//   * Requisites are ordering edges. require / watch / onchanges make the
//     target run before the owner; require_in / watch_in / onchanges_in make
//     the owner run before the named target (the inverse view). Ties are
//     broken by declaration index (stable topological order), so the run
//     order is a pure function of the declarations.
//   * Each declaration executes at most once, in topological order. If any
//     incoming require / watch / onchanges target ended failed or skipped,
//     the declaration is skipped with a "requisite failed" event; a skipped
//     declaration is itself a failed prerequisite, so failure propagates.
//   * A declaration whose host result is "fail" is failed; otherwise it is
//     applied when its change count is > 0 and a noop when it is 0.
//   * watch / onchanges triggers fire when the watched source applied with
//     changes > 0. watch counts as a mod_watch call (watches), onchanges as a
//     plain re-run trigger (onchanges); ordering and failure semantics are
//     identical. Triggers never rebroadcast, so a cycle cannot recurse.
//   * total == applied + noop + failed + skipped always holds.
//
// v0.62.2 notes that shaped this module:
//   * Free functions only; every walk is index-based over parallel vectors.
//   * Ok/Err for Result[...] are constructed only in the leaf helpers
//     _bool_ok/_bool_err, _strs_ok/_strs_err, _ints_ok/_ints_err,
//     _runrep_ok/_runrep_err and _edge_ok/_edge_err (constructing Results
//     directly inside larger functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); every comparison is routed through _streq.
//   * Every byte read is widened and masked ((b as Int) & 0xFF) by the _byte
//     helper before any comparison (byte comparisons at >= 128 miscompile).
//   * Every Vec[Str]/Vec[Int] element read goes through a typed local first
//     (untyped element reads can mis-lower); no &mut scalar parameters are
//     used, all mutable state lives in structs (GrainSet, Pillar, SLS, _Tgt,
//     _Re, _Run, _Edge).

module xiom.salt

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result / Option leaf constructors (see the module header)
// --------------------------------------------------

// Ok(b) for Result[Bool, Str].
fn _bool_ok(b: Bool) -> Result[Bool, Str] {
  return Ok(b);
}

// Err(m) for Result[Bool, Str].
fn _bool_err(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _strs_ok(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _strs_err(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ints_ok(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _ints_err(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(r) for Result[RunReport, Str].
fn _runrep_ok(r: RunReport) -> Result[RunReport, Str] {
  return Ok(r);
}

// Err(m) for Result[RunReport, Str].
fn _runrep_err(m: Str) -> Result[RunReport, Str] {
  return Err(m);
}

// Ok(e) for Result[_Edge, Str].
fn _edge_ok(e: _Edge) -> Result[_Edge, Str] {
  return Ok(e);
}

// Err(m) for Result[_Edge, Str].
fn _edge_err(m: Str) -> Result[_Edge, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and byte-level helpers
// --------------------------------------------------

const _SALT_SPACE: Int = 32;
const _SALT_DOLLAR: Int = 36;
const _SALT_LPAREN: Int = 40;
const _SALT_RPAREN: Int = 41;
const _SALT_STAR: Int = 42;
const _SALT_PLUS: Int = 43;
const _SALT_DOT: Int = 46;
const _SALT_QUESTION: Int = 63;
const _SALT_LBRACKET: Int = 91;
const _SALT_BACKSLASH: Int = 92;
const _SALT_RBRACKET: Int = 93;
const _SALT_CARET: Int = 94;
const _SALT_COLON: Int = 58;

// Grain value type tags.
const _SALT_TYPE_STR: Int = 0;
const _SALT_TYPE_INT: Int = 1;
const _SALT_TYPE_BOOL: Int = 2;

// Host-supplied state result.
const _SALT_RES_OK: Int = 0;
const _SALT_RES_FAIL: Int = 1;

// Requisite kinds (the *_in kinds are normalized to kind - 3 when edges are
// built, so watch_in becomes a watch edge on the named target).
const _SALT_RQ_REQUIRE: Int = 0;
const _SALT_RQ_WATCH: Int = 1;
const _SALT_RQ_ONCHANGES: Int = 2;
const _SALT_RQ_REQUIRE_IN: Int = 3;
const _SALT_RQ_WATCH_IN: Int = 4;
const _SALT_RQ_ONCHANGES_IN: Int = 5;

// Execution state of one declaration.
const _SALT_ST_PENDING: Int = 0;
const _SALT_ST_APPLIED: Int = 1;
const _SALT_ST_NOOP: Int = 2;
const _SALT_ST_FAILED: Int = 3;
const _SALT_ST_SKIPPED: Int = 4;

// Bounds: total backtracking steps for one regex match (fail closed).
const _SALT_RE_MAX_STEPS: Int = 65536;

// Widen and mask one byte of `s`. byte_at returns UInt8 and comparisons on
// bytes >= 128 miscompile unless widened to Int and masked first, so every
// byte read in this module goes through here.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Byte-exact Str equality through str_compare (BUG 17: `==` on Str values
// read from Vec[Str] elements lowers to a pointer comparison).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `s` is a valid declaration id or state function: non-empty, no
// byte <= space, no '[' and no ']'.
fn _ident_ok(s: Str) -> Bool {
  if s.len() == 0 {
    return false;
  }
  var i = 0;
  while i < s.len() {
    let c = _byte(s, i);
    if c <= _SALT_SPACE {
      return false;
    }
    if c == _SALT_LBRACKET || c == _SALT_RBRACKET {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Grains: typed facts with precedence
// --------------------------------------------------

/// A set of typed grain facts. `types[i]` is 0 str, 1 int, 2 bool and
/// `levels[i]` is 0 core, 1 config, 2 custom for `keys[i]`/`values[i]`.
/// Build one with salt_grains_set_str / salt_grains_set_int /
/// salt_grains_set_bool; merge with salt_grains_merge.
pub type GrainSet = {
  keys: Vec[Str];
  values: Vec[Str];   // canonical text of the fact ("4", "true", "Ubuntu")
  types: Vec[Int];    // _SALT_TYPE_*
  levels: Vec[Int];   // 0 core, 1 config, 2 custom
}

/// An empty grain set.
pub fn salt_grains_new() -> GrainSet {
  return GrainSet{ keys: Vec[Str].new(); values: Vec[Str].new(); types: Vec[Int].new(); levels: Vec[Int].new(); };
}

// Precedence level of a level name ("core" 0, "config" 1, "custom" 2), or -1.
fn _grain_level_of(l: Str) -> Int {
  if _streq(l, "core") {
    return 0;
  }
  if _streq(l, "config") {
    return 1;
  }
  if _streq(l, "custom") {
    return 2;
  }
  return -1;
}

// Level name of a level number.
fn _grain_level_name(lv: Int) -> Str {
  if lv == 0 {
    return "core";
  }
  if lv == 1 {
    return "config";
  }
  return "custom";
}

// Type name of a type tag.
fn _grain_type_name(t: Int) -> Str {
  if t == _SALT_TYPE_STR {
    return "str";
  }
  if t == _SALT_TYPE_INT {
    return "int";
  }
  return "bool";
}

// Assign a fact: a new key is appended (position = first insertion); an
// existing key is replaced when level >= its current level (equal level =
// later wins) and left alone otherwise.
fn _grain_put(gs: &mut GrainSet, key: Str, value: Str, typ: Int, level: Int) {
  var i = 0;
  while i < gs.keys.len() {
    let k: Str = gs.keys[i];
    if _streq(k, key) {
      let cur: Int = gs.levels[i];
      if level >= cur {
        gs.values[i] = value;
        gs.types[i] = typ;
        gs.levels[i] = level;
      }
      return;
    }
    i = i + 1;
  }
  gs.keys.push(key);
  gs.values.push(value);
  gs.types.push(typ);
  gs.levels.push(level);
}

// Index of fact `key` in `gs`, or -1 (first match).
fn _grain_index(gs: &GrainSet, key: Str) -> Int {
  var i = 0;
  while i < gs.keys.len() {
    let k: Str = gs.keys[i];
    if _streq(k, key) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Set a string fact at the named level ("core", "config" or "custom").
/// Returns false for an unknown level (nothing is stored).
pub fn salt_grains_set_str(gs: &mut GrainSet, key: Str, value: Str, level: Str) -> Bool {
  let lv = _grain_level_of(level);
  if lv < 0 {
    return false;
  }
  _grain_put(gs, key, value, _SALT_TYPE_STR, lv);
  return true;
}

/// Set an integer fact at the named level; it is stored as canonical text.
/// Returns false for an unknown level (nothing is stored).
pub fn salt_grains_set_int(gs: &mut GrainSet, key: Str, value: Int, level: Str) -> Bool {
  let lv = _grain_level_of(level);
  if lv < 0 {
    return false;
  }
  _grain_put(gs, key, convert.int_to_string(value), _SALT_TYPE_INT, lv);
  return true;
}

/// Set a boolean fact at the named level; it is stored as "true"/"false".
/// Returns false for an unknown level (nothing is stored).
pub fn salt_grains_set_bool(gs: &mut GrainSet, key: Str, value: Bool, level: Str) -> Bool {
  let lv = _grain_level_of(level);
  if lv < 0 {
    return false;
  }
  _grain_put(gs, key, convert.bool_to_string(value), _SALT_TYPE_BOOL, lv);
  return true;
}

/// Type tag of a fact (0 str, 1 int, 2 bool), or -1 when absent.
pub fn salt_grains_type(gs: &GrainSet, key: Str) -> Int {
  let i = _grain_index(gs, key);
  if i < 0 {
    return -1;
  }
  let t: Int = gs.types[i];
  return t;
}

/// Precedence level of a fact (0 core, 1 config, 2 custom), or -1.
pub fn salt_grains_level(gs: &GrainSet, key: Str) -> Int {
  let i = _grain_index(gs, key);
  if i < 0 {
    return -1;
  }
  let lv: Int = gs.levels[i];
  return lv;
}

/// String value of a str-typed fact; None when absent or another type.
pub fn salt_grains_get_str(gs: &GrainSet, key: Str) -> Option[Str] {
  let i = _grain_index(gs, key);
  if i < 0 {
    return None;
  }
  let t: Int = gs.types[i];
  if t != _SALT_TYPE_STR {
    return None;
  }
  let v: Str = gs.values[i];
  return Some(v);
}

/// Integer value of an int-typed fact; None when absent or another type.
pub fn salt_grains_get_int(gs: &GrainSet, key: Str) -> Option[Int] {
  let i = _grain_index(gs, key);
  if i < 0 {
    return None;
  }
  let t: Int = gs.types[i];
  if t != _SALT_TYPE_INT {
    return None;
  }
  let v: Str = gs.values[i];
  let r = string.str_to_int(v);
  match r {
    Ok(n) => { let out: Int = n; return Some(out); },
    Err(_) => { return None; },
  }
  return None;
}

/// Boolean value of a bool-typed fact; None when absent or another type.
pub fn salt_grains_get_bool(gs: &GrainSet, key: Str) -> Option[Bool] {
  let i = _grain_index(gs, key);
  if i < 0 {
    return None;
  }
  let t: Int = gs.types[i];
  if t != _SALT_TYPE_BOOL {
    return None;
  }
  let v: Str = gs.values[i];
  if _streq(v, "true") {
    return Some(true);
  }
  if _streq(v, "false") {
    return Some(false);
  }
  return None;
}

/// Merge `overlay` into `base` with the documented precedence rule; neither
/// input is modified. Applying salt_grains_merge once per source, in
/// precedence order, resolves a grain chain.
pub fn salt_grains_merge(base: &GrainSet, overlay: &GrainSet) -> GrainSet {
  var out = salt_grains_new();
  var i = 0;
  while i < base.keys.len() {
    let k: Str = base.keys[i];
    let v: Str = base.values[i];
    let t: Int = base.types[i];
    let lv: Int = base.levels[i];
    _grain_put(&mut out, k, v, t, lv);
    i = i + 1;
  }
  var j = 0;
  while j < overlay.keys.len() {
    let k2: Str = overlay.keys[j];
    let v2: Str = overlay.values[j];
    let t2: Int = overlay.types[j];
    let lv2: Int = overlay.levels[j];
    _grain_put(&mut out, k2, v2, t2, lv2);
    j = j + 1;
  }
  return out;
}

/// Number of facts with type tag `typ` (aggregation by type).
pub fn salt_grains_agg(gs: &GrainSet, typ: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < gs.types.len() {
    let t: Int = gs.types[i];
    if t == typ {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Canonical render: one counter header line then one
/// "key=value type=.. level=.." line per fact, insertion order, LF separated
/// with no trailing LF.
pub fn salt_grains_render(gs: &GrainSet) -> Str {
  var out = "grains: count=" + convert.int_to_string(gs.keys.len());
  out = out + " str=" + convert.int_to_string(salt_grains_agg(gs, _SALT_TYPE_STR));
  out = out + " int=" + convert.int_to_string(salt_grains_agg(gs, _SALT_TYPE_INT));
  out = out + " bool=" + convert.int_to_string(salt_grains_agg(gs, _SALT_TYPE_BOOL));
  var i = 0;
  while i < gs.keys.len() {
    let k: Str = gs.keys[i];
    let v: Str = gs.values[i];
    let t: Int = gs.types[i];
    let lv: Int = gs.levels[i];
    out = out + "\n" + k + "=" + v + " type=" + _grain_type_name(t) + " level=" + _grain_level_name(lv);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Targeting: glob
// --------------------------------------------------

/// Glob match over bytes: '*' matches any run (including empty), '?' matches
/// exactly one byte, every other byte is literal and case-sensitive.
/// Backtracking is bounded by the standard two-pointer algorithm (no
/// recursion), so it always terminates.
pub fn salt_glob_match(pat: Str, text: Str) -> Bool {
  var p = 0;
  var t = 0;
  var star_p = -1;
  var star_t = 0;
  while t < text.len() {
    var matched = false;
    if p < pat.len() {
      let pc = _byte(pat, p);
      if pc == _SALT_QUESTION {
        matched = true;
      } else {
        if pc == _byte(text, t) {
          matched = true;
        }
      }
    }
    if matched {
      p = p + 1;
      t = t + 1;
    } else {
      var star_here = false;
      if p < pat.len() {
        if _byte(pat, p) == _SALT_STAR {
          star_here = true;
        }
      }
      if star_here {
        star_p = p;
        star_t = t;
        p = p + 1;
      } else {
        if star_p >= 0 {
          star_t = star_t + 1;
          t = star_t;
          p = star_p + 1;
        } else {
          return false;
        }
      }
    }
  }
  while p < pat.len() {
    if _byte(pat, p) != _SALT_STAR {
      return false;
    }
    p = p + 1;
  }
  return true;
}

// --------------------------------------------------
//  Targeting: regex-like subset
// --------------------------------------------------

// Mutable regex backtracking state (module-internal; no &mut scalar params).
type _Re = {
  steps: Int;
}

// Length in pattern bytes of the atom starting at pi: 2 for an escape pair
// "\x", else 1. A trailing '\' is a literal backslash (length 1).
fn _re_atom_len(pat: Str, pi: Int) -> Int {
  if _byte(pat, pi) == _SALT_BACKSLASH && pi + 1 < pat.len() {
    return 2;
  }
  return 1;
}

// True when the atom at pi is the unescaped "any byte" dot.
fn _re_atom_is_any(pat: Str, pi: Int) -> Bool {
  if _byte(pat, pi) == _SALT_BACKSLASH {
    return false;
  }
  return _byte(pat, pi) == _SALT_DOT;
}

// Literal byte of the atom at pi (the escaped byte for "\x").
fn _re_atom_byte(pat: Str, pi: Int) -> Int {
  if _byte(pat, pi) == _SALT_BACKSLASH && pi + 1 < pat.len() {
    return _byte(pat, pi + 1);
  }
  return _byte(pat, pi);
}

// True when the atom at pi matches text[ti].
fn _re_atom_matches(pat: Str, pi: Int, text: Str, ti: Int) -> Bool {
  if ti >= text.len() {
    return false;
  }
  if _re_atom_is_any(pat, pi) {
    return true;
  }
  let ab = _re_atom_byte(pat, pi);
  let tb = _byte(text, ti);
  return ab == tb;
}

// Quantifier kind at pattern position qi: 0 '*' (zero+), 1 '+' (one+),
// 2 '?' (zero or one), -1 none.
fn _re_quant_at(pat: Str, qi: Int) -> Int {
  if qi >= pat.len() {
    return -1;
  }
  let c = _byte(pat, qi);
  if c == _SALT_STAR {
    return 0;
  }
  if c == _SALT_PLUS {
    return 1;
  }
  if c == _SALT_QUESTION {
    return 2;
  }
  return -1;
}

// True when pattern[pi..] matches text[ti..] from ti onward (the match may
// leave text bytes unconsumed; a trailing unescaped '$' forces the end).
fn _re_here(pat: Str, pi: Int, text: Str, ti: Int, st: &mut _Re) -> Bool {
  st.steps = st.steps + 1;
  if st.steps > _SALT_RE_MAX_STEPS {
    return false;
  }
  if pi >= pat.len() {
    return true;
  }
  let c = _byte(pat, pi);
  if c == _SALT_DOLLAR && pi == pat.len() - 1 {
    return ti == text.len();
  }
  let alen = _re_atom_len(pat, pi);
  let qi = pi + alen;
  let q = _re_quant_at(pat, qi);
  if q == 0 {
    var k = ti;
    while k < text.len() && _re_atom_matches(pat, pi, text, k) {
      k = k + 1;
    }
    var m = k;
    while m >= ti {
      if _re_here(pat, qi + 1, text, m, st) {
        return true;
      }
      m = m - 1;
    }
    return false;
  }
  if q == 1 {
    var k2 = ti;
    while k2 < text.len() && _re_atom_matches(pat, pi, text, k2) {
      k2 = k2 + 1;
    }
    var m2 = k2;
    while m2 >= ti + 1 {
      if _re_here(pat, qi + 1, text, m2, st) {
        return true;
      }
      m2 = m2 - 1;
    }
    return false;
  }
  if q == 2 {
    if _re_atom_matches(pat, pi, text, ti) {
      if _re_here(pat, qi + 1, text, ti + 1, st) {
        return true;
      }
    }
    return _re_here(pat, qi + 1, text, ti, st);
  }
  if _re_atom_matches(pat, pi, text, ti) {
    return _re_here(pat, qi, text, ti + 1, st);
  }
  return false;
}

/// Regex-like match over bytes, a documented subset of PCRE:
///   ^  start anchor (only when the first pattern byte), $ end anchor (only
///      when the last pattern byte)
///   .  any one byte
///   * + ?  quantifiers on the preceding atom (literal, escaped literal or
///      dot), greedy with backtracking
///   \x  literal byte x (so \. \* \+ \? \^ \$ \\ are literals)
/// Everything else is a literal byte; classes, groups and alternation are not
/// supported. Without '^' the pattern matches any substring (search); with
/// '^' the match must start at byte 0. A trailing '$' forces the match to end
/// at the text end. The empty pattern matches every text. Backtracking fails
/// closed after 65536 steps.
pub fn salt_regex_match(pat: Str, text: Str) -> Bool {
  var st = _Re{ steps: 0 };
  var p0 = 0;
  if pat.len() > 0 {
    if _byte(pat, 0) == _SALT_CARET {
      p0 = 1;
    }
  }
  if p0 > 0 {
    return _re_here(pat, p0, text, 0, &mut st);
  }
  var t = 0;
  while t <= text.len() {
    if _re_here(pat, p0, text, t, &mut st) {
      return true;
    }
    t = t + 1;
  }
  return false;
}

// --------------------------------------------------
//  Targeting: grain matches and compound expressions
// --------------------------------------------------

// Index of the first ':' in `expr`, or -1. Returns the string index.
fn _colon_index(expr: Str) -> Int {
  let ix = string.index_of(expr, ":");
  match ix {
    Some(v) => { let out: Int = v; return out; },
    None => { return -1; },
  }
  return -1;
}

/// Grain match: `key:pattern` where the grain value is compared with
/// salt_glob_match. False when the key is absent, the key is empty or the
/// expression has no ':'. Int and bool facts compare their canonical text
/// ("4", "true").
pub fn salt_grain_match(gs: &GrainSet, expr: Str) -> Bool {
  let ci = _colon_index(expr);
  if ci <= 0 {
    return false;
  }
  let key = string.str_slice(expr, 0, ci);
  let pat = string.str_slice(expr, ci + 1, expr.len());
  let gi = _grain_index(gs, key);
  if gi < 0 {
    return false;
  }
  let value: Str = gs.values[gi];
  return salt_glob_match(pat, value);
}

/// Grain match with the regex subset instead of a glob: `key:pattern` where
/// the value is compared with salt_regex_match. Same absence rules as
/// salt_grain_match.
pub fn salt_grain_match_regex(gs: &GrainSet, expr: Str) -> Bool {
  let ci = _colon_index(expr);
  if ci <= 0 {
    return false;
  }
  let key = string.str_slice(expr, 0, ci);
  let pat = string.str_slice(expr, ci + 1, expr.len());
  let gi = _grain_index(gs, key);
  if gi < 0 {
    return false;
  }
  let value: Str = gs.values[gi];
  return salt_regex_match(pat, value);
}

// Compound-expression token stream (module-internal).
type _Tgt = {
  toks: Vec[Str];
  pos: Int;
}

// Tokenize a compound expression: '(' and ')' are single tokens, whitespace
// separates tokens, everything else runs until whitespace or a paren.
fn _tgt_tokenize(expr: Str, out: &mut Vec[Str]) {
  var i = 0;
  while i < expr.len() {
    let c = _byte(expr, i);
    if c <= _SALT_SPACE {
      i = i + 1;
    } else {
      if c == _SALT_LPAREN {
        out.push("(");
        i = i + 1;
      } else {
        if c == _SALT_RPAREN {
          out.push(")");
          i = i + 1;
        } else {
          var j = i;
          var go = true;
          while go && j < expr.len() {
            let cj = _byte(expr, j);
            if cj <= _SALT_SPACE || cj == _SALT_LPAREN || cj == _SALT_RPAREN {
              go = false;
            } else {
              j = j + 1;
            }
          }
          let tok = string.str_slice(expr, i, j);
          out.push(tok);
          i = j;
        }
      }
    }
  }
}

// Parse one term: bare glob, G@glob, E@regex, I@key:glob, P@key:regex.
fn _p_term(t: &mut _Tgt, minion_id: Str, gs: &GrainSet) -> Result[Bool, Str] {
  if t.pos >= t.toks.len() {
    return _bool_err("salt: targeting: unexpected end of expression");
  }
  let tok: Str = t.toks[t.pos];
  t.pos = t.pos + 1;
  if _streq(tok, ")") {
    return _bool_err("salt: targeting: unexpected token: )");
  }
  if _streq(tok, "and") || _streq(tok, "or") || _streq(tok, "not") {
    return _bool_err("salt: targeting: unexpected token: " + tok);
  }
  if string.str_starts_with(tok, "G@") {
    let pat = string.str_slice(tok, 2, tok.len());
    return _bool_ok(salt_glob_match(pat, minion_id));
  }
  if string.str_starts_with(tok, "E@") {
    let pat = string.str_slice(tok, 2, tok.len());
    return _bool_ok(salt_regex_match(pat, minion_id));
  }
  if string.str_starts_with(tok, "I@") {
    let rest = string.str_slice(tok, 2, tok.len());
    if _colon_index(rest) <= 0 {
      return _bool_err("salt: targeting: malformed grain term: " + tok);
    }
    return _bool_ok(salt_grain_match(gs, rest));
  }
  if string.str_starts_with(tok, "P@") {
    let rest = string.str_slice(tok, 2, tok.len());
    if _colon_index(rest) <= 0 {
      return _bool_err("salt: targeting: malformed grain term: " + tok);
    }
    return _bool_ok(salt_grain_match_regex(gs, rest));
  }
  return _bool_ok(salt_glob_match(tok, minion_id));
}

// Parse "(" expr ")" or a term.
fn _p_primary(t: &mut _Tgt, minion_id: Str, gs: &GrainSet) -> Result[Bool, Str] {
  if t.pos >= t.toks.len() {
    return _bool_err("salt: targeting: unexpected end of expression");
  }
  let tok: Str = t.toks[t.pos];
  if _streq(tok, "(") {
    t.pos = t.pos + 1;
    let inner = _p_or(t, minion_id, gs);
    match inner {
      Ok(v) => {
        if t.pos >= t.toks.len() {
          return _bool_err("salt: targeting: expected ')'");
        }
        let close: Str = t.toks[t.pos];
        if !_streq(close, ")") {
          return _bool_err("salt: targeting: expected ')'");
        }
        t.pos = t.pos + 1;
        return _bool_ok(v);
      },
      Err(e) => { return _bool_err(e); },
    }
  }
  return _p_term(t, minion_id, gs);
}

// Parse "not" not-expr | primary.
fn _p_not(t: &mut _Tgt, minion_id: Str, gs: &GrainSet) -> Result[Bool, Str] {
  if t.pos < t.toks.len() {
    let tok: Str = t.toks[t.pos];
    if _streq(tok, "not") {
      t.pos = t.pos + 1;
      let r = _p_not(t, minion_id, gs);
      match r {
        Ok(v) => { return _bool_ok(!v); },
        Err(e) => { return _bool_err(e); },
      }
    }
  }
  return _p_primary(t, minion_id, gs);
}

// Parse and-expr. The full expression is always parsed, so a malformed tail
// is an error even when the head already decides the value.
fn _p_and(t: &mut _Tgt, minion_id: Str, gs: &GrainSet) -> Result[Bool, Str] {
  let first = _p_not(t, minion_id, gs);
  var acc = false;
  match first {
    Ok(v) => { acc = v; },
    Err(e) => { return _bool_err(e); },
  }
  var go = true;
  while go && t.pos < t.toks.len() {
    let tok: Str = t.toks[t.pos];
    if _streq(tok, "and") {
      t.pos = t.pos + 1;
      let r = _p_not(t, minion_id, gs);
      match r {
        Ok(v2) => { acc = acc && v2; },
        Err(e2) => { return _bool_err(e2); },
      }
    } else {
      go = false;
    }
  }
  return _bool_ok(acc);
}

// Parse or-expr (lowest precedence: not > and > or).
fn _p_or(t: &mut _Tgt, minion_id: Str, gs: &GrainSet) -> Result[Bool, Str] {
  let first = _p_and(t, minion_id, gs);
  var acc = false;
  match first {
    Ok(v) => { acc = v; },
    Err(e) => { return _bool_err(e); },
  }
  var go = true;
  while go && t.pos < t.toks.len() {
    let tok: Str = t.toks[t.pos];
    if _streq(tok, "or") {
      t.pos = t.pos + 1;
      let r = _p_and(t, minion_id, gs);
      match r {
        Ok(v2) => { acc = acc || v2; },
        Err(e2) => { return _bool_err(e2); },
      }
    } else {
      go = false;
    }
  }
  return _bool_ok(acc);
}

/// Evaluate a compound minion-targeting expression against a minion id and
/// its grains. Grammar:
///   expr    = and ( "or"  and )*
///   and     = not ( "and" not )*
///   not     = "not" not | primary
///   primary = "(" expr ")" | term
///   term    = "G@" glob | "E@" regex | "I@" key:glob | "P@" key:regex
///           | bare-glob
/// Precedence is not > and > or. Err messages:
/// "salt: targeting: unexpected end of expression",
/// "salt: targeting: expected ')'",
/// "salt: targeting: unexpected token: <token>" and
/// "salt: targeting: malformed grain term: <term>".
pub fn salt_target_match(minion_id: Str, gs: &GrainSet, expr: Str) -> Result[Bool, Str] {
  var toks = Vec[Str].new();
  _tgt_tokenize(expr, &mut toks);
  var t = _Tgt{ toks: toks; pos: 0 };
  let r = _p_or(&mut t, minion_id, gs);
  match r {
    Ok(v) => {
      if t.pos != t.toks.len() {
        let extra: Str = t.toks[t.pos];
        return _bool_err("salt: targeting: unexpected token: " + extra);
      }
      return _bool_ok(v);
    },
    Err(e) => { return _bool_err(e); },
  }
  return _bool_err("salt: targeting: unreachable");
}

// --------------------------------------------------
//  Pillar: top-file targeting and layered merge
// --------------------------------------------------

/// A top file: target-expression rows plus the SLS name each row applies to,
/// in declaration order.
pub type Top = {
  t_target: Vec[Str];   // compound target expression
  t_sls: Vec[Str];      // SLS name applied when the expression matches
}

/// An empty top file.
pub fn salt_top_new() -> Top {
  return Top{ t_target: Vec[Str].new(); t_sls: Vec[Str].new(); };
}

/// Append a top-file row: when `target_expr` matches a minion, `sls` applies.
pub fn salt_top_add(top: &mut Top, target_expr: Str, sls: Str) {
  top.t_target.push(target_expr);
  top.t_sls.push(sls);
}

/// The ordered SLS list a top file yields for a minion: every row whose
/// target expression matches, in declaration order, duplicates preserved.
/// A malformed target expression is the first targeting error.
pub fn salt_top_sls(top: &Top, minion_id: Str, gs: &GrainSet) -> Result[Vec[Str], Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < top.t_target.len() {
    let expr: Str = top.t_target[i];
    let r = salt_target_match(minion_id, gs, expr);
    match r {
      Ok(v) => {
        if v {
          let s: Str = top.t_sls[i];
          out.push(s);
        }
      },
      Err(e) => { return _strs_err(e); },
    }
    i = i + 1;
  }
  return _strs_ok(out);
}

/// A pillar data set: key/value rows with a precedence level (0 base, 1 env,
/// 2 override) and an origin (source) string per row.
pub type Pillar = {
  keys: Vec[Str];
  values: Vec[Str];
  levels: Vec[Int];
  origins: Vec[Str];
}

/// An empty pillar.
pub fn salt_pillar_new() -> Pillar {
  return Pillar{ keys: Vec[Str].new(); values: Vec[Str].new(); levels: Vec[Int].new(); origins: Vec[Str].new(); };
}

// Precedence level of a pillar level name ("base" 0, "env" 1, "override" 2).
fn _pillar_level_of(l: Str) -> Int {
  if _streq(l, "base") {
    return 0;
  }
  if _streq(l, "env") {
    return 1;
  }
  if _streq(l, "override") {
    return 2;
  }
  return -1;
}

// Level name of a pillar level number.
fn _pillar_level_name(lv: Int) -> Str {
  if lv == 0 {
    return "base";
  }
  if lv == 1 {
    return "env";
  }
  return "override";
}

// Assign a pillar value: new keys append (position = first insertion);
// existing keys are replaced when level >= the current level (equal level =
// later wins) and left alone otherwise.
fn _pillar_put(p: &mut Pillar, key: Str, value: Str, level: Int, origin: Str) {
  var i = 0;
  while i < p.keys.len() {
    let k: Str = p.keys[i];
    if _streq(k, key) {
      let cur: Int = p.levels[i];
      if level >= cur {
        p.values[i] = value;
        p.levels[i] = level;
        p.origins[i] = origin;
      }
      return;
    }
    i = i + 1;
  }
  p.keys.push(key);
  p.values.push(value);
  p.levels.push(level);
  p.origins.push(origin);
}

// Index of pillar key `key`, or -1 (first match).
fn _pillar_index(p: &Pillar, key: Str) -> Int {
  var i = 0;
  while i < p.keys.len() {
    let k: Str = p.keys[i];
    if _streq(k, key) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Set `key = value` at the named level ("base", "env" or "override") with an
/// origin label. Returns false for an unknown level (nothing is stored).
pub fn salt_pillar_set(p: &mut Pillar, key: Str, value: Str, level: Str, origin: Str) -> Bool {
  let lv = _pillar_level_of(level);
  if lv < 0 {
    return false;
  }
  _pillar_put(p, key, value, lv, origin);
  return true;
}

/// Winning value of `key`; None when absent.
pub fn salt_pillar_get(p: &Pillar, key: Str) -> Option[Str] {
  let i = _pillar_index(p, key);
  if i < 0 {
    return None;
  }
  let v: Str = p.values[i];
  return Some(v);
}

/// Winning level of `key` (0 base, 1 env, 2 override), or -1.
pub fn salt_pillar_level(p: &Pillar, key: Str) -> Int {
  let i = _pillar_index(p, key);
  if i < 0 {
    return -1;
  }
  let lv: Int = p.levels[i];
  return lv;
}

/// Origin of the winning assignment of `key`; None when absent.
pub fn salt_pillar_origin(p: &Pillar, key: Str) -> Option[Str] {
  let i = _pillar_index(p, key);
  if i < 0 {
    return None;
  }
  let o: Str = p.origins[i];
  return Some(o);
}

/// Merge `overlay` into `base` with the documented precedence rule; neither
/// input is modified. Applying salt_pillar_merge once per source, in top-file
/// order, resolves a pillar chain.
pub fn salt_pillar_merge(base: &Pillar, overlay: &Pillar) -> Pillar {
  var out = salt_pillar_new();
  var i = 0;
  while i < base.keys.len() {
    let k: Str = base.keys[i];
    let v: Str = base.values[i];
    let lv: Int = base.levels[i];
    let o: Str = base.origins[i];
    _pillar_put(&mut out, k, v, lv, o);
    i = i + 1;
  }
  var j = 0;
  while j < overlay.keys.len() {
    let k2: Str = overlay.keys[j];
    let v2: Str = overlay.values[j];
    let lv2: Int = overlay.levels[j];
    let o2: Str = overlay.origins[j];
    _pillar_put(&mut out, k2, v2, lv2, o2);
    j = j + 1;
  }
  return out;
}

/// Canonical render: one counter header line then one
/// "key=value level=.. origin=.." line per key, insertion order, LF separated
/// with no trailing LF.
pub fn salt_pillar_render(p: &Pillar) -> Str {
  var out = "pillar: count=" + convert.int_to_string(p.keys.len());
  var i = 0;
  while i < p.keys.len() {
    let k: Str = p.keys[i];
    let v: Str = p.values[i];
    let lv: Int = p.levels[i];
    let o: Str = p.origins[i];
    out = out + "\n" + k + "=" + v + " level=" + _pillar_level_name(lv) + " origin=" + o;
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  States: declarations and requisites
// --------------------------------------------------

/// A Salt state list (SLS): state declarations with their ids, state
/// functions and names plus host-supplied outcomes, and requisite rows
/// (require / watch / onchanges and the *_in inverses). Every row family is a
/// parallel vector; the builders keep owners aligned.
pub type SLS = {
  name: Str;
  ids: Vec[Str];        // declaration id, e.g. "nginx_pkg"
  funs: Vec[Str];       // state function, e.g. "pkg.installed"
  names: Vec[Str];      // name argument, e.g. "nginx"
  results: Vec[Int];    // host-supplied _SALT_RES_OK / _SALT_RES_FAIL
  changes: Vec[Int];    // host-supplied change count (forced 0 on failure)
  rq_owner: Vec[Int];   // declaration owning each requisite row
  rq_kind: Vec[Int];    // _SALT_RQ_*
  rq_target: Vec[Str];  // target declaration id
}

/// An empty state list with the given name.
pub fn salt_sls_new(name: Str) -> SLS {
  return SLS{
    name: name;
    ids: Vec[Str].new();
    funs: Vec[Str].new();
    names: Vec[Str].new();
    results: Vec[Int].new();
    changes: Vec[Int].new();
    rq_owner: Vec[Int].new();
    rq_kind: Vec[Int].new();
    rq_target: Vec[Str].new();
  };
}

/// Append a state declaration and return its index, defaulting to result ok
/// with one change (as if the state would change the system). Returns -1 and
/// stores nothing when `id` or `fun` is not a valid identifier (non-empty, no
/// whitespace, no brackets) or `name` is empty.
pub fn salt_state_add(sls: &mut SLS, id: Str, fun: Str, name: Str) -> Int {
  if !_ident_ok(id) {
    return -1;
  }
  if !_ident_ok(fun) {
    return -1;
  }
  if name.len() == 0 {
    return -1;
  }
  sls.ids.push(id);
  sls.funs.push(fun);
  sls.names.push(name);
  sls.results.push(_SALT_RES_OK);
  sls.changes.push(1);
  return sls.ids.len() - 1;
}

/// Number of declarations in a state list.
pub fn salt_state_count(sls: &SLS) -> Int {
  return sls.ids.len();
}

/// Declaration id at `i` ("" when out of range).
pub fn salt_state_id(sls: &SLS, i: Int) -> Str {
  if i < 0 || i >= sls.ids.len() {
    return "";
  }
  let x: Str = sls.ids[i];
  return x;
}

/// State function at `i` ("" when out of range).
pub fn salt_state_fun(sls: &SLS, i: Int) -> Str {
  if i < 0 || i >= sls.funs.len() {
    return "";
  }
  let x: Str = sls.funs[i];
  return x;
}

/// Name argument at `i` ("" when out of range).
pub fn salt_state_name(sls: &SLS, i: Int) -> Str {
  if i < 0 || i >= sls.names.len() {
    return "";
  }
  let x: Str = sls.names[i];
  return x;
}

/// Set the host-supplied outcome of declaration `i`: `result` is
/// _SALT_RES_OK (0) or _SALT_RES_FAIL (1); `changes` is the reported change
/// count (clamped to >= 0 and forced to 0 on failure). Returns false when `i`
/// is out of range (nothing is stored).
pub fn salt_state_set_outcome(sls: &mut SLS, i: Int, result: Int, changes: Int) -> Bool {
  if i < 0 || i >= sls.ids.len() {
    return false;
  }
  sls.results[i] = result;
  var ch = changes;
  if ch < 0 {
    ch = 0;
  }
  if result == _SALT_RES_FAIL {
    ch = 0;
  }
  sls.changes[i] = ch;
  return true;
}

// Append one requisite row, validating the owner index and target id.
fn _requisite_add(sls: &mut SLS, owner: Int, kind: Int, target: Str) -> Bool {
  if owner < 0 || owner >= sls.ids.len() {
    return false;
  }
  if target.len() == 0 {
    return false;
  }
  sls.rq_owner.push(owner);
  sls.rq_kind.push(kind);
  sls.rq_target.push(target);
  return true;
}

/// Declare that declaration `owner` requires `target`: `target` runs first
/// and must end applied or noop, else `owner` is skipped.
pub fn salt_state_require(sls: &mut SLS, owner: Int, target: Str) -> Bool {
  return _requisite_add(sls, owner, _SALT_RQ_REQUIRE, target);
}

/// Declare that declaration `owner` watches `target`: ordering and failure
/// semantics as require; when `target` applies with changes, a watch trigger
/// fires for `owner`.
pub fn salt_state_watch(sls: &mut SLS, owner: Int, target: Str) -> Bool {
  return _requisite_add(sls, owner, _SALT_RQ_WATCH, target);
}

/// Declare that declaration `owner` reacts to changes of `target`: same
/// rules as watch, counted as an onchanges trigger instead of a mod_watch.
pub fn salt_state_onchanges(sls: &mut SLS, owner: Int, target: Str) -> Bool {
  return _requisite_add(sls, owner, _SALT_RQ_ONCHANGES, target);
}

/// Inverse view: declaration `owner` is required by `target` (the target
/// runs after `owner`).
pub fn salt_state_require_in(sls: &mut SLS, owner: Int, target: Str) -> Bool {
  return _requisite_add(sls, owner, _SALT_RQ_REQUIRE_IN, target);
}

/// Inverse view: declaration `owner` is watched by `target` (the target
/// runs after `owner` and watch-triggers on `owner`'s changes).
pub fn salt_state_watch_in(sls: &mut SLS, owner: Int, target: Str) -> Bool {
  return _requisite_add(sls, owner, _SALT_RQ_WATCH_IN, target);
}

/// Inverse view: declaration `owner`'s changes trigger `target` (the target
/// runs after `owner` and onchanges-triggers on `owner`'s changes).
pub fn salt_state_onchanges_in(sls: &mut SLS, owner: Int, target: Str) -> Bool {
  return _requisite_add(sls, owner, _SALT_RQ_ONCHANGES_IN, target);
}

/// Number of requisite rows.
pub fn salt_requisite_count(sls: &SLS) -> Int {
  return sls.rq_owner.len();
}

/// Owner declaration index of requisite row `k` (-1 when out of range).
pub fn salt_requisite_owner(sls: &SLS, k: Int) -> Int {
  if k < 0 || k >= sls.rq_owner.len() {
    return -1;
  }
  let x: Int = sls.rq_owner[k];
  return x;
}

/// Kind of requisite row `k` (-1 when out of range): 0 require, 1 watch,
/// 2 onchanges, 3 require_in, 4 watch_in, 5 onchanges_in.
pub fn salt_requisite_kind(sls: &SLS, k: Int) -> Int {
  if k < 0 || k >= sls.rq_kind.len() {
    return -1;
  }
  let x: Int = sls.rq_kind[k];
  return x;
}

/// Target declaration id of requisite row `k` ("" when out of range).
pub fn salt_requisite_target(sls: &SLS, k: Int) -> Str {
  if k < 0 || k >= sls.rq_target.len() {
    return "";
  }
  let x: Str = sls.rq_target[k];
  return x;
}

// --------------------------------------------------
//  States: ordering edges and execution
// --------------------------------------------------

// Normalized ordering edges (module-internal): ef[i] must run before et[i],
// ek[i] is the _SALT_RQ_* kind with the *_in kinds mapped to 0/1/2.
type _Edge = {
  ef: Vec[Int];
  et: Vec[Int];
  ek: Vec[Int];
}

// Index of declaration id `id`, or -1 (first match).
fn _decl_index(sls: &SLS, id: Str) -> Int {
  var i = 0;
  while i < sls.ids.len() {
    let x: Str = sls.ids[i];
    if _streq(x, id) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Build the normalized edge list; every requisite target must resolve.
fn _edges_build(sls: &SLS) -> Result[_Edge, Str] {
  var ef = Vec[Int].new();
  var et = Vec[Int].new();
  var ek = Vec[Int].new();
  var i = 0;
  while i < sls.rq_owner.len() {
    let owner: Int = sls.rq_owner[i];
    let kind: Int = sls.rq_kind[i];
    let tgt: Str = sls.rq_target[i];
    let ti = _decl_index(sls, tgt);
    if ti < 0 {
      return _edge_err("salt: unknown state id: " + tgt);
    }
    if kind == _SALT_RQ_REQUIRE || kind == _SALT_RQ_WATCH || kind == _SALT_RQ_ONCHANGES {
      ef.push(ti);
      et.push(owner);
      ek.push(kind);
    } else {
      ef.push(owner);
      et.push(ti);
      ek.push(kind - 3);
    }
    i = i + 1;
  }
  return _edge_ok(_Edge{ ef: ef; et: et; ek: ek });
}

/// Stable topological execution order: repeatedly pick the lowest declaration
/// index with in-degree zero. Ties are therefore broken by declaration order
/// and the order is a pure function of the declarations. Err:
/// "salt: unknown state id: <id>" or "salt: requisite cycle".
pub fn salt_run_order(sls: &SLS) -> Result[Vec[Int], Str] {
  let eb = _edges_build(sls);
  match eb {
    Ok(ed) => {
      var indeg = Vec[Int].new();
      var i = 0;
      while i < sls.ids.len() {
        indeg.push(0);
        i = i + 1;
      }
      i = 0;
      while i < ed.et.len() {
        let t: Int = ed.et[i];
        let d: Int = indeg[t];
        indeg[t] = d + 1;
        i = i + 1;
      }
      var emitted = Vec[Int].new();
      var k = 0;
      while k < sls.ids.len() {
        emitted.push(0);
        k = k + 1;
      }
      var order = Vec[Int].new();
      var step = 0;
      while step < sls.ids.len() {
        var pick = -1;
        var j = 0;
        while j < sls.ids.len() {
          let em: Int = emitted[j];
          let dg: Int = indeg[j];
          if em == 0 && dg == 0 && pick < 0 {
            pick = j;
          }
          j = j + 1;
        }
        if pick < 0 {
          return _ints_err("salt: requisite cycle");
        }
        emitted[pick] = 1;
        order.push(pick);
        var m = 0;
        while m < ed.ef.len() {
          let f: Int = ed.ef[m];
          let t2: Int = ed.et[m];
          if f == pick {
            let d2: Int = indeg[t2];
            indeg[t2] = d2 - 1;
          }
          m = m + 1;
        }
        step = step + 1;
      }
      return _ints_ok(order);
    },
    Err(m) => { return _ints_err(m); },
  }
  return _ints_err("salt: unreachable");
}

/// The deterministic result of simulating one SLS run.
pub type RunReport = {
  total: Int;
  applied: Int;
  noop: Int;
  failed: Int;
  skipped: Int;
  watches: Int;
  onchanges: Int;
  changes: Int;
  events: Vec[Str];
}

// Mutable run state (module-internal; no &mut scalar parameters).
type _Run = {
  status: Vec[Int];
  applied: Int;
  noop: Int;
  failed: Int;
  skipped: Int;
  watches: Int;
  onchanges: Int;
  changes: Int;
  events: Vec[Str];
}

// Fresh run state sized to `n`.
fn _run_new(n: Int) -> _Run {
  var st = Vec[Int].new();
  var i = 0;
  while i < n {
    st.push(_SALT_ST_PENDING);
    i = i + 1;
  }
  return _Run{
    status: st;
    applied: 0;
    noop: 0;
    failed: 0;
    skipped: 0;
    watches: 0;
    onchanges: 0;
    changes: 0;
    events: Vec[Str].new();
  };
}

// First edge source feeding `i` whose state ended failed or skipped, or -1.
// The scan is inlined into _run_visit with direct ru.status reads.

// Fire watch / onchanges triggers for `i`: each incoming watch / onchanges
// edge whose source applied with changes > 0 counts one trigger and logs an
// event, in requisite row order.
fn _fire_prereqs(ed: &_Edge, i: Int, sls: &SLS, ru: &mut _Run) {
  var m = 0;
  while m < ed.et.len() {
    let t: Int = ed.et[m];
    if t == i {
      let k: Int = ed.ek[m];
      if k == _SALT_RQ_WATCH || k == _SALT_RQ_ONCHANGES {
        let f: Int = ed.ef[m];
        let fs: Int = ru.status[f];
        if fs == _SALT_ST_APPLIED {
          let fsrc: Str = sls.ids[f];
          let self_id: Str = sls.ids[i];
          if k == _SALT_RQ_WATCH {
            ru.watches = ru.watches + 1;
            ru.events.push("watch: " + fsrc + " -> " + self_id);
          } else {
            ru.onchanges = ru.onchanges + 1;
            ru.events.push("onchanges: " + fsrc + " -> " + self_id);
          }
        }
      }
    }
    m = m + 1;
  }
}

// Classify and execute declaration `i`.
fn _run_visit(ed: &_Edge, sls: &SLS, i: Int, ru: &mut _Run) {
  var bad = -1;
  var m = 0;
  while m < ed.et.len() {
    let t: Int = ed.et[m];
    if t == i && bad < 0 {
      let f: Int = ed.ef[m];
      let s: Int = ru.status[f];
      if s == _SALT_ST_FAILED || s == _SALT_ST_SKIPPED {
        bad = f;
      }
    }
    m = m + 1;
  }
  let id: Str = sls.ids[i];
  if bad >= 0 {
    ru.status[i] = _SALT_ST_SKIPPED;
    ru.skipped = ru.skipped + 1;
    let bsrc: Str = sls.ids[bad];
    ru.events.push("skipped: " + id + " (requisite failed: " + bsrc + ")");
    return;
  }
  let res: Int = sls.results[i];
  if res == _SALT_RES_FAIL {
    ru.status[i] = _SALT_ST_FAILED;
    ru.failed = ru.failed + 1;
    ru.events.push("failed: " + id);
    return;
  }
  let ch: Int = sls.changes[i];
  if ch > 0 {
    ru.status[i] = _SALT_ST_APPLIED;
    ru.applied = ru.applied + 1;
    ru.changes = ru.changes + ch;
    ru.events.push("applied: " + id + " (changes=" + convert.int_to_string(ch) + ")");
  } else {
    ru.status[i] = _SALT_ST_NOOP;
    ru.noop = ru.noop + 1;
    ru.events.push("noop: " + id);
  }
  _fire_prereqs(ed, i, sls, ru);
}

/// Simulate one SLS run: stable topological order (salt_run_order), then the
/// documented requisite / outcome rules. Returns the deterministic report, or
/// the same errors as salt_run_order. total always equals applied + noop +
/// failed + skipped.
pub fn salt_run(sls: &SLS) -> Result[RunReport, Str] {
  let ord = salt_run_order(sls);
  match ord {
    Ok(order) => {
      let eb = _edges_build(sls);
      match eb {
        Ok(ed) => {
          var ru = _run_new(sls.ids.len());
          var i = 0;
          while i < order.len() {
            let idx: Int = order[i];
            _run_visit(&ed, sls, idx, &mut ru);
            i = i + 1;
          }
          var ev = Vec[Str].new();
          var j = 0;
          while j < ru.events.len() {
            let e: Str = ru.events[j];
            ev.push(e);
            j = j + 1;
          }
          return _runrep_ok(RunReport{
            total: sls.ids.len();
            applied: ru.applied;
            noop: ru.noop;
            failed: ru.failed;
            skipped: ru.skipped;
            watches: ru.watches;
            onchanges: ru.onchanges;
            changes: ru.changes;
            events: ev;
          });
        },
        Err(m) => { return _runrep_err(m); },
      }
    },
    Err(m2) => { return _runrep_err(m2); },
  }
  return _runrep_err("salt: unreachable");
}

/// Canonical render: a counts header line, a trigger header line and one
/// "event: <event>" line per event, LF separated with no trailing LF. An
/// empty run renders exactly the two header lines.
pub fn salt_run_render(r: &RunReport) -> Str {
  var out = "salt run: total=" + convert.int_to_string(r.total) + " applied=" + convert.int_to_string(r.applied) + " noop=" + convert.int_to_string(r.noop) + " failed=" + convert.int_to_string(r.failed) + " skipped=" + convert.int_to_string(r.skipped);
  out = out + "\nwatches=" + convert.int_to_string(r.watches) + " onchanges=" + convert.int_to_string(r.onchanges) + " changes=" + convert.int_to_string(r.changes);
  var i = 0;
  while i < r.events.len() {
    let e: Str = r.events[i];
    out = out + "\nevent: " + e;
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Event bus and reactor rules
// --------------------------------------------------

/// A published-event buffer: one tag per event, plus index-aligned payload
/// key/value rows owned by the event index. Frame with salt_event_frame.
pub type EventBuf = {
  tags: Vec[Str];
  p_owner: Vec[Int];    // event index owning each payload row
  p_key: Vec[Str];
  p_value: Vec[Str];
}

/// An empty event buffer.
pub fn salt_eventbuf_new() -> EventBuf {
  return EventBuf{ tags: Vec[Str].new(); p_owner: Vec[Int].new(); p_key: Vec[Str].new(); p_value: Vec[Str].new(); };
}

/// Publish an event with tag `tag` and return its event index. Payload rows
/// are added with salt_event_put in call order.
pub fn salt_event_publish(buf: &mut EventBuf, tag: Str) -> Int {
  buf.tags.push(tag);
  return buf.tags.len() - 1;
}

/// Append one payload key/value row to event `ev`. Returns false when `ev` is
/// out of range (nothing is stored); duplicate keys are preserved.
pub fn salt_event_put(buf: &mut EventBuf, ev: Int, key: Str, value: Str) -> Bool {
  if ev < 0 || ev >= buf.tags.len() {
    return false;
  }
  buf.p_owner.push(ev);
  buf.p_key.push(key);
  buf.p_value.push(value);
  return true;
}

/// Number of published events.
pub fn salt_event_count(buf: &EventBuf) -> Int {
  return buf.tags.len();
}

/// Tag of event `ev` ("" when out of range).
pub fn salt_event_tag(buf: &EventBuf, ev: Int) -> Str {
  if ev < 0 || ev >= buf.tags.len() {
    return "";
  }
  let t: Str = buf.tags[ev];
  return t;
}

/// Deterministic payload frame of event `ev`: "<tag>|k=v;k=v" with payload
/// rows in insertion order and no trailing separator; an event with no
/// payload frames as "<tag>|". "" when `ev` is out of range.
pub fn salt_event_frame(buf: &EventBuf, ev: Int) -> Str {
  if ev < 0 || ev >= buf.tags.len() {
    return "";
  }
  let tag: Str = buf.tags[ev];
  var out = tag + "|";
  var first = true;
  var i = 0;
  while i < buf.p_owner.len() {
    let o: Int = buf.p_owner[i];
    if o == ev {
      let k: Str = buf.p_key[i];
      let v: Str = buf.p_value[i];
      if !first {
        out = out + ";";
      }
      out = out + k + "=" + v;
      first = false;
    }
    i = i + 1;
  }
  return out;
}

/// Reactor rules: one glob tag pattern and one action string per rule, in
/// declaration order.
pub type Reactor = {
  r_tag: Vec[Str];
  r_action: Vec[Str];
}

/// An empty reactor.
pub fn salt_reactor_new() -> Reactor {
  return Reactor{ r_tag: Vec[Str].new(); r_action: Vec[Str].new(); };
}

/// Append a reactor rule: when an event tag matches `tag_glob`
/// (salt_glob_match), `action` runs.
pub fn salt_reactor_add(reactor: &mut Reactor, tag_glob: Str, action: Str) {
  reactor.r_tag.push(tag_glob);
  reactor.r_action.push(action);
}

/// Actions of every rule whose tag glob matches `tag`, in rule order
/// (duplicates preserved).
pub fn salt_reactor_match(reactor: &Reactor, tag: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < reactor.r_tag.len() {
    let pat: Str = reactor.r_tag[i];
    if salt_glob_match(pat, tag) {
      let a: Str = reactor.r_action[i];
      out.push(a);
    }
    i = i + 1;
  }
  return out;
}

/// Dispatch every published event through the reactor: for each event in
/// publish order and each matching rule in rule order, append
/// "<event-index>:<action>". Duplicates reflect multiple events or rules.
pub fn salt_reactor_dispatch(reactor: &Reactor, buf: &EventBuf) -> Vec[Str] {
  var out = Vec[Str].new();
  var e = 0;
  while e < buf.tags.len() {
    let tag: Str = buf.tags[e];
    let evs = convert.int_to_string(e);
    var i = 0;
    while i < reactor.r_tag.len() {
      let pat: Str = reactor.r_tag[i];
      if salt_glob_match(pat, tag) {
        let a: Str = reactor.r_action[i];
        out.push(evs + ":" + a);
      }
      i = i + 1;
    }
    e = e + 1;
  }
  return out;
}
