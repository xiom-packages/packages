// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.ansible: a pure, deterministic configuration-management model
// Port task: replace the xiom.ansible placeholder with a real, tested,
// pure-XIOM package (no SSH, no network, no FFI, no clock).
//
// Model: the semantic core of an Ansible-like configuration-management tool as
// a pure, deterministic value machine. There is no SSH, no network, no
// subprocess, no clock and no I/O here: simulated modules return one of four
// result codes from their name and argument text, and the executor applies the
// documented ordering rules. The package owns:
//   * inventory: hosts, groups, parent/child group edges, direct host
//     membership and group/host variables with a documented precedence order
//     (host vars > deeper group vars > shallower group vars; among groups of
//     equal depth the later declared wins);
//   * playbooks: plays, blocks, tasks and handlers as parallel Vec fields,
//     with builders that validate names, indices and the module registry;
//   * the module registry: a fixed, documented builtin set with an explicit
//     if/else dispatch (never a table of function values);
//   * a fact store: typed (Str/Int/Bool) index-aligned parallel vectors with
//     scope-aware get/set, replacement semantics and aggregation;
//   * tag/limit filtering: comma-tagged tasks with always/never/all rules and
//     a host or group limit pattern;
//   * handler notification: dedup per (handler, host) pair, first-notification
//     queue order, handlers executed at the end of the play in that order;
//   * a deterministic executor with linear (task-major) and free (host-major)
//     strategies and changed/ok/failed/skipped result accounting;
//   * a RunReport trace: every executed task and handler line in execution
//     order, rendered as "play | name | host | result".
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the tiny leaf helpers (_str_ok/_str_err, _int_ok/_int_err,
// _bool_ok/_bool_err, _rep_ok/_rep_err); every Vec element read is bound with
// a typed `let`; Str equality goes through xiom.string.compare.str_compare;
// every Vec push on one parallel vector is mirrored on all siblings; no
// Vec[StructType]; no Vec[Float64]; no `mut` in match patterns; no `&mut Int`
// scalar parameters (counters live in the RunReport struct); recursion is
// depth-budgeted; every loop is bounded by a stored length or an explicit cap.

module xiom.ansible

use xiom.string;
use xiom.convert;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// The implicit root group name: every host belongs to it, and its group vars
/// have the lowest precedence of all.
pub const ANSIBLE_ALL: Str = "all";

/// Tag that selects a task whenever any tag filter is active.
pub const ANSIBLE_TAG_ALWAYS: Str = "always";

/// Tag that excludes a task unless "never" is explicitly requested.
pub const ANSIBLE_TAG_NEVER: Str = "never";

/// Play strategy: task-major order (each task across every target host).
pub const ANSIBLE_STRATEGY_LINEAR: Int = 0;

/// Play strategy: host-major order (each host runs the whole play).
pub const ANSIBLE_STRATEGY_FREE: Int = 1;

/// Module kind: not in the documented registry.
pub const ANSIBLE_MODULE_UNKNOWN: Int = 0;

/// Module kind: ping (always ok, never changed).
pub const ANSIBLE_MODULE_PING: Int = 1;

/// Module kind: debug (always ok, never changed).
pub const ANSIBLE_MODULE_DEBUG: Int = 2;

/// Module kind: fail (always failed).
pub const ANSIBLE_MODULE_FAIL: Int = 3;

/// Module kind: command (simulated).
pub const ANSIBLE_MODULE_COMMAND: Int = 4;

/// Module kind: shell (simulated).
pub const ANSIBLE_MODULE_SHELL: Int = 5;

/// Module kind: copy (simulated).
pub const ANSIBLE_MODULE_COPY: Int = 6;

/// Module kind: template (simulated).
pub const ANSIBLE_MODULE_TEMPLATE: Int = 7;

/// Module kind: file (simulated).
pub const ANSIBLE_MODULE_FILE: Int = 8;

/// Module kind: package (simulated).
pub const ANSIBLE_MODULE_PACKAGE: Int = 9;

/// Module kind: service (simulated).
pub const ANSIBLE_MODULE_SERVICE: Int = 10;

/// Module kind: user (simulated).
pub const ANSIBLE_MODULE_USER: Int = 11;

/// Module kind: setup (always ok; gathers typed facts for the host).
pub const ANSIBLE_MODULE_SETUP: Int = 12;

/// Result code: succeeded without a change.
pub const ANSIBLE_RESULT_OK: Int = 0;

/// Result code: succeeded and reported a change.
pub const ANSIBLE_RESULT_CHANGED: Int = 1;

/// Result code: failed.
pub const ANSIBLE_RESULT_FAILED: Int = 2;

/// Result code: skipped.
pub const ANSIBLE_RESULT_SKIPPED: Int = 3;

/// Fact kind: Str payload.
pub const ANSIBLE_FACT_STR: Int = 0;

/// Fact kind: Int payload.
pub const ANSIBLE_FACT_INT: Int = 1;

/// Fact kind: Bool payload (stored as 0/1 in the Int slot).
pub const ANSIBLE_FACT_BOOL: Int = 2;

/// Maximum number of hosts in one inventory.
pub const ANSIBLE_MAX_HOSTS: Int = 256;

/// Maximum number of groups in one inventory.
pub const ANSIBLE_MAX_GROUPS: Int = 128;

/// Maximum number of membership, child and variable edges combined.
pub const ANSIBLE_MAX_VARS: Int = 4096;

/// Maximum number of plays in one playbook.
pub const ANSIBLE_MAX_PLAYS: Int = 64;

/// Maximum number of blocks in one playbook.
pub const ANSIBLE_MAX_BLOCKS: Int = 128;

/// Maximum number of tasks in one playbook.
pub const ANSIBLE_MAX_TASKS: Int = 512;

/// Maximum number of handlers in one playbook.
pub const ANSIBLE_MAX_HANDLERS: Int = 128;

/// Maximum number of entries in one fact store.
pub const ANSIBLE_MAX_FACTS: Int = 4096;

/// Maximum number of result and trace lines in one report.
pub const ANSIBLE_MAX_TRACE: Int = 8192;

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _str_ok(s: Str) -> Result[Str, Str] { return Ok(s); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }
fn _int_ok(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }
fn _bool_ok(v: Bool) -> Result[Bool, Str] { return Ok(v); }
fn _bool_err(m: Str) -> Result[Bool, Str] { return Err(m); }
fn _rep_ok(r: RunReport) -> Result[RunReport, Str] { return Ok(r); }
fn _rep_err(m: Str) -> Result[RunReport, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A host/group inventory. `hosts` and `groups` are name lists in declaration
/// order. Membership is the edge list `member_group[i]` -> `member_host[i]`;
/// the group hierarchy is the edge list `parent_group[i]` -> `child_group[i]`.
/// Group variables are the triples (`gvar_group`, `gvar_key`, `gvar_value`)
/// with replace-in-place semantics; host variables are the triples
/// (`hvar_host`, `hvar_key`, `hvar_value`). All parallel vectors are pushed
/// together so they can never skew.
pub type Inventory = {
  hosts: Vec[Str];
  groups: Vec[Str];
  member_group: Vec[Str];
  member_host: Vec[Str];
  parent_group: Vec[Str];
  child_group: Vec[Str];
  gvar_group: Vec[Str];
  gvar_key: Vec[Str];
  gvar_value: Vec[Str];
  hvar_host: Vec[Str];
  hvar_key: Vec[Str];
  hvar_value: Vec[Str];
}

/// A typed fact store. `scopes` and `keys` identify an entry; `kinds` holds an
/// ANSIBLE_FACT_* code; `strs` holds the Str payload and `ints` the Int or
/// Bool payload (0/1). Setting an existing (scope, key) replaces both the kind
/// and the payload in place, so entry count only grows for new keys.
pub type FactStore = {
  scopes: Vec[Str];
  keys: Vec[Str];
  kinds: Vec[Int];
  strs: Vec[Str];
  ints: Vec[Int];
}

/// A playbook. Plays own tasks and handlers by index; tasks reference an
/// optional block by index (-1 = play level). Every vector is index-aligned
/// with the entity named in its prefix; tags are comma-separated with no
/// surrounding whitespace.
pub type Playbook = {
  play_names: Vec[Str];
  play_hosts: Vec[Str];
  play_strategy: Vec[Int];
  play_tags: Vec[Str];
  block_play: Vec[Int];
  block_names: Vec[Str];
  block_tags: Vec[Str];
  task_play: Vec[Int];
  task_block: Vec[Int];
  task_names: Vec[Str];
  task_module: Vec[Str];
  task_args: Vec[Str];
  task_tags: Vec[Str];
  task_notify: Vec[Str];
  handler_play: Vec[Int];
  handler_names: Vec[Str];
  handler_module: Vec[Str];
  handler_args: Vec[Str];
}

/// The play-global handler notification state. `queue` lists notified handler
/// names in first-notification order with duplicates removed; `handlers` and
/// `hosts` are the parallel (handler, host) notification pairs.
pub type Notifier = {
  queue: Vec[Str];
  handlers: Vec[Str];
  hosts: Vec[Str];
}

/// Per-play execution state: the resolved target hosts, the per-host failure
/// flags aligned by index (1 = the host failed earlier in this play) and the
/// notifier.
pub type RunState = {
  targets: Vec[Str];
  flags: Vec[Int];
  notifier: Notifier;
}

/// The outcome of one `run_playbook` call. Task-level vectors are parallel
/// and hold the executed task lines in execution order; handler-level vectors
/// hold the executed handler lines in the order handlers were run. `trace`
/// renders every line as "play | name | host | result". Counters cover task
/// and handler lines together; `filtered` counts tasks excluded by the tag
/// filter (they produce no result line).
pub type RunReport = {
  play_names: Vec[Str];
  task_names: Vec[Str];
  hosts: Vec[Str];
  modules: Vec[Str];
  results: Vec[Int];
  trace: Vec[Str];
  handler_play: Vec[Str];
  handler_names: Vec[Str];
  handler_hosts: Vec[Str];
  handler_results: Vec[Int];
  notified: Vec[Str];
  changed: Int;
  ok: Int;
  failed: Int;
  skipped: Int;
  filtered: Int;
}

// ---------------------------------------------------------------------------
// Str primitives
// ---------------------------------------------------------------------------

// Byte-exact Str equality through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison (BUG-17 family).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Index of `s` in a Vec[Str], or -1.
fn _index_of_str(v: &Vec[Str], s: Str) -> Int {
  var i = 0;
  while i < v.len() {
    let cur: Str = v[i];
    if _streq(cur, s) { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `s` is present in a Vec[Str].
fn _vec_has_str(v: &Vec[Str], s: Str) -> Bool {
  return _index_of_str(v, s) >= 0;
}

// A name usable as a host or group: non-empty, no comma, no space, no tab.
fn _invalid_name(s: Str) -> Bool {
  if s.len() == 0 { return true; }
  if string.str_contains(s, ",") { return true; }
  if string.str_contains(s, " ") { return true; }
  if string.str_contains(s, "\u{0009}") { return true; }
  return false;
}

// Shared positional Result accessor for Str vectors.
fn _at(v: &Vec[Str], i: Int, what: Str) -> Result[Str, Str] {
  if i < 0 || i >= v.len() {
    return _str_err("ansible: index out of range: " + what);
  }
  let s: Str = v[i];
  return _str_ok(s);
}

// ---------------------------------------------------------------------------
// Fact primitives
// ---------------------------------------------------------------------------

// Index of the (scope, key) entry in the fact store, or -1.
fn _fact_index(fs: &FactStore, scope: Str, key: Str) -> Int {
  var i = 0;
  while i < fs.scopes.len() {
    let s: Str = fs.scopes[i];
    let k: Str = fs.keys[i];
    if _streq(s, scope) && _streq(k, key) { return i; }
    i = i + 1;
  }
  return -1;
}

/// Human-readable fact kind.
pub fn facts_kind_name(kind: Int) -> Str {
  if kind == ANSIBLE_FACT_STR { return "str"; }
  if kind == ANSIBLE_FACT_INT { return "int"; }
  if kind == ANSIBLE_FACT_BOOL { return "bool"; }
  return "unknown";
}

// Error text for a missing fact.
fn _undefined_fact(scope: Str, key: Str) -> Str {
  return "ansible: undefined fact: " + scope + "." + key;
}

// Internal unchecked put: replaces an existing entry or appends a new one.
// Returns the entry index, or -1 at capacity.
fn _facts_put_str(fs: &mut FactStore, scope: Str, key: Str, value: Str) -> Int {
  let idx = _fact_index(fs, scope, key);
  if idx >= 0 {
    fs.kinds[idx] = ANSIBLE_FACT_STR;
    fs.strs[idx] = value;
    fs.ints[idx] = 0;
    return idx;
  }
  if fs.scopes.len() >= ANSIBLE_MAX_FACTS { return -1; }
  fs.scopes.push(scope);
  fs.keys.push(key);
  fs.kinds.push(ANSIBLE_FACT_STR);
  fs.strs.push(value);
  fs.ints.push(0);
  return fs.scopes.len() - 1;
}

// Internal unchecked put for the Int payload (kind = Int).
fn _facts_put_int(fs: &mut FactStore, scope: Str, key: Str, value: Int) -> Int {
  let idx = _fact_index(fs, scope, key);
  if idx >= 0 {
    fs.kinds[idx] = ANSIBLE_FACT_INT;
    fs.strs[idx] = "";
    fs.ints[idx] = value;
    return idx;
  }
  if fs.scopes.len() >= ANSIBLE_MAX_FACTS { return -1; }
  fs.scopes.push(scope);
  fs.keys.push(key);
  fs.kinds.push(ANSIBLE_FACT_INT);
  fs.strs.push("");
  fs.ints.push(value);
  return fs.scopes.len() - 1;
}

// Internal unchecked put for the Bool payload (kind = Bool, stored 0/1).
fn _facts_put_bool(fs: &mut FactStore, scope: Str, key: Str, value: Bool) -> Int {
  var iv = 0;
  if value { iv = 1; }
  let idx = _fact_index(fs, scope, key);
  if idx >= 0 {
    fs.kinds[idx] = ANSIBLE_FACT_BOOL;
    fs.strs[idx] = "";
    fs.ints[idx] = iv;
    return idx;
  }
  if fs.scopes.len() >= ANSIBLE_MAX_FACTS { return -1; }
  fs.scopes.push(scope);
  fs.keys.push(key);
  fs.kinds.push(ANSIBLE_FACT_BOOL);
  fs.strs.push("");
  fs.ints.push(iv);
  return fs.scopes.len() - 1;
}

// ---------------------------------------------------------------------------
// Inventory: construction and accessors
// ---------------------------------------------------------------------------

/// An empty inventory.
pub fn inventory_new() -> Inventory {
  return Inventory{
    hosts: Vec[Str].new();
    groups: Vec[Str].new();
    member_group: Vec[Str].new();
    member_host: Vec[Str].new();
    parent_group: Vec[Str].new();
    child_group: Vec[Str].new();
    gvar_group: Vec[Str].new();
    gvar_key: Vec[Str].new();
    gvar_value: Vec[Str].new();
    hvar_host: Vec[Str].new();
    hvar_key: Vec[Str].new();
    hvar_value: Vec[Str].new();
  };
}

/// Register a host. Returns its declaration index.
pub fn inventory_add_host(inv: &mut Inventory, name: Str) -> Result[Int, Str] {
  if _invalid_name(name) { return _int_err("ansible: empty name"); }
  if _vec_has_str(&inv.hosts, name) {
    return _int_err("ansible: duplicate host: " + name);
  }
  if inv.hosts.len() >= ANSIBLE_MAX_HOSTS {
    return _int_err("ansible: capacity exceeded");
  }
  inv.hosts.push(name);
  return _int_ok(inv.hosts.len() - 1);
}

/// Register a group. Returns its declaration index.
pub fn inventory_add_group(inv: &mut Inventory, name: Str) -> Result[Int, Str] {
  if _invalid_name(name) { return _int_err("ansible: empty name"); }
  if _streq(name, ANSIBLE_ALL) {
    return _int_err("ansible: group name is reserved: " + name);
  }
  if _vec_has_str(&inv.groups, name) {
    return _int_err("ansible: duplicate group: " + name);
  }
  if inv.groups.len() >= ANSIBLE_MAX_GROUPS {
    return _int_err("ansible: capacity exceeded");
  }
  inv.groups.push(name);
  return _int_ok(inv.groups.len() - 1);
}

/// Add the direct membership edge host -> group. Both must exist.
pub fn inventory_add_host_to_group(inv: &mut Inventory, host: Str, group: Str) -> Result[Int, Str] {
  if !_vec_has_str(&inv.hosts, host) {
    return _int_err("ansible: unknown host: " + host);
  }
  if !_vec_has_str(&inv.groups, group) {
    return _int_err("ansible: unknown group: " + group);
  }
  var i = 0;
  while i < inv.member_group.len() {
    let g: Str = inv.member_group[i];
    let h: Str = inv.member_host[i];
    if _streq(g, group) && _streq(h, host) {
      return _int_err("ansible: duplicate membership: " + host + " in " + group);
    }
    i = i + 1;
  }
  if inv.member_group.len() >= ANSIBLE_MAX_VARS {
    return _int_err("ansible: capacity exceeded");
  }
  inv.member_group.push(group);
  inv.member_host.push(host);
  return _int_ok(inv.member_group.len() - 1);
}

/// Add the hierarchy edge parent -> child. Both groups must exist; duplicate
/// edges and cycles are refused.
pub fn inventory_add_group_child(inv: &mut Inventory, parent: Str, child: Str) -> Result[Int, Str] {
  if !_vec_has_str(&inv.groups, parent) {
    return _int_err("ansible: unknown group: " + parent);
  }
  if !_vec_has_str(&inv.groups, child) {
    return _int_err("ansible: unknown group: " + child);
  }
  var i = 0;
  while i < inv.child_group.len() {
    let p: Str = inv.parent_group[i];
    let c: Str = inv.child_group[i];
    if _streq(p, parent) && _streq(c, child) {
      return _int_err("ansible: duplicate group child: " + parent + ">" + child);
    }
    i = i + 1;
  }
  if _group_reaches(inv, child, parent, inv.groups.len() + 1) {
    return _int_err("ansible: group cycle: " + parent + ">" + child);
  }
  if inv.child_group.len() >= ANSIBLE_MAX_VARS {
    return _int_err("ansible: capacity exceeded");
  }
  inv.parent_group.push(parent);
  inv.child_group.push(child);
  return _int_ok(inv.child_group.len() - 1);
}

/// Set or replace a group variable (the last assignment wins). The implicit
/// "all" group may carry variables without being registered.
pub fn inventory_set_group_var(inv: &mut Inventory, group: Str, key: Str, value: Str) -> Result[Int, Str] {
  if !_streq(group, ANSIBLE_ALL) && !_vec_has_str(&inv.groups, group) {
    return _int_err("ansible: unknown group: " + group);
  }
  if key.len() == 0 { return _int_err("ansible: empty name"); }
  var i = 0;
  while i < inv.gvar_group.len() {
    let g: Str = inv.gvar_group[i];
    let k: Str = inv.gvar_key[i];
    if _streq(g, group) && _streq(k, key) {
      inv.gvar_value[i] = value;
      return _int_ok(i);
    }
    i = i + 1;
  }
  if inv.gvar_group.len() >= ANSIBLE_MAX_VARS {
    return _int_err("ansible: capacity exceeded");
  }
  inv.gvar_group.push(group);
  inv.gvar_key.push(key);
  inv.gvar_value.push(value);
  return _int_ok(inv.gvar_group.len() - 1);
}

/// Set or replace a host variable (the last assignment wins).
pub fn inventory_set_host_var(inv: &mut Inventory, host: Str, key: Str, value: Str) -> Result[Int, Str] {
  if !_vec_has_str(&inv.hosts, host) {
    return _int_err("ansible: unknown host: " + host);
  }
  if key.len() == 0 { return _int_err("ansible: empty name"); }
  var i = 0;
  while i < inv.hvar_host.len() {
    let h: Str = inv.hvar_host[i];
    let k: Str = inv.hvar_key[i];
    if _streq(h, host) && _streq(k, key) {
      inv.hvar_value[i] = value;
      return _int_ok(i);
    }
    i = i + 1;
  }
  if inv.hvar_host.len() >= ANSIBLE_MAX_VARS {
    return _int_err("ansible: capacity exceeded");
  }
  inv.hvar_host.push(host);
  inv.hvar_key.push(key);
  inv.hvar_value.push(value);
  return _int_ok(inv.hvar_host.len() - 1);
}

/// Number of registered hosts.
pub fn inventory_host_count(inv: &Inventory) -> Int {
  return inv.hosts.len();
}

/// Number of registered groups.
pub fn inventory_group_count(inv: &Inventory) -> Int {
  return inv.groups.len();
}

/// Number of direct membership edges.
pub fn inventory_member_count(inv: &Inventory) -> Int {
  return inv.member_group.len();
}

/// Number of group hierarchy edges.
pub fn inventory_child_count(inv: &Inventory) -> Int {
  return inv.child_group.len();
}

/// Host name at a declaration index.
pub fn inventory_host_at(inv: &Inventory, i: Int) -> Result[Str, Str] {
  return _at(&inv.hosts, i, "host");
}

/// Group name at a declaration index.
pub fn inventory_group_at(inv: &Inventory, i: Int) -> Result[Str, Str] {
  return _at(&inv.groups, i, "group");
}

/// True when the host is registered.
pub fn inventory_has_host(inv: &Inventory, name: Str) -> Bool {
  return _vec_has_str(&inv.hosts, name);
}

/// True when the group is registered.
pub fn inventory_has_group(inv: &Inventory, name: Str) -> Bool {
  return _vec_has_str(&inv.groups, name);
}

/// True when `parent` already reaches `target` through child edges.
fn _group_reaches(inv: &Inventory, from: Str, target: Str, budget: Int) -> Bool {
  if _streq(from, target) { return true; }
  if budget <= 0 { return false; }
  var i = 0;
  while i < inv.child_group.len() {
    let p: Str = inv.parent_group[i];
    if _streq(p, from) {
      let c: Str = inv.child_group[i];
      if _group_reaches(inv, c, target, budget - 1) { return true; }
    }
    i = i + 1;
  }
  return false;
}

// Depth of a group in the hierarchy: "all" is -1, a root group 0, a child
// max(parent depth) + 1. Cycles are refused at build time; the budget bounds
// recursion regardless.
fn _group_depth(inv: &Inventory, group: Str, budget: Int) -> Int {
  if _streq(group, ANSIBLE_ALL) { return -1; }
  if budget <= 0 { return 0; }
  var best = -1;
  var i = 0;
  while i < inv.child_group.len() {
    let c: Str = inv.child_group[i];
    if _streq(c, group) {
      let p: Str = inv.parent_group[i];
      let d = _group_depth(inv, p, budget - 1) + 1;
      if d > best { best = d; }
    }
    i = i + 1;
  }
  if best < 0 { return 0; }
  return best;
}

fn _group_contains(inv: &Inventory, group: Str, host: Str, budget: Int) -> Bool {
  if _streq(group, ANSIBLE_ALL) { return true; }
  if budget <= 0 { return false; }
  var i = 0;
  while i < inv.member_group.len() {
    let g: Str = inv.member_group[i];
    if _streq(g, group) {
      let h: Str = inv.member_host[i];
      if _streq(h, host) { return true; }
    }
    i = i + 1;
  }
  i = 0;
  while i < inv.child_group.len() {
    let p: Str = inv.parent_group[i];
    if _streq(p, group) {
      let c: Str = inv.child_group[i];
      if _group_contains(inv, c, host, budget - 1) { return true; }
    }
    i = i + 1;
  }
  return false;
}

/// True when `host` belongs to `group`, directly or through any descendant
/// group. "all" contains every host.
pub fn inventory_group_contains(inv: &Inventory, group: Str, host: Str) -> Bool {
  return _group_contains(inv, group, host, inv.groups.len() + 1);
}

/// Direct group memberships of a host in declaration order.
pub fn inventory_host_groups(inv: &Inventory, host: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  var i = 0;
  while i < inv.member_group.len() {
    let h: Str = inv.member_host[i];
    if _streq(h, host) {
      let g: Str = inv.member_group[i];
      out.push(g);
    }
    i = i + 1;
  }
  return out;
}

/// Resolve a target pattern to hosts in declaration order:
/// "all" -> every host; a group name -> every host in its closure; a host
/// name -> that host; anything else -> empty. A group name wins over a host
/// name when both exist.
pub fn inventory_target_hosts(inv: &Inventory, pattern: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  if pattern.len() == 0 { return out; }
  if _streq(pattern, ANSIBLE_ALL) {
    var i = 0;
    while i < inv.hosts.len() {
      let h: Str = inv.hosts[i];
      out.push(h);
      i = i + 1;
    }
    return out;
  }
  if _vec_has_str(&inv.groups, pattern) {
    var i = 0;
    let budget = inv.groups.len() + 1;
    while i < inv.hosts.len() {
      let h: Str = inv.hosts[i];
      if _group_contains(inv, pattern, h, budget) { out.push(h); }
      i = i + 1;
    }
    return out;
  }
  if _vec_has_str(&inv.hosts, pattern) { out.push(pattern); }
  return out;
}

/// Resolve a variable for a host under the documented precedence:
/// host vars > deeper group vars > shallower group vars; among groups of
/// equal depth the later declared wins; group vars on "all" are lowest.
pub fn inventory_var(inv: &Inventory, host: Str, key: Str) -> Result[Str, Str] {
  if !_vec_has_str(&inv.hosts, host) {
    return _str_err("ansible: unknown host: " + host);
  }
  var found = false;
  var best_depth = 0;
  var best_group = -1;
  var best_value = "";
  let budget = inv.groups.len() + 1;
  let total = inv.groups.len() + 1;
  var gi = 0;
  while gi < total {
    var g = "";
    if gi < inv.groups.len() {
      let gn: Str = inv.groups[gi];
      g = gn;
    } else {
      g = ANSIBLE_ALL;
    }
    if _group_contains(inv, g, host, budget) {
      let d = _group_depth(inv, g, budget);
      var vi = 0;
      while vi < inv.gvar_group.len() {
        let vg: Str = inv.gvar_group[vi];
        if _streq(vg, g) {
          let vk: Str = inv.gvar_key[vi];
          if _streq(vk, key) {
            var take = false;
            if !found { take = true; }
            if d > best_depth { take = true; }
            if d == best_depth && gi > best_group { take = true; }
            if take {
              found = true;
              best_depth = d;
              best_group = gi;
              let val: Str = inv.gvar_value[vi];
              best_value = val;
            }
          }
        }
        vi = vi + 1;
      }
    }
    gi = gi + 1;
  }
  var hi = 0;
  while hi < inv.hvar_host.len() {
    let hh: Str = inv.hvar_host[hi];
    if _streq(hh, host) {
      let hk: Str = inv.hvar_key[hi];
      if _streq(hk, key) {
        let hv: Str = inv.hvar_value[hi];
        return _str_ok(hv);
      }
    }
    hi = hi + 1;
  }
  if found { return _str_ok(best_value); }
  return _str_err("ansible: undefined variable: " + key);
}

/// `inventory_var` with a fallback for unknown hosts and undefined variables.
pub fn inventory_var_or(inv: &Inventory, host: Str, key: Str, fallback: Str) -> Str {
  match inventory_var(inv, host, key) {
    Ok(v) => { let s: Str = v; return s; },
    Err(_) => { return fallback; },
  }
  return fallback;
}

/// Structural validation of a hand-built inventory: every membership, child
/// and variable edge must reference registered hosts/groups. Builders already
/// enforce this; the check exists for values assembled field by field.
pub fn inventory_validate(inv: &Inventory) -> Result[Int, Str] {
  var i = 0;
  while i < inv.member_group.len() {
    let g: Str = inv.member_group[i];
    let h: Str = inv.member_host[i];
    if !_vec_has_str(&inv.groups, g) {
      return _int_err("ansible: invalid membership edge");
    }
    if !_vec_has_str(&inv.hosts, h) {
      return _int_err("ansible: invalid membership edge");
    }
    i = i + 1;
  }
  i = 0;
  while i < inv.child_group.len() {
    let p: Str = inv.parent_group[i];
    let c: Str = inv.child_group[i];
    if !_vec_has_str(&inv.groups, p) {
      return _int_err("ansible: invalid group child edge");
    }
    if !_vec_has_str(&inv.groups, c) {
      return _int_err("ansible: invalid group child edge");
    }
    i = i + 1;
  }
  i = 0;
  while i < inv.gvar_group.len() {
    let g: Str = inv.gvar_group[i];
    if !_streq(g, ANSIBLE_ALL) && !_vec_has_str(&inv.groups, g) {
      return _int_err("ansible: invalid group var edge");
    }
    i = i + 1;
  }
  i = 0;
  while i < inv.hvar_host.len() {
    let h: Str = inv.hvar_host[i];
    if !_vec_has_str(&inv.hosts, h) {
      return _int_err("ansible: invalid host var edge");
    }
    i = i + 1;
  }
  return _int_ok(inv.hosts.len());
}

// ---------------------------------------------------------------------------
// Module registry (explicit case dispatch; never a Vec[fn] table)
// ---------------------------------------------------------------------------

/// Kind code of a module name (ANSIBLE_MODULE_*), or ANSIBLE_MODULE_UNKNOWN.
/// This is the explicit case dispatch of the registry.
pub fn module_kind(name: Str) -> Int {
  if _streq(name, "ping") { return ANSIBLE_MODULE_PING; }
  if _streq(name, "debug") { return ANSIBLE_MODULE_DEBUG; }
  if _streq(name, "fail") { return ANSIBLE_MODULE_FAIL; }
  if _streq(name, "command") { return ANSIBLE_MODULE_COMMAND; }
  if _streq(name, "shell") { return ANSIBLE_MODULE_SHELL; }
  if _streq(name, "copy") { return ANSIBLE_MODULE_COPY; }
  if _streq(name, "template") { return ANSIBLE_MODULE_TEMPLATE; }
  if _streq(name, "file") { return ANSIBLE_MODULE_FILE; }
  if _streq(name, "package") { return ANSIBLE_MODULE_PACKAGE; }
  if _streq(name, "service") { return ANSIBLE_MODULE_SERVICE; }
  if _streq(name, "user") { return ANSIBLE_MODULE_USER; }
  if _streq(name, "setup") { return ANSIBLE_MODULE_SETUP; }
  return ANSIBLE_MODULE_UNKNOWN;
}

/// True when the name is a documented builtin module.
pub fn module_is_known(name: Str) -> Bool {
  return module_kind(name) != ANSIBLE_MODULE_UNKNOWN;
}

/// Canonical name of a module kind.
pub fn module_kind_name(kind: Int) -> Str {
  if kind == ANSIBLE_MODULE_PING { return "ping"; }
  if kind == ANSIBLE_MODULE_DEBUG { return "debug"; }
  if kind == ANSIBLE_MODULE_FAIL { return "fail"; }
  if kind == ANSIBLE_MODULE_COMMAND { return "command"; }
  if kind == ANSIBLE_MODULE_SHELL { return "shell"; }
  if kind == ANSIBLE_MODULE_COPY { return "copy"; }
  if kind == ANSIBLE_MODULE_TEMPLATE { return "template"; }
  if kind == ANSIBLE_MODULE_FILE { return "file"; }
  if kind == ANSIBLE_MODULE_PACKAGE { return "package"; }
  if kind == ANSIBLE_MODULE_SERVICE { return "service"; }
  if kind == ANSIBLE_MODULE_USER { return "user"; }
  if kind == ANSIBLE_MODULE_SETUP { return "setup"; }
  return "unknown";
}

/// The documented builtin module names in kind order.
pub fn module_names() -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  out.push("ping");
  out.push("debug");
  out.push("fail");
  out.push("command");
  out.push("shell");
  out.push("copy");
  out.push("template");
  out.push("file");
  out.push("package");
  out.push("service");
  out.push("user");
  out.push("setup");
  return out;
}

/// Number of documented builtin modules.
pub fn module_count() -> Int {
  return module_names().len();
}

/// Name of a result code.
pub fn module_result_name(code: Int) -> Str {
  if code == ANSIBLE_RESULT_OK { return "ok"; }
  if code == ANSIBLE_RESULT_CHANGED { return "changed"; }
  if code == ANSIBLE_RESULT_FAILED { return "failed"; }
  if code == ANSIBLE_RESULT_SKIPPED { return "skipped"; }
  return "unknown";
}

/// True when `args` contains the literal flag.
fn _arg_has(args: Str, flag: Str) -> Bool {
  if args.len() == 0 { return false; }
  return string.str_contains(args, flag);
}

/// Simulate a module execution from its name and argument text.
/// Deterministic rules:
///   * ping and debug always succeed without a change;
///   * fail always fails;
///   * an unknown module fails;
///   * otherwise the literal flags failed=1, skip=1 and changed=1 are checked
///     in that order and the last fallback is an unchanged ok.
pub fn module_simulate(mod_name: Str, args: Str) -> Int {
  let kind = module_kind(mod_name);
  if kind == ANSIBLE_MODULE_PING { return ANSIBLE_RESULT_OK; }
  if kind == ANSIBLE_MODULE_DEBUG { return ANSIBLE_RESULT_OK; }
  if kind == ANSIBLE_MODULE_FAIL { return ANSIBLE_RESULT_FAILED; }
  if kind == ANSIBLE_MODULE_UNKNOWN { return ANSIBLE_RESULT_FAILED; }
  if _arg_has(args, "failed=1") { return ANSIBLE_RESULT_FAILED; }
  if _arg_has(args, "skip=1") { return ANSIBLE_RESULT_SKIPPED; }
  if _arg_has(args, "changed=1") { return ANSIBLE_RESULT_CHANGED; }
  return ANSIBLE_RESULT_OK;
}

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------

/// True when the comma-separated tag string contains `tag` as one token.
/// Empty tag strings and empty tokens never match.
pub fn ansible_tags_has(tags: Str, tag: Str) -> Bool {
  if tags.len() == 0 || tag.len() == 0 { return false; }
  let parts = string.str_split(tags, ",");
  var i = 0;
  while i < parts.len() {
    let t: Str = parts[i];
    if _streq(t, tag) { return true; }
    i = i + 1;
  }
  return false;
}

/// Number of non-empty tags in a comma-separated tag string.
pub fn ansible_tags_count(tags: Str) -> Int {
  if tags.len() == 0 { return 0; }
  let parts = string.str_split(tags, ",");
  var n = 0;
  var i = 0;
  while i < parts.len() {
    let t: Str = parts[i];
    if t.len() > 0 { n = n + 1; }
    i = i + 1;
  }
  return n;
}

// Any of the three tag sources carries `tag`.
fn _tags_any(a: Str, b: Str, c: Str, tag: Str) -> Bool {
  if ansible_tags_has(a, tag) { return true; }
  if ansible_tags_has(b, tag) { return true; }
  if ansible_tags_has(c, tag) { return true; }
  return false;
}

/// Tag-filter decision for one task. The effective tags are the union of the
/// play, block and task tag strings. Rules:
///   * a task tagged "never" (in any of the three sources) runs only when the
///     request itself asks for "never";
///   * an empty request runs every non-"never" task;
///   * a task tagged "always" runs whenever a request is active;
///   * the token "all" in the request runs every non-"never" task;
///   * otherwise the task runs when any requested token matches any effective
///     tag.
pub fn ansible_tags_match(requested: Str, play_tags: Str, block_tags: Str, task_tags: Str) -> Bool {
  let has_never = _tags_any(play_tags, block_tags, task_tags, ANSIBLE_TAG_NEVER);
  if has_never {
    return ansible_tags_has(requested, ANSIBLE_TAG_NEVER);
  }
  if requested.len() == 0 { return true; }
  if _tags_any(play_tags, block_tags, task_tags, ANSIBLE_TAG_ALWAYS) { return true; }
  if ansible_tags_has(requested, ANSIBLE_ALL) { return true; }
  let parts = string.str_split(requested, ",");
  var i = 0;
  while i < parts.len() {
    let r: Str = parts[i];
    if r.len() > 0 {
      if _tags_any(play_tags, block_tags, task_tags, r) { return true; }
    }
    i = i + 1;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Playbook construction and validation
// ---------------------------------------------------------------------------

/// An empty playbook.
pub fn playbook_new() -> Playbook {
  return Playbook{
    play_names: Vec[Str].new();
    play_hosts: Vec[Str].new();
    play_strategy: Vec[Int].new();
    play_tags: Vec[Str].new();
    block_play: Vec[Int].new();
    block_names: Vec[Str].new();
    block_tags: Vec[Str].new();
    task_play: Vec[Int].new();
    task_block: Vec[Int].new();
    task_names: Vec[Str].new();
    task_module: Vec[Str].new();
    task_args: Vec[Str].new();
    task_tags: Vec[Str].new();
    task_notify: Vec[Str].new();
    handler_play: Vec[Int].new();
    handler_names: Vec[Str].new();
    handler_module: Vec[Str].new();
    handler_args: Vec[Str].new();
  };
}

/// True for ANSIBLE_STRATEGY_LINEAR or ANSIBLE_STRATEGY_FREE.
pub fn ansible_strategy_valid(strategy: Int) -> Bool {
  if strategy == ANSIBLE_STRATEGY_LINEAR { return true; }
  if strategy == ANSIBLE_STRATEGY_FREE { return true; }
  return false;
}

/// Name of a strategy code.
pub fn ansible_strategy_name(strategy: Int) -> Str {
  if strategy == ANSIBLE_STRATEGY_LINEAR { return "linear"; }
  if strategy == ANSIBLE_STRATEGY_FREE { return "free"; }
  return "unknown";
}

/// True when `play` is a valid play index.
fn _valid_play(pb: &Playbook, play: Int) -> Bool {
  if play < 0 { return false; }
  if play >= pb.play_names.len() { return false; }
  return true;
}

/// True when `block` is a valid block index.
fn _valid_block(pb: &Playbook, block: Int) -> Bool {
  if block < 0 { return false; }
  if block >= pb.block_names.len() { return false; }
  return true;
}

/// Add a play. `hosts` is a target pattern (host, group or "all"); `strategy`
/// is ANSIBLE_STRATEGY_LINEAR or ANSIBLE_STRATEGY_FREE.
pub fn playbook_add_play(pb: &mut Playbook, name: Str, hosts: Str, strategy: Int) -> Result[Int, Str] {
  if name.len() == 0 || hosts.len() == 0 {
    return _int_err("ansible: empty name");
  }
  if !ansible_strategy_valid(strategy) {
    return _int_err("ansible: invalid strategy");
  }
  if pb.play_names.len() >= ANSIBLE_MAX_PLAYS {
    return _int_err("ansible: capacity exceeded");
  }
  pb.play_names.push(name);
  pb.play_hosts.push(hosts);
  pb.play_strategy.push(strategy);
  pb.play_tags.push("");
  return _int_ok(pb.play_names.len() - 1);
}

/// Set or replace the tag string of a play.
pub fn playbook_set_play_tags(pb: &mut Playbook, play: Int, tags: Str) -> Result[Int, Str] {
  if !_valid_play(pb, play) {
    return _int_err("ansible: unknown play");
  }
  pb.play_tags[play] = tags;
  return _int_ok(play);
}

/// Add a block to a play. Blocks group tasks and carry tags that cascade to
/// their member tasks during tag filtering.
pub fn playbook_add_block(pb: &mut Playbook, play: Int, name: Str, tags: Str) -> Result[Int, Str] {
  if !_valid_play(pb, play) {
    return _int_err("ansible: unknown play");
  }
  if name.len() == 0 { return _int_err("ansible: empty name"); }
  if pb.block_names.len() >= ANSIBLE_MAX_BLOCKS {
    return _int_err("ansible: capacity exceeded");
  }
  pb.block_play.push(play);
  pb.block_names.push(name);
  pb.block_tags.push(tags);
  return _int_ok(pb.block_names.len() - 1);
}

/// Add a task to a play. `block` is a block index or -1 for play level; the
/// module must be in the registry; `notify` is a handler name or "".
pub fn playbook_add_task(pb: &mut Playbook, play: Int, block: Int, name: Str, mod_name: Str, args: Str, tags: Str, notify: Str) -> Result[Int, Str] {
  if !_valid_play(pb, play) {
    return _int_err("ansible: unknown play");
  }
  if block >= 0 {
    if !_valid_block(pb, block) {
      return _int_err("ansible: unknown block");
    }
    let owner: Int = pb.block_play[block];
    if owner != play {
      return _int_err("ansible: unknown block");
    }
  }
  if name.len() == 0 { return _int_err("ansible: empty name"); }
  if !module_is_known(mod_name) {
    return _int_err("ansible: unknown module: " + mod_name);
  }
  if pb.task_names.len() >= ANSIBLE_MAX_TASKS {
    return _int_err("ansible: capacity exceeded");
  }
  pb.task_play.push(play);
  pb.task_block.push(block);
  pb.task_names.push(name);
  pb.task_module.push(mod_name);
  pb.task_args.push(args);
  pb.task_tags.push(tags);
  pb.task_notify.push(notify);
  return _int_ok(pb.task_names.len() - 1);
}

/// Add a handler to a play. Handlers are addressed by name within the play.
pub fn playbook_add_handler(pb: &mut Playbook, play: Int, name: Str, mod_name: Str, args: Str) -> Result[Int, Str] {
  if !_valid_play(pb, play) {
    return _int_err("ansible: unknown play");
  }
  if name.len() == 0 { return _int_err("ansible: empty name"); }
  if !module_is_known(mod_name) {
    return _int_err("ansible: unknown module: " + mod_name);
  }
  if pb.handler_names.len() >= ANSIBLE_MAX_HANDLERS {
    return _int_err("ansible: capacity exceeded");
  }
  pb.handler_play.push(play);
  pb.handler_names.push(name);
  pb.handler_module.push(mod_name);
  pb.handler_args.push(args);
  return _int_ok(pb.handler_names.len() - 1);
}

/// Number of plays.
pub fn playbook_play_count(pb: &Playbook) -> Int {
  return pb.play_names.len();
}

/// Number of blocks.
pub fn playbook_block_count(pb: &Playbook) -> Int {
  return pb.block_names.len();
}

/// Number of tasks.
pub fn playbook_task_count(pb: &Playbook) -> Int {
  return pb.task_names.len();
}

/// Number of handlers.
pub fn playbook_handler_count(pb: &Playbook) -> Int {
  return pb.handler_names.len();
}

/// Play name at an index.
pub fn playbook_play_name(pb: &Playbook, i: Int) -> Result[Str, Str] {
  return _at(&pb.play_names, i, "play");
}

/// Play target pattern at an index.
pub fn playbook_play_hosts(pb: &Playbook, i: Int) -> Result[Str, Str] {
  return _at(&pb.play_hosts, i, "play");
}

/// Block name at an index.
pub fn playbook_block_name(pb: &Playbook, i: Int) -> Result[Str, Str] {
  return _at(&pb.block_names, i, "block");
}

/// Task name at an index.
pub fn playbook_task_name(pb: &Playbook, i: Int) -> Result[Str, Str] {
  return _at(&pb.task_names, i, "task");
}

/// Task module name at an index.
pub fn playbook_task_module(pb: &Playbook, i: Int) -> Result[Str, Str] {
  return _at(&pb.task_module, i, "task");
}

/// Handler name at an index.
pub fn playbook_handler_name(pb: &Playbook, i: Int) -> Result[Str, Str] {
  return _at(&pb.handler_names, i, "handler");
}

/// Index of handler `name` in play `play`, or -1.
fn _handler_index(pb: &Playbook, play: Int, name: Str) -> Int {
  var i = 0;
  while i < pb.handler_names.len() {
    let p: Int = pb.handler_play[i];
    if p == play {
      let n: Str = pb.handler_names[i];
      if _streq(n, name) { return i; }
    }
    i = i + 1;
  }
  return -1;
}

/// Validate a playbook: every task module is in the registry and every task
/// `notify` names a handler of the same play. Returns Ok(task count).
pub fn playbook_validate(pb: &mut Playbook) -> Result[Int, Str] {
  var i = 0;
  while i < pb.task_names.len() {
    let play: Int = pb.task_play[i];
    let mod_name: Str = pb.task_module[i];
    if !module_is_known(mod_name) {
      return _int_err("ansible: unknown module: " + mod_name);
    }
    let notify: Str = pb.task_notify[i];
    if notify.len() > 0 {
      if _handler_index(pb, play, notify) < 0 {
        return _int_err("ansible: unknown handler: " + notify);
      }
    }
    i = i + 1;
  }
  return _int_ok(pb.task_names.len());
}

// ---------------------------------------------------------------------------
// Fact store: public API
// ---------------------------------------------------------------------------

/// An empty fact store.
pub fn facts_new() -> FactStore {
  return FactStore{
    scopes: Vec[Str].new();
    keys: Vec[Str].new();
    kinds: Vec[Int].new();
    strs: Vec[Str].new();
    ints: Vec[Int].new();
  };
}

/// Number of stored facts.
pub fn facts_count(fs: &FactStore) -> Int {
  return fs.scopes.len();
}

/// True when (scope, key) exists.
pub fn facts_has(fs: &FactStore, scope: Str, key: Str) -> Bool {
  return _fact_index(fs, scope, key) >= 0;
}

/// Set or replace a Str fact.
pub fn facts_set_str(fs: &mut FactStore, scope: Str, key: Str, value: Str) -> Result[Int, Str] {
  if scope.len() == 0 || key.len() == 0 {
    return _int_err("ansible: empty name");
  }
  if _fact_index(fs, scope, key) < 0 && fs.scopes.len() >= ANSIBLE_MAX_FACTS {
    return _int_err("ansible: capacity exceeded");
  }
  return _int_ok(_facts_put_str(fs, scope, key, value));
}

/// Set or replace an Int fact.
pub fn facts_set_int(fs: &mut FactStore, scope: Str, key: Str, value: Int) -> Result[Int, Str] {
  if scope.len() == 0 || key.len() == 0 {
    return _int_err("ansible: empty name");
  }
  if _fact_index(fs, scope, key) < 0 && fs.scopes.len() >= ANSIBLE_MAX_FACTS {
    return _int_err("ansible: capacity exceeded");
  }
  return _int_ok(_facts_put_int(fs, scope, key, value));
}

/// Set or replace a Bool fact.
pub fn facts_set_bool(fs: &mut FactStore, scope: Str, key: Str, value: Bool) -> Result[Int, Str] {
  if scope.len() == 0 || key.len() == 0 {
    return _int_err("ansible: empty name");
  }
  if _fact_index(fs, scope, key) < 0 && fs.scopes.len() >= ANSIBLE_MAX_FACTS {
    return _int_err("ansible: capacity exceeded");
  }
  return _int_ok(_facts_put_bool(fs, scope, key, value));
}

/// Read a Str fact.
pub fn facts_get_str(fs: &FactStore, scope: Str, key: Str) -> Result[Str, Str] {
  let idx = _fact_index(fs, scope, key);
  if idx < 0 { return _str_err(_undefined_fact(scope, key)); }
  let kind: Int = fs.kinds[idx];
  if kind != ANSIBLE_FACT_STR {
    return _str_err("ansible: fact type mismatch: " + scope + "." + key);
  }
  let v: Str = fs.strs[idx];
  return _str_ok(v);
}

/// Read an Int fact.
pub fn facts_get_int(fs: &FactStore, scope: Str, key: Str) -> Result[Int, Str] {
  let idx = _fact_index(fs, scope, key);
  if idx < 0 { return _int_err(_undefined_fact(scope, key)); }
  let kind: Int = fs.kinds[idx];
  if kind != ANSIBLE_FACT_INT {
    return _int_err("ansible: fact type mismatch: " + scope + "." + key);
  }
  let v: Int = fs.ints[idx];
  return _int_ok(v);
}

/// Read a Bool fact.
pub fn facts_get_bool(fs: &FactStore, scope: Str, key: Str) -> Result[Bool, Str] {
  let idx = _fact_index(fs, scope, key);
  if idx < 0 { return _bool_err(_undefined_fact(scope, key)); }
  let kind: Int = fs.kinds[idx];
  if kind != ANSIBLE_FACT_BOOL {
    return _bool_err("ansible: fact type mismatch: " + scope + "." + key);
  }
  let v: Int = fs.ints[idx];
  if v != 0 { return _bool_ok(true); }
  return _bool_ok(false);
}

/// Number of facts whose scope is `scope`.
pub fn facts_scope_count(fs: &FactStore, scope: Str) -> Int {
  var n = 0;
  var i = 0;
  while i < fs.scopes.len() {
    let s: Str = fs.scopes[i];
    if _streq(s, scope) { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Sum of the Int facts in `scope` whose key starts with `prefix`. An empty
/// scope means every scope; an empty prefix means every key.
pub fn facts_sum_int(fs: &FactStore, scope: Str, prefix: Str) -> Int {
  var total = 0;
  var i = 0;
  while i < fs.scopes.len() {
    let s: Str = fs.scopes[i];
    let k: Str = fs.keys[i];
    let kind: Int = fs.kinds[i];
    if (scope.len() == 0 || _streq(s, scope)) && kind == ANSIBLE_FACT_INT {
      if prefix.len() == 0 || string.str_starts_with(k, prefix) {
        let v: Int = fs.ints[i];
        total = total + v;
      }
    }
    i = i + 1;
  }
  return total;
}

/// Count the Str facts named `key` with value `value` across every scope.
pub fn facts_count_str(fs: &FactStore, key: Str, value: Str) -> Int {
  var n = 0;
  var i = 0;
  while i < fs.scopes.len() {
    let k: Str = fs.keys[i];
    let kind: Int = fs.kinds[i];
    if kind == ANSIBLE_FACT_STR && _streq(k, key) {
      let v: Str = fs.strs[i];
      if _streq(v, value) { n = n + 1; }
    }
    i = i + 1;
  }
  return n;
}

// ---------------------------------------------------------------------------
// Executor internals
// ---------------------------------------------------------------------------

/// An empty run report.
fn _report_new() -> RunReport {
  return RunReport{
    play_names: Vec[Str].new();
    task_names: Vec[Str].new();
    hosts: Vec[Str].new();
    modules: Vec[Str].new();
    results: Vec[Int].new();
    trace: Vec[Str].new();
    handler_play: Vec[Str].new();
    handler_names: Vec[Str].new();
    handler_hosts: Vec[Str].new();
    handler_results: Vec[Int].new();
    notified: Vec[Str].new();
    changed: 0;
    ok: 0;
    failed: 0;
    skipped: 0;
    filtered: 0;
  };
}

// Render one trace line.
fn _trace_line(play: Str, task: Str, host: Str, code: Int) -> Str {
  return play + " | " + task + " | " + host + " | " + module_result_name(code);
}

// Increment the counter that belongs to `code`.
fn _bump(rep: &mut RunReport, code: Int) {
  if code == ANSIBLE_RESULT_CHANGED { rep.changed = rep.changed + 1; }
  if code == ANSIBLE_RESULT_OK { rep.ok = rep.ok + 1; }
  if code == ANSIBLE_RESULT_FAILED { rep.failed = rep.failed + 1; }
  if code == ANSIBLE_RESULT_SKIPPED { rep.skipped = rep.skipped + 1; }
}

// Record one executed task line.
fn _record(rep: &mut RunReport, play: Str, task: Str, host: Str, mod_name: Str, code: Int) {
  rep.play_names.push(play);
  rep.task_names.push(task);
  rep.hosts.push(host);
  rep.modules.push(mod_name);
  rep.results.push(code);
  rep.trace.push(_trace_line(play, task, host, code));
  _bump(rep, code);
}

// Record one executed handler line.
fn _record_handler(rep: &mut RunReport, play: Str, handler: Str, host: Str, code: Int) {
  rep.handler_play.push(play);
  rep.handler_names.push(handler);
  rep.handler_hosts.push(host);
  rep.handler_results.push(code);
  rep.trace.push(_trace_line(play, handler, host, code));
  _bump(rep, code);
}

// True when the (handler, host) pair was already notified.
fn _pair_present(handlers: &Vec[Str], hosts: &Vec[Str], handler: Str, host: Str) -> Bool {
  var i = 0;
  while i < handlers.len() {
    let h: Str = handlers[i];
    let hs: Str = hosts[i];
    if _streq(h, handler) && _streq(hs, host) { return true; }
    i = i + 1;
  }
  return false;
}

// Notify a handler for a host: the (handler, host) pair is recorded once and
// the handler enters the queue at its first notification.
fn _notify(n: &mut Notifier, handler: Str, host: Str) {
  if _pair_present(&n.handlers, &n.hosts, handler, host) { return; }
  n.handlers.push(handler);
  n.hosts.push(host);
  if !_vec_has_str(&n.queue, handler) { n.queue.push(handler); }
}

// Number of tasks that belong to play `pi`.
fn _count_play_tasks(pb: &Playbook, pi: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < pb.task_names.len() {
    let p: Int = pb.task_play[i];
    if p == pi { n = n + 1; }
    i = i + 1;
  }
  return n;
}

// Block tags of task `ti` ("" when the task is at play level).
fn _block_tags_of(pb: &Playbook, ti: Int) -> Str {
  let b: Int = pb.task_block[ti];
  if b < 0 { return ""; }
  if b >= pb.block_tags.len() { return ""; }
  let t: Str = pb.block_tags[b];
  return t;
}

// Tag-filter decision for one task of play `pi`.
fn _task_selected(pb: &Playbook, ti: Int, requested: Str, ptags: Str) -> Bool {
  let btags = _block_tags_of(pb, ti);
  let ttags: Str = pb.task_tags[ti];
  return ansible_tags_match(requested, ptags, btags, ttags);
}

// Number of tasks of play `pi` that pass the tag filter.
fn _count_selected(pb: &Playbook, pi: Int, requested: Str) -> Int {
  let ptags: Str = pb.play_tags[pi];
  var n = 0;
  var i = 0;
  while i < pb.task_names.len() {
    let p: Int = pb.task_play[i];
    if p == pi {
      if _task_selected(pb, i, requested, ptags) { n = n + 1; }
    }
    i = i + 1;
  }
  return n;
}

// Resolve play target pattern then apply the limit pattern ("" or "all" = no
// limit; otherwise a host or group name).
fn _limit_hosts(inv: &Inventory, pattern: Str, limit: Str) -> Vec[Str] {
  let all = inventory_target_hosts(inv, pattern);
  if limit.len() == 0 { return all; }
  if _streq(limit, ANSIBLE_ALL) { return all; }
  let wanted = inventory_target_hosts(inv, limit);
  var out: Vec[Str] = Vec[Str].new();
  var i = 0;
  while i < all.len() {
    let h: Str = all[i];
    if _vec_has_str(&wanted, h) { out.push(h); }
    i = i + 1;
  }
  return out;
}

// Gather the typed setup facts for `host`. Returns 0, or -1 when the store
// has no room for the new keys.
fn _gather_facts(inv: &Inventory, fs: &mut FactStore, host: Str) -> Int {
  var need = 0;
  if _fact_index(fs, host, "ansible_host_name") < 0 { need = need + 1; }
  if _fact_index(fs, host, "ansible_distribution") < 0 { need = need + 1; }
  if _fact_index(fs, host, "ansible_cpu_count") < 0 { need = need + 1; }
  if _fact_index(fs, host, "ansible_gathered") < 0 { need = need + 1; }
  if fs.scopes.len() + need > ANSIBLE_MAX_FACTS { return -1; }
  _facts_put_str(fs, host, "ansible_host_name", host);
  let dist = inventory_var_or(inv, host, "ansible_distribution", "unknown");
  _facts_put_str(fs, host, "ansible_distribution", dist);
  let cpu_s = inventory_var_or(inv, host, "ansible_cpu_count", "0");
  var cpu = 0;
  match string.str_to_int(cpu_s) {
    Ok(v) => { let cv: Int = v; cpu = cv; },
    Err(_) => { cpu = 0; },
  }
  _facts_put_int(fs, host, "ansible_cpu_count", cpu);
  _facts_put_bool(fs, host, "ansible_gathered", true);
  return 0;
}

// Execute one task for one host. Returns 0, or a negative error code
// (-1 trace capacity, -2 fact capacity).
fn _execute_task(pb: &Playbook, inv: &Inventory, fs: &mut FactStore, rep: &mut RunReport, pi: Int, ti: Int, st: &mut RunState, hi: Int) -> Int {
  let pname: Str = pb.play_names[pi];
  let tname: Str = pb.task_names[ti];
  let host: Str = st.targets[hi];
  let mod_name: Str = pb.task_module[ti];
  let args: Str = pb.task_args[ti];
  let flag: Int = st.flags[hi];
  if flag != 0 {
    _record(rep, pname, tname, host, mod_name, ANSIBLE_RESULT_SKIPPED);
    return 0;
  }
  let kind = module_kind(mod_name);
  if kind == ANSIBLE_MODULE_SETUP {
    let rc = _gather_facts(inv, fs, host);
    if rc < 0 { return -2; }
  }
  let code = module_simulate(mod_name, args);
  _record(rep, pname, tname, host, mod_name, code);
  if code == ANSIBLE_RESULT_FAILED { st.flags[hi] = 1; }
  if code == ANSIBLE_RESULT_CHANGED {
    let notify: Str = pb.task_notify[ti];
    if notify.len() > 0 {
      _notify(&mut st.notifier, notify, host);
    }
  }
  return 0;
}

// Run one play: tag-filtered tasks under the play strategy, then the notified
// handlers in first-notification order. Returns 0, or a negative error code.
fn _run_play(pb: &Playbook, inv: &Inventory, fs: &mut FactStore, pi: Int, requested: Str, limit: Str, rep: &mut RunReport) -> Int {
  let pname: Str = pb.play_names[pi];
  let phosts: Str = pb.play_hosts[pi];
  let strategy: Int = pb.play_strategy[pi];
  let ptags: Str = pb.play_tags[pi];
  let targets = _limit_hosts(inv, phosts, limit);
  let selected = _count_selected(pb, pi, requested);
  let total = _count_play_tasks(pb, pi);
  rep.filtered = rep.filtered + (total - selected);
  if targets.len() == 0 { return 0; }
  let needed = rep.task_names.len() + rep.handler_names.len() + (selected * targets.len() * 2) + 1;
  if needed > ANSIBLE_MAX_TRACE { return -1; }
  var flags: Vec[Int] = Vec[Int].new();
  var fi = 0;
  while fi < targets.len() {
    flags.push(0);
    fi = fi + 1;
  }
  var st = RunState{
    targets: targets;
    flags: flags;
    notifier: Notifier{ queue: Vec[Str].new(); handlers: Vec[Str].new(); hosts: Vec[Str].new(); };
  };
  if strategy == ANSIBLE_STRATEGY_LINEAR {
    var ti = 0;
    while ti < pb.task_names.len() {
      let tplay: Int = pb.task_play[ti];
      if tplay == pi {
        if _task_selected(pb, ti, requested, ptags) {
          var hi = 0;
          while hi < st.targets.len() {
            let rc = _execute_task(pb, inv, fs, rep, pi, ti, &mut st, hi);
            if rc < 0 { return rc; }
            hi = hi + 1;
          }
        }
      }
      ti = ti + 1;
    }
  } else {
    var hi = 0;
    while hi < st.targets.len() {
      var ti = 0;
      while ti < pb.task_names.len() {
        let tplay: Int = pb.task_play[ti];
        if tplay == pi {
          if _task_selected(pb, ti, requested, ptags) {
            let rc = _execute_task(pb, inv, fs, rep, pi, ti, &mut st, hi);
            if rc < 0 { return rc; }
          }
        }
        ti = ti + 1;
      }
      hi = hi + 1;
    }
  }
  var qi = 0;
  while qi < st.notifier.queue.len() {
    let hname: Str = st.notifier.queue[qi];
    rep.notified.push(hname);
    let hidx = _handler_index(pb, pi, hname);
    if hidx >= 0 {
      let hmod: Str = pb.handler_module[hidx];
      let hargs: Str = pb.handler_args[hidx];
      var hi = 0;
      while hi < st.targets.len() {
        let host: Str = st.targets[hi];
        let flag: Int = st.flags[hi];
        if flag == 0 {
          if _pair_present(&st.notifier.handlers, &st.notifier.hosts, hname, host) {
            let code = module_simulate(hmod, hargs);
            _record_handler(rep, pname, hname, host, code);
          }
        }
        hi = hi + 1;
      }
    }
    qi = qi + 1;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Public executor
// ---------------------------------------------------------------------------

/// Execute a validated playbook against an inventory. `tags` is the requested
/// tag filter ("" = all non-never tasks, "all" = all non-never tasks) and
/// `limit` restricts hosts ("" or "all" = no restriction, otherwise a host or
/// group name). Setup tasks gather typed facts into `fs`. Returns the run
/// report, or an error when the playbook is invalid or a capacity is hit.
pub fn run_playbook(pb: &mut Playbook, inv: &Inventory, fs: &mut FactStore, tags: Str, limit: Str) -> Result[RunReport, Str] {
  var valid = true;
  var msg = "";
  match playbook_validate(pb) {
    Ok(_) => { valid = true; },
    Err(m) => { valid = false; msg = m; },
  }
  if !valid { return _rep_err(msg); }
  var rep = _report_new();
  var pi = 0;
  while pi < pb.play_names.len() {
    let rc = _run_play(pb, inv, fs, pi, tags, limit, &mut rep);
    if rc == -1 { return _rep_err("ansible: trace capacity exceeded"); }
    if rc == -2 { return _rep_err("ansible: fact capacity exceeded"); }
    pi = pi + 1;
  }
  return _rep_ok(rep);
}

// ---------------------------------------------------------------------------
// RunReport accessors
// ---------------------------------------------------------------------------

/// Number of executed task lines.
pub fn report_len(rep: &RunReport) -> Int {
  return rep.task_names.len();
}

/// Result code of task line `i`, or -1 out of range.
pub fn report_result(rep: &RunReport, i: Int) -> Int {
  if i < 0 || i >= rep.results.len() { return -1; }
  let v: Int = rep.results[i];
  return v;
}

/// Play name of task line `i`.
pub fn report_play_name(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.play_names, i, "result");
}

/// Task name of task line `i`.
pub fn report_task_name(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.task_names, i, "result");
}

/// Host of task line `i`.
pub fn report_host(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.hosts, i, "result");
}

/// Module of task line `i`.
pub fn report_module(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.modules, i, "result");
}

/// Trace line `i`.
pub fn report_trace_at(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.trace, i, "trace");
}

/// Number of task lines with result code `code`.
pub fn report_result_count(rep: &RunReport, code: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < rep.results.len() {
    let c: Int = rep.results[i];
    if c == code { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Number of queued handler notifications.
pub fn report_notified_count(rep: &RunReport) -> Int {
  return rep.notified.len();
}

/// Queued handler name at `i`.
pub fn report_notified_at(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.notified, i, "notified");
}

/// Number of executed handler lines.
pub fn report_handler_count(rep: &RunReport) -> Int {
  return rep.handler_names.len();
}

/// Handler name of handler line `i`.
pub fn report_handler_name(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.handler_names, i, "handler");
}

/// Host of handler line `i`.
pub fn report_handler_host(rep: &RunReport, i: Int) -> Result[Str, Str] {
  return _at(&rep.handler_hosts, i, "handler");
}

/// Result code of handler line `i`, or -1 out of range.
pub fn report_handler_result(rep: &RunReport, i: Int) -> Int {
  if i < 0 || i >= rep.handler_results.len() { return -1; }
  let v: Int = rep.handler_results[i];
  return v;
}

/// The whole trace, one line per entry, LF-joined.
pub fn report_trace_text(rep: &RunReport) -> Str {
  var out = "";
  var i = 0;
  while i < rep.trace.len() {
    let line: Str = rep.trace[i];
    if i > 0 { out = out + "\n"; }
    out = out + line;
    i = i + 1;
  }
  return out;
}

/// One-line counter summary: "changed=N ok=N failed=N skipped=N filtered=N".
pub fn report_summary(rep: &RunReport) -> Str {
  return "changed=" + convert.int_to_string(rep.changed) + " ok=" + convert.int_to_string(rep.ok) + " failed=" + convert.int_to_string(rep.failed) + " skipped=" + convert.int_to_string(rep.skipped) + " filtered=" + convert.int_to_string(rep.filtered);
}

// ---------------------------------------------------------------------------
// Sanity: every non-empty tag string token count and a deterministic render
// used by the conformance suite.
// ---------------------------------------------------------------------------

/// Render the executed task order as "task@host" entries joined with commas.
pub fn report_order_text(rep: &RunReport) -> Str {
  var out = "";
  var i = 0;
  while i < rep.task_names.len() {
    let t: Str = rep.task_names[i];
    let h: Str = rep.hosts[i];
    if i > 0 { out = out + ","; }
    out = out + t + "@" + h;
    i = i + 1;
  }
  return out;
}

