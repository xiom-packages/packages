// XIOM -- xiom.chef: pure Chef-style configuration-management model
// Port task: promote the xiom.chef placeholder to a real, tested, pure-XIOM
// package: cookbook/recipe/resource declarations, resource-collection compile
// phase, runlist and role expansion, attribute precedence (default/normal/
// override), explicit provider dispatch, notification/subscription timing
// (immediate vs delayed) and a deterministic idempotence / converge report.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: MODEL ONLY. There is no network, no shell-out, no FFI and no file
// I/O. A converge run is a pure function of the declared cookbook, role set
// and runlist: the same inputs always produce the same ResourceCollection and
// the same Report. A host that actually converges a machine supplies the
// "satisfied" resource attribute (whether the live state already matches) and
// uses the report to drive real providers.
//
// Model (Vec[StructType] is unsupported in this compiler, so every collection
// is a set of index-aligned parallel vectors):
//   Cookbook   recipe declarations plus resource rows (res_*) each owned by a
//              recipe index, attribute rows (at_*) each owned by a resource
//              index, notification rows (nt_*) and subscription rows (sb_*).
//   RoleSet    role names plus entry rows (e_*) owned by a role index. An
//              entry is any runlist entry, including role[...] references.
//   Attrs      attribute keys/values plus a precedence level per row.
//   Collection the compiled, runlist-ordered resource rows with their
//              attributes, notifications and subscriptions re-owned by
//              collection index.
//   Report     converge counters (total/updated/unchanged/skipped/provider
//              calls/immediate/delayed) plus an ordered event log.
//
// Attribute precedence (lowest to highest): default (0) < normal (1) <
// override (2). Merge order is defaults, then normal, then overrides; within
// the same level the later assignment wins; a lower level never overwrites a
// higher one; a key keeps the position of its first insertion.
//
// Provider dispatch is an explicit case analysis on the resource type:
//   package -> package; service -> service; group -> group; user -> user;
//   file/template/cookbook_file/remote_file/directory -> file;
//   execute/bash/script -> execute; anything else -> Err. A resource
//   attribute "provider" overrides the type dispatch and must name one of
//   the six known providers.
//
// Converge model (deterministic, bounded; see SPEC.md section 7):
//   * Resources converge in collection order, each at most once per run.
//   * action == "nothing" -> skipped unless forced by a notification.
//   * attribute satisfied == "true" -> unchanged unless forced.
//   * otherwise updated: provider call, then its notifications/subscriptions
//     are delivered. Immediate deliveries fire at that point and force a
//     not-yet-converged target; delayed deliveries queue FIFO and are
//     delivered after the main pass.
//   * A delivery to an already-converged unchanged/skipped resource promotes
//     it to updated (one extra provider call); a delivery to an
//     already-updated resource only bumps the fired counter.
//   * Deliveries never rebroadcast the target's own notifications, so a
//     notification cycle cannot recurse; a hard step cap (8192) fails the
//     run closed if it ever would.
//   * total == updated + unchanged + skipped always holds.
//
// v0.62.2 notes that shaped this module:
//   * Free functions only; every walk is index-based over parallel vectors.
//   * Ok/Err for Result[...] are constructed only in the leaf helpers
//     _col_ok/_col_err, _strs_ok/_strs_err, _report_ok/_report_err,
//     _str_ok/_str_err and _bool_ok/_bool_err (constructing Results directly
//     inside larger functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); every comparison is routed through _streq.
//   * Every byte read is widened and masked ((b as Int) & 0xFF) by the _byte
//     helper before any comparison (byte comparisons at >= 128 miscompile).
//   * Every Vec[Str]/Vec[Int] element read goes through a typed local first
//     (untyped element reads can mis-lower); no &mut scalar parameters are
//     used, all mutable state lives in the Conv struct.

module xiom.chef

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result / Option leaf constructors (see the module header)
// --------------------------------------------------

// Ok(c) for Result[Collection, Str].
fn _col_ok(c: Collection) -> Result[Collection, Str] {
  return Ok(c);
}

// Err(m) for Result[Collection, Str].
fn _col_err(m: Str) -> Result[Collection, Str] {
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

// Ok(r) for Result[Report, Str].
fn _report_ok(r: Report) -> Result[Report, Str] {
  return Ok(r);
}

// Err(m) for Result[Report, Str].
fn _report_err(m: Str) -> Result[Report, Str] {
  return Err(m);
}

// Ok(s) for Result[Str, Str].
fn _str_ok(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(m) for Result[Str, Str].
fn _str_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(b) for Result[Bool, Str].
fn _bool_ok(b: Bool) -> Result[Bool, Str] {
  return Ok(b);
}

// Err(m) for Result[Bool, Str].
fn _bool_err(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and byte-level helpers
// --------------------------------------------------

const _CHEF_LBRACKET: Int = 91;
const _CHEF_RBRACKET: Int = 93;
const _CHEF_SPACE: Int = 32;

// Precedence levels for chef_attrs_set / chef_attrs_resolve.
const _CHEF_ATTR_DEFAULT: Int = 0;
const _CHEF_ATTR_NORMAL: Int = 1;
const _CHEF_ATTR_OVERRIDE: Int = 2;

// Notification timing.
const _CHEF_IMMEDIATE: Int = 0;
const _CHEF_DELAYED: Int = 1;

// Converge state of one resource.
const _CHEF_ST_PENDING: Int = 0;
const _CHEF_ST_UPDATED: Int = 1;
const _CHEF_ST_UNCHANGED: Int = 2;
const _CHEF_ST_SKIPPED: Int = 3;

// Bounds (trap D): role nesting depth, expanded recipe count and total
// notification deliveries per converge run.
const _CHEF_MAX_DEPTH: Int = 32;
const _CHEF_MAX_RECIPES: Int = 512;
const _CHEF_MAX_STEPS: Int = 8192;

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

// True when `v` contains `s` (byte-exact, through _streq).
fn _vec_has(v: &Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let x: Str = v[i];
    if _streq(x, s) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when `s` is a valid recipe/role name: non-empty, no byte <= space, no
// '[' and no ']'.
fn _name_ok(s: Str) -> Bool {
  if s.len() == 0 {
    return false;
  }
  var i = 0;
  while i < s.len() {
    let c = _byte(s, i);
    if c <= _CHEF_SPACE {
      return false;
    }
    if c == _CHEF_LBRACKET || c == _CHEF_RBRACKET {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A Chef-style cookbook: recipe declarations plus resource rows and their
/// attribute, notification and subscription rows. Every row family is a
/// parallel vector; see the module header for the ownership rules. Build one
/// with chef_cookbook_new / chef_add_recipe / chef_add_resource /
/// chef_set_attr / chef_notifies / chef_subscribes.
pub type Cookbook = {
  name: Str;
  recipes: Vec[Str];       // recipe names, declaration order
  res_recipe: Vec[Int];    // recipe index owning each resource row
  res_type: Vec[Str];      // resource type, e.g. "package"
  res_name: Vec[Str];      // resource name, e.g. "nginx"
  res_action: Vec[Str];    // desired action, e.g. "install"; "nothing" = no-op
  at_owner: Vec[Int];      // resource index owning each attribute row
  at_key: Vec[Str];
  at_value: Vec[Str];
  nt_owner: Vec[Int];      // resource index declaring each notification row
  nt_action: Vec[Str];     // action the target should run
  nt_target: Vec[Str];     // "type[name]" or bare "name" reference
  nt_timing: Vec[Int];     // _CHEF_IMMEDIATE or _CHEF_DELAYED
  sb_owner: Vec[Int];      // subscribing (target) resource index
  sb_action: Vec[Str];     // action the subscriber runs when the source updates
  sb_source: Vec[Str];     // "type[name]" or bare "name" reference
  sb_timing: Vec[Int];     // _CHEF_IMMEDIATE or _CHEF_DELAYED
}

/// A named set of roles. Role `names[i]` owns every entry row with
/// e_owner == i, in row order. Entries are ordinary runlist entries and may
/// reference other roles (nested roles are expanded with cycle detection).
pub type RoleSet = {
  names: Vec[Str];
  e_owner: Vec[Int];
  e_entry: Vec[Str];
}

/// A layered attribute set: keys/values/levels are index-aligned. Level 0 is
/// default, 1 normal, 2 override; the resolved value of a key is the value of
/// its highest-level assignment and, at equal levels, the latest one.
pub type Attrs = {
  keys: Vec[Str];
  values: Vec[Str];
  levels: Vec[Int];
}

/// The compiled resource collection: runlist-ordered resource rows with
/// attributes, notifications and subscriptions re-owned by collection index.
/// Produced by chef_compile; consumed by chef_converge_collection.
pub type Collection = {
  recipes: Vec[Str];       // recipe name owning each resource row
  res_type: Vec[Str];
  res_name: Vec[Str];
  res_action: Vec[Str];
  at_owner: Vec[Int];
  at_key: Vec[Str];
  at_value: Vec[Str];
  nt_owner: Vec[Int];
  nt_action: Vec[Str];
  nt_target: Vec[Str];
  nt_timing: Vec[Int];
  sb_owner: Vec[Int];
  sb_action: Vec[Str];
  sb_source: Vec[Str];
  sb_timing: Vec[Int];
}

/// The deterministic converge report. `total` always equals updated +
/// unchanged + skipped; `events` is the ordered event log rendered by
/// chef_report_render.
pub type Report = {
  total: Int;
  updated: Int;
  unchanged: Int;
  skipped: Int;
  provider_calls: Int;
  immediate_fired: Int;
  delayed_fired: Int;
  events: Vec[Str];
}

// Mutable converge state (module-internal; no &mut scalar parameters).
type Conv = {
  total: Int;
  updated: Int;
  unchanged: Int;
  skipped: Int;
  provider_calls: Int;
  immediate_fired: Int;
  delayed_fired: Int;
  state: Vec[Int];          // per resource: _CHEF_ST_*
  forced: Vec[Int];         // per resource: 1 when a notification forces a run
  events: Vec[Str];
  delayed: Vec[Int];        // delayed-pass target indices, FIFO
  delayed_owner: Vec[Int];  // parallel delivery owners for the event log
  steps: Int;               // deliveries so far, against _CHEF_MAX_STEPS
}

// --------------------------------------------------
//  Attribute set
// --------------------------------------------------

/// An empty attribute set.
pub fn chef_attrs_new() -> Attrs {
  return Attrs{ keys: Vec[Str].new(); values: Vec[Str].new(); levels: Vec[Int].new(); };
}

// Level of a level name ("default" 0, "normal" 1, "override" 2), or -1.
fn _attr_level_of(l: Str) -> Int {
  if _streq(l, "default") {
    return _CHEF_ATTR_DEFAULT;
  }
  if _streq(l, "normal") {
    return _CHEF_ATTR_NORMAL;
  }
  if _streq(l, "override") {
    return _CHEF_ATTR_OVERRIDE;
  }
  return -1;
}

// Notify timing of a timing name ("immediate" 0, "delayed" 1), or -1.
fn _timing_of(t: Str) -> Int {
  if _streq(t, "immediate") {
    return _CHEF_IMMEDIATE;
  }
  if _streq(t, "delayed") {
    return _CHEF_DELAYED;
  }
  return -1;
}

// Assign key/value at `level`: a new key is appended (its position is the
// first insertion); an existing key is replaced when level >= its current
// level (equal level = later wins) and left alone otherwise.
fn _attrs_put(a: &mut Attrs, key: Str, value: Str, level: Int) {
  var i = 0;
  while i < a.keys.len() {
    let k: Str = a.keys[i];
    if _streq(k, key) {
      let cur: Int = a.levels[i];
      if level >= cur {
        a.values[i] = value;
        a.levels[i] = level;
      }
      return;
    }
    i = i + 1;
  }
  a.keys.push(key);
  a.values.push(value);
  a.levels.push(level);
}

/// Assign `key = value` at the named precedence level ("default", "normal" or
/// "override"). Returns false for an unknown level (nothing is stored).
pub fn chef_attrs_set(a: &mut Attrs, key: Str, value: Str, level: Str) -> Bool {
  let lv = _attr_level_of(level);
  if lv < 0 {
    return false;
  }
  _attrs_put(a, key, value, lv);
  return true;
}

/// Resolved value of `key`; None when absent. Position-sensitive lookup over
/// the first match (keys are unique by construction).
pub fn chef_attrs_get(a: &Attrs, key: Str) -> Option[Str] {
  var i = 0;
  while i < a.keys.len() {
    let k: Str = a.keys[i];
    if _streq(k, key) {
      let v: Str = a.values[i];
      return Some(v);
    }
    i = i + 1;
  }
  return None;
}

/// Precedence level of `key` (0 default, 1 normal, 2 override), or -1 when
/// the key is absent.
pub fn chef_attrs_level(a: &Attrs, key: Str) -> Int {
  var i = 0;
  while i < a.keys.len() {
    let k: Str = a.keys[i];
    if _streq(k, key) {
      let lv: Int = a.levels[i];
      return lv;
    }
    i = i + 1;
  }
  return -1;
}

/// Merge `overlay` into `base` with the documented precedence rule; neither
/// input is modified. Applying chef_attrs_merge(base, overlay) once per
/// source, in precedence order, is exactly chef_attrs_resolve for three
/// sources.
pub fn chef_attrs_merge(base: &Attrs, overlay: &Attrs) -> Attrs {
  var out = chef_attrs_new();
  var i = 0;
  while i < base.keys.len() {
    let k: Str = base.keys[i];
    let v: Str = base.values[i];
    let lv: Int = base.levels[i];
    _attrs_put(&mut out, k, v, lv);
    i = i + 1;
  }
  var j = 0;
  while j < overlay.keys.len() {
    let k2: Str = overlay.keys[j];
    let v2: Str = overlay.values[j];
    let lv2: Int = overlay.levels[j];
    _attrs_put(&mut out, k2, v2, lv2);
    j = j + 1;
  }
  return out;
}

/// Resolve a three-source attribute chain in the documented merge order:
/// defaults, then normal, then overrides. A higher level always beats a
/// lower one regardless of input order; within a level, later wins.
pub fn chef_attrs_resolve(defaults: &Attrs, normal: &Attrs, overrides: &Attrs) -> Attrs {
  let merged = chef_attrs_merge(defaults, normal);
  return chef_attrs_merge(&merged, overrides);
}

// --------------------------------------------------
//  Cookbook builders
// --------------------------------------------------

/// An empty cookbook with the given name.
pub fn chef_cookbook_new(name: Str) -> Cookbook {
  return Cookbook{
    name: name;
    recipes: Vec[Str].new();
    res_recipe: Vec[Int].new();
    res_type: Vec[Str].new();
    res_name: Vec[Str].new();
    res_action: Vec[Str].new();
    at_owner: Vec[Int].new();
    at_key: Vec[Str].new();
    at_value: Vec[Str].new();
    nt_owner: Vec[Int].new();
    nt_action: Vec[Str].new();
    nt_target: Vec[Str].new();
    nt_timing: Vec[Int].new();
    sb_owner: Vec[Int].new();
    sb_action: Vec[Str].new();
    sb_source: Vec[Str].new();
    sb_timing: Vec[Int].new();
  };
}

/// Append a recipe and return its index. Recipes are looked up by first
/// match; callers should use unique names.
pub fn chef_add_recipe(cb: &mut Cookbook, name: Str) -> Int {
  cb.recipes.push(name);
  return cb.recipes.len() - 1;
}

/// Append one resource row owned by recipe index `recipe` and return its
/// resource index. `action` "nothing" declares a resource that is skipped
/// unless a notification forces it.
pub fn chef_add_resource(cb: &mut Cookbook, recipe: Int, typ: Str, name: Str, action: Str) -> Int {
  cb.res_recipe.push(recipe);
  cb.res_type.push(typ);
  cb.res_name.push(name);
  cb.res_action.push(action);
  return cb.res_type.len() - 1;
}

/// Append one attribute row to resource index `res`. The converge model reads
/// the special keys "satisfied" (exact "true" = already converged) and
/// "provider" (provider name override); any other key is model metadata.
pub fn chef_set_attr(cb: &mut Cookbook, res: Int, key: Str, value: Str) {
  cb.at_owner.push(res);
  cb.at_key.push(key);
  cb.at_value.push(value);
}

/// Append a notification to resource index `res`: when `res` updates, the
/// target reference (`"type[name]"` or a bare name) runs `action` with the
/// given timing ("immediate" or "delayed"). Returns false for an unknown
/// timing (nothing is stored).
pub fn chef_notifies(cb: &mut Cookbook, res: Int, action: Str, target: Str, timing: Str) -> Bool {
  let tm = _timing_of(timing);
  if tm < 0 {
    return false;
  }
  cb.nt_owner.push(res);
  cb.nt_action.push(action);
  cb.nt_target.push(target);
  cb.nt_timing.push(tm);
  return true;
}

/// Append a subscription to resource index `sub`: when the source reference
/// (`"type[name]"` or a bare name) updates, `sub` runs `action` with the
/// given timing. A subscription is the inverse view of a notification.
/// Returns false for an unknown timing (nothing is stored).
pub fn chef_subscribes(cb: &mut Cookbook, sub: Int, action: Str, source: Str, timing: Str) -> Bool {
  let tm = _timing_of(timing);
  if tm < 0 {
    return false;
  }
  cb.sb_owner.push(sub);
  cb.sb_action.push(action);
  cb.sb_source.push(source);
  cb.sb_timing.push(tm);
  return true;
}

// --------------------------------------------------
//  Role set builders
// --------------------------------------------------

/// An empty role set.
pub fn chef_roleset_new() -> RoleSet {
  return RoleSet{ names: Vec[Str].new(); e_owner: Vec[Int].new(); e_entry: Vec[Str].new(); };
}

/// Append a role and return its index. Roles are looked up by first match.
pub fn chef_add_role(rs: &mut RoleSet, name: Str) -> Int {
  rs.names.push(name);
  return rs.names.len() - 1;
}

/// Append one runlist entry (recipe[...], role[...] or a bare recipe name) to
/// role index `role`, preserving declaration order.
pub fn chef_role_entry(rs: &mut RoleSet, role: Int, entry: Str) {
  rs.e_owner.push(role);
  rs.e_entry.push(entry);
}

// --------------------------------------------------
//  Lookup helpers
// --------------------------------------------------

// Index of recipe `name` in `cb`, or -1 (first match).
fn _recipe_index(cb: &Cookbook, name: Str) -> Int {
  var i = 0;
  while i < cb.recipes.len() {
    let r: Str = cb.recipes[i];
    if _streq(r, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of role `name` in `rs`, or -1 (first match).
fn _role_index(rs: &RoleSet, name: Str) -> Int {
  var i = 0;
  while i < rs.names.len() {
    let r: Str = rs.names[i];
    if _streq(r, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Value of attribute `key` on cookbook resource `res`, or "".
fn _cb_attr(cb: &Cookbook, res: Int, key: Str) -> Str {
  var i = 0;
  while i < cb.at_owner.len() {
    let o: Int = cb.at_owner[i];
    if o == res {
      let k: Str = cb.at_key[i];
      if _streq(k, key) {
        let v: Str = cb.at_value[i];
        return v;
      }
    }
    i = i + 1;
  }
  return "";
}

// Value of attribute `key` on collection resource `res`, or "".
fn _col_attr(col: &Collection, res: Int, key: Str) -> Str {
  var i = 0;
  while i < col.at_owner.len() {
    let o: Int = col.at_owner[i];
    if o == res {
      let k: Str = col.at_key[i];
      if _streq(k, key) {
        let v: Str = col.at_value[i];
        return v;
      }
    }
    i = i + 1;
  }
  return "";
}

// Human label of collection resource `i`: "type[name]".
fn _label(col: &Collection, i: Int) -> Str {
  let t: Str = col.res_type[i];
  let n: Str = col.res_name[i];
  return t + "[" + n + "]";
}

// --------------------------------------------------
//  Runlist entry parsing and expansion
// --------------------------------------------------

// Entry form: 0 explicit recipe[...], 1 role[...], 2 bare recipe, 3 malformed.
fn _entry_kind(e: Str) -> Int {
  if string.str_starts_with(e, "recipe[") && string.str_ends_with(e, "]") && e.len() >= 8 {
    return 0;
  }
  if string.str_starts_with(e, "role[") && string.str_ends_with(e, "]") && e.len() >= 6 {
    return 1;
  }
  var i = 0;
  while i < e.len() {
    let c = _byte(e, i);
    if c == _CHEF_LBRACKET || c == _CHEF_RBRACKET {
      return 3;
    }
    i = i + 1;
  }
  if e.len() == 0 {
    return 3;
  }
  return 2;
}

// Body of a "kind[...]" entry (prefix length `off`, trailing ']' dropped).
fn _entry_body(e: Str, off: Int) -> Str {
  return string.str_slice(e, off, e.len() - 1);
}

// Expand every entry of `entries` in order into `out`, using `stack` for role
// cycle detection. `depth` bounds role nesting.
fn _expand_all(out: &mut Vec[Str], stack: &mut Vec[Str], cb: &Cookbook, rs: &RoleSet, entries: &Vec[Str], depth: Int) -> Result[Bool, Str] {
  var i = 0;
  while i < entries.len() {
    let e: Str = entries[i];
    let r = _expand_entry(out, stack, cb, rs, e, depth);
    match r {
      Ok(_) => {},
      Err(m) => { return _bool_err(m); },
    }
    i = i + 1;
  }
  return _bool_ok(true);
}

// Expand one runlist entry into `out`.
fn _expand_entry(out: &mut Vec[Str], stack: &mut Vec[Str], cb: &Cookbook, rs: &RoleSet, e: Str, depth: Int) -> Result[Bool, Str] {
  let kind = _entry_kind(e);
  if kind == 3 {
    return _bool_err("chef: malformed runlist entry: " + e);
  }
  if kind == 0 {
    let n = _entry_body(e, 7);
    if !_name_ok(n) {
      return _bool_err("chef: malformed runlist entry: " + e);
    }
    if _recipe_index(cb, n) < 0 {
      return _bool_err("chef: unknown recipe: " + n);
    }
    out.push(n);
    if out.len() > _CHEF_MAX_RECIPES {
      return _bool_err("chef: runlist expansion exceeded " + convert.int_to_string(_CHEF_MAX_RECIPES) + " recipes");
    }
    return _bool_ok(true);
  }
  if kind == 2 {
    if !_name_ok(e) {
      return _bool_err("chef: malformed runlist entry: " + e);
    }
    if _recipe_index(cb, e) < 0 {
      return _bool_err("chef: unknown recipe: " + e);
    }
    out.push(e);
    if out.len() > _CHEF_MAX_RECIPES {
      return _bool_err("chef: runlist expansion exceeded " + convert.int_to_string(_CHEF_MAX_RECIPES) + " recipes");
    }
    return _bool_ok(true);
  }
  let n2 = _entry_body(e, 5);
  if !_name_ok(n2) {
    return _bool_err("chef: malformed runlist entry: " + e);
  }
  let ri = _role_index(rs, n2);
  if ri < 0 {
    return _bool_err("chef: unknown role: " + n2);
  }
  if depth >= _CHEF_MAX_DEPTH {
    return _bool_err("chef: runlist role nesting exceeded depth " + convert.int_to_string(_CHEF_MAX_DEPTH));
  }
  if _vec_has(stack, n2) {
    return _bool_err("chef: role cycle: " + n2);
  }
  stack.push(n2);
  var j = 0;
  while j < rs.e_owner.len() {
    let o: Int = rs.e_owner[j];
    if o == ri {
      let sub: Str = rs.e_entry[j];
      let r = _expand_entry(out, stack, cb, rs, sub, depth + 1);
      match r {
        Ok(_) => {},
        Err(m) => { return _bool_err(m); },
      }
    }
    j = j + 1;
  }
  match stack.pop() {
    Some(_) => {},
    None => {},
  }
  return _bool_ok(true);
}

/// Expand a runlist to the ordered recipe names it names: bare names and
/// recipe[...] entries are recipes, role[...] entries expand recursively to
/// their entries in declaration order (role entries may reference roles, with
/// cycle detection and a nesting cap). Duplicate recipes are preserved as
/// written. Err messages: "chef: malformed runlist entry: <e>", "chef:
/// unknown recipe: <name>", "chef: unknown role: <name>", "chef: role cycle:
/// <name>", "chef: runlist role nesting exceeded depth 32" and "chef: runlist
/// expansion exceeded 512 recipes".
pub fn chef_runlist_expand(cb: &Cookbook, rs: &RoleSet, runlist: &Vec[Str]) -> Result[Vec[Str], Str] {
  var out = Vec[Str].new();
  var stack = Vec[Str].new();
  let r = _expand_all(&mut out, &mut stack, cb, rs, runlist, 0);
  match r {
    Ok(_) => { return _strs_ok(out); },
    Err(e) => { return _strs_err(e); },
  }
  return _strs_err("chef: unreachable");
}

// --------------------------------------------------
//  Provider dispatch
// --------------------------------------------------

/// Resolve the provider for a resource type by explicit case analysis:
/// "package" -> "package", "service" -> "service", "group" -> "group",
/// "user" -> "user", the file family ("file", "template", "cookbook_file",
/// "remote_file", "directory") -> "file", the execute family ("execute",
/// "bash", "script") -> "execute". Anything else is Err("chef: no provider
/// for resource type: <type>").
pub fn chef_provider_for(typ: Str) -> Result[Str, Str] {
  if _streq(typ, "package") {
    return _str_ok("package");
  }
  if _streq(typ, "service") {
    return _str_ok("service");
  }
  if _streq(typ, "file") || _streq(typ, "template") || _streq(typ, "cookbook_file") || _streq(typ, "remote_file") || _streq(typ, "directory") {
    return _str_ok("file");
  }
  if _streq(typ, "execute") || _streq(typ, "bash") || _streq(typ, "script") {
    return _str_ok("execute");
  }
  if _streq(typ, "group") {
    return _str_ok("group");
  }
  if _streq(typ, "user") {
    return _str_ok("user");
  }
  return _str_err("chef: no provider for resource type: " + typ);
}

// True when `p` is one of the six known provider names.
fn _provider_known(p: Str) -> Bool {
  if _streq(p, "package") {
    return true;
  }
  if _streq(p, "service") {
    return true;
  }
  if _streq(p, "file") {
    return true;
  }
  if _streq(p, "execute") {
    return true;
  }
  if _streq(p, "group") {
    return true;
  }
  return _streq(p, "user");
}

/// Provider for cookbook resource `res`: the "provider" attribute when
/// present (and one of the six known names, else Err("chef: unknown provider
/// name: <name>")), otherwise chef_provider_for(resource type).
pub fn chef_resource_provider(cb: &Cookbook, res: Int) -> Result[Str, Str] {
  let ov = _cb_attr(cb, res, "provider");
  if ov.len() > 0 {
    if _provider_known(ov) {
      return _str_ok(ov);
    }
    return _str_err("chef: unknown provider name: " + ov);
  }
  let typ: Str = cb.res_type[res];
  return chef_provider_for(typ);
}

// Provider for collection resource `res` (same rule as chef_resource_provider).
fn _col_resource_provider(col: &Collection, res: Int) -> Result[Str, Str] {
  let ov = _col_attr(col, res, "provider");
  if ov.len() > 0 {
    if _provider_known(ov) {
      return _str_ok(ov);
    }
    return _str_err("chef: unknown provider name: " + ov);
  }
  let typ: Str = col.res_type[res];
  return chef_provider_for(typ);
}

// --------------------------------------------------
//  Compile phase
// --------------------------------------------------

// An empty compiled collection.
fn _collection_new() -> Collection {
  return Collection{
    recipes: Vec[Str].new();
    res_type: Vec[Str].new();
    res_name: Vec[Str].new();
    res_action: Vec[Str].new();
    at_owner: Vec[Int].new();
    at_key: Vec[Str].new();
    at_value: Vec[Str].new();
    nt_owner: Vec[Int].new();
    nt_action: Vec[Str].new();
    nt_target: Vec[Str].new();
    nt_timing: Vec[Int].new();
    sb_owner: Vec[Int].new();
    sb_action: Vec[Str].new();
    sb_source: Vec[Str].new();
    sb_timing: Vec[Int].new();
  };
}

// Append cookbook resource `res` to `col`, copying its attribute,
// notification and subscription rows with the owners rebound to the new
// collection index. Returns the new resource index.
fn _collection_add(col: &mut Collection, cb: &Cookbook, res: Int, recipe: Str) -> Int {
  let typ: Str = cb.res_type[res];
  let name: Str = cb.res_name[res];
  let action: Str = cb.res_action[res];
  col.recipes.push(recipe);
  col.res_type.push(typ);
  col.res_name.push(name);
  col.res_action.push(action);
  let idx = col.res_type.len() - 1;
  var k = 0;
  while k < cb.at_owner.len() {
    let o: Int = cb.at_owner[k];
    if o == res {
      let key: Str = cb.at_key[k];
      let value: Str = cb.at_value[k];
      col.at_owner.push(idx);
      col.at_key.push(key);
      col.at_value.push(value);
    }
    k = k + 1;
  }
  k = 0;
  while k < cb.nt_owner.len() {
    let o2: Int = cb.nt_owner[k];
    if o2 == res {
      let a2: Str = cb.nt_action[k];
      let t2: Str = cb.nt_target[k];
      let tm2: Int = cb.nt_timing[k];
      col.nt_owner.push(idx);
      col.nt_action.push(a2);
      col.nt_target.push(t2);
      col.nt_timing.push(tm2);
    }
    k = k + 1;
  }
  k = 0;
  while k < cb.sb_owner.len() {
    let o3: Int = cb.sb_owner[k];
    if o3 == res {
      let a3: Str = cb.sb_action[k];
      let s3: Str = cb.sb_source[k];
      let tm3: Int = cb.sb_timing[k];
      col.sb_owner.push(idx);
      col.sb_action.push(a3);
      col.sb_source.push(s3);
      col.sb_timing.push(tm3);
    }
    k = k + 1;
  }
  return idx;
}

// Resolve a "type[name]" reference to a collection index, or -1.
fn _resolve_typed(col: &Collection, typ: Str, name: Str) -> Int {
  var i = 0;
  while i < col.res_type.len() {
    let t: Str = col.res_type[i];
    let n: Str = col.res_name[i];
    if _streq(t, typ) && _streq(n, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Resolve a bare-name reference to the first collection row with that name,
// or -1.
fn _resolve_plain(col: &Collection, name: Str) -> Int {
  var i = 0;
  while i < col.res_name.len() {
    let n: Str = col.res_name[i];
    if _streq(n, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Resolve a target/source reference: "type[name]" (requires a non-empty
// type and name) or a bare name; -1 when no resource matches.
fn _resolve_ref(col: &Collection, r: Str) -> Int {
  let open = string.index_of(r, "[");
  var op = -1;
  match open {
    Some(v) => { op = v; },
    None => { op = -1; },
  }
  if op > 0 {
    let n = r.len();
    if n > op + 2 && string.str_ends_with(r, "]") {
      let typ = string.str_slice(r, 0, op);
      let name = string.str_slice(r, op + 1, n - 1);
      return _resolve_typed(col, typ, name);
    }
    return -1;
  }
  return _resolve_plain(col, r);
}

// Validate the compiled collection: every resource must resolve a provider
// (explicit dispatch or a known "provider" override) and every notification
// target / subscription source must resolve to a resource.
fn _validate_collection(col: &Collection) -> Result[Bool, Str] {
  var i = 0;
  while i < col.res_type.len() {
    let typ: Str = col.res_type[i];
    let ov: Str = _col_attr(col, i, "provider");
    if ov.len() > 0 {
      if !_provider_known(ov) {
        return _bool_err("chef: unknown provider name: " + ov);
      }
    } else {
      let pr = chef_provider_for(typ);
      match pr {
        Ok(_) => {},
        Err(e) => { return _bool_err(e); },
      }
    }
    i = i + 1;
  }
  var j = 0;
  while j < col.nt_target.len() {
    let t: Str = col.nt_target[j];
    if _resolve_ref(col, t) < 0 {
      return _bool_err("chef: unknown notification target: " + t);
    }
    j = j + 1;
  }
  j = 0;
  while j < col.sb_source.len() {
    let s: Str = col.sb_source[j];
    if _resolve_ref(col, s) < 0 {
      return _bool_err("chef: unknown subscription source: " + s);
    }
    j = j + 1;
  }
  return _bool_ok(true);
}

/// Compile a runlist into a resource collection: expand the runlist to recipe
/// names (chef_runlist_expand), copy each recipe's resources in runlist order
/// and declaration order, then validate providers and notification /
/// subscription references. Returns the deterministic ResourceCollection or
/// the first error (same message catalog as chef_runlist_expand plus "chef:
/// unknown notification target: <ref>", "chef: unknown subscription source:
/// <ref>", "chef: no provider for resource type: <type>" and "chef: unknown
/// provider name: <name>").
pub fn chef_compile(cb: &Cookbook, rs: &RoleSet, runlist: &Vec[Str]) -> Result[Collection, Str] {
  let ex = chef_runlist_expand(cb, rs, runlist);
  match ex {
    Err(e) => { return _col_err(e); },
    Ok(names) => {
      var col = _collection_new();
      var i = 0;
      while i < names.len() {
        let rn: Str = names[i];
        let ri = _recipe_index(cb, rn);
        if ri >= 0 {
          var j = 0;
          while j < cb.res_type.len() {
            let owner: Int = cb.res_recipe[j];
            if owner == ri {
              _collection_add(&mut col, cb, j, rn);
            }
            j = j + 1;
          }
        }
        i = i + 1;
      }
      let v = _validate_collection(&col);
      match v {
        Ok(_) => {},
        Err(m) => { return _col_err(m); },
      }
      return _col_ok(col);
    },
  }
  return _col_err("chef: unreachable");
}

// --------------------------------------------------
//  Collection accessors
// --------------------------------------------------

/// Number of resources in a compiled collection.
pub fn chef_collection_len(col: &Collection) -> Int {
  return col.res_type.len();
}

/// Resource type at `i` ("" when `i` is out of range).
pub fn chef_collection_type(col: &Collection, i: Int) -> Str {
  if i < 0 || i >= col.res_type.len() {
    return "";
  }
  let t: Str = col.res_type[i];
  return t;
}

/// Resource name at `i` ("" when `i` is out of range).
pub fn chef_collection_name(col: &Collection, i: Int) -> Str {
  if i < 0 || i >= col.res_name.len() {
    return "";
  }
  let n: Str = col.res_name[i];
  return n;
}

/// Resource action at `i` ("" when `i` is out of range).
pub fn chef_collection_action(col: &Collection, i: Int) -> Str {
  if i < 0 || i >= col.res_action.len() {
    return "";
  }
  let a: Str = col.res_action[i];
  return a;
}

/// Recipe name owning resource `i` ("" when `i` is out of range).
pub fn chef_collection_recipe(col: &Collection, i: Int) -> Str {
  if i < 0 || i >= col.recipes.len() {
    return "";
  }
  let r: Str = col.recipes[i];
  return r;
}

/// Attribute `key` of resource `i`; None when absent or out of range.
pub fn chef_collection_attr(col: &Collection, i: Int, key: Str) -> Option[Str] {
  if i < 0 || i >= col.res_type.len() {
    return None;
  }
  var k = 0;
  while k < col.at_owner.len() {
    let o: Int = col.at_owner[k];
    if o == i {
      let kk: Str = col.at_key[k];
      if _streq(kk, key) {
        let v: Str = col.at_value[k];
        return Some(v);
      }
    }
    k = k + 1;
  }
  return None;
}

// --------------------------------------------------
//  Converge phase
// --------------------------------------------------

// Fresh converge state sized to `col`.
fn _conv_new(col: &Collection) -> Conv {
  var st = Vec[Int].new();
  var fd = Vec[Int].new();
  var i = 0;
  while i < col.res_type.len() {
    st.push(_CHEF_ST_PENDING);
    fd.push(0);
    i = i + 1;
  }
  return Conv{
    total: col.res_type.len();
    updated: 0;
    unchanged: 0;
    skipped: 0;
    provider_calls: 0;
    immediate_fired: 0;
    delayed_fired: 0;
    state: st;
    forced: fd;
    events: Vec[Str].new();
    delayed: Vec[Int].new();
    delayed_owner: Vec[Int].new();
    steps: 0;
  };
}

// Deliver one notification / subscription to `target`. A target that has not
// converged yet is forced (it updates when its turn comes); a target that
// already ended unchanged/skipped is promoted to updated with one extra
// provider call; a target that already updated only bumps the fired counter.
// Deliveries never rebroadcast the target's own notifications.
fn _deliver(cv: &mut Conv, col: &Collection, owner: Int, target: Int, is_delayed: Bool) -> Result[Bool, Str] {
  cv.steps = cv.steps + 1;
  if cv.steps > _CHEF_MAX_STEPS {
    return _bool_err("chef: notification cascade exceeded bound");
  }
  var tag = "immediate: ";
  if is_delayed {
    cv.delayed_fired = cv.delayed_fired + 1;
    tag = "delayed: ";
  } else {
    cv.immediate_fired = cv.immediate_fired + 1;
  }
  cv.events.push(tag + _label(col, owner) + " -> " + _label(col, target));
  let s: Int = cv.state[target];
  if s == _CHEF_ST_PENDING {
    cv.forced[target] = 1;
    return _bool_ok(true);
  }
  if s == _CHEF_ST_UPDATED {
    return _bool_ok(true);
  }
  if s == _CHEF_ST_UNCHANGED {
    cv.unchanged = cv.unchanged - 1;
  } else {
    cv.skipped = cv.skipped - 1;
  }
  cv.updated = cv.updated + 1;
  cv.provider_calls = cv.provider_calls + 1;
  cv.state[target] = _CHEF_ST_UPDATED;
  cv.events.push("notified-update: " + _label(col, target));
  return _bool_ok(true);
}

// Deliver every notification declared by `src` and every subscription whose
// source resolves to `src`, in collection row order (notifications first,
// then subscriptions). Immediate deliveries fire now; delayed deliveries are
// queued FIFO for the delayed pass.
fn _deliver_source(cv: &mut Conv, col: &Collection, src: Int) -> Result[Bool, Str] {
  var i = 0;
  while i < col.nt_owner.len() {
    let o: Int = col.nt_owner[i];
    if o == src {
      let t: Str = col.nt_target[i];
      let tm: Int = col.nt_timing[i];
      let ti = _resolve_ref(col, t);
      if ti < 0 {
        return _bool_err("chef: unknown notification target: " + t);
      }
      if tm == _CHEF_DELAYED {
        cv.delayed.push(ti);
        cv.delayed_owner.push(src);
      } else {
        let r = _deliver(cv, col, src, ti, false);
        match r {
          Ok(_) => {},
          Err(e) => { return _bool_err(e); },
        }
      }
    }
    i = i + 1;
  }
  var j = 0;
  while j < col.sb_owner.len() {
    let sref: Str = col.sb_source[j];
    let si = _resolve_ref(col, sref);
    if si == src {
      let sub: Int = col.sb_owner[j];
      let tm2: Int = col.sb_timing[j];
      if tm2 == _CHEF_DELAYED {
        cv.delayed.push(sub);
        cv.delayed_owner.push(src);
      } else {
        let r2 = _deliver(cv, col, src, sub, false);
        match r2 {
          Ok(_) => {},
          Err(e2) => { return _bool_err(e2); },
        }
      }
    }
    j = j + 1;
  }
  return _bool_ok(true);
}

// Classify and converge collection resource `i`.
fn _visit(cv: &mut Conv, col: &Collection, i: Int) -> Result[Bool, Str] {
  let pr = _col_resource_provider(col, i);
  match pr {
    Ok(_) => {},
    Err(e) => { return _bool_err(e); },
  }
  let action: Str = col.res_action[i];
  let f: Int = cv.forced[i];
  if _streq(action, "nothing") && f == 0 {
    cv.skipped = cv.skipped + 1;
    cv.state[i] = _CHEF_ST_SKIPPED;
    cv.events.push("skipped: " + _label(col, i));
    return _bool_ok(true);
  }
  let sat = _col_attr(col, i, "satisfied");
  if _streq(sat, "true") && f == 0 {
    cv.unchanged = cv.unchanged + 1;
    cv.state[i] = _CHEF_ST_UNCHANGED;
    cv.events.push("unchanged: " + _label(col, i));
    return _bool_ok(true);
  }
  cv.updated = cv.updated + 1;
  cv.provider_calls = cv.provider_calls + 1;
  cv.state[i] = _CHEF_ST_UPDATED;
  cv.events.push("updated: " + _label(col, i));
  return _deliver_source(cv, col, i);
}

// Build the immutable report from the mutable state.
fn _conv_report(cv: &Conv) -> Report {
  var ev = Vec[Str].new();
  var i = 0;
  while i < cv.events.len() {
    let e: Str = cv.events[i];
    ev.push(e);
    i = i + 1;
  }
  return Report{
    total: cv.total;
    updated: cv.updated;
    unchanged: cv.unchanged;
    skipped: cv.skipped;
    provider_calls: cv.provider_calls;
    immediate_fired: cv.immediate_fired;
    delayed_fired: cv.delayed_fired;
    events: ev;
  };
}

/// Converge a compiled collection and return the deterministic report: the
/// main pass in collection order, then the delayed-notification pass in FIFO
/// delivery order. See the module header and SPEC.md section 7 for the exact
/// rules; the run fails closed with "chef: notification cascade exceeded
/// bound" if deliveries exceed 8192.
pub fn chef_converge_collection(col: &Collection) -> Result[Report, Str] {
  var cv = _conv_new(col);
  var i = 0;
  while i < col.res_type.len() {
    let r = _visit(&mut cv, col, i);
    match r {
      Ok(_) => {},
      Err(e) => { return _report_err(e); },
    }
    i = i + 1;
  }
  var qi = 0;
  while qi < cv.delayed.len() {
    let owner: Int = cv.delayed_owner[qi];
    let target: Int = cv.delayed[qi];
    let r2 = _deliver(&mut cv, col, owner, target, true);
    match r2 {
      Ok(_) => {},
      Err(e2) => { return _report_err(e2); },
    }
    qi = qi + 1;
  }
  return _report_ok(_conv_report(&cv));
}

/// Compile a runlist and converge it: chef_converge(cb, rs, runlist) ==
/// chef_converge_collection(chef_compile(cb, rs, runlist)[?]).
pub fn chef_converge(cb: &Cookbook, rs: &RoleSet, runlist: &Vec[Str]) -> Result[Report, Str] {
  let cr = chef_compile(cb, rs, runlist);
  match cr {
    Ok(col) => { return chef_converge_collection(&col); },
    Err(e) => { return _report_err(e); },
  }
  return _report_err("chef: unreachable");
}

// --------------------------------------------------
//  Report rendering
// --------------------------------------------------

/// Render a report to canonical text: one counts header line, one delivery
/// header line and one "event: <event>" line per event, LF separated with no
/// trailing LF. An empty run renders the two header lines only.
pub fn chef_report_render(r: &Report) -> Str {
  var out = "chef report: total=" + convert.int_to_string(r.total) + " updated=" + convert.int_to_string(r.updated) + " unchanged=" + convert.int_to_string(r.unchanged) + " skipped=" + convert.int_to_string(r.skipped);
  out = out + "\nprovider_calls=" + convert.int_to_string(r.provider_calls) + " immediate=" + convert.int_to_string(r.immediate_fired) + " delayed=" + convert.int_to_string(r.delayed_fired);
  var i = 0;
  while i < r.events.len() {
    let e: Str = r.events[i];
    out = out + "\nevent: " + e;
    i = i + 1;
  }
  return out;
}
