// XIOM -- xiom.layers: layered configuration over dotted keys
// Port task: promote the xiom.layers placeholder to a real, tested, pure-XIOM
// package: an ordered stack of string-keyed layers resolved with later-wins
// precedence, explicit replace/append/delete sentinels, provenance tracking
// (which layer won), shadowed-value queries, flattening to a final map and a
// layer-to-layer diff. Text/map in, map out: no file IO, no environment.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a LayerStack holds parallel vectors only (Vec[StructType] is
// unsupported in this compiler): `names` lists layer names in precedence
// order (index 0 = lowest precedence), `keys`/`vals`/`owner` hold every
// entry in layer order, and `owner[i]` is the layer index of entry i. Every
// push on one entry vector is mirrored on the other two (parallel-vector
// invariant). Within one layer keys are unique, so a layer is a map; across
// layers the same key may appear repeatedly, which is what precedence is.
//
// Resolution semantics (SPEC.md states them precisely):
//   * Later layers win per exact dotted key path; a key keeps the position
//     of its first introduction.
//   * A plain value sets the key. "!replace:<text>" is the explicit form of
//     the same operation. "!append:<text>" folds onto the accumulated value
//     with "," as separator, or starts fresh when the key was absent or
//     deleted. The exact value "!delete" tombstones the key; a later entry
//     resurrects it. A value starting with "!!" is an escape: one "!" is
//     stripped and the rest is stored literally.
//   * Deletes are path-exact: deleting "server" does not delete "server.port".
//   * Provenance is the layer of the last entry for a key, whatever its
//     kind; for an append chain that is the last appender.
//
// v0.62.1 notes that shaped this module:
//   * Ok/Err for Result[LayerStack, Str] / Result[LayerDiff, Str] are built
//     only in the leaf helpers _stack_ok/_stack_err and _diff_ok/_diff_err.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); every comparison is routed through _streq.
//   * Every byte read is widened and masked ((b as Int) & 0xFF) before any
//     comparison.
//   * Rendering concatenates Str directly (no sb_to_str), so no NUL sentinel
//     can ever truncate the output.

module xiom.layers

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Sentinel and byte constants
// --------------------------------------------------

const _TL_APPEND: Str = "!append:";
const _TL_REPLACE: Str = "!replace:";
const _TL_DELETE: Str = "!delete";
const _TL_ESCAPE: Str = "!!";
const _TL_SEP: Str = ",";

const _TL_KIND_PLAIN: Int = 0;
const _TL_KIND_REPLACE: Int = 1;
const _TL_KIND_APPEND: Int = 2;
const _TL_KIND_DELETE: Int = 3;
const _TL_KIND_LITERAL: Int = 4;

const _TL_DOT: Int = 46;
const _TL_SPACE: Int = 32;
const _TL_EQ: Int = 61;
const _TL_LBRACKET: Int = 91;
const _TL_RBRACKET: Int = 93;
const _TL_HASH: Int = 35;
const _TL_SEMI: Int = 59;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// An ordered stack of configuration layers. `names` are the layer names in
/// precedence order (index 0 = lowest precedence, last index = highest).
/// `keys`/`vals`/`owner` are index-aligned parallel vectors holding every
/// entry in layer order; `owner[e]` is the layer index of entry `e`. Build
/// stacks with layers_new/layers_add to keep the invariants.
pub type LayerStack = {
  names: Vec[Str];
  keys: Vec[Str];
  vals: Vec[Str];
  owner: Vec[Int];
}

/// A flattened configuration: `keys` and `vals` are index-aligned live
/// entries in first-introduction order; `layer[i]` is the winning layer
/// index for `keys[i]` (provenance). Deleted keys are absent.
pub type FlatMap = {
  keys: Vec[Str];
  vals: Vec[Str];
  layer: Vec[Int];
}

/// A layer-to-layer diff over raw entry text: keys only in the other layer
/// (`added`, other-layer order), keys only in the base layer (`removed`,
/// base-layer order) and keys present in both with different raw values
/// (`changed`, base-layer order).
pub type LayerDiff = {
  added: Vec[Str];
  removed: Vec[Str];
  changed: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(s) for Result[LayerStack, Str].
fn _stack_ok(s: LayerStack) -> Result[LayerStack, Str] {
  return Ok(s);
}

// Err(m) for Result[LayerStack, Str].
fn _stack_err(m: Str) -> Result[LayerStack, Str] {
  return Err(m);
}

// Ok(d) for Result[LayerDiff, Str].
fn _diff_ok(d: LayerDiff) -> Result[LayerDiff, Str] {
  return Ok(d);
}

// Err(m) for Result[LayerDiff, Str].
fn _diff_err(m: Str) -> Result[LayerDiff, Str] {
  return Err(m);
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

// --------------------------------------------------
//  Sentinel grammar
// --------------------------------------------------

// Classify a raw entry value. The "!!" escape is checked first so a literal
// "!append:"-looking text never parses as a sentinel.
fn _kind_of(v: Str) -> Int {
  if string.str_starts_with(v, _TL_ESCAPE) {
    return _TL_KIND_LITERAL;
  }
  if string.str_starts_with(v, _TL_REPLACE) {
    return _TL_KIND_REPLACE;
  }
  if string.str_starts_with(v, _TL_APPEND) {
    return _TL_KIND_APPEND;
  }
  if _streq(v, _TL_DELETE) {
    return _TL_KIND_DELETE;
  }
  return _TL_KIND_PLAIN;
}

// The stored text of a non-delete entry: the value itself for a plain entry,
// the text after the sentinel token for replace/append, and the value minus
// its first "!" for an escaped literal.
fn _payload_of(v: Str, kind: Int) -> Str {
  if kind == _TL_KIND_LITERAL {
    return string.str_slice(v, 1, v.len());
  }
  if kind == _TL_KIND_REPLACE {
    return string.str_slice(v, 9, v.len());
  }
  if kind == _TL_KIND_APPEND {
    return string.str_slice(v, 8, v.len());
  }
  return v;
}

/// True when the raw value is exactly the delete sentinel "!delete".
pub fn layers_is_delete(v: Str) -> Bool {
  return _kind_of(v) == _TL_KIND_DELETE;
}

/// True when the raw value starts with the append sentinel "!append:".
pub fn layers_is_append(v: Str) -> Bool {
  return _kind_of(v) == _TL_KIND_APPEND;
}

/// True when the raw value starts with the replace sentinel "!replace:".
pub fn layers_is_replace(v: Str) -> Bool {
  return _kind_of(v) == _TL_KIND_REPLACE;
}

/// True when the raw value starts with the escape "!!".
pub fn layers_is_escaped(v: Str) -> Bool {
  return _kind_of(v) == _TL_KIND_LITERAL;
}

// --------------------------------------------------
//  Key validation
// --------------------------------------------------

/// True when `k` is a valid dotted key: one or more non-empty segments of
/// bytes above space (32) that are not '=', '[', ']', '#', ';' or '.'. The
/// same rule xiom.config uses for its keys.
pub fn layers_key_valid(k: Str) -> Bool {
  let n = k.len();
  if n == 0 {
    return false;
  }
  var prev_dot = true;
  var i = 0;
  while i < n {
    let c = _byte(k, i);
    if c == _TL_DOT {
      if prev_dot {
        return false;
      }
      prev_dot = true;
    } else {
      if c <= _TL_SPACE {
        return false;
      }
      if c == _TL_EQ || c == _TL_LBRACKET || c == _TL_RBRACKET {
        return false;
      }
      if c == _TL_HASH || c == _TL_SEMI {
        return false;
      }
      prev_dot = false;
    }
    i = i + 1;
  }
  if prev_dot {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Stack construction
// --------------------------------------------------

/// An empty layer stack (no layers, no entries).
pub fn layers_new() -> LayerStack {
  return LayerStack{
    names: Vec[Str].new();
    keys: Vec[Str].new();
    vals: Vec[Str].new();
    owner: Vec[Int].new();
  };
}

// Deep copy of `s`: names and all three parallel entry vectors.
fn _copy_stack(s: &LayerStack) -> LayerStack {
  var out = LayerStack{
    names: Vec[Str].new();
    keys: Vec[Str].new();
    vals: Vec[Str].new();
    owner: Vec[Int].new();
  };
  var i = 0;
  while i < s.names.len() {
    let nm: Str = s.names[i];
    out.names.push(nm);
    i = i + 1;
  }
  var j = 0;
  while j < s.keys.len() {
    let k: Str = s.keys[j];
    let v: Str = s.vals[j];
    let o: Int = s.owner[j];
    out.keys.push(k);
    out.vals.push(v);
    out.owner.push(o);
    j = j + 1;
  }
  return out;
}

/// Append one layer on top of `s` (highest precedence) and return the new
/// stack; `s` itself is untouched. `keys[i]` pairs with `vals[i]`; both
/// vectors must have the same length and every key must be a valid dotted
/// key (layers_key_valid) and unique within this layer. The layer name must
/// be non-empty and unique across the stack. Err messages are
/// "layers: layer name must not be empty", "layers: keys and values are not
/// aligned", "layers: invalid key: <key>", "layers: duplicate key in layer:
/// <key>" and "layers: duplicate layer name: <name>".
pub fn layers_add(s: &LayerStack, name: Str, keys: &Vec[Str], vals: &Vec[Str]) -> Result[LayerStack, Str] {
  if name.len() == 0 {
    return _stack_err("layers: layer name must not be empty");
  }
  if keys.len() != vals.len() {
    return _stack_err("layers: keys and values are not aligned");
  }
  var i = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    if !layers_key_valid(k) {
      return _stack_err("layers: invalid key: " + k);
    }
    var j = 0;
    while j < i {
      let prev: Str = keys[j];
      if _streq(prev, k) {
        return _stack_err("layers: duplicate key in layer: " + k);
      }
      j = j + 1;
    }
    i = i + 1;
  }
  var d = 0;
  while d < s.names.len() {
    let existing: Str = s.names[d];
    if _streq(existing, name) {
      return _stack_err("layers: duplicate layer name: " + name);
    }
    d = d + 1;
  }
  var out = _copy_stack(s);
  let lay = s.names.len();
  var e = 0;
  while e < keys.len() {
    let k2: Str = keys[e];
    let v2: Str = vals[e];
    out.keys.push(k2);
    out.vals.push(v2);
    out.owner.push(lay);
    e = e + 1;
  }
  out.names.push(name);
  return _stack_ok(out);
}

/// Number of layers in the stack.
pub fn layers_count(s: &LayerStack) -> Int {
  return s.names.len();
}

/// Name of layer `i`, or None when `i` is out of range.
pub fn layers_name(s: &LayerStack, i: Int) -> Option[Str] {
  if i < 0 || i >= s.names.len() {
    return None;
  }
  let nm: Str = s.names[i];
  return Some(nm);
}

/// Number of entries in layer `i` (0 when `i` is out of range).
pub fn layers_layer_len(s: &LayerStack, i: Int) -> Int {
  if i < 0 || i >= s.names.len() {
    return 0;
  }
  var n = 0;
  var e = 0;
  while e < s.owner.len() {
    let o: Int = s.owner[e];
    if o == i {
      n = n + 1;
    }
    e = e + 1;
  }
  return n;
}

// --------------------------------------------------
//  Entry lookups
// --------------------------------------------------

// Index of the (unique) entry for `key` in `layer`, or -1.
fn _entry_of(s: &LayerStack, layer: Int, key: Str) -> Int {
  var e = 0;
  while e < s.keys.len() {
    let o: Int = s.owner[e];
    if o == layer {
      let k: Str = s.keys[e];
      if _streq(k, key) {
        return e;
      }
    }
    e = e + 1;
  }
  return -1;
}

// Index of the last entry for `key` in stack order, or -1 when the key never
// appears. The last entry is the winner: it determines liveness and (for a
// fold) contributed last.
fn _last_entry_of(s: &LayerStack, key: Str) -> Int {
  var e = s.keys.len() - 1;
  while e >= 0 {
    let k: Str = s.keys[e];
    if _streq(k, key) {
      return e;
    }
    e = e - 1;
  }
  return -1;
}

/// True when `key` appears in at least one layer (even if its winner is a
/// delete).
pub fn layers_has(s: &LayerStack, key: Str) -> Bool {
  return _last_entry_of(s, key) >= 0;
}

/// Provenance: the layer index of the last entry for `key` (the winning
/// layer, whether the entry sets, appends or deletes it), or None when the
/// key never appears.
pub fn layers_winner(s: &LayerStack, key: Str) -> Option[Int] {
  let e = _last_entry_of(s, key);
  if e < 0 {
    return None;
  }
  let o: Int = s.owner[e];
  return Some(o);
}

/// Layer indices of the losing entries for `key`: every entry for the key
/// before its winning (last) entry, in stack order. Empty when the key never
/// appears or has a single entry.
pub fn layers_shadowed_layers(s: &LayerStack, key: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let last = _last_entry_of(s, key);
  if last < 0 {
    return out;
  }
  var e = 0;
  while e < last {
    let k: Str = s.keys[e];
    if _streq(k, key) {
      let o: Int = s.owner[e];
      out.push(o);
    }
    e = e + 1;
  }
  return out;
}

/// Raw stored texts of the losing entries for `key`, aligned with
/// layers_shadowed_layers (sentinels appear verbatim, e.g. "!append:x").
pub fn layers_shadowed_values(s: &LayerStack, key: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let last = _last_entry_of(s, key);
  if last < 0 {
    return out;
  }
  var e = 0;
  while e < last {
    let k: Str = s.keys[e];
    if _streq(k, key) {
      let v: Str = s.vals[e];
      out.push(v);
    }
    e = e + 1;
  }
  return out;
}

// --------------------------------------------------
//  Resolution
// --------------------------------------------------

// Fold the whole stack into per-key state: out_keys/out_vals/out_layer/
// out_alive are index-aligned, in first-introduction order. `out_alive` is
// 1 for live keys and 0 for tombstoned keys (a key whose last entry is
// "!delete"); all four vectors are pushed and updated together.
fn _fold_states(s: &LayerStack, out_keys: &mut Vec[Str], out_vals: &mut Vec[Str], out_layer: &mut Vec[Int], out_alive: &mut Vec[Int]) {
  var e = 0;
  while e < s.keys.len() {
    let k: Str = s.keys[e];
    let v: Str = s.vals[e];
    let lay: Int = s.owner[e];
    let kind = _kind_of(v);
    var idx = -1;
    var q = 0;
    while q < out_keys.len() {
      let ek: Str = out_keys[q];
      if _streq(ek, k) {
        idx = q;
        break;
      }
      q = q + 1;
    }
    if idx < 0 {
      out_keys.push(k);
      out_layer.push(lay);
      if kind == _TL_KIND_DELETE {
        out_vals.push("");
        out_alive.push(0);
      } else {
        let p0 = _payload_of(v, kind);
        out_vals.push(p0);
        out_alive.push(1);
      }
    } else {
      out_layer[idx] = lay;
      if kind == _TL_KIND_DELETE {
        out_vals[idx] = "";
        out_alive[idx] = 0;
      } else {
        if kind == _TL_KIND_APPEND {
          let prev_alive: Int = out_alive[idx];
          let p1 = _payload_of(v, kind);
          if prev_alive == 0 {
            out_vals[idx] = p1;
          } else {
            let old: Str = out_vals[idx];
            let merged = old + _TL_SEP + p1;
            out_vals[idx] = merged;
          }
        } else {
          let p2 = _payload_of(v, kind);
          out_vals[idx] = p2;
        }
        out_alive[idx] = 1;
      }
    }
    e = e + 1;
  }
}

/// Resolve the whole stack to a FlatMap: live keys only, in
/// first-introduction order, with the winning layer index for each key.
/// A key whose last entry is "!delete" is absent; any later entry
/// resurrects it. Pure: the stack is not modified.
pub fn layers_flatten(s: &LayerStack) -> FlatMap {
  var st_keys = Vec[Str].new();
  var st_vals = Vec[Str].new();
  var st_layer = Vec[Int].new();
  var st_alive = Vec[Int].new();
  _fold_states(s, &mut st_keys, &mut st_vals, &mut st_layer, &mut st_alive);
  var mk = Vec[Str].new();
  var mv = Vec[Str].new();
  var ml = Vec[Int].new();
  var i = 0;
  while i < st_keys.len() {
    let alive: Int = st_alive[i];
    if alive != 0 {
      let k: Str = st_keys[i];
      let v: Str = st_vals[i];
      let l: Int = st_layer[i];
      mk.push(k);
      mv.push(v);
      ml.push(l);
    }
    i = i + 1;
  }
  return FlatMap{ keys: mk; vals: mv; layer: ml; };
}

/// Keys whose last entry is "!delete", in first-introduction order. A key
/// deleted and later revived is not a tombstone.
pub fn layers_tombstones(s: &LayerStack) -> Vec[Str] {
  var st_keys = Vec[Str].new();
  var st_vals = Vec[Str].new();
  var st_layer = Vec[Int].new();
  var st_alive = Vec[Int].new();
  _fold_states(s, &mut st_keys, &mut st_vals, &mut st_layer, &mut st_alive);
  var out = Vec[Str].new();
  var i = 0;
  while i < st_keys.len() {
    let alive: Int = st_alive[i];
    if alive == 0 {
      let k: Str = st_keys[i];
      out.push(k);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  FlatMap queries
// --------------------------------------------------

// Index of `key` in the map, or -1.
fn _map_index(m: &FlatMap, key: Str) -> Int {
  var i = 0;
  while i < m.keys.len() {
    let k: Str = m.keys[i];
    if _streq(k, key) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Number of live entries in the map.
pub fn flatmap_len(m: &FlatMap) -> Int {
  return m.keys.len();
}

/// True when the flattened map contains `key`.
pub fn flatmap_has(m: &FlatMap, key: Str) -> Bool {
  return _map_index(m, key) >= 0;
}

/// Flattened value of `key`, or None when absent (never present keys and
/// deleted keys are indistinguishable here, as both are absent).
pub fn flatmap_get(m: &FlatMap, key: Str) -> Option[Str] {
  let i = _map_index(m, key);
  if i < 0 {
    return None;
  }
  let v: Str = m.vals[i];
  return Some(v);
}

/// Winning layer index of `key` in the flattened map, or None when absent.
pub fn flatmap_layer(m: &FlatMap, key: Str) -> Option[Int] {
  let i = _map_index(m, key);
  if i < 0 {
    return None;
  }
  let l: Int = m.layer[i];
  return Some(l);
}

/// Live keys in first-introduction order (a fresh copy).
pub fn flatmap_keys(m: &FlatMap) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < m.keys.len() {
    let k: Str = m.keys[i];
    out.push(k);
    i = i + 1;
  }
  return out;
}

/// Live values in key order (a fresh copy).
pub fn flatmap_values(m: &FlatMap) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < m.vals.len() {
    let v: Str = m.vals[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// All live entries as index-aligned parallel vectors: (keys, values). Both
/// are fresh copies; mutating them does not change the map.
pub fn flatmap_entries(m: &FlatMap) -> (Vec[Str], Vec[Str]) {
  var ks = Vec[Str].new();
  var vs = Vec[Str].new();
  var i = 0;
  while i < m.keys.len() {
    let k: Str = m.keys[i];
    let v: Str = m.vals[i];
    ks.push(k);
    vs.push(v);
    i = i + 1;
  }
  return (ks, vs);
}

/// Render the map to canonical text: one `key = value` line per live entry,
/// in first-introduction order, LF separated with no trailing LF; an empty
/// map renders as "". Values are written verbatim (sentinel-looking text is
/// already resolved); a key with an empty value renders as "key = ".
/// Rendering concatenates Str directly, so an embedded control byte cannot
/// truncate it.
pub fn flatmap_render(m: &FlatMap) -> Str {
  var out = "";
  var i = 0;
  while i < m.keys.len() {
    if i > 0 {
      out = out + "\n";
    }
    let k: Str = m.keys[i];
    let v: Str = m.vals[i];
    out = out + k + " = " + v;
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Layer diff
// --------------------------------------------------

/// Compare layer `base` with layer `other` over their raw entry texts.
/// `added`: keys of `other` missing from `base` (other-layer order);
/// `removed`: keys of `base` missing from `other` (base-layer order);
/// `changed`: keys in both whose raw values differ (base-layer order).
/// Err "layers: no layer at index <i>" when either index is out of range.
pub fn layers_diff(s: &LayerStack, base: Int, other: Int) -> Result[LayerDiff, Str] {
  if base < 0 || base >= s.names.len() {
    return _diff_err("layers: no layer at index " + convert.int_to_string(base));
  }
  if other < 0 || other >= s.names.len() {
    return _diff_err("layers: no layer at index " + convert.int_to_string(other));
  }
  var added = Vec[Str].new();
  var removed = Vec[Str].new();
  var changed = Vec[Str].new();
  var e = 0;
  while e < s.keys.len() {
    let o: Int = s.owner[e];
    if o == other {
      let k: Str = s.keys[e];
      let ov: Str = s.vals[e];
      let b = _entry_of(s, base, k);
      if b < 0 {
        added.push(k);
      } else {
        let bv: Str = s.vals[b];
        if !_streq(bv, ov) {
          changed.push(k);
        }
      }
    }
    e = e + 1;
  }
  e = 0;
  while e < s.keys.len() {
    let o2: Int = s.owner[e];
    if o2 == base {
      let k2: Str = s.keys[e];
      let ob = _entry_of(s, other, k2);
      if ob < 0 {
        removed.push(k2);
      }
    }
    e = e + 1;
  }
  return _diff_ok(LayerDiff{ added: added; removed: removed; changed: changed; });
}
