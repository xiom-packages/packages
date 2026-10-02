// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.helm: chart manifests, values and shared primitives
// Port task: promote the xiom.helm placeholder to a real, tested, pure-XIOM
// package. This module holds the Chart model (Chart.yaml subset: apiVersion/
// name/version/appVersion/description) and the Values model (flat dotted-path
// scalars with Helm-style deep-merge precedence). Shared validators live in
// xiom.helm.base. See SPEC.md for the exact grammars.
//
// Model notes (compiler v0.62.2):
//   * Free functions only; no closures, no Vec[StructType] -- entries are
//     parallel homogeneous vectors, exactly like xiom.config.
//   * Str equality always goes through base.helm_streq / str_compare: `==` on
//     Str values read from Vec[Str] elements mislowers to a pointer compare.
//   * Every byte read is widened and masked ((b as Int) & 0xFF) by _byte
//     before any comparison.
//   * Ok/Err for struct payloads are built only in the tiny leaf helpers
//     _chart_ok/_chart_err and _values_ok/_values_err.
//   * Values::keys and Values::vals are pushed only by _vpush, so the
//     parallel vectors cannot drift; every reader guards with _vmin_len.

module xiom.helm

use xiom.string;
use xiom.helm.base;

// --------------------------------------------------
//  Result leaf constructors (struct payloads only)
// --------------------------------------------------

fn _chart_ok(c: Chart) -> Result[Chart, Str] {
  return Ok(c);
}

fn _chart_err(m: Str) -> Result[Chart, Str] {
  return Err(m);
}

fn _values_ok(v: Values) -> Result[Values, Str] {
  return Ok(v);
}

fn _values_err(m: Str) -> Result[Values, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Private byte helpers
// --------------------------------------------------

const _HASH: Int = 35;
const _DQUOTE: Int = 34;
const _CR: Int = 13;
const _DOT: Int = 46;
const _COLON: Int = 58;

// Widen and mask one byte of `s` (comparisons on raw UInt8 >= 128 miscompile).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// First ':' in `line`, or -1.
fn _find_colon(line: Str) -> Int {
  var i = 0;
  let n = string.str_len(line);
  while i < n {
    if _byte(line, i) == _COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Drop one trailing CR (line splitting is done on LF).
fn _strip_cr(s: Str) -> Str {
  let n = string.str_len(s);
  if n > 0 && _byte(s, n - 1) == _CR {
    return string.str_slice(s, 0, n - 1);
  }
  return s;
}

// Strip one pair of surrounding double quotes; no escapes exist in the subset.
fn _unquote(s: Str) -> Str {
  let n = string.str_len(s);
  if n >= 2 && _byte(s, 0) == _DQUOTE && _byte(s, n - 1) == _DQUOTE {
    return string.str_slice(s, 1, n - 1);
  }
  return s;
}

// True when `child` is a strict descendant of `parent` ("a.b.c" under "a.b").
fn _is_under(child: Str, parent: Str) -> Bool {
  let pn = string.str_len(parent);
  let cn = string.str_len(child);
  if pn == 0 || cn < pn + 2 {
    return false;
  }
  if !string.str_starts_with(child, parent) {
    return false;
  }
  return _byte(child, pn) == _DOT;
}

// --------------------------------------------------
//  Chart model
// --------------------------------------------------

/// A Chart.yaml subset: the five recognized top-level keys. Values are plain
/// text; presence and semantics are checked by chart_validate.
pub type Chart = {
  api_version: Str;
  name: Str;
  version: Str;
  app_version: Str;
  description: Str;
}

/// A chart with apiVersion "v2", the given name/version and empty optional
/// fields. Err when the name or version is invalid (same rules as
/// chart_validate). Use chart_parse for Chart.yaml text.
pub fn chart_new(name: Str, version: Str) -> Result[Chart, Str] {
  if !base.helm_dns_name_valid(name, base.HELM_CHART_NAME_MAX) {
    return _chart_err("chart: invalid chart name: " + name);
  }
  if !base.helm_semver_valid(version) {
    return _chart_err("chart: invalid chart version: " + version);
  }
  return _chart_ok(Chart{ api_version: "v2"; name: name; version: version; app_version: ""; description: ""; });
}

/// Parse a Chart.yaml subset. Grammar (SPEC.md section 3): LF/CRLF/CR lines;
/// blank lines and lines whose first non-space byte is '#' are skipped; every
/// other line is `key: value` where value may be double-quoted. The five
/// recognized keys are apiVersion, name, version, appVersion and description;
/// unknown keys are ignored (forward-compatible subset). Duplicate keys are
/// last-wins. Parse checks syntax only: chart_validate reports missing or
/// semantically invalid fields.
pub fn chart_parse(text: Str) -> Result[Chart, Str] {
  if base.helm_has_nul(text) {
    return _chart_err("chart: NUL byte in input");
  }
  if string.str_len(text) > base.HELM_MAX_INPUT {
    return _chart_err("chart: input too large");
  }
  var api = "";
  var nm = "";
  var ver = "";
  var app = "";
  var desc = "";
  let lines = string.str_split(text, "\n");
  let ln = lines.len();
  var li = 0;
  while li < ln {
    let raw0: Str = lines[li];
    let line = string.str_trim(_strip_cr(raw0));
    let n = string.str_len(line);
    if n == 0 {
      li = li + 1;
      continue;
    }
    if _byte(line, 0) == _HASH {
      li = li + 1;
      continue;
    }
    let colon = _find_colon(line);
    if colon < 0 {
      return _chart_err("chart: expected ':' in line: " + line);
    }
    let key = string.str_trim(string.str_slice(line, 0, colon));
    if string.str_len(key) == 0 {
      return _chart_err("chart: missing key in line: " + line);
    }
    let val = _unquote(string.str_trim(string.str_slice(line, colon + 1, n)));
    if base.helm_streq(key, "apiVersion") {
      api = val;
    } elif base.helm_streq(key, "name") {
      nm = val;
    } elif base.helm_streq(key, "version") {
      ver = val;
    } elif base.helm_streq(key, "appVersion") {
      app = val;
    } elif base.helm_streq(key, "description") {
      desc = val;
    }
    li = li + 1;
  }
  return _chart_ok(Chart{ api_version: api; name: nm; version: ver; app_version: app; description: desc; });
}

/// Validate a chart, returning ALL errors in fixed field order
/// (apiVersion, name, version); an empty vector means valid. appVersion and
/// description are unconstrained (any text, including empty).
pub fn chart_validate(c: &Chart) -> Vec[Str] {
  var errs = Vec[Str].new();
  let api = c.api_version;
  if string.str_len(api) == 0 {
    errs.push("chart: missing apiVersion");
  } elif !base.helm_streq(api, "v1") && !base.helm_streq(api, "v2") {
    errs.push("chart: unsupported apiVersion: " + api);
  }
  let nm = c.name;
  if string.str_len(nm) == 0 {
    errs.push("chart: missing name");
  } elif !base.helm_dns_name_valid(nm, base.HELM_CHART_NAME_MAX) {
    errs.push("chart: invalid chart name: " + nm);
  }
  let ver = c.version;
  if string.str_len(ver) == 0 {
    errs.push("chart: missing version");
  } elif !base.helm_semver_valid(ver) {
    errs.push("chart: invalid chart version: " + ver);
  }
  return errs;
}

/// True when chart_validate finds no error.
pub fn chart_valid(c: &Chart) -> Bool {
  let errs = chart_validate(c);
  return errs.len() == 0;
}

/// Render a chart to canonical Chart.yaml subset text: always the five keys,
/// in order apiVersion, name, version, appVersion, description, LF separated,
/// no trailing LF, raw values. Round-trips through chart_parse for values
/// without line breaks (a value that itself starts and ends with '"' is
/// re-parsed with the quotes stripped). Empty optional fields render as
/// `appVersion:` / `description:`.
pub fn chart_render(c: &Chart) -> Str {
  var out = "apiVersion: " + c.api_version + "\n";
  out = out + "name: " + c.name + "\n";
  out = out + "version: " + c.version + "\n";
  out = out + "appVersion: " + c.app_version + "\n";
  out = out + "description: " + c.description;
  return out;
}

// --------------------------------------------------
//  Values model (flat dotted paths, Helm-style deep merge)
// --------------------------------------------------

/// A values map stored as flat dotted paths: `keys[i]` is a path such as
/// "image.tag" and `vals[i]` its scalar text, index-aligned. Paths are unique;
/// a "map" is implicit in the path structure. Build with values_set /
/// values_merge only: those enforce the deep-merge rules.
pub type Values = {
  keys: Vec[Str];
  vals: Vec[Str];
}

/// An empty values map.
pub fn values_new() -> Values {
  return Values{ keys: Vec[Str].new(); vals: Vec[Str].new(); };
}

// The single push site for both parallel vectors.
fn _vpush(v: &mut Values, key: Str, val: Str) {
  v.keys.push(key);
  v.vals.push(val);
}

// Safe aligned length of a Values map (min of the two vector lengths).
fn _vmin_len(v: &Values) -> Int {
  let a = v.keys.len();
  let b = v.vals.len();
  if a < b {
    return a;
  }
  return b;
}

// Deep copy of `v` (both vectors, aligned portion).
fn _copy_values(v: &Values) -> Values {
  var out = Values{ keys: Vec[Str].new(); vals: Vec[Str].new(); };
  let n = _vmin_len(v);
  var i = 0;
  while i < n {
    let k: Str = v.keys[i];
    let x: Str = v.vals[i];
    _vpush(&mut out, k, x);
    i = i + 1;
  }
  return out;
}

/// Number of entries.
pub fn values_len(v: &Values) -> Int {
  return _vmin_len(v);
}

/// Look up `path` (byte-exact); None when absent.
pub fn values_get(v: &Values, path: Str) -> Option[Str] {
  let n = _vmin_len(v);
  var i = 0;
  while i < n {
    let k: Str = v.keys[i];
    if base.helm_streq(k, path) {
      let x: Str = v.vals[i];
      return Some(x);
    }
    i = i + 1;
  }
  return None;
}

/// True when `path` is present.
pub fn values_has(v: &Values, path: Str) -> Bool {
  let o = values_get(v, path);
  match o {
    Some(_) => { return true; },
    None => { return false; },
  }
  return false;
}

/// All entries as index-aligned copies (keys, vals), in insertion order.
pub fn values_entries(v: &Values) -> (Vec[Str], Vec[Str]) {
  var ks = Vec[Str].new();
  var vs = Vec[Str].new();
  let n = _vmin_len(v);
  var i = 0;
  while i < n {
    let k: Str = v.keys[i];
    let x: Str = v.vals[i];
    ks.push(k);
    vs.push(x);
    i = i + 1;
  }
  return (ks, vs);
}

// Deep-set core: `path` replaces anything it conflicts with (equal path,
// descendants of the path, and strict ancestor scalars); the first conflicting
// base entry keeps the position.
fn _vconflict(a: Str, b: Str) -> Bool {
  if base.helm_streq(a, b) {
    return true;
  }
  if _is_under(a, b) {
    return true;
  }
  return _is_under(b, a);
}

fn _vset(base_map: &Values, path: Str, value: Str) -> Values {
  var out = Values{ keys: Vec[Str].new(); vals: Vec[Str].new(); };
  let n = _vmin_len(base_map);
  var placed = false;
  var i = 0;
  while i < n {
    let k: Str = base_map.keys[i];
    let x: Str = base_map.vals[i];
    if _vconflict(k, path) {
      if !placed {
        _vpush(&mut out, path, value);
        placed = true;
      }
    } else {
      _vpush(&mut out, k, x);
    }
    i = i + 1;
  }
  if !placed {
    _vpush(&mut out, path, value);
  }
  return out;
}

/// Set `path` to `value` with deep semantics, in a new Values map: an equal
/// path is replaced in place; a path replaces any descendant entries and any
/// strict ancestor scalar (the first conflicting entry keeps its position).
/// Err on a malformed path (see helm_values_path_valid). `v` is untouched.
pub fn values_set(v: &Values, path: Str, value: Str) -> Result[Values, Str] {
  if !base.helm_values_path_valid(path) {
    return _values_err("values: malformed path: " + path);
  }
  return _values_ok(_vset(v, path, value));
}

/// Deep merge with later-source-wins precedence: every overlay entry is
/// applied with values_set's deep rules (equal path replaced in place,
/// descendants dropped, ancestor scalars replaced by the subtree). Base
/// ordering is kept; overlay-only conflicts append in overlay order. Neither
/// input is modified. Err on a malformed overlay path.
pub fn values_merge(base_map: &Values, overlay: &Values) -> Result[Values, Str] {
  var out = _copy_values(base_map);
  let n = _vmin_len(overlay);
  var i = 0;
  while i < n {
    let k: Str = overlay.keys[i];
    let x: Str = overlay.vals[i];
    if !base.helm_values_path_valid(k) {
      return _values_err("values: malformed path: " + k);
    }
    let r = values_set(&out, k, x);
    match r {
      Ok(m) => { out = m; },
      Err(e) => { return _values_err(e); },
    }
    i = i + 1;
  }
  return _values_ok(out);
}

/// Resolve a three-source precedence chain: defaults <- file <- overrides
/// (later source wins), i.e. values_merge(values_merge(defaults, file),
/// overrides).
pub fn values_resolve(defaults: &Values, file: &Values, overrides: &Values) -> Result[Values, Str] {
  let r1 = values_merge(defaults, file);
  match r1 {
    Ok(m1) => {
      return values_merge(&m1, overrides);
    },
    Err(e) => {
      return _values_err(e);
    },
  }
  return _values_err("values: merge failed");
}

/// Render a values map to canonical `path: value` lines in insertion order,
/// LF separated, no trailing LF. Empty map renders as "".
pub fn values_render(v: &Values) -> Str {
  var out = "";
  let n = _vmin_len(v);
  var i = 0;
  while i < n {
    if i > 0 {
      out = out + "\n";
    }
    let k: Str = v.keys[i];
    let x: Str = v.vals[i];
    out = out + k + ": " + x;
    i = i + 1;
  }
  return out;
}
