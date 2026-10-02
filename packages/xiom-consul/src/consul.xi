// XIOM -- xiom.consul: deterministic Consul protocol model (no HTTP)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM, transport-free model of the parts of the Consul agent/HTTP API
// protocol that are pure semantics: the KV store (get/put/delete, CAS modes,
// monotonic store/modify indexes, tombstones, session locks and lock-delay),
// the service + check registry (register/deregister, TTL/HTTP/TCP check
// configuration shapes, status transitions and aggregate service health), the
// session lifecycle (create/renew/invalidate, TTL expiry, release-vs-delete
// behavior on invalidation) and the ACL token/policy model (the rules subset
// and capability resolution on paths).
//
// Overlap boundary (see SPEC.md): xiom.discovery owns the generic service
// discovery abstraction (weighted selection, watches, tag lookups, sweeps).
// xiom.consul owns the Consul-specific protocol semantics: the KV index/CAS
// model, check IDs and statuses, session behavior and ACL rules. It does not
// implement discovery selection or watches.
//
// Not in scope: HTTP, sockets, the agent, gossip/consensus, blocking queries,
// blocking indexes, health checking execution, snapshotting, DNS interface,
// Connect, intentions, prepared queries, namespaces, admin partitions,
// enterprise features, wall clock (all time is an integer tick the caller
// advances).
//
// Semantics are deterministic and total. Every mutation is explicit; every
// read is bounds-checked; every list is a set of parallel vectors (the
// compiler does not support Vec[StructType]) that never drift: each helper
// pushes or removes every sibling at once, and accessors guard mismatches.
//
// Language notes (XIOM v0.62.2):
//   * free functions only; Ok/Err are constructed only inside the leaf
//     helpers below;
//   * every byte read widens with `(b as Int) & 0xFF`;
//   * Str values are compared with xiom.string.compare.str_compare, never
//     with `==`;
//   * Vec element reads are bound to typed locals first;
//   * no `match`, no lambdas, no Vec[StructType], no Vec[Float64], no FFI,
//     no `&mut Int` scalar parameters (scalar state is threaded through
//     returns);
//   * every loop is bounded by a vector or string length and every iteration
//     makes progress.

module xiom.consul

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.convert;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// The Consul KV store model. Entries are parallel vectors sharing one
/// length; `keys.len()` is the entry count (live keys plus tombstones).
/// `present[i]` is 1 for a live key and 0 for a tombstone (a key deleted
/// after having existed; Consul keeps it listed so blocking queries can
/// observe the delete). `index` is the store-wide monotonic write index;
/// every successful write bumps it and stamps `modify_indexes[i]` with the
/// new value, so `index` is always the largest modify index ever written.
/// `create_indexes[i]` is set once when the key is first created (and again
/// if a tombstone is re-created). `lock_sessions[i]` is the session id that
/// holds the key ("" = unlocked), `lock_indexes[i]` the index of the
/// acquire, `lock_delays[i]` the remaining lock-delay ticks after a session
/// invalidation.
pub type ConsulKvStore = {
  keys: Vec[Str];
  values: Vec[Str];
  flags: Vec[Int];
  create_indexes: Vec[Int];
  modify_indexes: Vec[Int];
  present: Vec[Int];
  lock_sessions: Vec[Str];
  lock_indexes: Vec[Int];
  lock_delays: Vec[Int];
  index: Int;
}

/// The service and check registry. The five service vectors and the thirteen
/// check vectors are each parallel and share one length; `service_ids.len()`
/// and `check_ids.len()` are the counts. A check with an empty `service_id`
/// is node-level.
pub type ConsulServiceRegistry = {
  service_ids: Vec[Str];
  service_names: Vec[Str];
  service_addresses: Vec[Str];
  service_ports: Vec[Int];
  service_tags: Vec[Str];
  check_ids: Vec[Str];
  check_service_ids: Vec[Str];
  check_names: Vec[Str];
  check_kinds: Vec[Int];
  check_statuses: Vec[Int];
  check_ttls: Vec[Int];
  check_remainings: Vec[Int];
  check_intervals: Vec[Int];
  check_timeouts: Vec[Int];
  check_urls: Vec[Str];
  check_hosts: Vec[Str];
  check_ports: Vec[Int];
  check_notes: Vec[Str];
}

/// The session table. Sessions are never removed: `invalidated[i]` marks an
/// ended session (1) or a live one (0). `remainings[i]` counts down in ticks
/// and is reset to `ttls[i]` by renew. `behaviors[i]` is
/// CONSUL_BEHAVIOR_RELEASE or CONSUL_BEHAVIOR_DELETE and selects what
/// happens to the keys the session held when it is invalidated.
/// `lock_delays[i]` is the lock-delay applied to those keys on invalidation.
pub type ConsulSessions = {
  ids: Vec[Str];
  ttls: Vec[Int];
  remainings: Vec[Int];
  behaviors: Vec[Int];
  lock_delays: Vec[Int];
  invalidated: Vec[Int];
}

/// A parsed ACL rule set: four parallel vectors sharing one length.
/// `resource_codes[i]` is a CONSUL_RES_* code, `scopes[i]` is 0 for an exact
/// match and 1 for a prefix match, `paths[i]` the matched path and
/// `actions[i]` a CONSUL_ACL_* code.
pub type ConsulPolicyRules = {
  resource_codes: Vec[Int];
  scopes: Vec[Int];
  paths: Vec[Str];
  actions: Vec[Int];
}

/// The ACL store: policies parsed into flat rule vectors with an offsets
/// table, and tokens with a comma-joined policy list. The invariant is
/// `policy_rule_offsets.len() == policy_names.len() + 1` (the first offset is
/// 0; policy `i` owns rules `[offsets[i], offsets[i+1])`), and every
/// `token_policy_lists[i]` element names an existing policy.
pub type ConsulAcl = {
  policy_names: Vec[Str];
  policy_rule_offsets: Vec[Int];
  rule_resource_codes: Vec[Int];
  rule_scopes: Vec[Int];
  rule_paths: Vec[Str];
  rule_actions: Vec[Int];
  token_ids: Vec[Str];
  token_descriptions: Vec[Str];
  token_policy_lists: Vec[Str];
  token_management: Vec[Int];
  token_valid: Vec[Int];
}

// Internal parser span: `size < 0` marks a malformed token.
type ConsulSpan = {
  start: Int;
  size: Int;
}

// ---------------------------------------------------------------------------
// Result leaf constructors
// ---------------------------------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[ConsulPolicyRules, Str].
fn _ok_rules(v: ConsulPolicyRules) -> Result[ConsulPolicyRules, Str] {
  return Ok(v);
}

// Err(m) for Result[ConsulPolicyRules, Str].
fn _err_rules(m: Str) -> Result[ConsulPolicyRules, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// CAS mode: no check (unconditional put/delete).
pub const CONSUL_CAS_NONE: Int = -1;

/// CAS mode: create-only (put succeeds only when the key does not exist).
pub const CONSUL_CAS_CREATE: Int = 0;

/// Check/service health: passing.
pub const CONSUL_STATUS_PASSING: Int = 0;

/// Check/service health: warning.
pub const CONSUL_STATUS_WARNING: Int = 1;

/// Check/service health: critical.
pub const CONSUL_STATUS_CRITICAL: Int = 2;

/// Check kind: TTL check.
pub const CONSUL_CHECK_TTL: Int = 0;

/// Check kind: HTTP check.
pub const CONSUL_CHECK_HTTP: Int = 1;

/// Check kind: TCP check.
pub const CONSUL_CHECK_TCP: Int = 2;

/// Session behavior: release the held locks on invalidation.
pub const CONSUL_BEHAVIOR_RELEASE: Int = 0;

/// Session behavior: delete the keys held on invalidation.
pub const CONSUL_BEHAVIOR_DELETE: Int = 1;

/// ACL action: no access.
pub const CONSUL_ACL_NONE: Int = 0;

/// ACL action: read.
pub const CONSUL_ACL_READ: Int = 1;

/// ACL action: write (implies read).
pub const CONSUL_ACL_WRITE: Int = 2;

/// ACL action: list keys.
pub const CONSUL_ACL_LIST: Int = 3;

/// ACL action: explicit deny (wins over every grant).
pub const CONSUL_ACL_DENY: Int = 4;

/// ACL resource code: key.
pub const CONSUL_RES_KEY: Int = 0;

/// ACL resource code: node.
pub const CONSUL_RES_NODE: Int = 1;

/// ACL resource code: service.
pub const CONSUL_RES_SERVICE: Int = 2;

/// ACL resource code: session.
pub const CONSUL_RES_SESSION: Int = 3;

/// ACL resource code: acl.
pub const CONSUL_RES_ACL: Int = 4;

/// ACL resource code: event.
pub const CONSUL_RES_EVENT: Int = 5;

/// ACL resource code: query.
pub const CONSUL_RES_QUERY: Int = 6;

/// Sentinel returned by *_find and index accessors: not found.
pub const CONSUL_NOT_FOUND: Int = -1;

// ---------------------------------------------------------------------------
// String and byte helpers
// ---------------------------------------------------------------------------

// Byte at `i` widened to 0..255; callers guarantee the bounds.
fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Str equality through xiom.string.compare (never `==`).
fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when every byte is printable ASCII (0x20..0x7E).
fn _is_printable(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = _byte_at(s, i);
    if b < 32 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `p` is a prefix of `s` (the empty prefix matches everything).
fn _has_prefix(s: Str, p: Str) -> Bool {
  if p.len() > s.len() {
    return false;
  }
  var i = 0;
  while i < p.len() {
    if _byte_at(s, i) != _byte_at(p, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The first index of `s` in a sequential Str vector, or CONSUL_NOT_FOUND.
fn _find_str(v: &Vec[Str], s: Str) -> Int {
  var i = 0;
  while i < v.len() {
    let e: Str = v[i];
    if compare.str_compare(e, s) == 0 {
      return i;
    }
    i = i + 1;
  }
  return CONSUL_NOT_FOUND;
}

// Element count of a comma-joined list ("" has 0 elements).
fn _list_count(list: Str) -> Int {
  if list.len() == 0 {
    return 0;
  }
  var n = 1;
  var i = 0;
  while i < list.len() {
    if _byte_at(list, i) == 44 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// Span of the k-th element of a comma-joined list; callers guarantee
// 0 <= k < _list_count(list).
fn _list_span(list: Str, k: Int) -> ConsulSpan {
  var elem = 0;
  var start = 0;
  var i = 0;
  while i <= list.len() {
    if i == list.len() || _byte_at(list, i) == 44 {
      if elem == k {
        return ConsulSpan{ start: start; size: i - start };
      }
      elem = elem + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return ConsulSpan{ start: list.len(); size: 0 };
}

// True when `item` is a whole element of the comma-joined `list`.
fn _list_has(list: Str, item: Str) -> Bool {
  if item.len() == 0 || list.len() == 0 {
    return false;
  }
  let n = _list_count(list);
  var k = 0;
  while k < n {
    let sp = _list_span(list, k);
    if sp.size == item.len() {
      var j = 0;
      var eq = true;
      while j < sp.size {
        if _byte_at(list, sp.start + j) != _byte_at(item, j) {
          eq = false;
        }
        j = j + 1;
      }
      if eq {
        return true;
      }
    }
    k = k + 1;
  }
  return false;
}

// The bytes of a validated printable span as a Str (no NUL can be present,
// so the string builder cannot abort).
fn _span_to_str(text: Str, start: Int, size: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < size {
    sb.push(string.byte_at(text, start + i));
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Bytes of [start, start+size) equal the literal `lit`.
fn _word_eq(text: Str, start: Int, size: Int, lit: Str) -> Bool {
  if size != lit.len() {
    return false;
  }
  var i = 0;
  while i < size {
    if _byte_at(text, start + i) != _byte_at(lit, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The `size` last bytes of [start, start+size) equal `suf`.
fn _word_eq_suffix(text: Str, start: Int, size: Int, suf: Str) -> Bool {
  if suf.len() > size {
    return false;
  }
  var i = 0;
  while i < suf.len() {
    if _byte_at(text, start + size - suf.len() + i) != _byte_at(suf, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Skip spaces and tabs from `pos`; returns the first non-blank position.
fn _skip_ws(text: Str, pos: Int, end: Int) -> Int {
  var i = pos;
  var go = true;
  while i < end && go {
    let b = _byte_at(text, i);
    if b == 32 || b == 9 {
      i = i + 1;
    } else {
      go = false;
    }
  }
  return i;
}

// Scan a word at `pos` (stops at blank, quote, brace or equals); a
// non-printable byte yields size -1. An empty word has size 0.
fn _scan_word(text: Str, pos: Int, end: Int) -> ConsulSpan {
  var i = pos;
  var go = true;
  while i < end && go {
    let b = _byte_at(text, i);
    if b == 32 || b == 9 || b == 34 || b == 123 || b == 61 || b == 125 {
      go = false;
    } else {
      if b < 32 || b > 126 {
        return ConsulSpan{ start: pos; size: -1 };
      }
      i = i + 1;
    }
  }
  return ConsulSpan{ start: pos; size: i - pos };
}

// Scan a double-quoted string at `pos`; a missing closing quote or a
// non-printable byte yields size -1. The span excludes the quotes; the
// closing quote is at start + size.
fn _scan_quoted(text: Str, pos: Int, end: Int) -> ConsulSpan {
  if pos >= end {
    return ConsulSpan{ start: pos; size: -1 };
  }
  if _byte_at(text, pos) != 34 {
    return ConsulSpan{ start: pos; size: -1 };
  }
  var i = pos + 1;
  var go = true;
  while i < end && go {
    let b = _byte_at(text, i);
    if b == 34 {
      go = false;
    } else {
      if b < 32 || b > 126 {
        return ConsulSpan{ start: pos; size: -1 };
      }
      i = i + 1;
    }
  }
  if i >= end {
    return ConsulSpan{ start: pos; size: -1 };
  }
  return ConsulSpan{ start: pos + 1; size: i - pos - 1 };
}

// The ACL resource code for a whole resource word, or -1.
fn _resource_code(word: Str) -> Int {
  if _str_eq(word, "key") {
    return CONSUL_RES_KEY;
  }
  if _str_eq(word, "node") {
    return CONSUL_RES_NODE;
  }
  if _str_eq(word, "service") {
    return CONSUL_RES_SERVICE;
  }
  if _str_eq(word, "session") {
    return CONSUL_RES_SESSION;
  }
  if _str_eq(word, "acl") {
    return CONSUL_RES_ACL;
  }
  if _str_eq(word, "event") {
    return CONSUL_RES_EVENT;
  }
  if _str_eq(word, "query") {
    return CONSUL_RES_QUERY;
  }
  return CONSUL_NOT_FOUND;
}

// The ACL resource code for a rule word at [start, start+size): with
// scope 0 the word is the resource name; with scope 1 the word is
// `<resource>_prefix` (never `acl_prefix`). Returns -1 when unknown.
fn _resource_code_word(text: Str, start: Int, size: Int, scope: Int) -> Int {
  if scope == 0 {
    if _word_eq(text, start, size, "key") {
      return CONSUL_RES_KEY;
    }
    if _word_eq(text, start, size, "node") {
      return CONSUL_RES_NODE;
    }
    if _word_eq(text, start, size, "service") {
      return CONSUL_RES_SERVICE;
    }
    if _word_eq(text, start, size, "session") {
      return CONSUL_RES_SESSION;
    }
    if _word_eq(text, start, size, "acl") {
      return CONSUL_RES_ACL;
    }
    if _word_eq(text, start, size, "event") {
      return CONSUL_RES_EVENT;
    }
    if _word_eq(text, start, size, "query") {
      return CONSUL_RES_QUERY;
    }
    return CONSUL_NOT_FOUND;
  }
  if !_word_eq_suffix(text, start, size, "_prefix") {
    return CONSUL_NOT_FOUND;
  }
  let base = size - 7;
  if base <= 0 {
    return CONSUL_NOT_FOUND;
  }
  if _word_eq(text, start, base, "key") {
    return CONSUL_RES_KEY;
  }
  if _word_eq(text, start, base, "node") {
    return CONSUL_RES_NODE;
  }
  if _word_eq(text, start, base, "service") {
    return CONSUL_RES_SERVICE;
  }
  if _word_eq(text, start, base, "session") {
    return CONSUL_RES_SESSION;
  }
  if _word_eq(text, start, base, "event") {
    return CONSUL_RES_EVENT;
  }
  if _word_eq(text, start, base, "query") {
    return CONSUL_RES_QUERY;
  }
  return CONSUL_NOT_FOUND;
}

// The ACL action code for a word span, or -1.
fn _action_code_word(text: Str, start: Int, size: Int) -> Int {
  if _word_eq(text, start, size, "read") {
    return CONSUL_ACL_READ;
  }
  if _word_eq(text, start, size, "write") {
    return CONSUL_ACL_WRITE;
  }
  if _word_eq(text, start, size, "list") {
    return CONSUL_ACL_LIST;
  }
  if _word_eq(text, start, size, "deny") {
    return CONSUL_ACL_DENY;
  }
  return CONSUL_NOT_FOUND;
}

// ---------------------------------------------------------------------------
// KV store: lifecycle, lookups, accessors
// ---------------------------------------------------------------------------

/// A fresh empty KV store with store index 0. Complexity: O(1).
pub fn consul_kv_new() -> ConsulKvStore {
  return ConsulKvStore{
    keys: Vec[Str].new();
    values: Vec[Str].new();
    flags: Vec[Int].new();
    create_indexes: Vec[Int].new();
    modify_indexes: Vec[Int].new();
    present: Vec[Int].new();
    lock_sessions: Vec[Str].new();
    lock_indexes: Vec[Int].new();
    lock_delays: Vec[Int].new();
    index: 0;
  };
}

/// The current store index (0 before the first write; the largest modify
/// index ever written afterwards). Complexity: O(1).
pub fn consul_kv_index(kv: &ConsulKvStore) -> Int {
  return kv.index;
}

/// The number of entries: live keys plus tombstones. Complexity: O(1).
pub fn consul_kv_entry_count(kv: &ConsulKvStore) -> Int {
  return kv.keys.len();
}

/// The number of live keys (tombstones excluded). Complexity: O(entries).
pub fn consul_kv_live_count(kv: &ConsulKvStore) -> Int {
  var n = 0;
  var i = 0;
  while i < kv.keys.len() {
    if kv.present[i] == 1 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// The entry slot for `key` (live or tombstone), or CONSUL_NOT_FOUND.
/// Complexity: O(entries).
pub fn consul_kv_find(kv: &ConsulKvStore, key: Str) -> Int {
  return _find_str(&kv.keys, key);
}

/// True when slot `i` exists and is a tombstone.
/// Complexity: O(1).
pub fn consul_kv_is_tombstone(kv: &ConsulKvStore, i: Int) -> Bool {
  if i < 0 || i >= kv.keys.len() {
    return false;
  }
  return kv.present[i] == 0;
}

/// The key at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_kv_key_at(kv: &ConsulKvStore, i: Int) -> Str {
  if i < 0 || i >= kv.keys.len() {
    return "";
  }
  let v: Str = kv.keys[i];
  return v;
}

/// The value at slot `i`; "" for a tombstone or out of range.
/// Complexity: O(1).
pub fn consul_kv_value_at(kv: &ConsulKvStore, i: Int) -> Str {
  if i < 0 || i >= kv.values.len() {
    return "";
  }
  if kv.present[i] == 0 {
    return "";
  }
  let v: Str = kv.values[i];
  return v;
}

/// The flags at slot `i`, or CONSUL_NOT_FOUND out of range.
/// Complexity: O(1).
pub fn consul_kv_flags_at(kv: &ConsulKvStore, i: Int) -> Int {
  if i < 0 || i >= kv.flags.len() {
    return CONSUL_NOT_FOUND;
  }
  return kv.flags[i];
}

/// The create index at slot `i`, or CONSUL_NOT_FOUND out of range.
/// Complexity: O(1).
pub fn consul_kv_create_index_at(kv: &ConsulKvStore, i: Int) -> Int {
  if i < 0 || i >= kv.create_indexes.len() {
    return CONSUL_NOT_FOUND;
  }
  return kv.create_indexes[i];
}

/// The modify index at slot `i`, or CONSUL_NOT_FOUND out of range.
/// Complexity: O(1).
pub fn consul_kv_modify_index_at(kv: &ConsulKvStore, i: Int) -> Int {
  if i < 0 || i >= kv.modify_indexes.len() {
    return CONSUL_NOT_FOUND;
  }
  return kv.modify_indexes[i];
}

/// The session id holding slot `i`, or "" when unlocked/out of range.
/// Complexity: O(1).
pub fn consul_kv_lock_session(kv: &ConsulKvStore, i: Int) -> Str {
  if i < 0 || i >= kv.lock_sessions.len() {
    return "";
  }
  let v: Str = kv.lock_sessions[i];
  return v;
}

/// The lock index of slot `i`, or CONSUL_NOT_FOUND out of range/0 when
/// unlocked. Complexity: O(1).
pub fn consul_kv_lock_index(kv: &ConsulKvStore, i: Int) -> Int {
  if i < 0 || i >= kv.lock_indexes.len() {
    return CONSUL_NOT_FOUND;
  }
  return kv.lock_indexes[i];
}

/// The remaining lock-delay ticks of slot `i`, or CONSUL_NOT_FOUND out of
/// range. Complexity: O(1).
pub fn consul_kv_lock_delay(kv: &ConsulKvStore, i: Int) -> Int {
  if i < 0 || i >= kv.lock_delays.len() {
    return CONSUL_NOT_FOUND;
  }
  return kv.lock_delays[i];
}

// Append one default entry for `key` and return its slot.
fn _kv_append(kv: &mut ConsulKvStore, key: Str) -> Int {
  let i = kv.keys.len();
  kv.keys.push(key);
  kv.values.push("");
  kv.flags.push(0);
  kv.create_indexes.push(0);
  kv.modify_indexes.push(0);
  kv.present.push(0);
  kv.lock_sessions.push("");
  kv.lock_indexes.push(0);
  kv.lock_delays.push(0);
  return i;
}

// Deterministic key validation error ("" when valid).
fn _key_error(key: Str) -> Str {
  if key.len() == 0 {
    return "consul: empty key";
  }
  if !_is_printable(key) {
    return "consul: key not printable";
  }
  return "";
}

/// Get the value of a live key. Tombstones and missing keys are
/// Err("consul: key not found"). Complexity: O(entries).
pub fn consul_kv_get(kv: &ConsulKvStore, key: Str) -> Result[Str, Str] {
  let e = _key_error(key);
  if e.len() > 0 {
    return _err_str(e);
  }
  let i = _find_str(&kv.keys, key);
  if i < 0 {
    return _err_str("consul: key not found");
  }
  if kv.present[i] == 0 {
    return _err_str("consul: key not found");
  }
  let v: Str = kv.values[i];
  return _ok_str(v);
}

/// Put `value` at `key` with `flags`. CAS modes: `cas == CONSUL_CAS_NONE`
/// (-1) writes unconditionally; `cas == CONSUL_CAS_CREATE` (0) writes only
/// when the key does not exist (a tombstone counts as missing);
/// `cas > 0` writes only when the key is live and its modify index equals
/// `cas`. On success the store index is bumped, `modify_index` is the new
/// store index and `create_index` is set when the key is (re-)created.
/// Returns the new modify index. A locked key refuses
/// Err("consul: key is locked"). Complexity: O(entries).
pub fn consul_kv_put(kv: &mut ConsulKvStore, key: Str, value: Str, flags: Int, cas: Int) -> Result[Int, Str] {
  let ke = _key_error(key);
  if ke.len() > 0 {
    return _err_int(ke);
  }
  if flags < 0 {
    return _err_int("consul: flags must not be negative");
  }
  if cas < CONSUL_CAS_NONE {
    return _err_int("consul: invalid cas");
  }
  let i = _find_str(&kv.keys, key);
  var live = false;
  if i >= 0 {
    live = kv.present[i] == 1;
  }
  if i >= 0 && live {
    let held: Str = kv.lock_sessions[i];
    if held.len() > 0 {
      return _err_int("consul: key is locked");
    }
  }
  if cas == CONSUL_CAS_CREATE && live {
    return _err_int("consul: cas mismatch");
  }
  if cas > 0 {
    if !live {
      return _err_int("consul: cas mismatch");
    }
    if kv.modify_indexes[i] != cas {
      return _err_int("consul: cas mismatch");
    }
  }
  if i < 0 {
    let s = _kv_append(kv, key);
    kv.index = kv.index + 1;
    kv.values[s] = value;
    kv.flags[s] = flags;
    kv.create_indexes[s] = kv.index;
    kv.modify_indexes[s] = kv.index;
    kv.present[s] = 1;
    return _ok_int(kv.index);
  }
  kv.index = kv.index + 1;
  if !live {
    kv.create_indexes[i] = kv.index;
  }
  kv.values[i] = value;
  kv.flags[i] = flags;
  kv.modify_indexes[i] = kv.index;
  kv.present[i] = 1;
  return _ok_int(kv.index);
}

/// Delete `key`. CAS modes: `cas == CONSUL_CAS_NONE` (-1) deletes a live key
/// and returns Ok(true) even when there was nothing to delete;
/// `cas == CONSUL_CAS_CREATE` (0) deletes a live key and returns Ok(false)
/// otherwise; `cas > 0` deletes only when the key is live and its modify
/// index equals `cas` (otherwise Err("consul: cas mismatch")). A delete of a
/// live key leaves a tombstone (`consul_kv_is_tombstone` true,
/// `consul_kv_get` not found) and bumps the store index. A locked key
/// refuses Err("consul: key is locked"). Complexity: O(entries).
pub fn consul_kv_delete(kv: &mut ConsulKvStore, key: Str, cas: Int) -> Result[Bool, Str] {
  let ke = _key_error(key);
  if ke.len() > 0 {
    return _err_bool(ke);
  }
  if cas < CONSUL_CAS_NONE {
    return _err_bool("consul: invalid cas");
  }
  let i = _find_str(&kv.keys, key);
  var live = false;
  if i >= 0 {
    live = kv.present[i] == 1;
  }
  if i >= 0 && live {
    let held: Str = kv.lock_sessions[i];
    if held.len() > 0 {
      return _err_bool("consul: key is locked");
    }
  }
  if cas == CONSUL_CAS_CREATE {
    if !live {
      return _ok_bool(false);
    }
  }
  if cas > 0 {
    if !live {
      return _err_bool("consul: cas mismatch");
    }
    if kv.modify_indexes[i] != cas {
      return _err_bool("consul: cas mismatch");
    }
  }
  if !live {
    return _ok_bool(true);
  }
  kv.present[i] = 0;
  kv.lock_sessions[i] = "";
  kv.lock_indexes[i] = 0;
  kv.index = kv.index + 1;
  kv.modify_indexes[i] = kv.index;
  return _ok_bool(true);
}

/// Age every positive KV lock delay by `ticks` (floor 0); returns how many
/// delays reached zero in this call. Complexity: O(entries).
pub fn consul_kv_advance_locks(kv: &mut ConsulKvStore, ticks: Int) -> Int {
  if ticks <= 0 {
    return 0;
  }
  var expired = 0;
  var i = 0;
  while i < kv.keys.len() {
    let d = kv.lock_delays[i];
    if d > 0 {
      var nd = d - ticks;
      if nd < 0 {
        nd = 0;
      }
      kv.lock_delays[i] = nd;
      if nd == 0 {
        expired = expired + 1;
      }
    }
    i = i + 1;
  }
  return expired;
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// A fresh empty session table. Complexity: O(1).
pub fn consul_sessions_new() -> ConsulSessions {
  return ConsulSessions{
    ids: Vec[Str].new();
    ttls: Vec[Int].new();
    remainings: Vec[Int].new();
    behaviors: Vec[Int].new();
    lock_delays: Vec[Int].new();
    invalidated: Vec[Int].new();
  };
}

/// The session slot for `id`, or CONSUL_NOT_FOUND. Complexity: O(sessions).
pub fn consul_session_find(sessions: &ConsulSessions, id: Str) -> Int {
  return _find_str(&sessions.ids, id);
}

/// The number of sessions (live plus invalidated). Complexity: O(1).
pub fn consul_session_count(sessions: &ConsulSessions) -> Int {
  return sessions.ids.len();
}

/// The session id at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_session_id_at(sessions: &ConsulSessions, i: Int) -> Str {
  if i < 0 || i >= sessions.ids.len() {
    return "";
  }
  let v: Str = sessions.ids[i];
  return v;
}

/// The granted TTL at slot `i`, or CONSUL_NOT_FOUND out of range. O(1).
pub fn consul_session_ttl_at(sessions: &ConsulSessions, i: Int) -> Int {
  if i < 0 || i >= sessions.ttls.len() {
    return CONSUL_NOT_FOUND;
  }
  return sessions.ttls[i];
}

/// The remaining ticks at slot `i`, or CONSUL_NOT_FOUND out of range. O(1).
pub fn consul_session_remaining_at(sessions: &ConsulSessions, i: Int) -> Int {
  if i < 0 || i >= sessions.remainings.len() {
    return CONSUL_NOT_FOUND;
  }
  return sessions.remainings[i];
}

/// The behavior at slot `i`, or CONSUL_NOT_FOUND out of range. O(1).
pub fn consul_session_behavior_at(sessions: &ConsulSessions, i: Int) -> Int {
  if i < 0 || i >= sessions.behaviors.len() {
    return CONSUL_NOT_FOUND;
  }
  return sessions.behaviors[i];
}

/// The lock delay at slot `i`, or CONSUL_NOT_FOUND out of range. O(1).
pub fn consul_session_lock_delay_at(sessions: &ConsulSessions, i: Int) -> Int {
  if i < 0 || i >= sessions.lock_delays.len() {
    return CONSUL_NOT_FOUND;
  }
  return sessions.lock_delays[i];
}

/// 1 when slot `i` is invalidated, 0 when live, CONSUL_NOT_FOUND out of
/// range. Complexity: O(1).
pub fn consul_session_invalidated_at(sessions: &ConsulSessions, i: Int) -> Int {
  if i < 0 || i >= sessions.invalidated.len() {
    return CONSUL_NOT_FOUND;
  }
  return sessions.invalidated[i];
}

/// Create a session with `ttl` ticks, a behavior and a lock delay. The id is
/// deterministic: "consul-session-N" where N is the new slot + 1 (sessions
/// are never removed, so ids never repeat). Returns the new id.
/// Complexity: O(1).
pub fn consul_session_create(sessions: &mut ConsulSessions, ttl: Int, behavior: Int, lock_delay: Int) -> Result[Str, Str] {
  if ttl < 1 {
    return _err_str("consul: ttl must be >= 1");
  }
  if behavior != CONSUL_BEHAVIOR_RELEASE && behavior != CONSUL_BEHAVIOR_DELETE {
    return _err_str("consul: invalid session behavior");
  }
  if lock_delay < 0 {
    return _err_str("consul: lock delay must not be negative");
  }
  let id = "consul-session-" + convert.int_to_string(sessions.ids.len() + 1);
  sessions.ids.push(id);
  sessions.ttls.push(ttl);
  sessions.remainings.push(ttl);
  sessions.behaviors.push(behavior);
  sessions.lock_delays.push(lock_delay);
  sessions.invalidated.push(0);
  return _ok_str(id);
}

/// Renew a live session: the remaining ticks are reset to the granted TTL.
/// Returns the granted TTL. An invalidated session is
/// Err("consul: session invalidated"); an unknown id is
/// Err("consul: session not found"). Complexity: O(sessions).
pub fn consul_session_renew(sessions: &mut ConsulSessions, id: Str) -> Result[Int, Str] {
  let si = _find_str(&sessions.ids, id);
  if si < 0 {
    return _err_int("consul: session not found");
  }
  if sessions.invalidated[si] == 1 {
    return _err_int("consul: session invalidated");
  }
  let ttl = sessions.ttls[si];
  sessions.remainings[si] = ttl;
  return _ok_int(ttl);
}

// Apply an invalidated session's behavior to every key it holds; returns the
// number of keys affected. RELEASE clears the lock (the key keeps its value
// and gets the session's lock delay); DELETE leaves a tombstone (the value
// is discarded by present = 0), bumps the store index and also applies the
// lock delay. Every affected key's lock delay is reset to the session's
// lock delay so a new holder cannot acquire it until the delay elapses.
fn _session_apply(kv: &mut ConsulKvStore, sessions: &ConsulSessions, si: Int) -> Int {
  let sid: Str = sessions.ids[si];
  let behavior = sessions.behaviors[si];
  let delay = sessions.lock_delays[si];
  var count = 0;
  var i = 0;
  while i < kv.keys.len() {
    let held: Str = kv.lock_sessions[i];
    if _str_eq(held, sid) {
      if behavior == CONSUL_BEHAVIOR_DELETE {
        kv.present[i] = 0;
        kv.index = kv.index + 1;
        kv.modify_indexes[i] = kv.index;
      }
      kv.lock_sessions[i] = "";
      kv.lock_indexes[i] = 0;
      kv.lock_delays[i] = delay;
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Invalidate a session immediately. Behavior: RELEASE unlocks the keys it
/// held (values survive); DELETE tombstones them. Returns the number of keys
/// affected (0 when the session was already invalidated, so the call is
/// idempotent). Unknown id: Err("consul: session not found").
/// Complexity: O(keys + sessions).
pub fn consul_session_invalidate(kv: &mut ConsulKvStore, sessions: &mut ConsulSessions, id: Str) -> Result[Int, Str] {
  let si = _find_str(&sessions.ids, id);
  if si < 0 {
    return _err_int("consul: session not found");
  }
  if sessions.invalidated[si] == 1 {
    return _ok_int(0);
  }
  let count = _session_apply(kv, sessions, si);
  sessions.invalidated[si] = 1;
  return _ok_int(count);
}

/// Age every live session by `ticks`; a session whose remaining ticks reach
/// zero is invalidated (its behavior applied to the KV store) in slot order.
/// Returns how many sessions expired. `ticks <= 0` is a no-op.
/// Complexity: O(keys + sessions).
pub fn consul_session_advance(kv: &mut ConsulKvStore, sessions: &mut ConsulSessions, ticks: Int) -> Int {
  if ticks <= 0 {
    return 0;
  }
  var expired = 0;
  var i = 0;
  while i < sessions.ids.len() {
    if sessions.invalidated[i] == 0 {
      var r = sessions.remainings[i] - ticks;
      if r < 0 {
        r = 0;
      }
      sessions.remainings[i] = r;
      if r == 0 {
        let affected = _session_apply(kv, sessions, i);
        if affected >= 0 {
          sessions.invalidated[i] = 1;
          expired = expired + 1;
        }
      }
    }
    i = i + 1;
  }
  return expired;
}

// ---------------------------------------------------------------------------
// KV session locks (Acquire / Release)
// ---------------------------------------------------------------------------

/// Acquire the lock on `key` for `session_id`, writing `value` and
/// stamping `lock_index` with the new store index. Acquiring a key already
/// held by the same session refreshes the value and the lock index; a key
/// held by another session is Err("consul: key is locked"); a key inside a
/// lock-delay window is Err("consul: lock delay active"); an unknown or
/// invalidated session is an error. Returns the new lock index.
/// Complexity: O(entries + sessions).
pub fn consul_kv_acquire(kv: &mut ConsulKvStore, sessions: &ConsulSessions, key: Str, value: Str, session_id: Str) -> Result[Int, Str] {
  let ke = _key_error(key);
  if ke.len() > 0 {
    return _err_int(ke);
  }
  let si = _find_str(&sessions.ids, session_id);
  if si < 0 {
    return _err_int("consul: session not found");
  }
  if sessions.invalidated[si] == 1 {
    return _err_int("consul: session invalidated");
  }
  let i = _find_str(&kv.keys, key);
  if i >= 0 {
    let held: Str = kv.lock_sessions[i];
    if held.len() > 0 && !_str_eq(held, session_id) {
      return _err_int("consul: key is locked");
    }
    if kv.lock_delays[i] > 0 {
      return _err_int("consul: lock delay active");
    }
  }
  if i < 0 {
    let s = _kv_append(kv, key);
    kv.index = kv.index + 1;
    kv.values[s] = value;
    kv.flags[s] = 0;
    kv.create_indexes[s] = kv.index;
    kv.modify_indexes[s] = kv.index;
    kv.present[s] = 1;
    kv.lock_sessions[s] = session_id;
    kv.lock_indexes[s] = kv.index;
    return _ok_int(kv.index);
  }
  kv.index = kv.index + 1;
  if kv.present[i] == 0 {
    kv.create_indexes[i] = kv.index;
  }
  kv.values[i] = value;
  kv.flags[i] = 0;
  kv.modify_indexes[i] = kv.index;
  kv.present[i] = 1;
  kv.lock_sessions[i] = session_id;
  kv.lock_indexes[i] = kv.index;
  kv.lock_delays[i] = 0;
  return _ok_int(kv.index);
}

/// Release the lock on `key` held by `session_id`. The value and the modify
/// index are untouched. Returns Ok(false) when the key does not exist, is a
/// tombstone, or is not held by that session. Complexity: O(entries).
pub fn consul_kv_release(kv: &mut ConsulKvStore, key: Str, session_id: Str) -> Result[Bool, Str] {
  let ke = _key_error(key);
  if ke.len() > 0 {
    return _err_bool(ke);
  }
  let i = _find_str(&kv.keys, key);
  if i < 0 {
    return _ok_bool(false);
  }
  if kv.present[i] == 0 {
    return _ok_bool(false);
  }
  let held: Str = kv.lock_sessions[i];
  if held.len() == 0 || !_str_eq(held, session_id) {
    return _ok_bool(false);
  }
  kv.lock_sessions[i] = "";
  kv.lock_indexes[i] = 0;
  return _ok_bool(true);
}

// ---------------------------------------------------------------------------
// Service registry
// ---------------------------------------------------------------------------

/// A fresh empty service/check registry. Complexity: O(1).
pub fn consul_services_new() -> ConsulServiceRegistry {
  return ConsulServiceRegistry{
    service_ids: Vec[Str].new();
    service_names: Vec[Str].new();
    service_addresses: Vec[Str].new();
    service_ports: Vec[Int].new();
    service_tags: Vec[Str].new();
    check_ids: Vec[Str].new();
    check_service_ids: Vec[Str].new();
    check_names: Vec[Str].new();
    check_kinds: Vec[Int].new();
    check_statuses: Vec[Int].new();
    check_ttls: Vec[Int].new();
    check_remainings: Vec[Int].new();
    check_intervals: Vec[Int].new();
    check_timeouts: Vec[Int].new();
    check_urls: Vec[Str].new();
    check_hosts: Vec[Str].new();
    check_ports: Vec[Int].new();
    check_notes: Vec[Str].new();
  };
}

/// The number of registered services. Complexity: O(1).
pub fn consul_service_count(reg: &ConsulServiceRegistry) -> Int {
  return reg.service_ids.len();
}

/// The number of registered checks. Complexity: O(1).
pub fn consul_check_count(reg: &ConsulServiceRegistry) -> Int {
  return reg.check_ids.len();
}

/// The service slot for `id`, or CONSUL_NOT_FOUND. Complexity: O(services).
pub fn consul_service_find(reg: &ConsulServiceRegistry, id: Str) -> Int {
  return _find_str(&reg.service_ids, id);
}

/// The check slot for `check_id`, or CONSUL_NOT_FOUND. Complexity: O(checks).
pub fn consul_check_find(reg: &ConsulServiceRegistry, check_id: Str) -> Int {
  return _find_str(&reg.check_ids, check_id);
}

/// The service id at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_service_id_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.service_ids.len() {
    return "";
  }
  let v: Str = reg.service_ids[i];
  return v;
}

/// The service name at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_service_name_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.service_names.len() {
    return "";
  }
  let v: Str = reg.service_names[i];
  return v;
}

/// The service address at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_service_address_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.service_addresses.len() {
    return "";
  }
  let v: Str = reg.service_addresses[i];
  return v;
}

/// The service port at slot `i`, or CONSUL_NOT_FOUND out of range. O(1).
pub fn consul_service_port_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.service_ports.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.service_ports[i];
}

/// The comma-joined service tags at slot `i`, or "" out of range. O(1).
pub fn consul_service_tags_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.service_tags.len() {
    return "";
  }
  let v: Str = reg.service_tags[i];
  return v;
}

/// True when the service at slot `i` carries `tag` as a whole element.
/// Complexity: O(tag bytes).
pub fn consul_service_has_tag(reg: &ConsulServiceRegistry, i: Int, tag: Str) -> Bool {
  if i < 0 || i >= reg.service_tags.len() {
    return false;
  }
  let v: Str = reg.service_tags[i];
  return _list_has(v, tag);
}

// Deterministic comma-joined tag-list validation error ("" when valid).
fn _tags_error(tags: Str) -> Str {
  if tags.len() == 0 {
    return "";
  }
  if !_is_printable(tags) {
    return "consul: service tag not printable";
  }
  var start = 0;
  var i = 0;
  while i <= tags.len() {
    if i == tags.len() || _byte_at(tags, i) == 44 {
      if i == start {
        return "consul: empty service tag";
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return "";
}

/// Register a service. Validation order: empty/printable id, duplicate id,
/// empty/printable name, printable address, port 0..65535, tag list.
/// Returns the new slot. Complexity: O(services + tag bytes).
pub fn consul_register_service(reg: &mut ConsulServiceRegistry, id: Str, name: Str, address: Str, port: Int, tags: Str) -> Result[Int, Str] {
  if id.len() == 0 {
    return _err_int("consul: service id must not be empty");
  }
  if !_is_printable(id) {
    return _err_int("consul: service id not printable");
  }
  if _find_str(&reg.service_ids, id) >= 0 {
    return _err_int("consul: duplicate service");
  }
  if name.len() == 0 {
    return _err_int("consul: service name must not be empty");
  }
  if !_is_printable(name) {
    return _err_int("consul: service name not printable");
  }
  if !_is_printable(address) {
    return _err_int("consul: service address not printable");
  }
  if port < 0 || port > 65535 {
    return _err_int("consul: service port out of range");
  }
  let te = _tags_error(tags);
  if te.len() > 0 {
    return _err_int(te);
  }
  reg.service_ids.push(id);
  reg.service_names.push(name);
  reg.service_addresses.push(address);
  reg.service_ports.push(port);
  reg.service_tags.push(tags);
  return _ok_int(reg.service_ids.len() - 1);
}

// Remove service slot `at`, shifting the trailing services down.
fn _svc_remove(reg: &mut ConsulServiceRegistry, at: Int) {
  var i = at;
  while i + 1 < reg.service_ids.len() {
    reg.service_ids[i] = reg.service_ids[i + 1];
    reg.service_names[i] = reg.service_names[i + 1];
    reg.service_addresses[i] = reg.service_addresses[i + 1];
    reg.service_ports[i] = reg.service_ports[i + 1];
    reg.service_tags[i] = reg.service_tags[i + 1];
    i = i + 1;
  }
  reg.service_ids.pop();
  reg.service_names.pop();
  reg.service_addresses.pop();
  reg.service_ports.pop();
  reg.service_tags.pop();
}

// Remove check slot `at`, shifting the trailing checks down.
fn _check_remove(reg: &mut ConsulServiceRegistry, at: Int) {
  var i = at;
  while i + 1 < reg.check_ids.len() {
    reg.check_ids[i] = reg.check_ids[i + 1];
    reg.check_service_ids[i] = reg.check_service_ids[i + 1];
    reg.check_names[i] = reg.check_names[i + 1];
    reg.check_kinds[i] = reg.check_kinds[i + 1];
    reg.check_statuses[i] = reg.check_statuses[i + 1];
    reg.check_ttls[i] = reg.check_ttls[i + 1];
    reg.check_remainings[i] = reg.check_remainings[i + 1];
    reg.check_intervals[i] = reg.check_intervals[i + 1];
    reg.check_timeouts[i] = reg.check_timeouts[i + 1];
    reg.check_urls[i] = reg.check_urls[i + 1];
    reg.check_hosts[i] = reg.check_hosts[i + 1];
    reg.check_ports[i] = reg.check_ports[i + 1];
    reg.check_notes[i] = reg.check_notes[i + 1];
    i = i + 1;
  }
  reg.check_ids.pop();
  reg.check_service_ids.pop();
  reg.check_names.pop();
  reg.check_kinds.pop();
  reg.check_statuses.pop();
  reg.check_ttls.pop();
  reg.check_remainings.pop();
  reg.check_intervals.pop();
  reg.check_timeouts.pop();
  reg.check_urls.pop();
  reg.check_hosts.pop();
  reg.check_ports.pop();
  reg.check_notes.pop();
}

/// Deregister a service and every check attached to it, in check-slot order.
/// Returns the number of checks removed. Unknown id:
/// Err("consul: service not found"). Complexity: O(services + checks).
pub fn consul_deregister_service(reg: &mut ConsulServiceRegistry, id: Str) -> Result[Int, Str] {
  let si = _find_str(&reg.service_ids, id);
  if si < 0 {
    return _err_int("consul: service not found");
  }
  var removed = 0;
  var i = 0;
  while i < reg.check_ids.len() {
    let cs: Str = reg.check_service_ids[i];
    if _str_eq(cs, id) {
      _check_remove(reg, i);
      removed = removed + 1;
    } else {
      i = i + 1;
    }
  }
  _svc_remove(reg, si);
  return _ok_int(removed);
}

/// Deregister a check by id. Returns Ok(true) when it existed, Ok(false)
/// otherwise. Complexity: O(checks).
pub fn consul_deregister_check(reg: &mut ConsulServiceRegistry, check_id: Str) -> Result[Bool, Str] {
  let ci = _find_str(&reg.check_ids, check_id);
  if ci < 0 {
    return _ok_bool(false);
  }
  _check_remove(reg, ci);
  return _ok_bool(true);
}

// Deterministic common check validation error ("" when valid): empty and
// printable check id, duplicate id, service reference when non-empty, empty
// and printable name, printable notes.
fn _check_preamble(reg: &ConsulServiceRegistry, check_id: Str, service_id: Str, name: Str, notes: Str) -> Str {
  if check_id.len() == 0 {
    return "consul: check id must not be empty";
  }
  if !_is_printable(check_id) {
    return "consul: check id not printable";
  }
  if _find_str(&reg.check_ids, check_id) >= 0 {
    return "consul: duplicate check";
  }
  if service_id.len() > 0 {
    if _find_str(&reg.service_ids, service_id) < 0 {
      return "consul: unknown service for check";
    }
  }
  if name.len() == 0 {
    return "consul: check name must not be empty";
  }
  if !_is_printable(name) {
    return "consul: check name not printable";
  }
  if notes.len() > 0 && !_is_printable(notes) {
    return "consul: check notes not printable";
  }
  return "";
}

/// Add a TTL check (status passing) attached to `service_id` ("" for
/// node-level). `ttl` is the TTL in ticks and must be >= 1. Returns the new
/// check slot. Complexity: O(checks).
pub fn consul_add_ttl_check(reg: &mut ConsulServiceRegistry, check_id: Str, service_id: Str, name: Str, ttl: Int, notes: Str) -> Result[Int, Str] {
  let pe = _check_preamble(reg, check_id, service_id, name, notes);
  if pe.len() > 0 {
    return _err_int(pe);
  }
  if ttl < 1 {
    return _err_int("consul: ttl must be >= 1");
  }
  reg.check_ids.push(check_id);
  reg.check_service_ids.push(service_id);
  reg.check_names.push(name);
  reg.check_kinds.push(CONSUL_CHECK_TTL);
  reg.check_statuses.push(CONSUL_STATUS_PASSING);
  reg.check_ttls.push(ttl);
  reg.check_remainings.push(ttl);
  reg.check_intervals.push(0);
  reg.check_timeouts.push(0);
  reg.check_urls.push("");
  reg.check_hosts.push("");
  reg.check_ports.push(0);
  reg.check_notes.push(notes);
  return _ok_int(reg.check_ids.len() - 1);
}

// Deterministic HTTP/TCP scheduling shape error ("" when valid): interval
// and timeout are >= 1 and timeout <= interval.
fn _schedule_error(interval: Int, timeout: Int) -> Str {
  if interval < 1 {
    return "consul: interval must be >= 1";
  }
  if timeout < 1 {
    return "consul: timeout must be >= 1";
  }
  if timeout > interval {
    return "consul: timeout must not exceed interval";
  }
  return "";
}

/// Add an HTTP check (status passing). The URL must start with `http://` or
/// `https://`; `interval`/`timeout` are ticks with
/// `1 <= timeout <= interval`. Returns the new check slot.
/// Complexity: O(checks + url bytes).
pub fn consul_add_http_check(reg: &mut ConsulServiceRegistry, check_id: Str, service_id: Str, name: Str, url: Str, interval: Int, timeout: Int, notes: Str) -> Result[Int, Str] {
  let pe = _check_preamble(reg, check_id, service_id, name, notes);
  if pe.len() > 0 {
    return _err_int(pe);
  }
  if !_has_prefix(url, "http://") && !_has_prefix(url, "https://") {
    return _err_int("consul: invalid http check url");
  }
  let se = _schedule_error(interval, timeout);
  if se.len() > 0 {
    return _err_int(se);
  }
  reg.check_ids.push(check_id);
  reg.check_service_ids.push(service_id);
  reg.check_names.push(name);
  reg.check_kinds.push(CONSUL_CHECK_HTTP);
  reg.check_statuses.push(CONSUL_STATUS_PASSING);
  reg.check_ttls.push(0);
  reg.check_remainings.push(0);
  reg.check_intervals.push(interval);
  reg.check_timeouts.push(timeout);
  reg.check_urls.push(url);
  reg.check_hosts.push("");
  reg.check_ports.push(0);
  reg.check_notes.push(notes);
  return _ok_int(reg.check_ids.len() - 1);
}

/// Add a TCP check (status passing). The host must be non-empty and
/// printable and the port 1..65535; `interval`/`timeout` are ticks with
/// `1 <= timeout <= interval`. Returns the new check slot.
/// Complexity: O(checks + host bytes).
pub fn consul_add_tcp_check(reg: &mut ConsulServiceRegistry, check_id: Str, service_id: Str, name: Str, host: Str, port: Int, interval: Int, timeout: Int, notes: Str) -> Result[Int, Str] {
  let pe = _check_preamble(reg, check_id, service_id, name, notes);
  if pe.len() > 0 {
    return _err_int(pe);
  }
  if host.len() == 0 {
    return _err_int("consul: tcp host must not be empty");
  }
  if !_is_printable(host) {
    return _err_int("consul: tcp host not printable");
  }
  if port < 1 || port > 65535 {
    return _err_int("consul: tcp port out of range");
  }
  let se = _schedule_error(interval, timeout);
  if se.len() > 0 {
    return _err_int(se);
  }
  reg.check_ids.push(check_id);
  reg.check_service_ids.push(service_id);
  reg.check_names.push(name);
  reg.check_kinds.push(CONSUL_CHECK_TCP);
  reg.check_statuses.push(CONSUL_STATUS_PASSING);
  reg.check_ttls.push(0);
  reg.check_remainings.push(0);
  reg.check_intervals.push(interval);
  reg.check_timeouts.push(timeout);
  reg.check_urls.push("");
  reg.check_hosts.push(host);
  reg.check_ports.push(port);
  reg.check_notes.push(notes);
  return _ok_int(reg.check_ids.len() - 1);
}

/// The check id at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_check_id_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.check_ids.len() {
    return "";
  }
  let v: Str = reg.check_ids[i];
  return v;
}

/// The service id a check is attached to at slot `i` ("" = node-level), or
/// "" out of range. Complexity: O(1).
pub fn consul_check_service_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.check_service_ids.len() {
    return "";
  }
  let v: Str = reg.check_service_ids[i];
  return v;
}

/// The check name at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_check_name_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.check_names.len() {
    return "";
  }
  let v: Str = reg.check_names[i];
  return v;
}

/// The check kind at slot `i`, or CONSUL_NOT_FOUND out of range. O(1).
pub fn consul_check_kind_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.check_kinds.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.check_kinds[i];
}

/// The check status at slot `i`, or CONSUL_NOT_FOUND out of range. O(1).
pub fn consul_check_status_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.check_statuses.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.check_statuses[i];
}

/// The TTL of a TTL check at slot `i` (0 otherwise), or CONSUL_NOT_FOUND
/// out of range. Complexity: O(1).
pub fn consul_check_ttl_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.check_ttls.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.check_ttls[i];
}

/// The remaining TTL ticks at slot `i`, or CONSUL_NOT_FOUND out of range.
/// Complexity: O(1).
pub fn consul_check_remaining_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.check_remainings.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.check_remainings[i];
}

/// The scheduling interval at slot `i`, or CONSUL_NOT_FOUND out of range.
/// Complexity: O(1).
pub fn consul_check_interval_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.check_intervals.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.check_intervals[i];
}

/// The scheduling timeout at slot `i`, or CONSUL_NOT_FOUND out of range.
/// Complexity: O(1).
pub fn consul_check_timeout_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.check_timeouts.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.check_timeouts[i];
}

/// The HTTP URL at slot `i` ("" for other kinds), or "" out of range.
/// Complexity: O(1).
pub fn consul_check_url_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.check_urls.len() {
    return "";
  }
  let v: Str = reg.check_urls[i];
  return v;
}

/// The TCP host at slot `i` ("" for other kinds), or "" out of range.
/// Complexity: O(1).
pub fn consul_check_host_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.check_hosts.len() {
    return "";
  }
  let v: Str = reg.check_hosts[i];
  return v;
}

/// The TCP port at slot `i` (0 for other kinds), or CONSUL_NOT_FOUND out of
/// range. Complexity: O(1).
pub fn consul_check_port_at(reg: &ConsulServiceRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.check_ports.len() {
    return CONSUL_NOT_FOUND;
  }
  return reg.check_ports[i];
}

/// The notes at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_check_notes_at(reg: &ConsulServiceRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.check_notes.len() {
    return "";
  }
  let v: Str = reg.check_notes[i];
  return v;
}

/// Set the status of a check to passing/warning/critical. Any transition is
/// allowed (Consul's TTL and script checks set status explicitly). Returns
/// the previous status. Unknown check: Err("consul: check not found");
/// an out-of-range status: Err("consul: invalid check status").
/// Complexity: O(checks).
pub fn consul_check_set_status(reg: &mut ConsulServiceRegistry, check_id: Str, status: Int) -> Result[Int, Str] {
  if status < CONSUL_STATUS_PASSING || status > CONSUL_STATUS_CRITICAL {
    return _err_int("consul: invalid check status");
  }
  let ci = _find_str(&reg.check_ids, check_id);
  if ci < 0 {
    return _err_int("consul: check not found");
  }
  let prev = reg.check_statuses[ci];
  reg.check_statuses[ci] = status;
  return _ok_int(prev);
}

/// Heartbeat a TTL check: remaining ticks reset to the TTL and the status
/// becomes passing. Returns the granted TTL. A non-TTL check is
/// Err("consul: check is not a ttl check"). Complexity: O(checks).
pub fn consul_check_heartbeat(reg: &mut ConsulServiceRegistry, check_id: Str) -> Result[Int, Str] {
  let ci = _find_str(&reg.check_ids, check_id);
  if ci < 0 {
    return _err_int("consul: check not found");
  }
  if reg.check_kinds[ci] != CONSUL_CHECK_TTL {
    return _err_int("consul: check is not a ttl check");
  }
  let ttl = reg.check_ttls[ci];
  reg.check_remainings[ci] = ttl;
  reg.check_statuses[ci] = CONSUL_STATUS_PASSING;
  return _ok_int(ttl);
}

/// Age every TTL check by `ticks` in slot order. A check whose remaining
/// ticks reach zero becomes critical (remaining floored at 0); a check
/// already critical is not counted again. Returns how many checks became
/// critical in this call. HTTP/TCP checks are not aged. `ticks <= 0` is a
/// no-op. Complexity: O(checks).
pub fn consul_check_advance(reg: &mut ConsulServiceRegistry, ticks: Int) -> Int {
  if ticks <= 0 {
    return 0;
  }
  var became = 0;
  var i = 0;
  while i < reg.check_ids.len() {
    if reg.check_kinds[i] == CONSUL_CHECK_TTL {
      if reg.check_remainings[i] > 0 {
        var r = reg.check_remainings[i] - ticks;
        if r < 0 {
          r = 0;
        }
        reg.check_remainings[i] = r;
        if r == 0 && reg.check_statuses[i] != CONSUL_STATUS_CRITICAL {
          reg.check_statuses[i] = CONSUL_STATUS_CRITICAL;
          became = became + 1;
        }
      }
    }
    i = i + 1;
  }
  return became;
}

/// The number of checks attached to `service_id` ("" counts node-level
/// checks). Complexity: O(checks).
pub fn consul_service_check_count(reg: &ConsulServiceRegistry, service_id: Str) -> Int {
  var n = 0;
  var i = 0;
  while i < reg.check_ids.len() {
    let cs: Str = reg.check_service_ids[i];
    if _str_eq(cs, service_id) {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Aggregate health of `service_id`: the worst status among its checks
/// (critical > warning > passing), passing when it has no checks. An empty
/// `service_id` aggregates node-level checks. An unknown non-empty service
/// returns CONSUL_NOT_FOUND. Complexity: O(checks).
pub fn consul_service_health(reg: &ConsulServiceRegistry, service_id: Str) -> Int {
  if service_id.len() > 0 {
    if _find_str(&reg.service_ids, service_id) < 0 {
      return CONSUL_NOT_FOUND;
    }
  }
  var worst = CONSUL_STATUS_PASSING;
  var i = 0;
  while i < reg.check_ids.len() {
    let cs: Str = reg.check_service_ids[i];
    if _str_eq(cs, service_id) {
      let s = reg.check_statuses[i];
      if s > worst {
        worst = s;
      }
    }
    i = i + 1;
  }
  return worst;
}

// ---------------------------------------------------------------------------
// ACL model
// ---------------------------------------------------------------------------

/// A fresh empty ACL store. Complexity: O(1).
pub fn consul_acl_new() -> ConsulAcl {
  return ConsulAcl{
    policy_names: Vec[Str].new();
    policy_rule_offsets: Vec[Int].new();
    rule_resource_codes: Vec[Int].new();
    rule_scopes: Vec[Int].new();
    rule_paths: Vec[Str].new();
    rule_actions: Vec[Int].new();
    token_ids: Vec[Str].new();
    token_descriptions: Vec[Str].new();
    token_policy_lists: Vec[Str].new();
    token_management: Vec[Int].new();
    token_valid: Vec[Int].new();
  };
}

/// The number of policies. Complexity: O(1).
pub fn consul_acl_policy_count(acl: &ConsulAcl) -> Int {
  return acl.policy_names.len();
}

/// The number of tokens. Complexity: O(1).
pub fn consul_acl_token_count(acl: &ConsulAcl) -> Int {
  return acl.token_ids.len();
}

/// The policy slot for `name`, or CONSUL_NOT_FOUND. Complexity: O(policies).
pub fn consul_acl_policy_find(acl: &ConsulAcl, name: Str) -> Int {
  return _find_str(&acl.policy_names, name);
}

/// The token slot for `id`, or CONSUL_NOT_FOUND. Complexity: O(tokens).
pub fn consul_acl_token_find(acl: &ConsulAcl, id: Str) -> Int {
  return _find_str(&acl.token_ids, id);
}

// The malformed-rule error with the offending line number.
fn _malformed(line_no: Int) -> Str {
  return "consul: malformed acl rule at line " + convert.int_to_string(line_no);
}

/// Parse the ACL rules subset into a rule set. Grammar (one rule per line;
/// blank lines, `#` comments and `//` comments are ignored; spaces and tabs
/// are free):
///
///   key_prefix "path" { policy = "read" }
///   key "path" { policy = "write" }
///   node_prefix "path" { policy = "read" }
///   service_prefix "path" { policy = "write" }
///   session_prefix "path" { policy = "write" }
///   event_prefix "path" { policy = "read" }
///   query_prefix "path" { policy = "read" }
///   acl = "read"
///
/// Resources: key, node, service, session, event, query (exact or _prefix)
/// and acl (exact only). Actions: read, write, list, deny. Paths are
/// printable ASCII without quotes and may be empty (a prefix rule with an
/// empty path matches every path). Errors carry the 1-based line number;
/// an unknown resource or action is a distinct error.
/// Complexity: O(text bytes).
pub fn consul_policy_parse(name: Str, text: Str) -> Result[ConsulPolicyRules, Str] {
  if name.len() == 0 {
    return _err_rules("consul: empty policy name");
  }
  if !_is_printable(name) {
    return _err_rules("consul: policy name not printable");
  }
  var rules = ConsulPolicyRules{
    resource_codes: Vec[Int].new();
    scopes: Vec[Int].new();
    paths: Vec[Str].new();
    actions: Vec[Int].new();
  };
  var pos = 0;
  var line_no = 1;
  while pos <= text.len() {
    var end = pos;
    while end < text.len() && _byte_at(text, end) != 10 {
      end = end + 1;
    }
    let i = _skip_ws(text, pos, end);
    if i < end {
      let b0 = _byte_at(text, i);
      var comment = b0 == 35;
      if b0 == 47 && i + 1 < end {
        if _byte_at(text, i + 1) == 47 {
          comment = true;
        }
      }
      if !comment {
        let w = _scan_word(text, i, end);
        if w.size <= 0 {
          return _err_rules(_malformed(line_no));
        }
        var scope = 0;
        var rc = _resource_code_word(text, w.start, w.size, 0);
        if rc < 0 {
          rc = _resource_code_word(text, w.start, w.size, 1);
          if rc >= 0 {
            scope = 1;
          }
        }
        if rc < 0 {
          return _err_rules("consul: unknown acl resource at line " + convert.int_to_string(line_no));
        }
        if rc == CONSUL_RES_ACL && scope != 0 {
          return _err_rules("consul: unknown acl resource at line " + convert.int_to_string(line_no));
        }
        var j = _skip_ws(text, w.start + w.size, end);
        var pth = "";
        var act = 0;
        if rc == CONSUL_RES_ACL {
          if j >= end || _byte_at(text, j) != 61 {
            return _err_rules(_malformed(line_no));
          }
          j = _skip_ws(text, j + 1, end);
          let q = _scan_quoted(text, j, end);
          if q.size < 0 {
            return _err_rules(_malformed(line_no));
          }
          act = _action_code_word(text, q.start, q.size);
          if act < 0 {
            return _err_rules("consul: unknown acl policy at line " + convert.int_to_string(line_no));
          }
          j = _skip_ws(text, q.start + q.size + 1, end);
          if j != end {
            return _err_rules(_malformed(line_no));
          }
        } else {
          let q = _scan_quoted(text, j, end);
          if q.size < 0 {
            return _err_rules(_malformed(line_no));
          }
          pth = _span_to_str(text, q.start, q.size);
          j = _skip_ws(text, q.start + q.size + 1, end);
          if j >= end || _byte_at(text, j) != 123 {
            return _err_rules(_malformed(line_no));
          }
          j = _skip_ws(text, j + 1, end);
          let kw = _scan_word(text, j, end);
          if kw.size <= 0 || !_word_eq(text, kw.start, kw.size, "policy") {
            return _err_rules(_malformed(line_no));
          }
          j = _skip_ws(text, kw.start + kw.size, end);
          if j >= end || _byte_at(text, j) != 61 {
            return _err_rules(_malformed(line_no));
          }
          j = _skip_ws(text, j + 1, end);
          let qa = _scan_quoted(text, j, end);
          if qa.size < 0 {
            return _err_rules(_malformed(line_no));
          }
          act = _action_code_word(text, qa.start, qa.size);
          if act < 0 {
            return _err_rules("consul: unknown acl policy at line " + convert.int_to_string(line_no));
          }
          j = _skip_ws(text, qa.start + qa.size + 1, end);
          if j >= end || _byte_at(text, j) != 125 {
            return _err_rules(_malformed(line_no));
          }
          j = _skip_ws(text, j + 1, end);
          if j != end {
            return _err_rules(_malformed(line_no));
          }
        }
        rules.resource_codes.push(rc);
        rules.scopes.push(scope);
        rules.paths.push(pth);
        rules.actions.push(act);
      }
    }
    pos = end + 1;
    line_no = line_no + 1;
  }
  return _ok_rules(rules);
}

/// Add a parsed policy. The name must be non-empty, printable and unique
/// (Err("consul: duplicate policy"), checked before parsing). On success the
/// rules are appended and the offsets table is extended; returns the number
/// of rules added. Complexity: O(text bytes + policies).
pub fn consul_acl_add_policy(acl: &mut ConsulAcl, name: Str, text: Str) -> Result[Int, Str] {
  if _find_str(&acl.policy_names, name) >= 0 {
    return _err_int("consul: duplicate policy");
  }
  let pr = consul_policy_parse(name, text);
  if !pr.is_ok {
    return _err_int(pr.error);
  }
  let rules: ConsulPolicyRules = pr.value;
  var base = 0;
  if acl.policy_names.len() > 0 {
    base = acl.policy_rule_offsets[acl.policy_rule_offsets.len() - 1];
  } else {
    acl.policy_rule_offsets.push(0);
  }
  var k = 0;
  while k < rules.resource_codes.len() {
    let rcode = rules.resource_codes[k];
    let sc = rules.scopes[k];
    let pth: Str = rules.paths[k];
    let act = rules.actions[k];
    acl.rule_resource_codes.push(rcode);
    acl.rule_scopes.push(sc);
    acl.rule_paths.push(pth);
    acl.rule_actions.push(act);
    k = k + 1;
  }
  let count = rules.resource_codes.len();
  acl.policy_names.push(name);
  acl.policy_rule_offsets.push(base + count);
  return _ok_int(count);
}

// Deterministic token policy-list validation error ("" when valid). A list
// is a comma-joined set of existing policy names; empty elements and
// unknown policies are refused.
fn _token_policies_error(acl: &ConsulAcl, list: Str) -> Str {
  if list.len() == 0 {
    return "";
  }
  if !_is_printable(list) {
    return "consul: token policy list not printable";
  }
  let n = _list_count(list);
  var k = 0;
  while k < n {
    let sp = _list_span(list, k);
    if sp.size == 0 {
      return "consul: empty policy in token list";
    }
    let pname: Str = _span_to_str(list, sp.start, sp.size);
    if _find_str(&acl.policy_names, pname) < 0 {
      return "consul: unknown policy in token: " + pname;
    }
    k = k + 1;
  }
  return "";
}

/// Add a token with an id, a description, a comma-joined policy list and a
/// management flag (0 client, 1 management; management tokens bypass ACL
/// checks). The id must be non-empty, printable and unique; every policy in
/// the list must already exist. Returns the new token slot. Complexity:
/// O(policy list bytes + tokens).
pub fn consul_acl_add_token(acl: &mut ConsulAcl, id: Str, description: Str, policy_list: Str, management: Int) -> Result[Int, Str] {
  if id.len() == 0 {
    return _err_int("consul: token id must not be empty");
  }
  if !_is_printable(id) {
    return _err_int("consul: token id not printable");
  }
  if _find_str(&acl.token_ids, id) >= 0 {
    return _err_int("consul: duplicate token");
  }
  if description.len() > 0 && !_is_printable(description) {
    return _err_int("consul: token description not printable");
  }
  if management != 0 && management != 1 {
    return _err_int("consul: invalid token management flag");
  }
  let pe = _token_policies_error(acl, policy_list);
  if pe.len() > 0 {
    return _err_int(pe);
  }
  acl.token_ids.push(id);
  acl.token_descriptions.push(description);
  acl.token_policy_lists.push(policy_list);
  acl.token_management.push(management);
  acl.token_valid.push(1);
  return _ok_int(acl.token_ids.len() - 1);
}

/// The token description at slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_acl_token_description(acl: &ConsulAcl, i: Int) -> Str {
  if i < 0 || i >= acl.token_descriptions.len() {
    return "";
  }
  let v: Str = acl.token_descriptions[i];
  return v;
}

/// The policy list at token slot `i`, or "" out of range. Complexity: O(1).
pub fn consul_acl_token_policies(acl: &ConsulAcl, i: Int) -> Str {
  if i < 0 || i >= acl.token_policy_lists.len() {
    return "";
  }
  let v: Str = acl.token_policy_lists[i];
  return v;
}

/// 1 for a management token, 0 for a client token, CONSUL_NOT_FOUND out of
/// range. Complexity: O(1).
pub fn consul_acl_token_management(acl: &ConsulAcl, i: Int) -> Int {
  if i < 0 || i >= acl.token_management.len() {
    return CONSUL_NOT_FOUND;
  }
  return acl.token_management[i];
}

/// 1 when the token at slot `i` is valid, 0 when invalid, CONSUL_NOT_FOUND
/// out of range. Complexity: O(1).
pub fn consul_acl_token_valid(acl: &ConsulAcl, i: Int) -> Int {
  if i < 0 || i >= acl.token_valid.len() {
    return CONSUL_NOT_FOUND;
  }
  return acl.token_valid[i];
}

// The policy action code that a single policy resolves for (resource, path):
// CONSUL_ACL_DENY when any matching rule denies; otherwise the most specific
// matching grant, where an exact rule beats every prefix, a longer prefix
// beats a shorter one and a later rule wins a tie; CONSUL_ACL_NONE when
// nothing matches.
fn _policy_action(acl: &ConsulAcl, pi: Int, rcode: Int, path: Str) -> Int {
  let start = acl.policy_rule_offsets[pi];
  let stop = acl.policy_rule_offsets[pi + 1];
  var denied = false;
  var best = CONSUL_ACL_NONE;
  var best_spec = -1;
  var i = start;
  while i < stop {
    if acl.rule_resource_codes[i] == rcode {
      let sc = acl.rule_scopes[i];
      let rp: Str = acl.rule_paths[i];
      var hit = false;
      if sc == 0 {
        hit = _str_eq(rp, path);
      } else {
        hit = _has_prefix(path, rp);
      }
      if hit {
        let a = acl.rule_actions[i];
        if a == CONSUL_ACL_DENY {
          denied = true;
        } else {
          var spec = 1000000;
          if sc == 1 {
            spec = rp.len();
          }
          if spec >= best_spec {
            best_spec = spec;
            best = a;
          }
        }
      }
    }
    i = i + 1;
  }
  if denied {
    return CONSUL_ACL_DENY;
  }
  return best;
}

// True when the resolved action code grants the requested action. Write
// implies read. List is its own capability.
fn _action_grants(eff: Int, action: Int) -> Bool {
  if action == CONSUL_ACL_READ {
    if eff == CONSUL_ACL_READ || eff == CONSUL_ACL_WRITE {
      return true;
    }
    return false;
  }
  if action == CONSUL_ACL_WRITE {
    return eff == CONSUL_ACL_WRITE;
  }
  if action == CONSUL_ACL_LIST {
    return eff == CONSUL_ACL_LIST;
  }
  return false;
}

// The effective action a token's policy list resolves for (resource, path):
// DENY when any policy denies, else WRITE over LIST over READ over NONE.
fn _token_action(acl: &ConsulAcl, ti: Int, rcode: Int, path: Str) -> Int {
  let list: Str = acl.token_policy_lists[ti];
  let n = _list_count(list);
  var has_write = false;
  var has_list = false;
  var has_read = false;
  var k = 0;
  while k < n {
    let sp = _list_span(list, k);
    let pname: Str = _span_to_str(list, sp.start, sp.size);
    let pi = _find_str(&acl.policy_names, pname);
    if pi >= 0 {
      let eff = _policy_action(acl, pi, rcode, path);
      if eff == CONSUL_ACL_DENY {
        return CONSUL_ACL_DENY;
      }
      if eff == CONSUL_ACL_WRITE {
        has_write = true;
      }
      if eff == CONSUL_ACL_LIST {
        has_list = true;
      }
      if eff == CONSUL_ACL_READ {
        has_read = true;
      }
    }
    k = k + 1;
  }
  if has_write {
    return CONSUL_ACL_WRITE;
  }
  if has_list {
    return CONSUL_ACL_LIST;
  }
  if has_read {
    return CONSUL_ACL_READ;
  }
  return CONSUL_ACL_NONE;
}

/// The effective capability of `token_id` on (resource, path): DENY when any
/// of its policies denies, WRITE when write is granted (write implies read),
/// else LIST, else READ, else NONE. Management tokens resolve to WRITE; an
/// invalid token resolves to NONE. Unknown token:
/// Err("consul: token not found"); unknown resource:
/// Err("consul: unknown acl resource"). Complexity: O(token policies *
/// policy rules).
pub fn consul_acl_capability(acl: &ConsulAcl, token_id: Str, resource: Str, path: Str) -> Result[Int, Str] {
  let ti = _find_str(&acl.token_ids, token_id);
  if ti < 0 {
    return _err_int("consul: token not found");
  }
  if acl.token_valid[ti] == 0 {
    return _ok_int(CONSUL_ACL_NONE);
  }
  if acl.token_management[ti] == 1 {
    return _ok_int(CONSUL_ACL_WRITE);
  }
  let rcode = _resource_code(resource);
  if rcode < 0 {
    return _err_int("consul: unknown acl resource");
  }
  let eff = _token_action(acl, ti, rcode, path);
  return _ok_int(eff);
}

/// True when `token_id` is allowed to perform `action` (read, write or
/// list) on (resource, path). A deny rule in any of the token's policies
/// wins over every grant; write implies read; list is its own capability.
/// Management tokens are allowed everything and invalid tokens nothing.
/// Unknown token: Err("consul: token not found"); unknown resource:
/// Err("consul: unknown acl resource"); unknown action:
/// Err("consul: invalid acl action"). Complexity: O(token policies *
/// policy rules).
pub fn consul_acl_allows(acl: &ConsulAcl, token_id: Str, resource: Str, path: Str, action: Int) -> Result[Bool, Str] {
  if action != CONSUL_ACL_READ && action != CONSUL_ACL_WRITE && action != CONSUL_ACL_LIST {
    return _err_bool("consul: invalid acl action");
  }
  let ti = _find_str(&acl.token_ids, token_id);
  if ti < 0 {
    return _err_bool("consul: token not found");
  }
  if acl.token_valid[ti] == 0 {
    return _ok_bool(false);
  }
  if acl.token_management[ti] == 1 {
    return _ok_bool(true);
  }
  let rcode = _resource_code(resource);
  if rcode < 0 {
    return _err_bool("consul: unknown acl resource");
  }
  let list: Str = acl.token_policy_lists[ti];
  let n = _list_count(list);
  var k = 0;
  while k < n {
    let sp = _list_span(list, k);
    let pname: Str = _span_to_str(list, sp.start, sp.size);
    let pi = _find_str(&acl.policy_names, pname);
    if pi >= 0 {
      let eff = _policy_action(acl, pi, rcode, path);
      if eff == CONSUL_ACL_DENY {
        return _ok_bool(false);
      }
    }
    k = k + 1;
  }
  k = 0;
  while k < n {
    let sp = _list_span(list, k);
    let pname: Str = _span_to_str(list, sp.start, sp.size);
    let pi = _find_str(&acl.policy_names, pname);
    if pi >= 0 {
      let eff = _policy_action(acl, pi, rcode, path);
      if _action_grants(eff, action) {
        return _ok_bool(true);
      }
    }
    k = k + 1;
  }
  return _ok_bool(false);
}

/// The resource code for a whole resource name (key, node, service,
/// session, acl, event, query), or CONSUL_NOT_FOUND.
/// Complexity: O(1).
pub fn consul_resource_code(resource: Str) -> Int {
  return _resource_code(resource);
}

// ---------------------------------------------------------------------------
// Name tables
// ---------------------------------------------------------------------------

/// "passing" / "warning" / "critical" / "unknown".
/// Complexity: O(1).
pub fn consul_status_name(status: Int) -> Str {
  if status == CONSUL_STATUS_PASSING {
    return "passing";
  }
  if status == CONSUL_STATUS_WARNING {
    return "warning";
  }
  if status == CONSUL_STATUS_CRITICAL {
    return "critical";
  }
  return "unknown";
}

/// "ttl" / "http" / "tcp" / "unknown". Complexity: O(1).
pub fn consul_check_kind_name(kind: Int) -> Str {
  if kind == CONSUL_CHECK_TTL {
    return "ttl";
  }
  if kind == CONSUL_CHECK_HTTP {
    return "http";
  }
  if kind == CONSUL_CHECK_TCP {
    return "tcp";
  }
  return "unknown";
}

/// "release" / "delete" / "unknown". Complexity: O(1).
pub fn consul_session_behavior_name(behavior: Int) -> Str {
  if behavior == CONSUL_BEHAVIOR_RELEASE {
    return "release";
  }
  if behavior == CONSUL_BEHAVIOR_DELETE {
    return "delete";
  }
  return "unknown";
}

/// "none" / "read" / "write" / "list" / "deny" / "unknown".
/// Complexity: O(1).
pub fn consul_acl_action_name(action: Int) -> Str {
  if action == CONSUL_ACL_NONE {
    return "none";
  }
  if action == CONSUL_ACL_READ {
    return "read";
  }
  if action == CONSUL_ACL_WRITE {
    return "write";
  }
  if action == CONSUL_ACL_LIST {
    return "list";
  }
  if action == CONSUL_ACL_DENY {
    return "deny";
  }
  return "unknown";
}

/// The canonical resource name for a resource code, or "unknown".
/// Complexity: O(1).
pub fn consul_resource_name(code: Int) -> Str {
  if code == CONSUL_RES_KEY {
    return "key";
  }
  if code == CONSUL_RES_NODE {
    return "node";
  }
  if code == CONSUL_RES_SERVICE {
    return "service";
  }
  if code == CONSUL_RES_SESSION {
    return "session";
  }
  if code == CONSUL_RES_ACL {
    return "acl";
  }
  if code == CONSUL_RES_EVENT {
    return "event";
  }
  if code == CONSUL_RES_QUERY {
    return "query";
  }
  return "unknown";
}
