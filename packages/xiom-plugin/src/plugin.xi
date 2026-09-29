// XIOM -- xiom.plugin: deterministic plugin registry and lifecycle model
// Port task: promote the xiom.plugin placeholder to a real, tested, pure-XIOM
// package: registration metadata, semver range checks, dependency-order
// resolution and a validated enable/activate state machine.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: metadata and ordering only. There is no dynamic loading, no dlopen
// and no FFI in this module: a Registry is a value that describes which
// plugins exist, what they depend on, what capabilities they declare and
// which lifecycle state each one is in. A host that actually loads code uses
// this model to decide *what* to load and in *which* order (see SPEC.md).
//
// Model (Vec[StructType] is unsupported in this compiler, so a Registry is a
// set of index-aligned parallel vectors):
//   names/versions/states   one row per registered plugin. `names` order is
//                           registration order and is the tie-break for every
//                           deterministic walk in this module.
//   dep_owner/dep_name      one row per declared dependency: the index of the
//                           declaring plugin and the dependency name as
//                           declared (declaration order is preserved).
//   cap_owner/cap_name      one row per declared capability: the index of the
//                           declaring plugin and the capability name.
//
// v0.62.1 notes that shaped this module:
//   * Free functions only; every walk is index-based over parallel vectors.
//   * Ok/Err for Result[...] are constructed only in the leaf helpers
//     _reg_ok/_reg_err, _names_ok/_names_err, _int_ok/_int_err and
//     _bool_ok/_bool_err (constructing Results directly inside larger
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); every comparison is routed through _streq.
//   * Every byte read is widened and masked ((b as Int) & 0xFF) by the _byte
//     helper before any comparison (byte comparisons at >= 128 miscompile).
//   * Every Vec[Str]/Vec[Int] element read goes through a typed local first
//     (untyped element reads can mis-lower to Str comparisons).

module xiom.plugin

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(r) for Result[Registry, Str].
fn _reg_ok(r: Registry) -> Result[Registry, Str] {
  return Ok(r);
}

// Err(m) for Result[Registry, Str].
fn _reg_err(m: Str) -> Result[Registry, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _names_ok(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _names_err(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _int_ok(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _int_err(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _bool_ok(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _bool_err(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (widened Int values; see _byte)
// --------------------------------------------------

const _PL_TAB: Int = 9;
const _PL_SPACE: Int = 32;
const _PL_STAR: Int = 42;
const _PL_COMMA: Int = 44;
const _PL_DOT: Int = 46;
const _PL_ZERO: Int = 48;
const _PL_NINE: Int = 57;
const _PL_LESS: Int = 60;
const _PL_EQ: Int = 61;
const _PL_GREATER: Int = 62;
const _PL_CARET: Int = 94;
const _PL_TILDE: Int = 126;

// Range-comparator op codes (internal).
const _PL_OP_EQ: Int = 1;
const _PL_OP_GT: Int = 2;
const _PL_OP_GE: Int = 3;
const _PL_OP_LT: Int = 4;
const _PL_OP_LE: Int = 5;
const _PL_OP_CARET: Int = 6;
const _PL_OP_TILDE: Int = 7;

// Version-component parser bounds: components are capped at 2147483647
// (the guard mirrors xiom.config's integer parser).
const _PL_MAX_DIV10: Int = 214748364;
const _PL_MAX_LAST: Int = 7;

// --------------------------------------------------
//  Lifecycle states
// --------------------------------------------------

/// Lifecycle state: registered (present, dependencies not checked yet).
pub const plugin_state_registered: Int = 0;
/// Lifecycle state: enabled (may be activated once its dependencies are).
pub const plugin_state_enabled: Int = 1;
/// Lifecycle state: active (enabled and running in the host).
pub const plugin_state_active: Int = 2;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// Registration metadata for one plugin: a non-empty name, a strict semantic
/// version `x.y.z`, its declared dependency names and its declared capability
/// names. Build a spec with plugin_spec; store it with plugin_register.
pub type PluginSpec = {
  name: Str;
  version: Str;
  deps: Vec[Str];
  caps: Vec[Str];
}

/// A plugin registry. All vectors are index-aligned:
/// `names`, `versions` and `states` have one entry per plugin (registration
/// order); `dep_owner`/`dep_name` and `cap_owner`/`cap_name` hold one entry
/// per declared dependency/capability, where the owner is the plugin index.
/// Invariants maintained by plugin_register: unique names; every version is a
/// valid strict semver; dependency/capability names are non-empty, unique per
/// plugin, and a plugin never depends on itself (cycles across plugins are
/// allowed at registration and reported by plugin_resolve).
pub type Registry = {
  names: Vec[Str];
  versions: Vec[Str];
  states: Vec[Int];
  dep_owner: Vec[Int];
  dep_name: Vec[Str];
  cap_owner: Vec[Int];
  cap_name: Vec[Str];
}

// --------------------------------------------------
//  Byte and Str primitives
// --------------------------------------------------

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

// True for the ASCII digits '0'..'9' (widened byte values).
fn _is_digit(c: Int) -> Bool {
  return c >= _PL_ZERO && c <= _PL_NINE;
}

// True for the range-expression delimiters: space, tab and comma.
fn _is_delim(c: Int) -> Bool {
  if c == _PL_SPACE {
    return true;
  }
  if c == _PL_TAB {
    return true;
  }
  return c == _PL_COMMA;
}

// Compare two (major, minor, patch) triples: -1, 0 or 1.
fn _cmp3(amaj: Int, amin: Int, apat: Int, bmaj: Int, bmin: Int, bpat: Int) -> Int {
  if amaj < bmaj {
    return -1;
  }
  if amaj > bmaj {
    return 1;
  }
  if amin < bmin {
    return -1;
  }
  if amin > bmin {
    return 1;
  }
  if apat < bpat {
    return -1;
  }
  if apat > bpat {
    return 1;
  }
  return 0;
}

// Compare two parsed 3-element version vectors: -1, 0 or 1.
fn _ver_cmp3(a: &Vec[Int], b: &Vec[Int]) -> Int {
  let am: Int = a[0];
  let an: Int = a[1];
  let ap: Int = a[2];
  let bm: Int = b[0];
  let bn: Int = b[1];
  let bp: Int = b[2];
  return _cmp3(am, an, ap, bm, bn, bp);
}

// Parse one numeric version component. Returns its value, or -1 when the
// component is empty, non-numeric, has a leading zero ("01"), or exceeds
// 2147483647.
fn _parse_component(c: Str) -> Int {
  let n = string.str_len(c);
  if n == 0 {
    return -1;
  }
  let first = _byte(c, 0);
  if !_is_digit(first) {
    return -1;
  }
  if first == _PL_ZERO && n > 1 {
    return -1;
  }
  var mag: Int = 0;
  var i = 0;
  while i < n {
    let ch = _byte(c, i);
    if !_is_digit(ch) {
      return -1;
    }
    let d = ch - _PL_ZERO;
    if mag > _PL_MAX_DIV10 {
      return -1;
    }
    if mag == _PL_MAX_DIV10 && d > _PL_MAX_LAST {
      return -1;
    }
    mag = mag * 10 + d;
    i = i + 1;
  }
  return mag;
}

// Parse a strict semantic version: exactly three dot-separated numeric
// components `x.y.z`, no leading zeros, no pre-release/build suffix.
// Returns a 3-element vector [major, minor, patch], or an empty vector when
// `v` is malformed.
fn _semver_parse(v: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = string.str_len(v);
  var d1 = -1;
  var d2 = -1;
  var i = 0;
  while i < n {
    if _byte(v, i) == _PL_DOT {
      if d1 < 0 {
        d1 = i;
      } elif d2 < 0 {
        d2 = i;
      } else {
        return out;
      }
    }
    i = i + 1;
  }
  if d1 < 0 || d2 < 0 {
    return out;
  }
  let a = _parse_component(string.str_slice(v, 0, d1));
  let b = _parse_component(string.str_slice(v, d1 + 1, d2));
  let c = _parse_component(string.str_slice(v, d2 + 1, n));
  if a < 0 || b < 0 || c < 0 {
    return out;
  }
  out.push(a);
  out.push(b);
  out.push(c);
  return out;
}

// --------------------------------------------------
//  Registry helpers
// --------------------------------------------------

// Registration index of `name`, or -1 when absent. Byte-exact, case-sensitive.
fn _plugin_index(reg: &Registry, name: Str) -> Int {
  var i = 0;
  while i < reg.names.len() {
    let n: Str = reg.names[i];
    if _streq(n, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Deep copy of `reg` (all seven parallel vectors, in order).
fn _copy_registry(reg: &Registry) -> Registry {
  var out = Registry{
    names: Vec[Str].new();
    versions: Vec[Str].new();
    states: Vec[Int].new();
    dep_owner: Vec[Int].new();
    dep_name: Vec[Str].new();
    cap_owner: Vec[Int].new();
    cap_name: Vec[Str].new();
  };
  var i = 0;
  while i < reg.names.len() {
    let n: Str = reg.names[i];
    let v: Str = reg.versions[i];
    let s: Int = reg.states[i];
    out.names.push(n);
    out.versions.push(v);
    out.states.push(s);
    i = i + 1;
  }
  i = 0;
  while i < reg.dep_name.len() {
    let o: Int = reg.dep_owner[i];
    let d: Str = reg.dep_name[i];
    out.dep_owner.push(o);
    out.dep_name.push(d);
    i = i + 1;
  }
  i = 0;
  while i < reg.cap_name.len() {
    let o: Int = reg.cap_owner[i];
    let c: Str = reg.cap_name[i];
    out.cap_owner.push(o);
    out.cap_name.push(c);
    i = i + 1;
  }
  return out;
}

// Number of dependencies declared by the plugin at `owner`.
fn _dep_count(reg: &Registry, owner: Int) -> Int {
  var k = 0;
  var i = 0;
  while i < reg.dep_name.len() {
    let o: Int = reg.dep_owner[i];
    if o == owner {
      k = k + 1;
    }
    i = i + 1;
  }
  return k;
}

// The k-th dependency name of `owner` in declaration order ("" when out of
// range).
fn _dep_at(reg: &Registry, owner: Int, k: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < reg.dep_name.len() {
    let o: Int = reg.dep_owner[i];
    if o == owner {
      if seen == k {
        let d: Str = reg.dep_name[i];
        return d;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

// Number of capabilities declared by the plugin at `owner`.
fn _cap_count(reg: &Registry, owner: Int) -> Int {
  var k = 0;
  var i = 0;
  while i < reg.cap_name.len() {
    let o: Int = reg.cap_owner[i];
    if o == owner {
      k = k + 1;
    }
    i = i + 1;
  }
  return k;
}

// The k-th capability name of `owner` in declaration order ("" when out of
// range).
fn _cap_at(reg: &Registry, owner: Int, k: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < reg.cap_name.len() {
    let o: Int = reg.cap_owner[i];
    if o == owner {
      if seen == k {
        let c: Str = reg.cap_name[i];
        return c;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

// True when the plugin at `owner` declares a dependency on the plugin at
// `dep_index`.
fn _depends_on(reg: &Registry, owner: Int, dep_index: Int) -> Bool {
  let want: Str = reg.names[dep_index];
  let k = _dep_count(reg, owner);
  var j = 0;
  while j < k {
    let d = _dep_at(reg, owner, j);
    if _streq(d, want) {
      return true;
    }
    j = j + 1;
  }
  return false;
}

// First dependency of the plugin at `idx` whose state is below `min_state`
// (a dependency missing from the registry counts as below); "" when every
// dependency passes.
fn _unready_dep(reg: &Registry, idx: Int, min_state: Int) -> Str {
  let k = _dep_count(reg, idx);
  var j = 0;
  while j < k {
    let d = _dep_at(reg, idx, j);
    let di = _plugin_index(reg, d);
    var ready = false;
    if di >= 0 {
      let s: Int = reg.states[di];
      if s >= min_state {
        ready = true;
      }
    }
    if !ready {
      return d;
    }
    j = j + 1;
  }
  return "";
}

// Name of the first plugin (in registration order) that is active and
// depends on the plugin at `idx`; "" when there is none.
fn _active_dependent(reg: &Registry, idx: Int) -> Str {
  var i = 0;
  while i < reg.names.len() {
    let s: Int = reg.states[i];
    if s == plugin_state_active && _depends_on(reg, i, idx) {
      let n: Str = reg.names[i];
      return n;
    }
    i = i + 1;
  }
  return "";
}

// Replace the state of the plugin at `idx` in a copy of `reg`.
fn _set_state(reg: &Registry, idx: Int, st: Int) -> Registry {
  var out = _copy_registry(reg);
  out.states[idx] = st;
  return out;
}

// --------------------------------------------------
//  Registration
// --------------------------------------------------

/// An empty registry: no plugins, no dependencies, no capabilities.
pub fn plugin_registry_new() -> Registry {
  return Registry{
    names: Vec[Str].new();
    versions: Vec[Str].new();
    states: Vec[Int].new();
    dep_owner: Vec[Int].new();
    dep_name: Vec[Str].new();
    cap_owner: Vec[Int].new();
    cap_name: Vec[Str].new();
  };
}

/// Build a PluginSpec, copying `deps` and `caps` so the spec does not alias
/// caller-owned vectors.
pub fn plugin_spec(name: Str, version: Str, deps: &Vec[Str], caps: &Vec[Str]) -> PluginSpec {
  var ds = Vec[Str].new();
  var i = 0;
  while i < deps.len() {
    let d: Str = deps[i];
    ds.push(d);
    i = i + 1;
  }
  var cs = Vec[Str].new();
  i = 0;
  while i < caps.len() {
    let c: Str = caps[i];
    cs.push(c);
    i = i + 1;
  }
  return PluginSpec{ name: name; version: version; deps: ds; caps: cs; };
}

/// Register one plugin. Returns the extended registry, or an Err with the
/// first problem found in this order: empty name; invalid version; duplicate
/// plugin name; empty/self/duplicate dependency; empty/duplicate capability.
/// On Err the input registry is unchanged. The new plugin starts in state
/// plugin_state_registered, and its metadata keeps its declaration order.
pub fn plugin_register(reg: &Registry, spec: &PluginSpec) -> Result[Registry, Str] {
  let name = spec.name;
  if string.str_len(name) == 0 {
    return _reg_err("plugin: empty plugin name");
  }
  let version = spec.version;
  let v = _semver_parse(version);
  if v.len() == 0 {
    return _reg_err("plugin: invalid version for " + name + ": " + version);
  }
  if _plugin_index(reg, name) >= 0 {
    return _reg_err("plugin: duplicate plugin: " + name);
  }
  let nd = spec.deps.len();
  var i = 0;
  while i < nd {
    let d: Str = spec.deps[i];
    if string.str_len(d) == 0 {
      return _reg_err("plugin: empty dependency name for " + name);
    }
    if _streq(d, name) {
      return _reg_err("plugin: self dependency for " + name);
    }
    var j = 0;
    while j < i {
      let prev: Str = spec.deps[j];
      if _streq(prev, d) {
        return _reg_err("plugin: duplicate dependency " + d + " for " + name);
      }
      j = j + 1;
    }
    i = i + 1;
  }
  let nc = spec.caps.len();
  i = 0;
  while i < nc {
    let c: Str = spec.caps[i];
    if string.str_len(c) == 0 {
      return _reg_err("plugin: empty capability name for " + name);
    }
    var j = 0;
    while j < i {
      let prev: Str = spec.caps[j];
      if _streq(prev, c) {
        return _reg_err("plugin: duplicate capability " + c + " for " + name);
      }
      j = j + 1;
    }
    i = i + 1;
  }
  var out = _copy_registry(reg);
  let idx = out.names.len();
  out.names.push(name);
  out.versions.push(version);
  out.states.push(plugin_state_registered);
  i = 0;
  while i < nd {
    let d: Str = spec.deps[i];
    out.dep_owner.push(idx);
    out.dep_name.push(d);
    i = i + 1;
  }
  i = 0;
  while i < nc {
    let c: Str = spec.caps[i];
    out.cap_owner.push(idx);
    out.cap_name.push(c);
    i = i + 1;
  }
  return _reg_ok(out);
}

// --------------------------------------------------
//  Metadata lookup
// --------------------------------------------------

/// Number of registered plugins.
pub fn plugin_count(reg: &Registry) -> Int {
  return reg.names.len();
}

/// Registered plugin names in registration order (a fresh copy).
pub fn plugin_names(reg: &Registry) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < reg.names.len() {
    let n: Str = reg.names[i];
    out.push(n);
    i = i + 1;
  }
  return out;
}

/// True when `name` is registered.
pub fn plugin_has(reg: &Registry, name: Str) -> Bool {
  return _plugin_index(reg, name) >= 0;
}

/// Registration index of `name` (0-based), or -1 when absent. Registration
/// order is the tie-break used by plugin_resolve.
pub fn plugin_index(reg: &Registry, name: Str) -> Int {
  return _plugin_index(reg, name);
}

/// Registered version of `name`; None when the plugin is unknown.
pub fn plugin_version(reg: &Registry, name: Str) -> Option[Str] {
  let i = _plugin_index(reg, name);
  if i < 0 {
    return None;
  }
  let v: Str = reg.versions[i];
  return Some(v);
}

/// Dependency names declared by `name` in declaration order (a fresh copy,
/// empty when the plugin is unknown).
pub fn plugin_deps(reg: &Registry, name: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let i = _plugin_index(reg, name);
  if i < 0 {
    return out;
  }
  let k = _dep_count(reg, i);
  var j = 0;
  while j < k {
    let d = _dep_at(reg, i, j);
    out.push(d);
    j = j + 1;
  }
  return out;
}

/// Lifecycle state of `name`: one of the plugin_state_* constants, or -1
/// when the plugin is unknown.
pub fn plugin_state(reg: &Registry, name: Str) -> Int {
  let i = _plugin_index(reg, name);
  if i < 0 {
    return -1;
  }
  let s: Int = reg.states[i];
  return s;
}

/// Human-readable name of a plugin_state_* value ("registered", "enabled",
/// "active", or "unknown").
pub fn plugin_state_name(state: Int) -> Str {
  if state == plugin_state_registered {
    return "registered";
  }
  if state == plugin_state_enabled {
    return "enabled";
  }
  if state == plugin_state_active {
    return "active";
  }
  return "unknown";
}

/// Number of registered plugins currently in `state`.
pub fn plugin_count_by_state(reg: &Registry, state: Int) -> Int {
  var k = 0;
  var i = 0;
  while i < reg.states.len() {
    let s: Int = reg.states[i];
    if s == state {
      k = k + 1;
    }
    i = i + 1;
  }
  return k;
}

// --------------------------------------------------
//  Capability lookup
// --------------------------------------------------

/// Declared capabilities of `name` in declaration order (a fresh copy, empty
/// when the plugin is unknown).
pub fn plugin_capabilities(reg: &Registry, name: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let i = _plugin_index(reg, name);
  if i < 0 {
    return out;
  }
  let k = _cap_count(reg, i);
  var j = 0;
  while j < k {
    let c = _cap_at(reg, i, j);
    out.push(c);
    j = j + 1;
  }
  return out;
}

/// True when `name` declares the capability `cap`.
pub fn plugin_has_capability(reg: &Registry, name: Str, cap: Str) -> Bool {
  let i = _plugin_index(reg, name);
  if i < 0 {
    return false;
  }
  let k = _cap_count(reg, i);
  var j = 0;
  while j < k {
    let c = _cap_at(reg, i, j);
    if _streq(c, cap) {
      return true;
    }
    j = j + 1;
  }
  return false;
}

/// First registered provider of `cap` (registration order), or None when no
/// plugin declares it.
pub fn plugin_find_capability(reg: &Registry, cap: Str) -> Option[Str] {
  var i = 0;
  while i < reg.cap_name.len() {
    let c: Str = reg.cap_name[i];
    if _streq(c, cap) {
      let o: Int = reg.cap_owner[i];
      let n: Str = reg.names[o];
      return Some(n);
    }
    i = i + 1;
  }
  return None;
}

/// Every provider of `cap` in registration order (a fresh copy; duplicate
/// providers are allowed and all are listed).
pub fn plugin_providers(reg: &Registry, cap: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < reg.cap_name.len() {
    let c: Str = reg.cap_name[i];
    if _streq(c, cap) {
      let o: Int = reg.cap_owner[i];
      let n: Str = reg.names[o];
      out.push(n);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Versions and range constraints
// --------------------------------------------------

/// True when `v` is a strict semantic version: exactly three dot-separated
/// numeric components, no leading zeros, each component <= 2147483647, and no
/// pre-release or build suffix.
pub fn plugin_version_valid(v: Str) -> Bool {
  let p = _semver_parse(v);
  return p.len() == 3;
}

/// Compare two strict semantic versions: Ok(-1) when a < b, Ok(0) when equal,
/// Ok(1) when a > b; Err("plugin: invalid version: <v>") for a malformed
/// version.
pub fn plugin_version_cmp(a: Str, b: Str) -> Result[Int, Str] {
  let va = _semver_parse(a);
  if va.len() == 0 {
    return _int_err("plugin: invalid version: " + a);
  }
  let vb = _semver_parse(b);
  if vb.len() == 0 {
    return _int_err("plugin: invalid version: " + b);
  }
  return _int_ok(_ver_cmp3(&va, &vb));
}

/// Check a strict semantic version against a range expression. The range is a
/// comma/whitespace separated list of comparators, all of which must hold
/// (logical AND); `*` matches any valid version. Comparator forms:
/// `=v`/`==v`/bare `v` (exact), `>v`, `>=v`, `<v`, `<=v`, `^v` (compatible:
/// `>=v` and below the next non-zero leading component) and `~v` (patch-level:
/// `>=v` and `<major.minor+1.0`). Comparators are written without internal
/// whitespace. Returns Ok(Bool), Err("plugin: invalid version: <v>") for a
/// malformed version, Err("plugin: empty range") when the range has no
/// comparator, or Err("plugin: invalid range token: <tok>") for a malformed
/// comparator.
pub fn plugin_check_constraint(version: Str, range: Str) -> Result[Bool, Str] {
  let v = _semver_parse(version);
  if v.len() == 0 {
    return _bool_err("plugin: invalid version: " + version);
  }
  let vmaj: Int = v[0];
  let vmin: Int = v[1];
  let vpat: Int = v[2];
  var ok = true;
  var any = false;
  let n = string.str_len(range);
  var i = 0;
  while i < n {
    while i < n && _is_delim(_byte(range, i)) {
      i = i + 1;
    }
    if i >= n {
      break;
    }
    let start = i;
    while i < n && !_is_delim(_byte(range, i)) {
      i = i + 1;
    }
    let tok = string.str_slice(range, start, i);
    let tlen = string.str_len(tok);
    var op = _PL_OP_EQ;
    var rest = tok;
    let c0 = _byte(tok, 0);
    if c0 == _PL_GREATER {
      if tlen >= 2 && _byte(tok, 1) == _PL_EQ {
        op = _PL_OP_GE;
        rest = string.str_slice(tok, 2, tlen);
      } else {
        op = _PL_OP_GT;
        rest = string.str_slice(tok, 1, tlen);
      }
    } elif c0 == _PL_LESS {
      if tlen >= 2 && _byte(tok, 1) == _PL_EQ {
        op = _PL_OP_LE;
        rest = string.str_slice(tok, 2, tlen);
      } else {
        op = _PL_OP_LT;
        rest = string.str_slice(tok, 1, tlen);
      }
    } elif c0 == _PL_EQ {
      if tlen >= 2 && _byte(tok, 1) == _PL_EQ {
        rest = string.str_slice(tok, 2, tlen);
      } else {
        rest = string.str_slice(tok, 1, tlen);
      }
    } elif c0 == _PL_CARET {
      op = _PL_OP_CARET;
      rest = string.str_slice(tok, 1, tlen);
    } elif c0 == _PL_TILDE {
      op = _PL_OP_TILDE;
      rest = string.str_slice(tok, 1, tlen);
    }
    any = true;
    if _streq(tok, "*") {
      continue;
    }
    let rv = _semver_parse(rest);
    if rv.len() == 0 {
      return _bool_err("plugin: invalid range token: " + tok);
    }
    let rmaj: Int = rv[0];
    let rmin: Int = rv[1];
    let rpat: Int = rv[2];
    let lo = _cmp3(vmaj, vmin, vpat, rmaj, rmin, rpat);
    if op == _PL_OP_EQ {
      if lo != 0 {
        ok = false;
      }
    } elif op == _PL_OP_GT {
      if lo <= 0 {
        ok = false;
      }
    } elif op == _PL_OP_GE {
      if lo < 0 {
        ok = false;
      }
    } elif op == _PL_OP_LT {
      if lo >= 0 {
        ok = false;
      }
    } elif op == _PL_OP_LE {
      if lo > 0 {
        ok = false;
      }
    } elif op == _PL_OP_CARET {
      if lo < 0 {
        ok = false;
      }
      var umaj = rmaj;
      var umin = 0;
      var upat = 0;
      if rmaj > 0 {
        umaj = rmaj + 1;
      } elif rmin > 0 {
        umaj = 0;
        umin = rmin + 1;
      } else {
        umaj = 0;
        umin = 0;
        upat = rpat + 1;
      }
      if _cmp3(vmaj, vmin, vpat, umaj, umin, upat) >= 0 {
        ok = false;
      }
    } else {
      if lo < 0 {
        ok = false;
      }
      if _cmp3(vmaj, vmin, vpat, rmaj, rmin + 1, 0) >= 0 {
        ok = false;
      }
    }
  }
  if !any {
    return _bool_err("plugin: empty range");
  }
  return _bool_ok(ok);
}

/// True when `version` satisfies `range`; False when either side is malformed
/// (see plugin_check_constraint for the error cases).
pub fn plugin_satisfies(version: Str, range: Str) -> Bool {
  let r = plugin_check_constraint(version, range);
  match r {
    Ok(b) => {
      return b;
    },
    Err(_) => {
      return false;
    },
  }
  return false;
}

/// True when `owner` declares `dep` and the registered version of `dep`
/// satisfies `range`. False when either plugin is unknown, `dep` is not
/// declared by `owner`, or the version/range is malformed.
pub fn plugin_dependency_satisfied(reg: &Registry, owner: Str, dep: Str, range: Str) -> Bool {
  let oi = _plugin_index(reg, owner);
  if oi < 0 {
    return false;
  }
  let di = _plugin_index(reg, dep);
  if di < 0 {
    return false;
  }
  if !_depends_on(reg, oi, di) {
    return false;
  }
  let dv: Str = reg.versions[di];
  return plugin_satisfies(dv, range);
}

// --------------------------------------------------
//  Dependency-order resolution
// --------------------------------------------------

// Render the residual cycle after a stalled Kahn pass: start at the lowest
// not-yet-emitted index, follow first not-yet-emitted dependencies until a
// node repeats, and print the repeated segment plus the closing edge.
fn _cycle_message(reg: &Registry, done: &Vec[Int]) -> Str {
  let n = reg.names.len();
  var start = -1;
  var i = 0;
  while i < n {
    let d: Int = done[i];
    if d == 0 {
      start = i;
      break;
    }
    i = i + 1;
  }
  if start < 0 {
    return "plugin: dependency cycle";
  }
  var path_names = Vec[Str].new();
  var path_idx = Vec[Int].new();
  var cur = start;
  while true {
    let cn: Str = reg.names[cur];
    var found = -1;
    var j = 0;
    while j < path_idx.len() {
      let pj: Int = path_idx[j];
      if pj == cur {
        found = j;
        break;
      }
      j = j + 1;
    }
    if found >= 0 {
      var msg = "plugin: dependency cycle: ";
      var first = true;
      var k = found;
      while k < path_names.len() {
        let pn: Str = path_names[k];
        if !first {
          msg = msg + " -> ";
        }
        msg = msg + pn;
        first = false;
        k = k + 1;
      }
      msg = msg + " -> " + cn;
      return msg;
    }
    path_names.push(cn);
    path_idx.push(cur);
    let dcount = _dep_count(reg, cur);
    var next = -1;
    var m = 0;
    while m < dcount {
      let dn = _dep_at(reg, cur, m);
      let dni = _plugin_index(reg, dn);
      if dni >= 0 {
        let dd: Int = done[dni];
        if dd == 0 {
          next = dni;
          break;
        }
      }
      m = m + 1;
    }
    if next < 0 {
      return "plugin: dependency cycle: " + cn;
    }
    cur = next;
  }
  return "plugin: dependency cycle";
}

/// Resolve the registry into a deterministic activation order: every
/// dependency appears before its dependents (Kahn's algorithm). Ready plugins
/// are emitted in registration order, so the result is stable. Returns
/// Err("plugin: missing dependency: <dep> (required by <owner>)") when a
/// declared dependency is not registered, and
/// Err("plugin: dependency cycle: <a> -> <b> -> ... -> <a>") when the
/// dependency graph contains a cycle.
pub fn plugin_resolve(reg: &Registry) -> Result[Vec[Str], Str] {
  let n = reg.names.len();
  var indeg = Vec[Int].new();
  var i = 0;
  while i < n {
    indeg.push(0);
    i = i + 1;
  }
  i = 0;
  while i < n {
    let k = _dep_count(reg, i);
    var j = 0;
    while j < k {
      let d = _dep_at(reg, i, j);
      let di = _plugin_index(reg, d);
      if di < 0 {
        let owner: Str = reg.names[i];
        return _names_err("plugin: missing dependency: " + d + " (required by " + owner + ")");
      }
      let cur: Int = indeg[i];
      indeg[i] = cur + 1;
      j = j + 1;
    }
    i = i + 1;
  }
  var done = Vec[Int].new();
  i = 0;
  while i < n {
    done.push(0);
    i = i + 1;
  }
  var out = Vec[Str].new();
  var emitted = 0;
  while emitted < n {
    var pick = -1;
    i = 0;
    while i < n {
      let d: Int = done[i];
      if d == 0 {
        let g: Int = indeg[i];
        if g == 0 {
          pick = i;
          break;
        }
      }
      i = i + 1;
    }
    if pick < 0 {
      return _names_err(_cycle_message(reg, &done));
    }
    let name: Str = reg.names[pick];
    out.push(name);
    done[pick] = 1;
    var j = 0;
    while j < n {
      let dj: Int = done[j];
      if dj == 0 && _depends_on(reg, j, pick) {
        let g: Int = indeg[j];
        indeg[j] = g - 1;
      }
      j = j + 1;
    }
    emitted = emitted + 1;
  }
  return _names_ok(out);
}

// --------------------------------------------------
//  Lifecycle state machine
// --------------------------------------------------

/// Transition a plugin from registered to enabled. Errors:
/// Err("plugin: unknown plugin: <name>") or
/// Err("plugin: cannot enable <name>: state is <state>").
pub fn plugin_enable(reg: &Registry, name: Str) -> Result[Registry, Str] {
  let i = _plugin_index(reg, name);
  if i < 0 {
    return _reg_err("plugin: unknown plugin: " + name);
  }
  let s: Int = reg.states[i];
  if s != plugin_state_registered {
    return _reg_err("plugin: cannot enable " + name + ": state is " + plugin_state_name(s));
  }
  return _reg_ok(_set_state(reg, i, plugin_state_enabled));
}

/// Transition a plugin from enabled back to registered. Errors:
/// Err("plugin: unknown plugin: <name>") or
/// Err("plugin: cannot disable <name>: state is <state>") (an active plugin
/// must be deactivated first).
pub fn plugin_disable(reg: &Registry, name: Str) -> Result[Registry, Str] {
  let i = _plugin_index(reg, name);
  if i < 0 {
    return _reg_err("plugin: unknown plugin: " + name);
  }
  let s: Int = reg.states[i];
  if s != plugin_state_enabled {
    return _reg_err("plugin: cannot disable " + name + ": state is " + plugin_state_name(s));
  }
  return _reg_ok(_set_state(reg, i, plugin_state_registered));
}

/// Transition a plugin from enabled to active. Every declared dependency must
/// be enabled or active. Errors:
/// Err("plugin: unknown plugin: <name>"),
/// Err("plugin: cannot activate <name>: state is <state>") or
/// Err("plugin: cannot activate <name>: dependency not enabled: <dep>").
pub fn plugin_activate(reg: &Registry, name: Str) -> Result[Registry, Str] {
  let i = _plugin_index(reg, name);
  if i < 0 {
    return _reg_err("plugin: unknown plugin: " + name);
  }
  let s: Int = reg.states[i];
  if s != plugin_state_enabled {
    return _reg_err("plugin: cannot activate " + name + ": state is " + plugin_state_name(s));
  }
  let bad = _unready_dep(reg, i, plugin_state_enabled);
  if string.str_len(bad) > 0 {
    return _reg_err("plugin: cannot activate " + name + ": dependency not enabled: " + bad);
  }
  return _reg_ok(_set_state(reg, i, plugin_state_active));
}

/// Transition a plugin from active back to enabled. No active plugin may
/// depend on it. Errors: Err("plugin: unknown plugin: <name>"),
/// Err("plugin: cannot deactivate <name>: state is <state>") or
/// Err("plugin: cannot deactivate <name>: active dependent: <dep>").
pub fn plugin_deactivate(reg: &Registry, name: Str) -> Result[Registry, Str] {
  let i = _plugin_index(reg, name);
  if i < 0 {
    return _reg_err("plugin: unknown plugin: " + name);
  }
  let s: Int = reg.states[i];
  if s != plugin_state_active {
    return _reg_err("plugin: cannot deactivate " + name + ": state is " + plugin_state_name(s));
  }
  let dep = _active_dependent(reg, i);
  if string.str_len(dep) > 0 {
    return _reg_err("plugin: cannot deactivate " + name + ": active dependent: " + dep);
  }
  return _reg_ok(_set_state(reg, i, plugin_state_enabled));
}

/// Enable every registered plugin in plugin_resolve order. Returns the same
/// errors as plugin_resolve (missing dependency or cycle).
pub fn plugin_enable_all(reg: &Registry) -> Result[Registry, Str] {
  let order = plugin_resolve(reg);
  match order {
    Ok(names) => {
      var out = _copy_registry(reg);
      var i = 0;
      while i < names.len() {
        let n: Str = names[i];
        let idx = _plugin_index(&out, n);
        out.states[idx] = plugin_state_enabled;
        i = i + 1;
      }
      return _reg_ok(out);
    },
    Err(e) => {
      let msg: Str = e;
      return _reg_err(msg);
    },
  }
  return _reg_err("plugin: internal error");
}

/// Activate every registered plugin in plugin_resolve order (dependencies
/// first, so the per-plugin precondition of plugin_activate always holds when
/// the registry is resolvable). Returns the same errors as plugin_resolve.
pub fn plugin_activate_all(reg: &Registry) -> Result[Registry, Str] {
  let order = plugin_resolve(reg);
  match order {
    Ok(names) => {
      var out = _copy_registry(reg);
      var i = 0;
      while i < names.len() {
        let n: Str = names[i];
        let idx = _plugin_index(&out, n);
        let st: Int = out.states[idx];
        if st != plugin_state_enabled {
          return _reg_err("plugin: cannot activate " + n + ": state is " + plugin_state_name(st));
        }
        out.states[idx] = plugin_state_active;
        i = i + 1;
      }
      return _reg_ok(out);
    },
    Err(e) => {
      let msg: Str = e;
      return _reg_err(msg);
    },
  }
  return _reg_err("plugin: internal error");
}
