// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.discovery conformance tests (22 checks)
//
// Covers the documented API: construction, registration validation and
// identity, health states and their transitions, heartbeat/TTL bookkeeping,
// the expiry sweep and reap, lookups by name and by tag, deterministic
// caller-seeded weighted selection (pinned across seeds), watches with
// sequence-numbered change notifications, the change log and the structural
// invariant.
//
// Fixtures are deterministic: the LCG pins below were computed from the
// documented formula state' = (1664525 * state + 1013904223) mod 2^31 and
// the pick pins from the documented cumulative-weight walk. All Str equality
// goes through str_compare (BUG 17 discipline: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison); Vec element reads use a
// typed `let`. Tests are called directly from main (no indexed Vec[fn]
// dispatch).

module discovery_tests
use xiom.io; use xiom.test;
use xiom.discovery;
use xiom.string.builder;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// A Str holding exactly the two given bytes (for non-printable tests).
fn str_two_bytes(a: Int, b: Int) -> Str {
  var sb = builder.sb_new();
  sb.push(a as UInt8);
  sb.push(b as UInt8);
  return builder.sb_to_str(&sb);
}

// Registered slot on success, -1 on any error.
fn reg_ok(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int, tags: &Vec[Str], weight: Int, ttl: Int) -> Int {
  let r = discovery_register(reg, name, address, port, tags, weight, ttl);
  if r.is_ok {
    let v: Int = r.value;
    return v;
  }
  return -1;
}

fn reg_err_is(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int, tags: &Vec[Str], weight: Int, ttl: Int, want: Str) -> Bool {
  let r = discovery_register(reg, name, address, port, tags, weight, ttl);
  if r.is_ok { return false; }
  let m: Str = r.error;
  return streq(m, want);
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let m: Str = r.error;
  return streq(m, want);
}

fn bool_err_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let m: Str = r.error;
  return streq(m, want);
}

// Heartbeat TTL on success, -1 on any error.
fn hb_ok(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Int {
  let r = discovery_heartbeat(reg, name, address, port);
  if r.is_ok {
    let v: Int = r.value;
    return v;
  }
  return -1;
}

// 1 on Ok(true), 0 on Ok(false), -1 on any error.
fn drain_ok(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Int {
  let r = discovery_mark_draining(reg, name, address, port);
  if !r.is_ok { return -1; }
  let v: Bool = r.value;
  if v { return 1; }
  return 0;
}

fn down_ok(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Int {
  let r = discovery_mark_down(reg, name, address, port);
  if !r.is_ok { return -1; }
  let v: Bool = r.value;
  if v { return 1; }
  return 0;
}

fn healthy_ok(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Int {
  let r = discovery_mark_healthy(reg, name, address, port);
  if !r.is_ok { return -1; }
  let v: Bool = r.value;
  if v { return 1; }
  return 0;
}

fn dereg_ok(reg: &mut DiscoveryRegistry, name: Str, address: Str, port: Int) -> Int {
  let r = discovery_deregister(reg, name, address, port);
  if !r.is_ok { return -1; }
  let v: Bool = r.value;
  if v { return 1; }
  return 0;
}

// Selected slot on success, -1 on any error.
fn sel_ok(reg: &DiscoveryRegistry, name: Str, seed: Int) -> Int {
  let r = discovery_select(reg, name, seed);
  if r.is_ok {
    let v: Int = r.value;
    return v;
  }
  return -1;
}

fn sel_tag_ok(reg: &DiscoveryRegistry, name: Str, tag: Str, seed: Int) -> Int {
  let r = discovery_select_tag(reg, name, tag, seed);
  if r.is_ok {
    let v: Int = r.value;
    return v;
  }
  return -1;
}

fn ints_equal(v: &Vec[Int], a: Int, b: Int) -> Bool {
  if v.len() != 2 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  if x != a { return false; }
  if y != b { return false; }
  return true;
}

fn ints_equal3(v: &Vec[Int], a: Int, b: Int, c: Int) -> Bool {
  if v.len() != 3 { return false; }
  let x: Int = v[0];
  let y: Int = v[1];
  let z: Int = v[2];
  if x != a { return false; }
  if y != b { return false; }
  if z != c { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// One healthy api instance: tags v1,blue; weight 1; ttl 5.
fn one_fixture() -> DiscoveryRegistry {
  var reg = discovery_new();
  var tags = Vec[Str].new();
  tags.push("v1");
  tags.push("blue");
  reg_ok(&mut reg, "api", "10.0.0.1", 8080, &tags, 1, 5);
  return reg;
}

// Three healthy api instances (weights 1, 2, 3; ttl 5; tags: slot 0 =
// v1,blue / slot 1 = v2 / slot 2 = v1,green) plus one web instance (weight 5,
// ttl 10, tags prod) at slot 3.
fn api_fixture() -> DiscoveryRegistry {
  var reg = discovery_new();
  var t0 = Vec[Str].new();
  t0.push("v1");
  t0.push("blue");
  reg_ok(&mut reg, "api", "10.0.0.1", 8080, &t0, 1, 5);
  var t1 = Vec[Str].new();
  t1.push("v2");
  reg_ok(&mut reg, "api", "10.0.0.2", 8080, &t1, 2, 5);
  var t2 = Vec[Str].new();
  t2.push("v1");
  t2.push("green");
  reg_ok(&mut reg, "api", "10.0.0.3", 8080, &t2, 3, 5);
  var t3 = Vec[Str].new();
  t3.push("prod");
  reg_ok(&mut reg, "web", "10.0.0.9", 80, &t3, 5, 10);
  return reg;
}

// api (tags v1,blue) and web (tags prod), both healthy: exactly 2 add events.
fn watch_fixture() -> DiscoveryRegistry {
  var reg = discovery_new();
  var t0 = Vec[Str].new();
  t0.push("v1");
  t0.push("blue");
  reg_ok(&mut reg, "api", "10.0.0.1", 8080, &t0, 1, 5);
  var t1 = Vec[Str].new();
  t1.push("prod");
  reg_ok(&mut reg, "web", "10.0.0.9", 80, &t1, 5, 10);
  return reg;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = discovery_lcg_next(0) == 1013904223;
  if discovery_lcg_next(1) != 1015568748 { ok = false; }
  if discovery_lcg_next(2) != 1017233273 { ok = false; }
  if discovery_lcg_next(42) != 1083814273 { ok = false; }
  if discovery_lcg_next(-1) != 1012239698 { ok = false; }
  if discovery_lcg_next(2147483648) != discovery_lcg_next(0) { ok = false; }
  if discovery_lcg_next(2147483647) != discovery_lcg_next(-1) { ok = false; }
  let v: Int = discovery_lcg_next(999);
  if v < 0 || v > 2147483647 { ok = false; }
  return assert(ok, "lcg: caller-seeded pins and normalization");
}

fn t2() -> TestResult {
  var reg = discovery_new();
  var tags = Vec[Str].new();
  tags.push("v1");
  tags.push("blue");
  let idx = reg_ok(&mut reg, "api", "10.0.0.1", 8080, &tags, 1, 5);
  var ok = idx == 0;
  if discovery_count(&reg) != 1 { ok = false; }
  if !streq(discovery_name(&reg, 0), "api") { ok = false; }
  if !streq(discovery_address(&reg, 0), "10.0.0.1") { ok = false; }
  if discovery_port(&reg, 0) != 8080 { ok = false; }
  if discovery_weight(&reg, 0) != 1 { ok = false; }
  if discovery_ttl(&reg, 0) != 5 { ok = false; }
  if discovery_remaining(&reg, 0) != 5 { ok = false; }
  if discovery_state(&reg, 0) != DISCOVERY_STATE_HEALTHY { ok = false; }
  if !streq(discovery_tags(&reg, 0), "v1,blue") { ok = false; }
  if !discovery_has_tag(&reg, 0, "v1") { ok = false; }
  if !discovery_has_tag(&reg, 0, "blue") { ok = false; }
  if discovery_has_tag(&reg, 0, "blu") { ok = false; }
  if discovery_find(&reg, "api", "10.0.0.1", 8080) != 0 { ok = false; }
  if discovery_find(&reg, "api", "10.0.0.1", 8081) != -1 { ok = false; }
  if discovery_change_count(&reg) != 1 { ok = false; }
  if discovery_last_seq(&reg) != 1 { ok = false; }
  if discovery_change_seq(&reg, 0) != 1 { ok = false; }
  if !streq(discovery_change_kind(&reg, 0), "add") { ok = false; }
  if !streq(discovery_change_name(&reg, 0), "api") { ok = false; }
  if !streq(discovery_change_address(&reg, 0), "10.0.0.1") { ok = false; }
  if discovery_change_port(&reg, 0) != 8080 { ok = false; }
  if !streq(discovery_change_tags(&reg, 0), "v1,blue") { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "register stores the instance and emits the first add event");
}

fn t3() -> TestResult {
  var reg = discovery_new();
  var none = Vec[Str].new();
  var ok = reg_err_is(&mut reg, "", "10.0.0.1", 8080, &none, 1, 5, "discovery: empty name");
  if !reg_err_is(&mut reg, str_two_bytes(97, 9), "10.0.0.1", 8080, &none, 1, 5, "discovery: name not printable") { ok = false; }
  if !reg_err_is(&mut reg, "api", "", 8080, &none, 1, 5, "discovery: empty address") { ok = false; }
  if !reg_err_is(&mut reg, "api", str_two_bytes(97, 7), 8080, &none, 1, 5, "discovery: address not printable") { ok = false; }
  if !reg_err_is(&mut reg, "api", "10.0.0.1", -1, &none, 1, 5, "discovery: port out of range") { ok = false; }
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 0, &none, 1, 5, "discovery: port out of range") { ok = false; }
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 65536, &none, 1, 5, "discovery: port out of range") { ok = false; }
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &none, 0, 5, "discovery: weight out of range") { ok = false; }
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &none, 65536, 5, "discovery: weight out of range") { ok = false; }
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &none, 1, 0, "discovery: ttl must be >= 1") { ok = false; }
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &none, 1, -5, "discovery: ttl must be >= 1") { ok = false; }
  var et = Vec[Str].new();
  et.push("");
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &et, 1, 5, "discovery: empty tag") { ok = false; }
  var ct = Vec[Str].new();
  ct.push("a,b");
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &ct, 1, 5, "discovery: tag contains ','") { ok = false; }
  var nt = Vec[Str].new();
  nt.push(str_two_bytes(120, 9));
  if !reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &nt, 1, 5, "discovery: tag not printable") { ok = false; }
  if discovery_count(&reg) != 0 { ok = false; }
  if discovery_change_count(&reg) != 0 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "register validation catalog leaves the registry unchanged");
}

fn t4() -> TestResult {
  var reg = api_fixture();
  var none = Vec[Str].new();
  var ok = reg_err_is(&mut reg, "api", "10.0.0.1", 8080, &none, 9, 9, "discovery: duplicate registration");
  if !reg_err_is(&mut reg, "web", "10.0.0.9", 80, &none, 5, 10, "discovery: duplicate registration") { ok = false; }
  var tags = Vec[Str].new();
  tags.push("v1");
  if reg_ok(&mut reg, "api", "10.0.0.1", 8081, &tags, 1, 5) != 4 { ok = false; }
  if reg_ok(&mut reg, "api", "10.0.0.4", 8080, &tags, 1, 5) != 5 { ok = false; }
  if discovery_count(&reg) != 6 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "instance identity is the (name, address, port) triple");
}

fn t5() -> TestResult {
  var reg = api_fixture();
  let la: Vec[Int] = discovery_lookup(&reg, "api");
  var ok = ints_equal3(&la, 0, 1, 2);
  let lw: Vec[Int] = discovery_lookup(&reg, "web");
  if lw.len() != 1 {
    ok = false;
  } else {
    let w0: Int = lw[0];
    if w0 != 3 { ok = false; }
  }
  let ln: Vec[Int] = discovery_lookup(&reg, "nope");
  if ln.len() != 0 { ok = false; }
  if down_ok(&mut reg, "api", "10.0.0.2", 8080) != 1 { ok = false; }
  let l2: Vec[Int] = discovery_lookup(&reg, "api");
  if !ints_equal(&l2, 0, 2) { ok = false; }
  return assert(ok, "lookup by name returns live slots in registration order");
}

fn t6() -> TestResult {
  var reg = api_fixture();
  let l1: Vec[Int] = discovery_lookup_tag(&reg, "api", "v1");
  var ok = ints_equal(&l1, 0, 2);
  let l2: Vec[Int] = discovery_lookup_tag(&reg, "api", "v2");
  if l2.len() != 1 {
    ok = false;
  } else {
    let e: Int = l2[0];
    if e != 1 { ok = false; }
  }
  let l3: Vec[Int] = discovery_lookup_tag(&reg, "api", "blue");
  if l3.len() != 1 {
    ok = false;
  } else {
    let e: Int = l3[0];
    if e != 0 { ok = false; }
  }
  let l4: Vec[Int] = discovery_lookup_tag(&reg, "api", "green");
  if l4.len() != 1 {
    ok = false;
  } else {
    let e: Int = l4[0];
    if e != 2 { ok = false; }
  }
  let l5: Vec[Int] = discovery_lookup_tag(&reg, "api", "v");
  if l5.len() != 0 { ok = false; }
  let l6: Vec[Int] = discovery_lookup_tag(&reg, "api", "blue2");
  if l6.len() != 0 { ok = false; }
  let l7: Vec[Int] = discovery_lookup_tag(&reg, "api", "");
  if l7.len() != 0 { ok = false; }
  let l8: Vec[Int] = discovery_lookup_tag(&reg, "web", "prod");
  if l8.len() != 1 {
    ok = false;
  } else {
    let e: Int = l8[0];
    if e != 3 { ok = false; }
  }
  if !discovery_has_tag(&reg, 1, "v2") { ok = false; }
  if discovery_has_tag(&reg, 1, "v1") { ok = false; }
  if discovery_has_tag(&reg, 1, "prod") { ok = false; }
  return assert(ok, "tag lookups are exact and delimiter-aware");
}

fn t7() -> TestResult {
  var reg = one_fixture();
  let e1 = discovery_sweep(&mut reg, 2);
  var ok = e1 == 0;
  if discovery_remaining(&reg, 0) != 3 { ok = false; }
  let refreshed = hb_ok(&mut reg, "api", "10.0.0.1", 8080);
  if refreshed != 5 { ok = false; }
  if discovery_remaining(&reg, 0) != 5 { ok = false; }
  if discovery_state(&reg, 0) != DISCOVERY_STATE_HEALTHY { ok = false; }
  if discovery_change_count(&reg) != 2 { ok = false; }
  if !streq(discovery_change_kind(&reg, 1), "renew") { ok = false; }
  let bad = discovery_heartbeat(&mut reg, "api", "10.0.0.2", 8080);
  if !int_err_is(bad, "discovery: unknown instance") { ok = false; }
  if discovery_change_count(&reg) != 2 { ok = false; }
  return assert(ok, "heartbeat refreshes the TTL and emits renew");
}

fn t8() -> TestResult {
  var reg = discovery_new();
  var none = Vec[Str].new();
  reg_ok(&mut reg, "svc", "10.0.0.1", 9000, &none, 1, 3);
  var ok = discovery_sweep(&mut reg, 1) == 0;
  if discovery_remaining(&reg, 0) != 2 { ok = false; }
  if discovery_sweep(&mut reg, 2) != 1 { ok = false; }
  if discovery_remaining(&reg, 0) != 0 { ok = false; }
  if discovery_state(&reg, 0) != DISCOVERY_STATE_DOWN { ok = false; }
  if discovery_change_count(&reg) != 2 { ok = false; }
  if !streq(discovery_change_kind(&reg, 1), "expire") { ok = false; }
  let lk: Vec[Int] = discovery_lookup(&reg, "svc");
  if lk.len() != 0 { ok = false; }
  let sel = discovery_select(&reg, "svc", 3);
  if !int_err_is(sel, "discovery: no eligible instance") { ok = false; }
  if discovery_sweep(&mut reg, 10) != 0 { ok = false; }
  if discovery_change_count(&reg) != 2 { ok = false; }
  if discovery_find(&reg, "svc", "10.0.0.1", 9000) != 0 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "expiry sweep marks down at zero and never re-emits");
}

fn t9() -> TestResult {
  var reg = discovery_new();
  var none = Vec[Str].new();
  reg_ok(&mut reg, "svc", "10.0.0.1", 9000, &none, 1, 4);
  var ok = discovery_sweep(&mut reg, 4) == 1;
  if discovery_state(&reg, 0) != DISCOVERY_STATE_DOWN { ok = false; }
  let back = hb_ok(&mut reg, "svc", "10.0.0.1", 9000);
  if back != 4 { ok = false; }
  if discovery_state(&reg, 0) != DISCOVERY_STATE_HEALTHY { ok = false; }
  if discovery_remaining(&reg, 0) != 4 { ok = false; }
  if !streq(discovery_change_kind(&reg, 1), "expire") { ok = false; }
  if !streq(discovery_change_kind(&reg, 2), "revive") { ok = false; }
  let lk: Vec[Int] = discovery_lookup(&reg, "svc");
  if lk.len() != 1 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "heartbeat revives a down instance");
}

fn t10() -> TestResult {
  var reg = one_fixture();
  var ok = down_ok(&mut reg, "api", "10.0.0.1", 8080) == 1;
  if discovery_state(&reg, 0) != DISCOVERY_STATE_DOWN { ok = false; }
  if down_ok(&mut reg, "api", "10.0.0.1", 8080) != 0 { ok = false; }
  let dr = discovery_mark_draining(&mut reg, "api", "10.0.0.1", 8080);
  if !bool_err_is(dr, "discovery: instance is down") { ok = false; }
  if healthy_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  if healthy_ok(&mut reg, "api", "10.0.0.1", 8080) != 0 { ok = false; }
  if drain_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  if discovery_state(&reg, 0) != DISCOVERY_STATE_DRAINING { ok = false; }
  if drain_ok(&mut reg, "api", "10.0.0.1", 8080) != 0 { ok = false; }
  if healthy_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  let md = discovery_mark_down(&mut reg, "api", "10.0.0.2", 8080);
  if !bool_err_is(md, "discovery: unknown instance") { ok = false; }
  let mh = discovery_mark_healthy(&mut reg, "api", "10.0.0.2", 8080);
  if !bool_err_is(mh, "discovery: unknown instance") { ok = false; }
  if discovery_change_count(&reg) != 5 { ok = false; }
  if !streq(discovery_change_kind(&reg, 1), "down") { ok = false; }
  if !streq(discovery_change_kind(&reg, 2), "healthy") { ok = false; }
  if !streq(discovery_change_kind(&reg, 3), "drain") { ok = false; }
  if !streq(discovery_change_kind(&reg, 4), "healthy") { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "health-state transitions and idempotent repeats");
}

fn t11() -> TestResult {
  var reg = api_fixture();
  var ok = sel_ok(&reg, "api", 0) == 1;
  if sel_ok(&reg, "api", 1) != 0 { ok = false; }
  if sel_ok(&reg, "api", 2) != 2 { ok = false; }
  if sel_ok(&reg, "api", 42) != 1 { ok = false; }
  if sel_ok(&reg, "api", 100) != 2 { ok = false; }
  if sel_ok(&reg, "api", 0) != sel_ok(&reg, "api", 0) { ok = false; }
  if sel_ok(&reg, "web", 0) != 3 { ok = false; }
  let draw: Int = discovery_lcg_next(0) % 6;
  if draw != 1 { ok = false; }
  return assert(ok, "weighted selection is pinned across seeds");
}

fn t12() -> TestResult {
  var reg = api_fixture();
  var ok = sel_tag_ok(&reg, "api", "v1", 1) == 0;
  if sel_tag_ok(&reg, "api", "v1", 0) != 2 { ok = false; }
  if sel_tag_ok(&reg, "api", "v1", 3) != 2 { ok = false; }
  if sel_tag_ok(&reg, "api", "v2", 5) != 1 { ok = false; }
  if sel_tag_ok(&reg, "api", "green", 7) != 2 { ok = false; }
  if sel_tag_ok(&reg, "api", "nope", 0) != -1 { ok = false; }
  if sel_tag_ok(&reg, "api", "", 0) != -1 { ok = false; }
  let r = discovery_select_tag(&reg, "api", "nope", 0);
  if !int_err_is(r, "discovery: no eligible instance") { ok = false; }
  return assert(ok, "tag-scoped selection uses only tagged healthy instances");
}

fn t13() -> TestResult {
  var reg = api_fixture();
  var ok = drain_ok(&mut reg, "api", "10.0.0.3", 8080) == 1;
  let lk: Vec[Int] = discovery_lookup(&reg, "api");
  if !ints_equal3(&lk, 0, 1, 2) { ok = false; }
  let l1: Vec[Int] = discovery_lookup_tag(&reg, "api", "v1");
  if !ints_equal(&l1, 0, 2) { ok = false; }
  if sel_ok(&reg, "api", 0) != 1 { ok = false; }
  if sel_ok(&reg, "api", 1) != 0 { ok = false; }
  if sel_ok(&reg, "api", 2) != 1 { ok = false; }
  if sel_ok(&reg, "api", 3) != 1 { ok = false; }
  if sel_tag_ok(&reg, "api", "green", 7) != -1 { ok = false; }
  if sel_tag_ok(&reg, "api", "v1", 0) != 0 { ok = false; }
  return assert(ok, "draining instances are looked up but not selectable");
}

fn t14() -> TestResult {
  var reg = api_fixture();
  var ok = dereg_ok(&mut reg, "api", "10.0.0.2", 8080) == 1;
  if discovery_count(&reg) != 3 { ok = false; }
  if discovery_find(&reg, "api", "10.0.0.2", 8080) != -1 { ok = false; }
  let lk: Vec[Int] = discovery_lookup(&reg, "api");
  if !ints_equal(&lk, 0, 1) { ok = false; }
  let lw: Vec[Int] = discovery_lookup(&reg, "web");
  if lw.len() != 1 {
    ok = false;
  } else {
    let e: Int = lw[0];
    if e != 2 { ok = false; }
  }
  if !streq(discovery_change_kind(&reg, 4), "deregister") { ok = false; }
  if !streq(discovery_change_name(&reg, 4), "api") { ok = false; }
  if !streq(discovery_change_tags(&reg, 4), "v2") { ok = false; }
  if discovery_change_port(&reg, 4) != 8080 { ok = false; }
  let again = discovery_deregister(&mut reg, "api", "10.0.0.2", 8080);
  if !bool_err_is(again, "discovery: unknown instance") { ok = false; }
  if down_ok(&mut reg, "api", "10.0.0.3", 8080) != 1 { ok = false; }
  if dereg_ok(&mut reg, "api", "10.0.0.3", 8080) != 1 { ok = false; }
  if discovery_count(&reg) != 2 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "deregistration removes any instance and rejects unknown triples");
}

fn t15() -> TestResult {
  var reg = discovery_new();
  var none = Vec[Str].new();
  reg_ok(&mut reg, "alpha", "10.0.0.1", 1, &none, 1, 1);
  reg_ok(&mut reg, "beta", "10.0.0.2", 2, &none, 1, 9);
  reg_ok(&mut reg, "gamma", "10.0.0.3", 3, &none, 1, 1);
  var ok = discovery_sweep(&mut reg, 1) == 2;
  if discovery_count(&reg) != 3 { ok = false; }
  if discovery_reap(&mut reg) != 2 { ok = false; }
  if discovery_count(&reg) != 1 { ok = false; }
  if discovery_find(&reg, "beta", "10.0.0.2", 2) != 0 { ok = false; }
  if discovery_find(&reg, "alpha", "10.0.0.1", 1) != -1 { ok = false; }
  if discovery_reap(&mut reg) != 0 { ok = false; }
  if discovery_change_count(&reg) != 7 { ok = false; }
  if !streq(discovery_change_kind(&reg, 5), "reap") { ok = false; }
  if !streq(discovery_change_name(&reg, 5), "alpha") { ok = false; }
  if !streq(discovery_change_name(&reg, 6), "gamma") { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "reap removes down instances in registration order");
}

fn t16() -> TestResult {
  var reg = watch_fixture();
  var ok = discovery_last_seq(&reg) == 2;
  let w = discovery_watch(&mut reg, "api", "");
  if w != 0 { ok = false; }
  if discovery_watch_count(&reg) != 1 { ok = false; }
  if discovery_watch_cursor(&reg, 0) != 2 { ok = false; }
  if !streq(discovery_watch_name(&reg, 0), "api") { ok = false; }
  if !streq(discovery_watch_tag(&reg, 0), "") { ok = false; }
  if hb_ok(&mut reg, "api", "10.0.0.1", 8080) != 5 { ok = false; }
  if drain_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  if hb_ok(&mut reg, "web", "10.0.0.9", 80) != 10 { ok = false; }
  let p1: Vec[Int] = discovery_watch_poll(&mut reg, 0);
  if !ints_equal(&p1, 2, 3) { ok = false; }
  if discovery_watch_cursor(&reg, 0) != 5 { ok = false; }
  let p2: Vec[Int] = discovery_watch_poll(&mut reg, 0);
  if p2.len() != 0 { ok = false; }
  if down_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  let p3: Vec[Int] = discovery_watch_poll(&mut reg, 0);
  if p3.len() != 1 {
    ok = false;
  } else {
    let e: Int = p3[0];
    if e != 5 { ok = false; }
  }
  let p4: Vec[Int] = discovery_watch_poll(&mut reg, 99);
  if p4.len() != 0 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "name-filtered watch polls matching events and advances");
}

fn t17() -> TestResult {
  var reg = watch_fixture();
  let w = discovery_watch(&mut reg, "", "prod");
  var ok = w == 0;
  if hb_ok(&mut reg, "api", "10.0.0.1", 8080) != 5 { ok = false; }
  if hb_ok(&mut reg, "web", "10.0.0.9", 80) != 10 { ok = false; }
  let p1: Vec[Int] = discovery_watch_poll(&mut reg, 0);
  if p1.len() != 1 {
    ok = false;
  } else {
    let e: Int = p1[0];
    if e != 3 { ok = false; }
  }
  if !streq(discovery_watch_tag(&reg, 0), "prod") { ok = false; }
  let w2 = discovery_watch(&mut reg, "", "");
  if w2 != 1 { ok = false; }
  if hb_ok(&mut reg, "api", "10.0.0.1", 8080) != 5 { ok = false; }
  let p2: Vec[Int] = discovery_watch_poll(&mut reg, 1);
  if p2.len() != 1 {
    ok = false;
  } else {
    let e: Int = p2[0];
    if e != 4 { ok = false; }
  }
  return assert(ok, "tag-filtered watch matches captured event tags");
}

fn t18() -> TestResult {
  var reg = watch_fixture();
  var ok = discovery_last_seq(&reg) == 2;
  if discovery_change_count(&reg) != 2 { ok = false; }
  if discovery_change_seq(&reg, 0) != 1 { ok = false; }
  if discovery_change_seq(&reg, 1) != 2 { ok = false; }
  if !streq(discovery_change_kind(&reg, 0), "add") { ok = false; }
  if !streq(discovery_change_kind(&reg, 1), "add") { ok = false; }
  if hb_ok(&mut reg, "api", "10.0.0.1", 8080) != 5 { ok = false; }
  if drain_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  if down_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  if healthy_ok(&mut reg, "api", "10.0.0.1", 8080) != 1 { ok = false; }
  if dereg_ok(&mut reg, "web", "10.0.0.9", 80) != 1 { ok = false; }
  if discovery_last_seq(&reg) != 7 { ok = false; }
  if discovery_change_count(&reg) != 7 { ok = false; }
  if !streq(discovery_change_kind(&reg, 2), "renew") { ok = false; }
  if !streq(discovery_change_kind(&reg, 3), "drain") { ok = false; }
  if !streq(discovery_change_kind(&reg, 4), "down") { ok = false; }
  if !streq(discovery_change_kind(&reg, 5), "healthy") { ok = false; }
  if !streq(discovery_change_kind(&reg, 6), "deregister") { ok = false; }
  if !streq(discovery_change_name(&reg, 6), "web") { ok = false; }
  if discovery_change_seq(&reg, 6) != 7 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "sequence numbers are contiguous and kinds are exact");
}

fn t19() -> TestResult {
  var reg = watch_fixture();
  let a: Vec[Int] = discovery_changes_since(&reg, "", 0);
  var ok = ints_equal(&a, 0, 1);
  let b2: Vec[Int] = discovery_changes_since(&reg, "api", 0);
  if b2.len() != 1 {
    ok = false;
  } else {
    let e: Int = b2[0];
    if e != 0 { ok = false; }
  }
  let c: Vec[Int] = discovery_changes_since(&reg, "web", 0);
  if c.len() != 1 {
    ok = false;
  } else {
    let e: Int = c[0];
    if e != 1 { ok = false; }
  }
  let d: Vec[Int] = discovery_changes_since(&reg, "", 2);
  if d.len() != 0 { ok = false; }
  if hb_ok(&mut reg, "api", "10.0.0.1", 8080) != 5 { ok = false; }
  let e2: Vec[Int] = discovery_changes_since(&reg, "", 2);
  if e2.len() != 1 {
    ok = false;
  } else {
    let e: Int = e2[0];
    if e != 2 { ok = false; }
  }
  let f: Vec[Int] = discovery_changes_since(&reg, "web", 2);
  if f.len() != 0 { ok = false; }
  return assert(ok, "changes_since honors the cursor and the name filter");
}

fn t20() -> TestResult {
  var reg = discovery_new();
  var none = Vec[Str].new();
  reg_ok(&mut reg, "a", "10.0.0.1", 1, &none, 1, 2);
  reg_ok(&mut reg, "b", "10.0.0.2", 2, &none, 1, 5);
  reg_ok(&mut reg, "c", "10.0.0.3", 3, &none, 1, 1);
  var ok = discovery_sweep(&mut reg, 0) == 0;
  if discovery_sweep(&mut reg, -3) != 0 { ok = false; }
  if discovery_change_count(&reg) != 3 { ok = false; }
  if discovery_sweep(&mut reg, 1) != 1 { ok = false; }
  if discovery_remaining(&reg, 0) != 1 { ok = false; }
  if discovery_remaining(&reg, 1) != 4 { ok = false; }
  if discovery_remaining(&reg, 2) != 0 { ok = false; }
  if discovery_state(&reg, 2) != DISCOVERY_STATE_DOWN { ok = false; }
  if discovery_sweep(&mut reg, 3) != 1 { ok = false; }
  if discovery_state(&reg, 0) != DISCOVERY_STATE_DOWN { ok = false; }
  if discovery_remaining(&reg, 1) != 1 { ok = false; }
  if discovery_sweep(&mut reg, 5) != 1 { ok = false; }
  if discovery_state(&reg, 1) != DISCOVERY_STATE_DOWN { ok = false; }
  if discovery_change_count(&reg) != 6 { ok = false; }
  if !streq(discovery_change_kind(&reg, 3), "expire") { ok = false; }
  if !streq(discovery_change_name(&reg, 3), "c") { ok = false; }
  if !streq(discovery_change_name(&reg, 4), "a") { ok = false; }
  if !streq(discovery_change_name(&reg, 5), "b") { ok = false; }
  if hb_ok(&mut reg, "a", "10.0.0.1", 1) != 2 { ok = false; }
  if discovery_sweep(&mut reg, 1) != 0 { ok = false; }
  if discovery_remaining(&reg, 0) != 1 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "a sweep ages by ticks and stops at zero");
}

fn t21() -> TestResult {
  var reg = api_fixture();
  var ok = streq(discovery_name(&reg, 99), "");
  if !streq(discovery_name(&reg, -1), "") { ok = false; }
  if !streq(discovery_address(&reg, 99), "") { ok = false; }
  if !streq(discovery_tags(&reg, 99), "") { ok = false; }
  if discovery_port(&reg, 99) != DISCOVERY_NOT_FOUND { ok = false; }
  if discovery_weight(&reg, 99) != -1 { ok = false; }
  if discovery_ttl(&reg, 99) != -1 { ok = false; }
  if discovery_remaining(&reg, 99) != -1 { ok = false; }
  if discovery_state(&reg, 99) != -1 { ok = false; }
  if discovery_has_tag(&reg, 99, "v1") { ok = false; }
  if !streq(discovery_state_name(0), "healthy") { ok = false; }
  if !streq(discovery_state_name(1), "draining") { ok = false; }
  if !streq(discovery_state_name(2), "down") { ok = false; }
  if !streq(discovery_state_name(9), "unknown") { ok = false; }
  if !streq(discovery_change_kind(&reg, 99), "") { ok = false; }
  if discovery_change_seq(&reg, 99) != -1 { ok = false; }
  if discovery_change_port(&reg, 99) != -1 { ok = false; }
  if !streq(discovery_watch_name(&reg, 99), "") { ok = false; }
  if discovery_watch_cursor(&reg, 99) != -1 { ok = false; }
  return assert(ok, "index accessors are total and return sentinels");
}

fn t22() -> TestResult {
  var reg = discovery_new();
  var ok = discovery_count(&reg) == 0;
  if !discovery_check_invariant(&reg) { ok = false; }
  if discovery_last_seq(&reg) != 0 { ok = false; }
  if discovery_change_count(&reg) != 0 { ok = false; }
  let lk: Vec[Int] = discovery_lookup(&reg, "api");
  if lk.len() != 0 { ok = false; }
  let lt: Vec[Int] = discovery_lookup_tag(&reg, "api", "v1");
  if lt.len() != 0 { ok = false; }
  let s = discovery_select(&reg, "api", 0);
  if !int_err_is(s, "discovery: no eligible instance") { ok = false; }
  let st = discovery_select_tag(&reg, "api", "v1", 0);
  if !int_err_is(st, "discovery: no eligible instance") { ok = false; }
  let dr = discovery_deregister(&mut reg, "api", "10.0.0.1", 8080);
  if !bool_err_is(dr, "discovery: unknown instance") { ok = false; }
  if discovery_reap(&mut reg) != 0 { ok = false; }
  if discovery_sweep(&mut reg, 10) != 0 { ok = false; }
  let w = discovery_watch(&mut reg, "api", "");
  if w != 0 { ok = false; }
  let p: Vec[Int] = discovery_watch_poll(&mut reg, 0);
  if p.len() != 0 { ok = false; }
  if !discovery_check_invariant(&reg) { ok = false; }
  return assert(ok, "empty registry is total and side-effect free");
}

fn main() -> Int {
  io.println("=== xiom.discovery conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.discovery: all tests passed");
  } else {
    io.println("xiom.discovery: tests failed");
  }
  return failed;
}
