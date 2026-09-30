// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.discovery: deterministic service-discovery registry model
//
// A pure, deterministic registry for service instances -- the semantic core
// a DNS-SD/mDNS responder, a Consul-style agent or a load balancer would
// drive. The library contains no sockets, no threads, no wall clock, no I/O
// and no FFI. Time is an explicit integer TTL tick count advanced by the
// caller through discovery_sweep.
//
// A DiscoveryRegistry stores every registration as one slot across parallel
// vectors (Vec[StructType] is unsupported by this compiler):
//   * names[i]      service name (case-sensitive, printable ASCII)
//   * addresses[i]  host address text (printable ASCII)
//   * ports[i]      1..65535
//   * tags[i]       comma-joined tag list ("" = no tags; tags cannot contain
//                   ',' or non-printable bytes)
//   * weights[i]    1..65535, used only by weighted selection
//   * ttls[i]       the TTL granted on registration / heartbeat, in ticks
//   * remaining[i]  ticks left before expiry (0 while DOWN)
//   * states[i]     DISCOVERY_STATE_HEALTHY | DRAINING | DOWN
// plus the change log (seq / kind / name / address / port / tags) and the
// watch table (name / tag / cursor). Every mutation appends one change event
// with a monotonically increasing sequence number starting at 1; the change
// log is never truncated and is the only notification mechanism.
//
// Semantics (all deterministic, all total):
//   * instance identity is the triple (name, address, port): registering a
//     duplicate is refused; deregistration and heartbeat address one triple.
//   * register -> HEALTHY with remaining = ttl and an "add" event.
//   * heartbeat refreshes remaining to ttl and emits "renew"; if the instance
//     was DOWN it is revived to HEALTHY and emits "revive" instead.
//   * sweep(ticks) ages every live (HEALTHY or DRAINING) instance by `ticks`
//     ticks. An instance whose remaining reaches 0 becomes DOWN (still
//     registered, not looked up, not selectable) and emits "expire" in
//     registration order. DOWN instances are not aged further.
//   * drain: HEALTHY -> DRAINING (still looked up, no longer selectable);
//     marking a DOWN instance draining is an error.
//   * mark_healthy: DRAINING or DOWN -> HEALTHY (TTL untouched).
//   * mark_down: HEALTHY or DRAINING -> DOWN.
//   * deregister removes any instance (including DOWN) and emits
//     "deregister"; reap removes every DOWN instance in registration order
//     and emits one "reap" per removed instance (indices shift after a
//     removal: re-resolve with discovery_find).
//   * lookup returns live slots in registration order; lookup_tag requires an
//     exact, delimiter-aware tag match.
//   * selection considers only HEALTHY instances; it walks the eligible slots
//     in registration order and picks the first whose cumulative weight
//     exceeds draw = discovery_lcg_next(seed) % total_weight, so the same
//     registry and seed always pick the same slot. No eligible instance is
//     Err("discovery: no eligible instance").
//   * watches are caller-polled: discovery_watch records the current head
//     sequence, discovery_watch_poll returns the matching change indices
//     since the cursor and jumps the cursor to the head (events skipped by a
//     filter are consumed).
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _ok_int/_ok_bool and _err_int/_err_bool leaf helpers;
// Vec element reads are bound with a typed `let`; Str values are compared
// only with xiom.string.compare.str_compare; tags are joined through
// xiom.string.join.str_join after printable validation; every
// loop is bounded by a vector length and every iteration makes progress; no
// `match`, no lambdas, no Vec[StructType], no Vec[Float64], no FFI.

module xiom.discovery

use xiom.string;
use xiom.string.compare;
use xiom.string.join;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Health state: serving and eligible for selection.
pub const DISCOVERY_STATE_HEALTHY: Int = 0;

/// Health state: still looked up, no longer eligible for selection.
pub const DISCOVERY_STATE_DRAINING: Int = 1;

/// Health state: expired or explicitly down; not looked up, not selectable.
pub const DISCOVERY_STATE_DOWN: Int = 2;

/// TTL granted by callers that want the conventional default (30 ticks).
pub const DISCOVERY_DEFAULT_TTL: Int = 30;

/// Numerical Recipes LCG multiplier used by discovery_lcg_next.
pub const DISCOVERY_LCG_MULTIPLIER: Int = 1664525;

/// Numerical Recipes LCG increment used by discovery_lcg_next.
pub const DISCOVERY_LCG_INCREMENT: Int = 1013904223;

/// LCG modulus 2^31: every state stays in 0..2147483647.
pub const DISCOVERY_LCG_MODULUS: Int = 2147483648;

/// Sentinel returned by discovery_find and index accessors: not registered.
pub const DISCOVERY_NOT_FOUND: Int = -1;

/// Discovery registry. Every field is an internal implementation detail;
/// callers must go through the discovery_* free functions. The eight
/// registration vectors are parallel and always share one length; the change
/// log vectors are parallel and share one length equal to `seq`; the watch
/// table vectors share one length.
pub type DiscoveryRegistry = {
  names: Vec[Str];
  addresses: Vec[Str];
  ports: Vec[Int];
  tags: Vec[Str];
  weights: Vec[Int];
  ttls: Vec[Int];
  remaining: Vec[Int];
  states: Vec[Int];
  seq: Int;
  change_seqs: Vec[Int];
  change_kinds: Vec[Str];
  change_names: Vec[Str];
  change_addresses: Vec[Str];
  change_ports: Vec[Int];
  change_tags: Vec[Str];
  watch_names: Vec[Str];
  watch_tags: Vec[Str];
  watch_cursors: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_bool(v: Bool) -> Result[Bool, Str] { return Ok(v); }
fn _err_bool(m: Str) -> Result[Bool, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Byte `pos` of `s` widened to 0..255; callers guarantee the bounds.
fn _byte_at(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// True when `a` and `b` hold the same bytes.
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `s` is non-empty and every byte is printable ASCII (0x20..0x7E).
fn _printable_only(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(s, i);
    if b < 32 { return false; }
    if b > 126 { return false; }
    i = i + 1;
  }
  return true;
}

// Join validated tags with ',' into one CSV string ("" for an empty list).
fn _join_tags(tags: &Vec[Str]) -> Str {
  return join.str_join(tags, ",");
}

// True when the comma-joined `csv` contains `tag` as one whole element.
// Delimiter-aware: "blue" does not match "blue2" or "blueberry".
fn _csv_has(csv: Str, tag: Str) -> Bool {
  if csv.len() == 0 { return false; }
  if tag.len() == 0 { return false; }
  let n = csv.len();
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || _byte_at(csv, i) == 44 {
      let part = string.str_slice(csv, start, i);
      if _streq(part, tag) { return true; }
      start = i + 1;
    }
    i = i + 1;
  }
  return false;
}

// Slot of the instance identified by (name, address, port), or -1.
fn _index_of(reg: &DiscoveryRegistry, name: Str, address: Str, port: Int) -> Int {
  var i = 0;
  while i < reg.names.len() {
    let nm: Str = reg.names[i];
    if _streq(nm, name) {
      let ad: Str = reg.addresses[i];
      if _streq(ad, address) {
        let pt: Int = reg.ports[i];
        if pt == port { return i; }
      }
    }
    i = i + 1;
  }
  return DISCOVERY_NOT_FOUND;
}

// Append one change event and bump the head sequence.
fn _emit(reg: &mut DiscoveryRegistry, kind: Str, name: Str, address: Str, port: Int, tags: Str) {
  let seq: Int = reg.seq + 1;
  reg.seq = seq;
  reg.change_seqs.push(seq);
  reg.change_kinds.push(kind);
  reg.change_names.push(name);
  reg.change_addresses.push(address);
  reg.change_ports.push(port);
  reg.change_tags.push(tags);
}

// Remove slot `slot` from every parallel registration vector.
fn _remove_slot(reg: &mut DiscoveryRegistry, slot: Int) {
  reg.names.remove(slot);
  reg.addresses.remove(slot);
  reg.ports.remove(slot);
  reg.tags.remove(slot);
  reg.weights.remove(slot);
  reg.ttls.remove(slot);
  reg.remaining.remove(slot);
  reg.states.remove(slot);
}

// True when `state` is looked up (HEALTHY or DRAINING).
fn _is_live(state: Int) -> Bool {
  if state == DISCOVERY_STATE_HEALTHY { return true; }
  if state == DISCOVERY_STATE_DRAINING { return true; }
  return false;
}

// True when slot `i` is selectable for (name, tag): HEALTHY, the name
// matches, and (when `tag` is non-empty) the slot carries that exact tag.
fn _eligible(reg: &DiscoveryRegistry, i: Int, name: Str, tag: Str) -> Bool {
  let nm: Str = reg.names[i];
  if !_streq(nm, name) { return false; }
  let st: Int = reg.states[i];
  if st != DISCOVERY_STATE_HEALTHY { return false; }
  if tag.len() == 0 { return true; }
  let tg: Str = reg.tags[i];
  return _csv_has(tg, tag);
}

// Weighted pick over the eligible slots for (name, tag), or -1 when none is
// eligible. draw = lcg(seed) % total; the first slot whose cumulative weight
// exceeds draw wins, so heavier weights win proportionally and ties always
// resolve to the lowest slot.
fn _select_slot(reg: &DiscoveryRegistry, name: Str, tag: Str, seed: Int) -> Int {
  var total = 0;
  var i = 0;
  while i < reg.names.len() {
    if _eligible(reg, i, name, tag) {
      let w: Int = reg.weights[i];
      total = total + w;
    }
    i = i + 1;
  }
  if total <= 0 { return DISCOVERY_NOT_FOUND; }
  let draw = discovery_lcg_next(seed) % total;
  var acc = 0;
  i = 0;
  while i < reg.names.len() {
    if _eligible(reg, i, name, tag) {
      let w2: Int = reg.weights[i];
      acc = acc + w2;
      if draw < acc { return i; }
    }
    i = i + 1;
  }
  return DISCOVERY_NOT_FOUND;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create an empty registry: no instances, no changes, no watches, head
/// sequence 0. Complexity: O(1).
pub fn discovery_new() -> DiscoveryRegistry {
  return DiscoveryRegistry{
    names: Vec[Str].new();
    addresses: Vec[Str].new();
    ports: Vec[Int].new();
    tags: Vec[Str].new();
    weights: Vec[Int].new();
    ttls: Vec[Int].new();
    remaining: Vec[Int].new();
    states: Vec[Int].new();
    seq: 0;
    change_seqs: Vec[Int].new();
    change_kinds: Vec[Str].new();
    change_names: Vec[Str].new();
    change_addresses: Vec[Str].new();
    change_ports: Vec[Int].new();
    change_tags: Vec[Str].new();
    watch_names: Vec[Str].new();
    watch_tags: Vec[Str].new();
    watch_cursors: Vec[Int].new();
  };
}

// ---------------------------------------------------------------------------
// Registration and removal
// ---------------------------------------------------------------------------

/// Register a service instance in the HEALTHY state with remaining = `ttl`
/// and emit an "add" change event.
/// Params: reg - the registry; name - service name; address - host text;
///         port - 1..65535; tags - tag list (each non-empty printable ASCII
///         without ','); weight - 1..65535; ttl - ticks, >= 1.
/// Returns: Ok(slot) with the new slot index; every Err leaves the registry
/// unchanged. Validation order: name empty / name not printable / address
/// empty / address not printable / port out of range / weight out of range /
/// ttl must be >= 1 / per tag: empty tag, tag not printable, tag contains
/// ',' / duplicate registration.
/// Complexity: O(instance count + tag bytes).
pub fn discovery_register(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int, tags: &Vec[Str], weight: Int, ttl: Int) -> Result[Int, Str] {
  if name.len() == 0 { return _err_int("discovery: empty name"); }
  if !_printable_only(name) { return _err_int("discovery: name not printable"); }
  if address.len() == 0 { return _err_int("discovery: empty address"); }
  if !_printable_only(address) { return _err_int("discovery: address not printable"); }
  if port < 1 || port > 65535 { return _err_int("discovery: port out of range"); }
  if weight < 1 || weight > 65535 { return _err_int("discovery: weight out of range"); }
  if ttl < 1 { return _err_int("discovery: ttl must be >= 1"); }
  var ti = 0;
  while ti < tags.len() {
    let t: Str = tags[ti];
    if t.len() == 0 { return _err_int("discovery: empty tag"); }
    if !_printable_only(t) { return _err_int("discovery: tag not printable"); }
    var k = 0;
    while k < t.len() {
      if _byte_at(t, k) == 44 { return _err_int("discovery: tag contains ','"); }
      k = k + 1;
    }
    ti = ti + 1;
  }
  if _index_of(reg, name, address, port) >= 0 {
    return _err_int("discovery: duplicate registration");
  }
  let tagcsv = _join_tags(tags);
  reg.names.push(name);
  reg.addresses.push(address);
  reg.ports.push(port);
  reg.tags.push(tagcsv);
  reg.weights.push(weight);
  reg.ttls.push(ttl);
  reg.remaining.push(ttl);
  reg.states.push(DISCOVERY_STATE_HEALTHY);
  _emit(reg, "add", name, address, port, tagcsv);
  return _ok_int(reg.names.len() - 1);
}

/// Remove the instance (name, address, port) -- in any state, including DOWN
/// -- and emit a "deregister" change event. Slots after it shift down by one.
/// Returns: Ok(true); Err("discovery: unknown instance") when the triple is
/// not registered.
/// Complexity: O(instance count).
pub fn discovery_deregister(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Result[Bool, Str] {
  let slot = _index_of(reg, name, address, port);
  if slot < 0 { return _err_bool("discovery: unknown instance"); }
  let tg: Str = reg.tags[slot];
  _remove_slot(reg, slot);
  _emit(reg, "deregister", name, address, port, tg);
  return _ok_bool(true);
}

/// Remove every DOWN instance in registration order (each emits a "reap"
/// event) and return the number removed. Live instances are untouched; a
/// second reap with nothing down returns 0.
/// Complexity: O(instance count).
pub fn discovery_reap(reg: &mut DiscoveryRegistry) -> Int {
  var removed = 0;
  var i = 0;
  while i < reg.names.len() {
    let st: Int = reg.states[i];
    if st == DISCOVERY_STATE_DOWN {
      let nm: Str = reg.names[i];
      let ad: Str = reg.addresses[i];
      let pt: Int = reg.ports[i];
      let tg: Str = reg.tags[i];
      _remove_slot(reg, i);
      _emit(reg, "reap", nm, ad, pt, tg);
      removed = removed + 1;
    } else {
      i = i + 1;
    }
  }
  return removed;
}

// ---------------------------------------------------------------------------
// Heartbeat and TTL sweep
// ---------------------------------------------------------------------------

/// Refresh the TTL of an instance: remaining becomes ttls[slot] and the entry
/// emits "renew". A DOWN instance is revived to HEALTHY and emits "revive"
/// instead. Works in any state; the TTL itself is never changed here.
/// Returns: Ok(ttl) with the refreshed TTL; Err("discovery: unknown
/// instance") when the triple is not registered.
/// Complexity: O(instance count).
pub fn discovery_heartbeat(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Result[Int, Str] {
  let slot = _index_of(reg, name, address, port);
  if slot < 0 { return _err_int("discovery: unknown instance"); }
  let ttl: Int = reg.ttls[slot];
  let st: Int = reg.states[slot];
  let tg: Str = reg.tags[slot];
  reg.remaining[slot] = ttl;
  if st == DISCOVERY_STATE_DOWN {
    reg.states[slot] = DISCOVERY_STATE_HEALTHY;
    _emit(reg, "revive", name, address, port, tg);
  } else {
    _emit(reg, "renew", name, address, port, tg);
  }
  return _ok_int(ttl);
}

/// Age every live instance by `ticks` ticks: remaining -= ticks; an instance
/// whose remaining reaches 0 becomes DOWN with remaining 0 and emits
/// "expire" (in registration order). Ticks <= 0 is a no-op returning 0.
/// DOWN instances are not aged and never re-emit.
/// Returns: the number of instances that expired in this sweep.
/// Complexity: O(instance count).
pub fn discovery_sweep(reg: &mut DiscoveryRegistry, ticks: Int) -> Int {
  if ticks <= 0 { return 0; }
  var expired = 0;
  var i = 0;
  while i < reg.names.len() {
    let st: Int = reg.states[i];
    if st != DISCOVERY_STATE_DOWN {
      let rem: Int = reg.remaining[i];
      if rem > ticks {
        reg.remaining[i] = rem - ticks;
      } else {
        reg.remaining[i] = 0;
        reg.states[i] = DISCOVERY_STATE_DOWN;
        let nm: Str = reg.names[i];
        let ad: Str = reg.addresses[i];
        let pt: Int = reg.ports[i];
        let tg: Str = reg.tags[i];
        _emit(reg, "expire", nm, ad, pt, tg);
        expired = expired + 1;
      }
    }
    i = i + 1;
  }
  return expired;
}

// ---------------------------------------------------------------------------
// Health-state transitions
// ---------------------------------------------------------------------------

/// Move a HEALTHY instance to DRAINING (looked up, not selectable) and emit
/// "drain". Returns: Ok(true) on the transition; Ok(false) when already
/// DRAINING (no event); Err("discovery: instance is down") when DOWN;
/// Err("discovery: unknown instance") when not registered.
/// Complexity: O(instance count).
pub fn discovery_mark_draining(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Result[Bool, Str] {
  let slot = _index_of(reg, name, address, port);
  if slot < 0 { return _err_bool("discovery: unknown instance"); }
  let st: Int = reg.states[slot];
  if st == DISCOVERY_STATE_DOWN { return _err_bool("discovery: instance is down"); }
  if st == DISCOVERY_STATE_DRAINING { return _ok_bool(false); }
  let tg: Str = reg.tags[slot];
  reg.states[slot] = DISCOVERY_STATE_DRAINING;
  _emit(reg, "drain", name, address, port, tg);
  return _ok_bool(true);
}

/// Move a HEALTHY or DRAINING instance to DOWN and emit "down".
/// Returns: Ok(true) on the transition; Ok(false) when already DOWN (no
/// event); Err("discovery: unknown instance") when not registered.
/// Complexity: O(instance count).
pub fn discovery_mark_down(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Result[Bool, Str] {
  let slot = _index_of(reg, name, address, port);
  if slot < 0 { return _err_bool("discovery: unknown instance"); }
  let st: Int = reg.states[slot];
  if st == DISCOVERY_STATE_DOWN { return _ok_bool(false); }
  let tg: Str = reg.tags[slot];
  reg.states[slot] = DISCOVERY_STATE_DOWN;
  _emit(reg, "down", name, address, port, tg);
  return _ok_bool(true);
}

/// Move a DRAINING or DOWN instance back to HEALTHY and emit "healthy". The
/// remaining TTL is not touched (use discovery_heartbeat to refresh it).
/// Returns: Ok(true) on the transition; Ok(false) when already HEALTHY (no
/// event); Err("discovery: unknown instance") when not registered.
/// Complexity: O(instance count).
pub fn discovery_mark_healthy(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Result[Bool, Str] {
  let slot = _index_of(reg, name, address, port);
  if slot < 0 { return _err_bool("discovery: unknown instance"); }
  let st: Int = reg.states[slot];
  if st == DISCOVERY_STATE_HEALTHY { return _ok_bool(false); }
  let tg: Str = reg.tags[slot];
  reg.states[slot] = DISCOVERY_STATE_HEALTHY;
  _emit(reg, "healthy", name, address, port, tg);
  return _ok_bool(true);
}

// ---------------------------------------------------------------------------
// Lookups
// ---------------------------------------------------------------------------

/// Slots of the live (HEALTHY or DRAINING) instances with this exact name, in
/// registration order; empty for an unknown name. DOWN instances are
/// excluded.
/// Complexity: O(instance count).
pub fn discovery_lookup(reg: &DiscoveryRegistry, name: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < reg.names.len() {
    let nm: Str = reg.names[i];
    if _streq(nm, name) {
      let st: Int = reg.states[i];
      if _is_live(st) { out.push(i); }
    }
    i = i + 1;
  }
  return out;
}

/// Slots of the live instances with this exact name that carry `tag` as a
/// whole tag, in registration order. An empty tag matches nothing.
/// Complexity: O(instance count * tag bytes).
pub fn discovery_lookup_tag(reg: &DiscoveryRegistry, name: Str, tag: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < reg.names.len() {
    let nm: Str = reg.names[i];
    if _streq(nm, name) {
      let st: Int = reg.states[i];
      if _is_live(st) {
        let tg: Str = reg.tags[i];
        if _csv_has(tg, tag) { out.push(i); }
      }
    }
    i = i + 1;
  }
  return out;
}

/// Slot of the registered instance (any state), or DISCOVERY_NOT_FOUND (-1).
/// Slots shift after deregister/reap, so re-resolve after removals.
/// Complexity: O(instance count).
pub fn discovery_find(reg: &DiscoveryRegistry, name: Str, address: Str, port: Int) -> Int {
  return _index_of(reg, name, address, port);
}

/// Number of registered instances, including DOWN ones.
/// Complexity: O(1).
pub fn discovery_count(reg: &DiscoveryRegistry) -> Int {
  return reg.names.len();
}

/// Name of slot `index` ("" when out of range). Complexity: O(1).
pub fn discovery_name(reg: &DiscoveryRegistry, index: Int) -> Str {
  if index < 0 || index >= reg.names.len() { return ""; }
  let v: Str = reg.names[index];
  return v;
}

/// Address text of slot `index` ("" when out of range). Complexity: O(1).
pub fn discovery_address(reg: &DiscoveryRegistry, index: Int) -> Str {
  if index < 0 || index >= reg.addresses.len() { return ""; }
  let v: Str = reg.addresses[index];
  return v;
}

/// Port of slot `index` (-1 when out of range). Complexity: O(1).
pub fn discovery_port(reg: &DiscoveryRegistry, index: Int) -> Int {
  if index < 0 || index >= reg.ports.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.ports[index];
  return v;
}

/// Comma-joined tag list of slot `index` ("" when out of range).
/// Complexity: O(1).
pub fn discovery_tags(reg: &DiscoveryRegistry, index: Int) -> Str {
  if index < 0 || index >= reg.tags.len() { return ""; }
  let v: Str = reg.tags[index];
  return v;
}

/// True when slot `index` carries `tag` as a whole tag. False out of range.
/// Complexity: O(tag bytes).
pub fn discovery_has_tag(reg: &DiscoveryRegistry, index: Int, tag: Str) -> Bool {
  if index < 0 || index >= reg.tags.len() { return false; }
  let v: Str = reg.tags[index];
  return _csv_has(v, tag);
}

/// Weight of slot `index` (-1 when out of range). Complexity: O(1).
pub fn discovery_weight(reg: &DiscoveryRegistry, index: Int) -> Int {
  if index < 0 || index >= reg.weights.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.weights[index];
  return v;
}

/// Granted TTL (ticks) of slot `index` (-1 when out of range). Complexity: O(1).
pub fn discovery_ttl(reg: &DiscoveryRegistry, index: Int) -> Int {
  if index < 0 || index >= reg.ttls.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.ttls[index];
  return v;
}

/// Ticks remaining before expiry for slot `index` (-1 when out of range).
/// Complexity: O(1).
pub fn discovery_remaining(reg: &DiscoveryRegistry, index: Int) -> Int {
  if index < 0 || index >= reg.remaining.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.remaining[index];
  return v;
}

/// Health state of slot `index`, or DISCOVERY_NOT_FOUND (-1) out of range.
/// Complexity: O(1).
pub fn discovery_state(reg: &DiscoveryRegistry, index: Int) -> Int {
  if index < 0 || index >= reg.states.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.states[index];
  return v;
}

/// Human name of a health state code: "healthy", "draining", "down", or
/// "unknown" for any other value. Complexity: O(1).
pub fn discovery_state_name(state: Int) -> Str {
  if state == DISCOVERY_STATE_HEALTHY { return "healthy"; }
  if state == DISCOVERY_STATE_DRAINING { return "draining"; }
  if state == DISCOVERY_STATE_DOWN { return "down"; }
  return "unknown";
}

// ---------------------------------------------------------------------------
// Deterministic weighted selection
// ---------------------------------------------------------------------------

/// Advance the caller-seeded LCG one step: state' = (1664525 * state +
/// 1013904223) mod 2^31, with the input normalized into 0..2^31-1 first (so
/// negative and out-of-range seeds are accepted). The result is in
/// 0..2147483647 and is the next seed as well as the raw draw for selection.
/// Complexity: O(1).
pub fn discovery_lcg_next(state: Int) -> Int {
  var s = state % DISCOVERY_LCG_MODULUS;
  if s < 0 { s = s + DISCOVERY_LCG_MODULUS; }
  var x = DISCOVERY_LCG_MULTIPLIER * s + DISCOVERY_LCG_INCREMENT;
  x = x % DISCOVERY_LCG_MODULUS;
  if x < 0 { x = x + DISCOVERY_LCG_MODULUS; }
  return x;
}

/// Select one HEALTHY instance of `name` by weight, deterministically from
/// `seed` (see _select_slot for the rule). Returns: Ok(slot);
/// Err("discovery: no eligible instance") when no HEALTHY instance named
/// `name` is registered.
/// Complexity: O(instance count).
pub fn discovery_select(reg: &DiscoveryRegistry, name: Str, seed: Int) -> Result[Int, Str] {
  let slot = _select_slot(reg, name, "", seed);
  if slot < 0 { return _err_int("discovery: no eligible instance"); }
  return _ok_int(slot);
}

/// Like discovery_select, restricted to HEALTHY instances that carry `tag`
/// as a whole tag. An empty tag matches nothing, so the result is
/// Err("discovery: no eligible instance") (there is no tag-less selector;
/// use discovery_select for the unfiltered pick).
/// Complexity: O(instance count * tag bytes).
pub fn discovery_select_tag(reg: &DiscoveryRegistry, name: Str, tag: Str, seed: Int) -> Result[Int, Str] {
  if tag.len() == 0 { return _err_int("discovery: no eligible instance"); }
  let slot = _select_slot(reg, name, tag, seed);
  if slot < 0 { return _err_int("discovery: no eligible instance"); }
  return _ok_int(slot);
}

// ---------------------------------------------------------------------------
// Watches and the change log
// ---------------------------------------------------------------------------

/// Subscribe to future change events: the watch starts at the current head
/// sequence (it never replays the past) and returns its id. `name` filters
/// by the event's service name ("" = every name); `tag` filters by the
/// event's captured tag list ("" = every tag). Each call appends one watch.
/// Complexity: O(1).
pub fn discovery_watch(reg: &mut DiscoveryRegistry, name: Str, tag: Str) -> Int {
  reg.watch_names.push(name);
  reg.watch_tags.push(tag);
  reg.watch_cursors.push(reg.seq);
  return reg.watch_names.len() - 1;
}

/// Number of watches ever created (there is no unwatch).
/// Complexity: O(1).
pub fn discovery_watch_count(reg: &DiscoveryRegistry) -> Int {
  return reg.watch_names.len();
}

/// Name filter of watch `id` ("" when out of range). Complexity: O(1).
pub fn discovery_watch_name(reg: &DiscoveryRegistry, id: Int) -> Str {
  if id < 0 || id >= reg.watch_names.len() { return ""; }
  let v: Str = reg.watch_names[id];
  return v;
}

/// Tag filter of watch `id` ("" when out of range). Complexity: O(1).
pub fn discovery_watch_tag(reg: &DiscoveryRegistry, id: Int) -> Str {
  if id < 0 || id >= reg.watch_tags.len() { return ""; }
  let v: Str = reg.watch_tags[id];
  return v;
}

/// Last sequence delivered to watch `id` (-1 when out of range).
/// Complexity: O(1).
pub fn discovery_watch_cursor(reg: &DiscoveryRegistry, id: Int) -> Int {
  if id < 0 || id >= reg.watch_cursors.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.watch_cursors[id];
  return v;
}

/// Return the change indices matching watch `id` since its cursor, in
/// sequence order, and jump the cursor to the current head. Events skipped
/// by the filters are consumed. An unknown id returns an empty list and
/// changes nothing.
/// Complexity: O(change count).
pub fn discovery_watch_poll(reg: &mut DiscoveryRegistry, id: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if id < 0 || id >= reg.watch_names.len() { return out; }
  let wname: Str = reg.watch_names[id];
  let wtag: Str = reg.watch_tags[id];
  let cursor: Int = reg.watch_cursors[id];
  var i = 0;
  while i < reg.change_seqs.len() {
    let s: Int = reg.change_seqs[i];
    if s > cursor {
      let en: Str = reg.change_names[i];
      let et: Str = reg.change_tags[i];
      var name_ok = true;
      if wname.len() > 0 {
        if !_streq(wname, en) { name_ok = false; }
      }
      var tag_ok = true;
      if name_ok {
        if wtag.len() > 0 {
          if !_csv_has(et, wtag) { tag_ok = false; }
        }
      }
      if name_ok {
        if tag_ok { out.push(i); }
      }
    }
    i = i + 1;
  }
  reg.watch_cursors[id] = reg.seq;
  return out;
}

/// Number of change events ever emitted. Complexity: O(1).
pub fn discovery_change_count(reg: &DiscoveryRegistry) -> Int {
  return reg.change_seqs.len();
}

/// Head sequence number: 0 for a fresh registry, otherwise the sequence of
/// the most recent change event. Complexity: O(1).
pub fn discovery_last_seq(reg: &DiscoveryRegistry) -> Int {
  return reg.seq;
}

/// Change indices with sequence strictly greater than `after_seq` (and, when
/// `name` is non-empty, exactly this service name), in sequence order.
/// Complexity: O(change count).
pub fn discovery_changes_since(reg: &DiscoveryRegistry, name: Str, after_seq: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < reg.change_seqs.len() {
    let s: Int = reg.change_seqs[i];
    if s > after_seq {
      if name.len() == 0 {
        out.push(i);
      } else {
        let en: Str = reg.change_names[i];
        if _streq(en, name) { out.push(i); }
      }
    }
    i = i + 1;
  }
  return out;
}

/// Sequence number of change `index` (-1 when out of range). Complexity: O(1).
pub fn discovery_change_seq(reg: &DiscoveryRegistry, index: Int) -> Int {
  if index < 0 || index >= reg.change_seqs.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.change_seqs[index];
  return v;
}

/// Kind of change `index`: one of "add", "renew", "revive", "drain",
/// "healthy", "down", "expire", "deregister", "reap" ("" when out of range).
/// Complexity: O(1).
pub fn discovery_change_kind(reg: &DiscoveryRegistry, index: Int) -> Str {
  if index < 0 || index >= reg.change_kinds.len() { return ""; }
  let v: Str = reg.change_kinds[index];
  return v;
}

/// Service name captured in change `index` ("" when out of range).
/// Complexity: O(1).
pub fn discovery_change_name(reg: &DiscoveryRegistry, index: Int) -> Str {
  if index < 0 || index >= reg.change_names.len() { return ""; }
  let v: Str = reg.change_names[index];
  return v;
}

/// Address captured in change `index` ("" when out of range).
/// Complexity: O(1).
pub fn discovery_change_address(reg: &DiscoveryRegistry, index: Int) -> Str {
  if index < 0 || index >= reg.change_addresses.len() { return ""; }
  let v: Str = reg.change_addresses[index];
  return v;
}

/// Port captured in change `index` (-1 when out of range). Complexity: O(1).
pub fn discovery_change_port(reg: &DiscoveryRegistry, index: Int) -> Int {
  if index < 0 || index >= reg.change_ports.len() { return DISCOVERY_NOT_FOUND; }
  let v: Int = reg.change_ports[index];
  return v;
}

/// Tag list captured in change `index` ("" when out of range). Changes
/// capture the tags at emission time, so they survive deregistration and
/// reaping. Complexity: O(1).
pub fn discovery_change_tags(reg: &DiscoveryRegistry, index: Int) -> Str {
  if index < 0 || index >= reg.change_tags.len() { return ""; }
  let v: Str = reg.change_tags[index];
  return v;
}

// ---------------------------------------------------------------------------
// Structural invariant
// ---------------------------------------------------------------------------

/// True when the parallel vectors agree in length and the head sequence
/// equals the change-log length -- the registry's structural invariant.
/// Complexity: O(1).
pub fn discovery_check_invariant(reg: &DiscoveryRegistry) -> Bool {
  let n = reg.names.len();
  if reg.addresses.len() != n { return false; }
  if reg.ports.len() != n { return false; }
  if reg.tags.len() != n { return false; }
  if reg.weights.len() != n { return false; }
  if reg.ttls.len() != n { return false; }
  if reg.remaining.len() != n { return false; }
  if reg.states.len() != n { return false; }
  let m = reg.change_seqs.len();
  if reg.change_kinds.len() != m { return false; }
  if reg.change_names.len() != m { return false; }
  if reg.change_addresses.len() != m { return false; }
  if reg.change_ports.len() != m { return false; }
  if reg.change_tags.len() != m { return false; }
  if reg.seq != m { return false; }
  let w = reg.watch_names.len();
  if reg.watch_tags.len() != w { return false; }
  if reg.watch_cursors.len() != w { return false; }
  return true;
}
