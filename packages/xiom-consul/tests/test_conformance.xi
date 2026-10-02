// XIOM -- xiom.consul conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented model end to end: KV put/get/delete with the three
// CAS modes, tombstones, monotonic store/modify/create indexes, session
// locks and lock-delay; service registration/deregistration and validation;
// TTL/HTTP/TCP check shapes, status transitions, heartbeats and expiry;
// aggregate service and node health; session create/renew/advance/invalidate
// with release and delete behaviors; ACL rule parsing, precedence and
// capability resolution; constants, name tables and accessor sentinels.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, and Ok/Err are never constructed in test
// functions (only read via is_ok/value/error).

module consul_tests
use xiom.io; use xiom.test;
use xiom.consul;
use xiom.string.compare;

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_rules_is(r: Result[ConsulPolicyRules, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn ok_int(r: Result[Int, Str]) -> Int {
  if r.is_ok {
    return r.value;
  }
  return -999999;
}

fn ok_str(r: Result[Str, Str]) -> Str {
  if r.is_ok {
    return r.value;
  }
  return "";
}

fn ok_bool(r: Result[Bool, Str]) -> Bool {
  if r.is_ok {
    return r.value;
  }
  return false;
}

// --------------------------------------------------
//  KV store
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  if consul_kv_index(&kv) != 0 { ok = false; }
  if consul_kv_entry_count(&kv) != 0 || consul_kv_live_count(&kv) != 0 { ok = false; }
  if !err_str_is(consul_kv_get(&kv, "a"), "consul: key not found") { ok = false; }
  let p1 = consul_kv_put(&mut kv, "a", "one", 7, CONSUL_CAS_NONE);
  if !p1.is_ok { ok = false; } else {
    let idx: Int = p1.value;
    if idx != 1 { ok = false; }
  }
  let g1 = consul_kv_get(&kv, "a");
  if !g1.is_ok { ok = false; } else {
    let v: Str = g1.value;
    if !str_eq(v, "one") { ok = false; }
  }
  if consul_kv_find(&kv, "a") != 0 { ok = false; }
  if consul_kv_flags_at(&kv, 0) != 7 { ok = false; }
  if consul_kv_create_index_at(&kv, 0) != 1 { ok = false; }
  if consul_kv_modify_index_at(&kv, 0) != 1 { ok = false; }
  if consul_kv_index(&kv) != 1 { ok = false; }
  if consul_kv_live_count(&kv) != 1 { ok = false; }
  let p2 = consul_kv_put(&mut kv, "a", "two", 0, CONSUL_CAS_NONE);
  if !p2.is_ok { ok = false; } else {
    let idx: Int = p2.value;
    if idx != 2 { ok = false; }
  }
  if !str_eq(ok_str(consul_kv_get(&kv, "a")), "two") { ok = false; }
  if consul_kv_create_index_at(&kv, 0) != 1 { ok = false; }
  if consul_kv_modify_index_at(&kv, 0) != 2 { ok = false; }
  if !err_str_is(consul_kv_get(&kv, ""), "consul: empty key") { ok = false; }
  let badkey = "a\u{0001}b";
  if !err_str_is(consul_kv_get(&kv, badkey), "consul: key not printable") { ok = false; }
  if !err_int_is(consul_kv_put(&mut kv, badkey, "v", 0, CONSUL_CAS_NONE), "consul: key not printable") { ok = false; }
  if !err_int_is(consul_kv_put(&mut kv, "a", "v", -1, CONSUL_CAS_NONE), "consul: flags must not be negative") { ok = false; }
  if !err_int_is(consul_kv_put(&mut kv, "a", "v", 0, -2), "consul: invalid cas") { ok = false; }
  if consul_kv_index(&kv) != 2 { ok = false; }
  return assert(ok, "kv put/get: values, flags, indexes, validation");
}

fn t2() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  // cas = 0 creates only when the key is absent.
  let c1 = consul_kv_put(&mut kv, "k", "v1", 0, CONSUL_CAS_CREATE);
  if !c1.is_ok { ok = false; } else {
    let idx: Int = c1.value;
    if idx != 1 { ok = false; }
  }
  if !err_int_is(consul_kv_put(&mut kv, "k", "v2", 0, CONSUL_CAS_CREATE), "consul: cas mismatch") { ok = false; }
  if !str_eq(ok_str(consul_kv_get(&kv, "k")), "v1") { ok = false; }
  if consul_kv_index(&kv) != 1 { ok = false; }
  // cas = modify index matches.
  let c2 = consul_kv_put(&mut kv, "k", "v3", 0, 1);
  if !c2.is_ok { ok = false; } else {
    let idx: Int = c2.value;
    if idx != 2 { ok = false; }
  }
  if !err_int_is(consul_kv_put(&mut kv, "k", "v4", 0, 1), "consul: cas mismatch") { ok = false; }
  if !str_eq(ok_str(consul_kv_get(&kv, "k")), "v3") { ok = false; }
  // cas on a missing key is a mismatch.
  if !err_int_is(consul_kv_put(&mut kv, "m", "v", 0, 3), "consul: cas mismatch") { ok = false; }
  // A tombstone counts as missing for create-only.
  let d = consul_kv_delete(&mut kv, "k", CONSUL_CAS_NONE);
  if !ok_bool(d) { ok = false; }
  if !consul_kv_is_tombstone(&kv, 0) { ok = false; }
  let c3 = consul_kv_put(&mut kv, "k", "v5", 0, CONSUL_CAS_CREATE);
  if !c3.is_ok { ok = false; } else {
    let idx: Int = c3.value;
    if idx != 4 { ok = false; }
  }
  if consul_kv_create_index_at(&kv, 0) != 4 { ok = false; }
  if consul_kv_modify_index_at(&kv, 0) != 4 { ok = false; }
  return assert(ok, "kv CAS: create-only, index match, tombstone re-create");
}

fn t3() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  let p = consul_kv_put(&mut kv, "a", "va", 0, CONSUL_CAS_NONE);
  if !p.is_ok { ok = false; }
  let d0 = consul_kv_delete(&mut kv, "a", CONSUL_CAS_CREATE);
  if !d0.is_ok { ok = false; } else {
    let b: Bool = d0.value;
    if !b { ok = false; }
  }
  if consul_kv_index(&kv) != 2 { ok = false; }
  if !consul_kv_is_tombstone(&kv, 0) { ok = false; }
  if !err_str_is(consul_kv_get(&kv, "a"), "consul: key not found") { ok = false; }
  if consul_kv_modify_index_at(&kv, 0) != 2 { ok = false; }
  if consul_kv_create_index_at(&kv, 0) != 1 { ok = false; }
  if !str_eq(consul_kv_value_at(&kv, 0), "") { ok = false; }
  // Delete of a tombstone with cas = 0 reports false and changes nothing.
  let d1 = consul_kv_delete(&mut kv, "a", CONSUL_CAS_CREATE);
  if !d1.is_ok { ok = false; } else {
    let b: Bool = d1.value;
    if b { ok = false; }
  }
  if consul_kv_index(&kv) != 2 { ok = false; }
  // Unconditional delete of a missing key is Ok(true) with no write.
  let d2 = consul_kv_delete(&mut kv, "nope", CONSUL_CAS_NONE);
  if !d2.is_ok { ok = false; } else {
    let b: Bool = d2.value;
    if !b { ok = false; }
  }
  if consul_kv_entry_count(&kv) != 1 { ok = false; }
  if consul_kv_index(&kv) != 2 { ok = false; }
  // cas > 0 on a missing key is a mismatch.
  if !err_bool_is(consul_kv_delete(&mut kv, "nope", 5), "consul: cas mismatch") { ok = false; }
  // Re-create and delete with a matching cas.
  let p2 = consul_kv_put(&mut kv, "a", "vb", 0, CONSUL_CAS_NONE);
  if !p2.is_ok { ok = false; }
  if !err_bool_is(consul_kv_delete(&mut kv, "a", 2), "consul: cas mismatch") { ok = false; }
  let d3 = consul_kv_delete(&mut kv, "a", 3);
  if !d3.is_ok { ok = false; } else {
    let b: Bool = d3.value;
    if !b { ok = false; }
  }
  if consul_kv_index(&kv) != 4 { ok = false; }
  if !err_bool_is(consul_kv_delete(&mut kv, "", CONSUL_CAS_NONE), "consul: empty key") { ok = false; }
  if !err_bool_is(consul_kv_delete(&mut kv, "a", -2), "consul: invalid cas") { ok = false; }
  return assert(ok, "kv delete: tombstones, idempotence, CAS modes");
}

fn t4() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  let r1 = consul_kv_put(&mut kv, "k1", "a", 0, CONSUL_CAS_NONE);
  let r2 = consul_kv_put(&mut kv, "k2", "b", 0, CONSUL_CAS_NONE);
  let r3 = consul_kv_put(&mut kv, "k1", "c", 0, CONSUL_CAS_NONE);
  let r4 = consul_kv_delete(&mut kv, "k2", CONSUL_CAS_NONE);
  let r5 = consul_kv_put(&mut kv, "k3", "d", 0, CONSUL_CAS_NONE);
  if ok_int(r1) != 1 || ok_int(r2) != 2 || ok_int(r3) != 3 { ok = false; }
  if !ok_bool(r4) || ok_int(r5) != 5 { ok = false; }
  if consul_kv_index(&kv) != 5 { ok = false; }
  // Monotonic: every modify index is <= the store index, and the store
  // index is exactly the largest modify index.
  var max_mod = 0;
  var i = 0;
  while i < consul_kv_entry_count(&kv) {
    let m = consul_kv_modify_index_at(&kv, i);
    if m > consul_kv_index(&kv) { ok = false; }
    if m > max_mod { max_mod = m; }
    i = i + 1;
  }
  if max_mod != consul_kv_index(&kv) { ok = false; }
  if consul_kv_create_index_at(&kv, consul_kv_find(&kv, "k1")) != 1 { ok = false; }
  if consul_kv_find(&kv, "missing") != CONSUL_NOT_FOUND { ok = false; }
  // Reads never bump the index.
  let g = consul_kv_get(&kv, "k1");
  if !g.is_ok { ok = false; }
  if consul_kv_index(&kv) != 5 { ok = false; }
  if consul_kv_live_count(&kv) != 2 { ok = false; }
  if !str_eq(consul_kv_key_at(&kv, 99), "") { ok = false; }
  if consul_kv_flags_at(&kv, 99) != CONSUL_NOT_FOUND { ok = false; }
  if consul_kv_modify_index_at(&kv, 99) != CONSUL_NOT_FOUND { ok = false; }
  if consul_kv_is_tombstone(&kv, 99) { ok = false; }
  return assert(ok, "kv monotonic indexes and accessor sentinels");
}

fn t5() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  var sessions = consul_sessions_new();
  let a0 = consul_kv_acquire(&mut kv, &sessions, "a", "v", "nope");
  if !err_int_is(a0, "consul: session not found") { ok = false; }
  let s1 = consul_session_create(&mut sessions, 10, CONSUL_BEHAVIOR_RELEASE, 0);
  if !s1.is_ok { ok = false; }
  let id1: Str = ok_str(s1);
  let a1 = consul_kv_acquire(&mut kv, &sessions, "a", "va", id1);
  if !a1.is_ok { ok = false; } else {
    let li: Int = a1.value;
    if li != 1 { ok = false; }
  }
  if !str_eq(consul_kv_lock_session(&kv, 0), id1) { ok = false; }
  if consul_kv_lock_index(&kv, 0) != 1 { ok = false; }
  if !err_int_is(consul_kv_put(&mut kv, "a", "x", 0, CONSUL_CAS_NONE), "consul: key is locked") { ok = false; }
  if !err_bool_is(consul_kv_delete(&mut kv, "a", CONSUL_CAS_NONE), "consul: key is locked") { ok = false; }
  let s2 = consul_session_create(&mut sessions, 10, CONSUL_BEHAVIOR_RELEASE, 0);
  let id2: Str = ok_str(s2);
  if !err_int_is(consul_kv_acquire(&mut kv, &sessions, "a", "vb", id2), "consul: key is locked") { ok = false; }
  // The holder can re-acquire, refreshing the value and lock index.
  let a2 = consul_kv_acquire(&mut kv, &sessions, "a", "vb", id1);
  if !a2.is_ok { ok = false; } else {
    let li: Int = a2.value;
    if li != 2 { ok = false; }
  }
  if !str_eq(ok_str(consul_kv_get(&kv, "a")), "vb") { ok = false; }
  if consul_kv_entry_count(&kv) != 1 { ok = false; }
  let rel0 = consul_kv_release(&mut kv, "a", id2);
  if !rel0.is_ok { ok = false; } else {
    let b: Bool = rel0.value;
    if b { ok = false; }
  }
  let rel1 = consul_kv_release(&mut kv, "a", id1);
  if !rel1.is_ok { ok = false; } else {
    let b: Bool = rel1.value;
    if !b { ok = false; }
  }
  if !str_eq(consul_kv_lock_session(&kv, 0), "") { ok = false; }
  if consul_kv_lock_index(&kv, 0) != 0 { ok = false; }
  let p = consul_kv_put(&mut kv, "a", "free", 0, CONSUL_CAS_NONE);
  if !p.is_ok { ok = false; }
  if !str_eq(ok_str(consul_kv_get(&kv, "a")), "free") { ok = false; }
  let rel2 = consul_kv_release(&mut kv, "missing", id1);
  if !rel2.is_ok { ok = false; } else {
    let b: Bool = rel2.value;
    if b { ok = false; }
  }
  return assert(ok, "kv session locks: acquire, refresh, refuse, release");
}

// --------------------------------------------------
//  Sessions
// --------------------------------------------------

fn t6() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  var sessions = consul_sessions_new();
  if consul_session_count(&sessions) != 0 { ok = false; }
  let s1 = consul_session_create(&mut sessions, 5, CONSUL_BEHAVIOR_RELEASE, 0);
  if !s1.is_ok { ok = false; } else {
    let id: Str = s1.value;
    if !str_eq(id, "consul-session-1") { ok = false; }
  }
  let s2 = consul_session_create(&mut sessions, 10, CONSUL_BEHAVIOR_DELETE, 2);
  if !s2.is_ok { ok = false; } else {
    let id: Str = s2.value;
    if !str_eq(id, "consul-session-2") { ok = false; }
  }
  if consul_session_count(&sessions) != 2 { ok = false; }
  if consul_session_find(&sessions, "consul-session-2") != 1 { ok = false; }
  if consul_session_ttl_at(&sessions, 0) != 5 { ok = false; }
  if consul_session_remaining_at(&sessions, 0) != 5 { ok = false; }
  if consul_session_behavior_at(&sessions, 1) != CONSUL_BEHAVIOR_DELETE { ok = false; }
  if consul_session_lock_delay_at(&sessions, 1) != 2 { ok = false; }
  if consul_session_invalidated_at(&sessions, 0) != 0 { ok = false; }
  if !err_str_is(consul_session_create(&mut sessions, 0, 0, 0), "consul: ttl must be >= 1") { ok = false; }
  if !err_str_is(consul_session_create(&mut sessions, 1, 9, 0), "consul: invalid session behavior") { ok = false; }
  if !err_str_is(consul_session_create(&mut sessions, 1, 0, -1), "consul: lock delay must not be negative") { ok = false; }
  if consul_session_count(&sessions) != 2 { ok = false; }
  let r1 = consul_session_renew(&mut sessions, "consul-session-1");
  if ok_int(r1) != 5 { ok = false; }
  if consul_session_advance(&mut kv, &mut sessions, 3) != 0 { ok = false; }
  if consul_session_remaining_at(&sessions, 0) != 2 { ok = false; }
  let r2 = consul_session_renew(&mut sessions, "consul-session-1");
  if ok_int(r2) != 5 { ok = false; }
  if consul_session_advance(&mut kv, &mut sessions, 5) != 1 { ok = false; }
  if consul_session_remaining_at(&sessions, 0) != 0 { ok = false; }
  if consul_session_invalidated_at(&sessions, 0) != 1 { ok = false; }
  if !err_int_is(consul_session_renew(&mut sessions, "consul-session-1"), "consul: session invalidated") { ok = false; }
  if !err_int_is(consul_session_renew(&mut sessions, "nope"), "consul: session not found") { ok = false; }
  if consul_session_advance(&mut kv, &mut sessions, 0) != 0 { ok = false; }
  if consul_session_advance(&mut kv, &mut sessions, -1) != 0 { ok = false; }
  if consul_session_id_at(&sessions, 99) != "" { ok = false; }
  if consul_session_ttl_at(&sessions, 99) != CONSUL_NOT_FOUND { ok = false; }
  return assert(ok, "sessions: deterministic ids, renew, TTL expiry");
}

fn t7() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  var sessions = consul_sessions_new();
  let s1 = consul_session_create(&mut sessions, 3, CONSUL_BEHAVIOR_RELEASE, 4);
  let id1: Str = ok_str(s1);
  let a = consul_kv_acquire(&mut kv, &sessions, "a", "va", id1);
  if !a.is_ok { ok = false; }
  if consul_session_advance(&mut kv, &mut sessions, 3) != 1 { ok = false; }
  // Release behavior keeps the value and applies the session lock delay.
  if !str_eq(ok_str(consul_kv_get(&kv, "a")), "va") { ok = false; }
  if !str_eq(consul_kv_lock_session(&kv, 0), "") { ok = false; }
  if consul_kv_lock_delay(&kv, 0) != 4 { ok = false; }
  let s2 = consul_session_create(&mut sessions, 5, CONSUL_BEHAVIOR_RELEASE, 0);
  let id2: Str = ok_str(s2);
  if !err_int_is(consul_kv_acquire(&mut kv, &sessions, "a", "vb", id2), "consul: lock delay active") { ok = false; }
  if consul_kv_advance_locks(&mut kv, 2) != 0 { ok = false; }
  if consul_kv_lock_delay(&kv, 0) != 2 { ok = false; }
  if !err_int_is(consul_kv_acquire(&mut kv, &sessions, "a", "vb", id2), "consul: lock delay active") { ok = false; }
  if consul_kv_advance_locks(&mut kv, 2) != 1 { ok = false; }
  if consul_kv_lock_delay(&kv, 0) != 0 { ok = false; }
  let a2 = consul_kv_acquire(&mut kv, &sessions, "a", "vb", id2);
  if !a2.is_ok { ok = false; } else {
    let li: Int = a2.value;
    if li != 2 { ok = false; }
  }
  if !str_eq(consul_kv_lock_session(&kv, 0), id2) { ok = false; }
  if consul_kv_advance_locks(&mut kv, 0) != 0 { ok = false; }
  return assert(ok, "session release behavior and lock delay window");
}

fn t8() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  var sessions = consul_sessions_new();
  let s1 = consul_session_create(&mut sessions, 2, CONSUL_BEHAVIOR_DELETE, 1);
  let id1: Str = ok_str(s1);
  let a = consul_kv_acquire(&mut kv, &sessions, "k", "v", id1);
  if !a.is_ok { ok = false; }
  if consul_session_advance(&mut kv, &mut sessions, 2) != 1 { ok = false; }
  // Delete behavior tombstones the key.
  if !err_str_is(consul_kv_get(&kv, "k"), "consul: key not found") { ok = false; }
  if !consul_kv_is_tombstone(&kv, 0) { ok = false; }
  if consul_kv_modify_index_at(&kv, 0) != 2 { ok = false; }
  if consul_kv_lock_delay(&kv, 0) != 1 { ok = false; }
  // Explicit invalidation is idempotent and reports the affected count.
  let s2 = consul_session_create(&mut sessions, 9, CONSUL_BEHAVIOR_DELETE, 0);
  let id2: Str = ok_str(s2);
  let a2 = consul_kv_acquire(&mut kv, &sessions, "k2", "v2", id2);
  if !a2.is_ok { ok = false; }
  let inv1 = consul_session_invalidate(&mut kv, &mut sessions, id2);
  if ok_int(inv1) != 1 { ok = false; }
  if !err_str_is(consul_kv_get(&kv, "k2"), "consul: key not found") { ok = false; }
  let inv2 = consul_session_invalidate(&mut kv, &mut sessions, id2);
  if ok_int(inv2) != 0 { ok = false; }
  let inv3 = consul_session_invalidate(&mut kv, &mut sessions, "nope");
  if !err_int_is(inv3, "consul: session not found") { ok = false; }
  return assert(ok, "session delete behavior and explicit invalidation");
}

fn t9() -> TestResult {
  var ok = true;
  var kv = consul_kv_new();
  var sessions = consul_sessions_new();
  // Acquiring with an invalidated session is refused.
  let s1 = consul_session_create(&mut sessions, 1, CONSUL_BEHAVIOR_RELEASE, 0);
  let id1: Str = ok_str(s1);
  if consul_session_advance(&mut kv, &mut sessions, 1) != 1 { ok = false; }
  if !err_int_is(consul_kv_acquire(&mut kv, &sessions, "x", "v", id1), "consul: session invalidated") { ok = false; }
  // A session with no held keys expires cleanly.
  let s2 = consul_session_create(&mut sessions, 2, CONSUL_BEHAVIOR_RELEASE, 0);
  if !s2.is_ok { ok = false; }
  if consul_session_advance(&mut kv, &mut sessions, 2) != 1 { ok = false; }
  if consul_kv_entry_count(&kv) != 0 { ok = false; }
  if consul_session_find(&sessions, "consul-session-2") != 1 { ok = false; }
  if consul_session_invalidated_at(&sessions, 1) != 1 { ok = false; }
  return assert(ok, "sessions: invalidated refusal, empty-session expiry");
}

// --------------------------------------------------
//  Services and checks
// --------------------------------------------------

fn t10() -> TestResult {
  var ok = true;
  var reg = consul_services_new();
  if consul_service_count(&reg) != 0 || consul_check_count(&reg) != 0 { ok = false; }
  let s1 = consul_register_service(&mut reg, "web-1", "web", "10.0.0.1", 8080, "a,b");
  if !s1.is_ok { ok = false; } else {
    let i: Int = s1.value;
    if i != 0 { ok = false; }
  }
  let s2 = consul_register_service(&mut reg, "web-2", "web", "10.0.0.2", 8081, "");
  if !s2.is_ok { ok = false; }
  if consul_service_count(&reg) != 2 { ok = false; }
  if consul_service_find(&reg, "web-2") != 1 { ok = false; }
  if !str_eq(consul_service_name_at(&reg, 0), "web") { ok = false; }
  if !str_eq(consul_service_address_at(&reg, 1), "10.0.0.2") { ok = false; }
  if consul_service_port_at(&reg, 0) != 8080 { ok = false; }
  if !str_eq(consul_service_tags_at(&reg, 0), "a,b") { ok = false; }
  if !consul_service_has_tag(&reg, 0, "b") { ok = false; }
  if consul_service_has_tag(&reg, 0, "a,b") { ok = false; }
  if consul_service_has_tag(&reg, 1, "a") { ok = false; }
  let c1 = consul_add_ttl_check(&mut reg, "c1", "web-1", "ttl", 5, "");
  if !c1.is_ok { ok = false; }
  let c2 = consul_add_http_check(&mut reg, "c2", "web-2", "http", "http://10.0.0.2/health", 10, 2, "");
  if !c2.is_ok { ok = false; }
  if consul_check_count(&reg) != 2 { ok = false; }
  // Deregistering a service removes its checks.
  let d = consul_deregister_service(&mut reg, "web-1");
  if !d.is_ok { ok = false; } else {
    let n: Int = d.value;
    if n != 1 { ok = false; }
  }
  if consul_service_count(&reg) != 1 { ok = false; }
  if consul_check_count(&reg) != 1 { ok = false; }
  if consul_service_find(&reg, "web-1") != CONSUL_NOT_FOUND { ok = false; }
  if consul_check_find(&reg, "c1") != CONSUL_NOT_FOUND { ok = false; }
  if consul_check_find(&reg, "c2") != 0 { ok = false; }
  if !err_int_is(consul_deregister_service(&mut reg, "nope"), "consul: service not found") { ok = false; }
  return assert(ok, "service registry: register, accessors, deregister with checks");
}

fn t11() -> TestResult {
  var ok = true;
  var reg = consul_services_new();
  let badid = "bad\u{0001}";
  if !err_int_is(consul_register_service(&mut reg, "", "n", "", 1, ""), "consul: service id must not be empty") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, badid, "n", "", 1, ""), "consul: service id not printable") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "", "", 1, ""), "consul: service name must not be empty") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", badid, "", 1, ""), "consul: service name not printable") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "n", badid, 1, ""), "consul: service address not printable") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "n", "", 70000, ""), "consul: service port out of range") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "n", "", -1, ""), "consul: service port out of range") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "n", "", 1, "a,,b"), "consul: empty service tag") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "n", "", 1, ",a"), "consul: empty service tag") { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "n", "", 1, badid), "consul: service tag not printable") { ok = false; }
  if consul_service_count(&reg) != 0 { ok = false; }
  let s = consul_register_service(&mut reg, "i", "n", "", 1, "");
  if !s.is_ok { ok = false; }
  if !err_int_is(consul_register_service(&mut reg, "i", "n2", "", 2, ""), "consul: duplicate service") { ok = false; }
  if consul_service_count(&reg) != 1 { ok = false; }
  return assert(ok, "service validation: every rejection leaves the registry unchanged");
}

fn t12() -> TestResult {
  var ok = true;
  var reg = consul_services_new();
  consul_register_service(&mut reg, "s", "svc", "", 1, "");
  let c = consul_add_ttl_check(&mut reg, "c", "s", "ttl", 5, "note");
  if !c.is_ok { ok = false; } else {
    let i: Int = c.value;
    if i != 0 { ok = false; }
  }
  if consul_check_kind_at(&reg, 0) != CONSUL_CHECK_TTL { ok = false; }
  if consul_check_status_at(&reg, 0) != CONSUL_STATUS_PASSING { ok = false; }
  if consul_check_ttl_at(&reg, 0) != 5 { ok = false; }
  if consul_check_remaining_at(&reg, 0) != 5 { ok = false; }
  if !str_eq(consul_check_notes_at(&reg, 0), "note") { ok = false; }
  if consul_service_health(&reg, "s") != CONSUL_STATUS_PASSING { ok = false; }
  let st1 = consul_check_set_status(&mut reg, "c", CONSUL_STATUS_WARNING);
  if ok_int(st1) != CONSUL_STATUS_PASSING { ok = false; }
  if consul_service_health(&reg, "s") != CONSUL_STATUS_WARNING { ok = false; }
  let st2 = consul_check_set_status(&mut reg, "c", CONSUL_STATUS_CRITICAL);
  if ok_int(st2) != CONSUL_STATUS_WARNING { ok = false; }
  if consul_service_health(&reg, "s") != CONSUL_STATUS_CRITICAL { ok = false; }
  let st3 = consul_check_set_status(&mut reg, "c", CONSUL_STATUS_PASSING);
  if ok_int(st3) != CONSUL_STATUS_CRITICAL { ok = false; }
  if !err_int_is(consul_check_set_status(&mut reg, "c", 3), "consul: invalid check status") { ok = false; }
  if !err_int_is(consul_check_set_status(&mut reg, "zz", CONSUL_STATUS_PASSING), "consul: check not found") { ok = false; }
  if consul_check_advance(&mut reg, 3) != 0 { ok = false; }
  if consul_check_remaining_at(&reg, 0) != 2 { ok = false; }
  let hb = consul_check_heartbeat(&mut reg, "c");
  if ok_int(hb) != 5 { ok = false; }
  if consul_check_remaining_at(&reg, 0) != 5 { ok = false; }
  // Heartbeat after a manual critical resets to passing.
  consul_check_set_status(&mut reg, "c", CONSUL_STATUS_CRITICAL);
  let hb2 = consul_check_heartbeat(&mut reg, "c");
  if ok_int(hb2) != 5 { ok = false; }
  if consul_check_status_at(&reg, 0) != CONSUL_STATUS_PASSING { ok = false; }
  let h2 = consul_add_http_check(&mut reg, "h", "s", "http", "http://x/y", 5, 1, "");
  if !h2.is_ok { ok = false; }
  if !err_int_is(consul_check_heartbeat(&mut reg, "h"), "consul: check is not a ttl check") { ok = false; }
  if !err_int_is(consul_add_ttl_check(&mut reg, "ct", "s", "t", 0, ""), "consul: ttl must be >= 1") { ok = false; }
  return assert(ok, "ttl checks: status transitions, heartbeat, manual override");
}

fn t13() -> TestResult {
  var ok = true;
  var reg = consul_services_new();
  consul_register_service(&mut reg, "s", "svc", "", 1, "");
  if !err_int_is(consul_add_http_check(&mut reg, "h1", "s", "h", "ftp://x", 5, 1, ""), "consul: invalid http check url") { ok = false; }
  if !err_int_is(consul_add_http_check(&mut reg, "h2", "s", "h", "http://x", 0, 1, ""), "consul: interval must be >= 1") { ok = false; }
  if !err_int_is(consul_add_http_check(&mut reg, "h3", "s", "h", "http://x", 5, 0, ""), "consul: timeout must be >= 1") { ok = false; }
  if !err_int_is(consul_add_http_check(&mut reg, "h4", "s", "h", "http://x", 5, 6, ""), "consul: timeout must not exceed interval") { ok = false; }
  if !err_int_is(consul_add_tcp_check(&mut reg, "t1", "s", "t", "", 80, 5, 1, ""), "consul: tcp host must not be empty") { ok = false; }
  if !err_int_is(consul_add_tcp_check(&mut reg, "t2", "s", "t", "h", 0, 5, 1, ""), "consul: tcp port out of range") { ok = false; }
  if !err_int_is(consul_add_tcp_check(&mut reg, "t3", "s", "t", "h", 70000, 5, 1, ""), "consul: tcp port out of range") { ok = false; }
  if !err_int_is(consul_add_ttl_check(&mut reg, "x", "nope", "x", 5, ""), "consul: unknown service for check") { ok = false; }
  if consul_check_count(&reg) != 0 { ok = false; }
  let h = consul_add_http_check(&mut reg, "h", "s", "http", "https://x/health", 10, 3, "n");
  if !h.is_ok { ok = false; } else {
    let i: Int = h.value;
    if i != 0 { ok = false; }
  }
  if consul_check_kind_at(&reg, 0) != CONSUL_CHECK_HTTP { ok = false; }
  if !str_eq(consul_check_url_at(&reg, 0), "https://x/health") { ok = false; }
  if consul_check_interval_at(&reg, 0) != 10 { ok = false; }
  if consul_check_timeout_at(&reg, 0) != 3 { ok = false; }
  let t = consul_add_tcp_check(&mut reg, "t", "s", "tcp", "db.local", 5432, 10, 2, "");
  if !t.is_ok { ok = false; } else {
    let i: Int = t.value;
    if i != 1 { ok = false; }
  }
  if consul_check_kind_at(&reg, 1) != CONSUL_CHECK_TCP { ok = false; }
  if !str_eq(consul_check_host_at(&reg, 1), "db.local") { ok = false; }
  if consul_check_port_at(&reg, 1) != 5432 { ok = false; }
  return assert(ok, "http/tcp check configuration shapes");
}

fn t14() -> TestResult {
  var ok = true;
  var reg = consul_services_new();
  consul_register_service(&mut reg, "s", "svc", "", 1, "");
  consul_add_ttl_check(&mut reg, "c", "s", "ttl", 4, "");
  consul_add_http_check(&mut reg, "h", "s", "http", "http://x", 5, 1, "");
  if consul_check_advance(&mut reg, 1) != 0 { ok = false; }
  if consul_check_remaining_at(&reg, 0) != 3 { ok = false; }
  if consul_check_advance(&mut reg, 3) != 1 { ok = false; }
  if consul_check_remaining_at(&reg, 0) != 0 { ok = false; }
  if consul_check_status_at(&reg, 0) != CONSUL_STATUS_CRITICAL { ok = false; }
  // Already critical: no repeat count.
  if consul_check_advance(&mut reg, 5) != 0 { ok = false; }
  // HTTP checks are not aged.
  if consul_check_remaining_at(&reg, 1) != 0 { ok = false; }
  if consul_check_advance(&mut reg, 100) != 0 { ok = false; }
  let hb = consul_check_heartbeat(&mut reg, "c");
  if ok_int(hb) != 4 { ok = false; }
  if consul_check_advance(&mut reg, 2) != 0 { ok = false; }
  if consul_check_remaining_at(&reg, 0) != 2 { ok = false; }
  if consul_check_advance(&mut reg, 2) != 1 { ok = false; }
  if consul_check_advance(&mut reg, 0) != 0 { ok = false; }
  return assert(ok, "ttl check expiry: one critical transition per reset");
}

fn t15() -> TestResult {
  var ok = true;
  var reg = consul_services_new();
  consul_register_service(&mut reg, "s1", "svc", "", 1, "");
  consul_register_service(&mut reg, "s2", "svc", "", 2, "");
  if consul_service_health(&reg, "s1") != CONSUL_STATUS_PASSING { ok = false; }
  consul_add_ttl_check(&mut reg, "w", "s1", "w", 5, "");
  consul_add_ttl_check(&mut reg, "c", "s1", "c", 5, "");
  consul_add_ttl_check(&mut reg, "n", "", "node", 5, "");
  consul_check_set_status(&mut reg, "w", CONSUL_STATUS_WARNING);
  consul_check_set_status(&mut reg, "c", CONSUL_STATUS_CRITICAL);
  consul_check_set_status(&mut reg, "n", CONSUL_STATUS_WARNING);
  if consul_service_health(&reg, "s1") != CONSUL_STATUS_CRITICAL { ok = false; }
  if consul_service_health(&reg, "s2") != CONSUL_STATUS_PASSING { ok = false; }
  if consul_service_health(&reg, "") != CONSUL_STATUS_WARNING { ok = false; }
  if consul_service_check_count(&reg, "s1") != 2 { ok = false; }
  if consul_service_check_count(&reg, "") != 1 { ok = false; }
  if consul_service_health(&reg, "nope") != CONSUL_NOT_FOUND { ok = false; }
  consul_check_set_status(&mut reg, "c", CONSUL_STATUS_WARNING);
  if consul_service_health(&reg, "s1") != CONSUL_STATUS_WARNING { ok = false; }
  return assert(ok, "aggregate service and node health: worst status wins");
}

fn t16() -> TestResult {
  var ok = true;
  var reg = consul_services_new();
  consul_register_service(&mut reg, "s", "svc", "", 1, "");
  let c1 = consul_add_ttl_check(&mut reg, "c1", "s", "a", 5, "");
  let c2 = consul_add_ttl_check(&mut reg, "c2", "s", "b", 5, "");
  if !c1.is_ok || !c2.is_ok { ok = false; }
  if !err_int_is(consul_add_ttl_check(&mut reg, "c1", "s", "dup", 5, ""), "consul: duplicate check") { ok = false; }
  let d1 = consul_deregister_check(&mut reg, "c1");
  if !d1.is_ok { ok = false; } else {
    let b: Bool = d1.value;
    if !b { ok = false; }
  }
  if consul_check_count(&reg) != 1 { ok = false; }
  if consul_check_find(&reg, "c1") != CONSUL_NOT_FOUND { ok = false; }
  let d2 = consul_deregister_check(&mut reg, "c1");
  if !d2.is_ok { ok = false; } else {
    let b: Bool = d2.value;
    if b { ok = false; }
  }
  let c3 = consul_add_ttl_check(&mut reg, "c3", "s", "c", 5, "");
  if !c3.is_ok { ok = false; }
  let d3 = consul_deregister_service(&mut reg, "s");
  if !d3.is_ok { ok = false; } else {
    let n: Int = d3.value;
    if n != 2 { ok = false; }
  }
  if consul_check_count(&reg) != 0 || consul_service_count(&reg) != 0 { ok = false; }
  if !err_int_is(consul_add_ttl_check(&mut reg, "c9", "", "", 5, ""), "consul: check name must not be empty") { ok = false; }
  if !err_int_is(consul_add_ttl_check(&mut reg, "", "", "n", 5, ""), "consul: check id must not be empty") { ok = false; }
  return assert(ok, "check deregistration, duplicates and cascade removal");
}

// --------------------------------------------------
//  ACL model
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = true;
  var acl = consul_acl_new();
  let text = "# comment\n// another\n\nkey_prefix \"app/\" { policy = \"read\" }\nkey \"app/cfg\" { policy = \"write\" }\nservice_prefix \"\" { policy = \"write\" }\nacl = \"read\"\n";
  let p = consul_acl_add_policy(&mut acl, "p", text);
  if !p.is_ok { ok = false; } else {
    let n: Int = p.value;
    if n != 4 { ok = false; }
  }
  if consul_acl_policy_count(&acl) != 1 { ok = false; }
  if consul_acl_policy_find(&acl, "p") != 0 { ok = false; }
  // Compact form without spaces parses too.
  let p2 = consul_acl_add_policy(&mut acl, "p2", "key \"k\" {policy=\"list\"}");
  if !p2.is_ok { ok = false; } else {
    let n: Int = p2.value;
    if n != 1 { ok = false; }
  }
  if consul_acl_policy_count(&acl) != 2 { ok = false; }
  // Rules are visible through capability resolution.
  let tok = consul_acl_add_token(&mut acl, "t", "", "p", 0);
  if !tok.is_ok { ok = false; }
  let cap1 = consul_acl_capability(&acl, "t", "key", "app/cfg");
  if ok_int(cap1) != CONSUL_ACL_WRITE { ok = false; }
  let cap2 = consul_acl_capability(&acl, "t", "key", "app/other");
  if ok_int(cap2) != CONSUL_ACL_READ { ok = false; }
  let cap3 = consul_acl_capability(&acl, "t", "key", "app/cfg/deep");
  if ok_int(cap3) != CONSUL_ACL_READ { ok = false; }
  let pr = consul_policy_parse("q", "key_prefix \"x\" { policy = \"deny\" }");
  if !pr.is_ok { ok = false; } else {
    let rules: ConsulPolicyRules = pr.value;
    if rules.resource_codes.len() != 1 { ok = false; }
    if rules.scopes[0] != 1 { ok = false; }
    if rules.actions[0] != CONSUL_ACL_DENY { ok = false; }
    if !str_eq(rules.paths[0], "x") { ok = false; }
  }
  return assert(ok, "acl rule parsing: comments, blanks, compact form");
}

fn t18() -> TestResult {
  var ok = true;
  if !err_rules_is(consul_policy_parse("p", "key \"k\" { policy = \"read\""), "consul: malformed acl rule at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "foo \"k\" { policy = \"read\" }"), "consul: unknown acl resource at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "acl_prefix \"\" { policy = \"read\" }"), "consul: unknown acl resource at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "key \"k\" { policy = \"root\" }"), "consul: unknown acl policy at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "key_prefix \"a\" { policy = \"read\""), "consul: malformed acl rule at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "key_prefix a { policy = \"read\" }"), "consul: malformed acl rule at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "key \"a\" { polic = \"read\" }"), "consul: malformed acl rule at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "key \"a\" { policy = \"read\" } extra"), "consul: malformed acl rule at line 1") { ok = false; }
  if !err_rules_is(consul_policy_parse("p", "key \"a\" { policy = \"read\" }\nfoo"), "consul: unknown acl resource at line 2") { ok = false; }
  if !err_rules_is(consul_policy_parse("", "key_prefix \"\" { policy = \"read\" }"), "consul: empty policy name") { ok = false; }
  return assert(ok, "acl rule errors: malformed, unknown resource/action, line numbers");
}

fn t19() -> TestResult {
  var ok = true;
  var acl = consul_acl_new();
  let text = "key_prefix \"app/\" { policy = \"read\" }\nkey \"app/cfg\" { policy = \"write\" }\nkey_prefix \"app/cfg/\" { policy = \"deny\" }\nkey_prefix \"\" { policy = \"list\" }\n";
  let p = consul_acl_add_policy(&mut acl, "p", text);
  if !p.is_ok { ok = false; }
  consul_acl_add_token(&mut acl, "t", "", "p", 0);
  // Longest prefix beats shorter ones.
  if ok_int(consul_acl_capability(&acl, "t", "key", "app/x")) != CONSUL_ACL_READ { ok = false; }
  // Exact beats every prefix.
  if ok_int(consul_acl_capability(&acl, "t", "key", "app/cfg")) != CONSUL_ACL_WRITE { ok = false; }
  // A deny rule wins over matching grants.
  if ok_int(consul_acl_capability(&acl, "t", "key", "app/cfg/x")) != CONSUL_ACL_DENY { ok = false; }
  // Empty prefix matches everything; list is its own capability.
  if ok_int(consul_acl_capability(&acl, "t", "key", "other")) != CONSUL_ACL_LIST { ok = false; }
  if ok_int(consul_acl_capability(&acl, "t", "service", "x")) != CONSUL_ACL_NONE { ok = false; }
  // Same-length prefixes: the later rule wins.
  var acl2 = consul_acl_new();
  let p2 = consul_acl_add_policy(&mut acl2, "p", "key_prefix \"ab/\" { policy = \"read\" }\nkey_prefix \"ab/\" { policy = \"write\" }\n");
  if !p2.is_ok { ok = false; }
  consul_acl_add_token(&mut acl2, "t", "", "p", 0);
  if ok_int(consul_acl_capability(&acl2, "t", "key", "ab/x")) != CONSUL_ACL_WRITE { ok = false; }
  return assert(ok, "acl precedence: exact > longest prefix > later rule; deny wins");
}

fn t20() -> TestResult {
  var ok = true;
  var acl = consul_acl_new();
  consul_acl_add_policy(&mut acl, "allow", "key_prefix \"\" { policy = \"write\" }");
  consul_acl_add_policy(&mut acl, "secret", "key \"secret\" { policy = \"deny\" }");
  let t = consul_acl_add_token(&mut acl, "tok", "both", "allow,secret", 0);
  if !t.is_ok { ok = false; }
  let w1 = consul_acl_allows(&acl, "tok", "key", "secret", CONSUL_ACL_WRITE);
  if !w1.is_ok { ok = false; } else {
    let b: Bool = w1.value;
    if b { ok = false; }
  }
  let r1 = consul_acl_allows(&acl, "tok", "key", "secret", CONSUL_ACL_READ);
  if !r1.is_ok { ok = false; } else {
    let b: Bool = r1.value;
    if b { ok = false; }
  }
  let w2 = consul_acl_allows(&acl, "tok", "key", "other", CONSUL_ACL_WRITE);
  if !w2.is_ok { ok = false; } else {
    let b: Bool = w2.value;
    if !b { ok = false; }
  }
  // A single-deny token: the deny policy alone resolves that path.
  var acl2 = consul_acl_new();
  consul_acl_add_policy(&mut acl2, "d", "key \"x\" { policy = \"deny\" }\nkey_prefix \"\" { policy = \"read\" }");
  consul_acl_add_token(&mut acl2, "t", "", "d", 0);
  let rd = consul_acl_allows(&acl2, "t", "key", "x", CONSUL_ACL_READ);
  if !rd.is_ok { ok = false; } else {
    let b: Bool = rd.value;
    if b { ok = false; }
  }
  let ro = consul_acl_allows(&acl2, "t", "key", "y", CONSUL_ACL_READ);
  if !ro.is_ok { ok = false; } else {
    let b: Bool = ro.value;
    if !b { ok = false; }
  }
  return assert(ok, "acl deny precedence across policies");
}

fn t21() -> TestResult {
  var ok = true;
  var acl = consul_acl_new();
  consul_acl_add_policy(&mut acl, "rw", "key_prefix \"app/\" { policy = \"write\" }\nkey_prefix \"logs/\" { policy = \"read\" }\nkey_prefix \"lst/\" { policy = \"list\" }");
  consul_acl_add_token(&mut acl, "t", "client", "rw", 0);
  if ok_int(consul_acl_capability(&acl, "t", "key", "app/x")) != CONSUL_ACL_WRITE { ok = false; }
  if ok_int(consul_acl_capability(&acl, "t", "key", "logs/x")) != CONSUL_ACL_READ { ok = false; }
  if ok_int(consul_acl_capability(&acl, "t", "key", "lst/x")) != CONSUL_ACL_LIST { ok = false; }
  if ok_int(consul_acl_capability(&acl, "t", "key", "nope")) != CONSUL_ACL_NONE { ok = false; }
  let a1 = consul_acl_allows(&acl, "t", "key", "app/x", CONSUL_ACL_READ);
  if !a1.is_ok { ok = false; } else {
    let b: Bool = a1.value;
    if !b { ok = false; }
  }
  let a2 = consul_acl_allows(&acl, "t", "key", "app/x", CONSUL_ACL_LIST);
  if !a2.is_ok { ok = false; } else {
    let b: Bool = a2.value;
    if b { ok = false; }
  }
  let a3 = consul_acl_allows(&acl, "t", "key", "logs/x", CONSUL_ACL_WRITE);
  if !a3.is_ok { ok = false; } else {
    let b: Bool = a3.value;
    if b { ok = false; }
  }
  let a4 = consul_acl_allows(&acl, "t", "key", "logs/x", CONSUL_ACL_READ);
  if !a4.is_ok { ok = false; } else {
    let b: Bool = a4.value;
    if !b { ok = false; }
  }
  let a5 = consul_acl_allows(&acl, "t", "key", "lst/x", CONSUL_ACL_LIST);
  if !a5.is_ok { ok = false; } else {
    let b: Bool = a5.value;
    if !b { ok = false; }
  }
  let a6 = consul_acl_allows(&acl, "t", "key", "lst/x", CONSUL_ACL_READ);
  if !a6.is_ok { ok = false; } else {
    let b: Bool = a6.value;
    if b { ok = false; }
  }
  let a7 = consul_acl_allows(&acl, "t", "key", "nope", CONSUL_ACL_READ);
  if !a7.is_ok { ok = false; } else {
    let b: Bool = a7.value;
    if b { ok = false; }
  }
  return assert(ok, "acl capabilities: read/write/list resolution and write-implies-read");
}

fn t22() -> TestResult {
  var ok = true;
  var acl = consul_acl_new();
  consul_acl_add_policy(&mut acl, "p", "key_prefix \"\" { policy = \"read\" }");
  consul_acl_add_token(&mut acl, "client", "", "p", 0);
  consul_acl_add_token(&mut acl, "root", "management", "", 1);
  if ok_int(consul_acl_capability(&acl, "root", "key", "anything")) != CONSUL_ACL_WRITE { ok = false; }
  let m = consul_acl_allows(&acl, "root", "key", "anything", CONSUL_ACL_WRITE);
  if !m.is_ok { ok = false; } else {
    let b: Bool = m.value;
    if !b { ok = false; }
  }
  let inv = consul_acl_allows(&acl, "client", "key", "x", 9);
  if !err_bool_is(inv, "consul: invalid acl action") { ok = false; }
  let urn = consul_acl_capability(&acl, "client", "widget", "x");
  if !err_int_is(urn, "consul: unknown acl resource") { ok = false; }
  let unknown = consul_acl_allows(&acl, "ghost", "key", "x", CONSUL_ACL_READ);
  if !err_bool_is(unknown, "consul: token not found") { ok = false; }
  let unknown2 = consul_acl_capability(&acl, "ghost", "key", "x");
  if !err_int_is(unknown2, "consul: token not found") { ok = false; }
  if consul_acl_token_valid(&acl, 0) != 1 { ok = false; }
  if consul_acl_token_management(&acl, 1) != 1 { ok = false; }
  if !str_eq(consul_acl_token_description(&acl, 1), "management") { ok = false; }
  if !str_eq(consul_acl_token_policies(&acl, 0), "p") { ok = false; }
  return assert(ok, "acl tokens: management bypass, invalid action, unknown token");
}

fn t23() -> TestResult {
  var ok = true;
  var acl = consul_acl_new();
  if consul_acl_policy_count(&acl) != 0 || consul_acl_token_count(&acl) != 0 { ok = false; }
  consul_acl_add_policy(&mut acl, "p", "key_prefix \"\" { policy = \"read\" }");
  if !err_int_is(consul_acl_add_policy(&mut acl, "p", "key \"x\" { policy = \"write\" }"), "consul: duplicate policy") { ok = false; }
  if consul_acl_policy_count(&acl) != 1 { ok = false; }
  if !err_int_is(consul_acl_add_token(&mut acl, "", "", "", 0), "consul: token id must not be empty") { ok = false; }
  if !err_int_is(consul_acl_add_token(&mut acl, "t", "", "nope", 0), "consul: unknown policy in token: nope") { ok = false; }
  if !err_int_is(consul_acl_add_token(&mut acl, "t", "", "p,,p2", 0), "consul: empty policy in token list") { ok = false; }
  if !err_int_is(consul_acl_add_token(&mut acl, "t", "", "p", 2), "consul: invalid token management flag") { ok = false; }
  let t = consul_acl_add_token(&mut acl, "t", "client", "p", 0);
  if !t.is_ok { ok = false; }
  if !err_int_is(consul_acl_add_token(&mut acl, "t", "", "p", 0), "consul: duplicate token") { ok = false; }
  if consul_acl_token_count(&acl) != 1 { ok = false; }
  if consul_acl_token_find(&acl, "t") != 0 { ok = false; }
  if consul_acl_token_management(&acl, 99) != CONSUL_NOT_FOUND { ok = false; }
  if !str_eq(consul_acl_token_description(&acl, 99), "") { ok = false; }
  let good = consul_policy_parse("x", "key \"k\" { policy = \"read\" }");
  if !good.is_ok { ok = false; } else {
    let rules: ConsulPolicyRules = good.value;
    if rules.resource_codes.len() != 1 { ok = false; }
  }
  return assert(ok, "acl store: duplicates, unknown policies, sentinels");
}

fn t24() -> TestResult {
  var ok = true;
  if CONSUL_CAS_NONE != -1 || CONSUL_CAS_CREATE != 0 { ok = false; }
  if CONSUL_STATUS_PASSING != 0 || CONSUL_STATUS_WARNING != 1 || CONSUL_STATUS_CRITICAL != 2 { ok = false; }
  if CONSUL_CHECK_TTL != 0 || CONSUL_CHECK_HTTP != 1 || CONSUL_CHECK_TCP != 2 { ok = false; }
  if CONSUL_BEHAVIOR_RELEASE != 0 || CONSUL_BEHAVIOR_DELETE != 1 { ok = false; }
  if CONSUL_ACL_NONE != 0 || CONSUL_ACL_READ != 1 || CONSUL_ACL_WRITE != 2 { ok = false; }
  if CONSUL_ACL_LIST != 3 || CONSUL_ACL_DENY != 4 { ok = false; }
  if CONSUL_RES_KEY != 0 || CONSUL_RES_NODE != 1 || CONSUL_RES_SERVICE != 2 { ok = false; }
  if CONSUL_RES_SESSION != 3 || CONSUL_RES_ACL != 4 || CONSUL_RES_EVENT != 5 || CONSUL_RES_QUERY != 6 { ok = false; }
  if !str_eq(consul_status_name(2), "critical") { ok = false; }
  if !str_eq(consul_status_name(9), "unknown") { ok = false; }
  if !str_eq(consul_check_kind_name(0), "ttl") { ok = false; }
  if !str_eq(consul_check_kind_name(9), "unknown") { ok = false; }
  if !str_eq(consul_session_behavior_name(1), "delete") { ok = false; }
  if !str_eq(consul_session_behavior_name(9), "unknown") { ok = false; }
  if !str_eq(consul_acl_action_name(3), "list") { ok = false; }
  if !str_eq(consul_acl_action_name(9), "unknown") { ok = false; }
  if !str_eq(consul_resource_name(4), "acl") { ok = false; }
  if !str_eq(consul_resource_name(9), "unknown") { ok = false; }
  if consul_resource_code("service") != CONSUL_RES_SERVICE { ok = false; }
  if consul_resource_code("widget") != CONSUL_NOT_FOUND { ok = false; }
  // Fresh stores and accessor sentinels.
  let kv = consul_kv_new();
  if consul_kv_entry_count(&kv) != 0 || consul_kv_index(&kv) != 0 { ok = false; }
  let reg = consul_services_new();
  if consul_service_id_at(&reg, 0) != "" { ok = false; }
  if consul_service_port_at(&reg, 0) != CONSUL_NOT_FOUND { ok = false; }
  if consul_check_id_at(&reg, 0) != "" { ok = false; }
  if consul_check_status_at(&reg, 0) != CONSUL_NOT_FOUND { ok = false; }
  if consul_check_ttl_at(&reg, 0) != CONSUL_NOT_FOUND { ok = false; }
  if !str_eq(consul_check_url_at(&reg, 0), "") { ok = false; }
  return assert(ok, "constants, name tables and fresh-store sentinels");
}

fn main() -> Int {
  io.println("=== xiom.consul conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.consul: all tests passed");
  } else {
    io.println("xiom.consul: tests failed");
  }
  return failed;
}
