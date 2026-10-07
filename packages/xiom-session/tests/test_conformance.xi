// XIOM -- xiom.session conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 6. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through compare.str_compare via the local streq
// helper (`==` on Str values is never used). Every Vec element read is bound
// to a typed local first. Session ids are drawn from the OS CSPRNG, so checks
// never assume a specific id value -- only its shape, uniqueness and that the
// store resolves it.
//
// Read-only wrappers take `&mut` so a shared read never precedes a `&mut`
// call on the same local in one function body (advisory E001; same pattern as
// the xiom.rate suite).

module session_tests
use xiom.io; use xiom.test; use xiom.session;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Read-only wrappers (see the header note)
// --------------------------------------------------

fn cnt(s: &mut SessionStore) -> Int {
  return session_count(s);
}

fn ttl_of(s: &mut SessionStore) -> Int {
  return session_store_ttl_ms(s);
}

fn get_s(s: &mut SessionStore, id: Str, now_ms: Int) -> Option[Session] {
  return session_get(s, id, now_ms);
}

fn val_s(s: &mut SessionStore, id: Str, key: Str, now_ms: Int) -> Option[Str] {
  return session_value(s, id, key, now_ms);
}

// --------------------------------------------------
//  Result / Option helpers
// --------------------------------------------------

// Ok id of a create/rotate result, or "" on Err.
fn res_id(r: Result[Str, Str]) -> Str {
  if !r.is_ok {
    return "";
  }
  let v: Str = r.value;
  return v;
}

// True when r is Err with exactly the message `want`.
fn res_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  if !o.is_some {
    return false;
  }
  let v: Str = o.value;
  return streq(v, want);
}

fn opt_str_none(o: Option[Str]) -> Bool {
  return !o.is_some;
}

fn opt_sess_some(o: Option[Session]) -> Bool {
  return o.is_some;
}

fn opt_sess_none(o: Option[Session]) -> Bool {
  return !o.is_some;
}

fn opt_sess_id_is(o: Option[Session], want_id: Str) -> Bool {
  if !o.is_some {
    return false;
  }
  let v: Session = o.value;
  return streq(v.id, want_id);
}

fn opt_sess_times_are(o: Option[Session], want_created: Int, want_expires: Int) -> Bool {
  if !o.is_some {
    return false;
  }
  let v: Session = o.value;
  if v.created_ms != want_created {
    return false;
  }
  if v.expires_ms != want_expires {
    return false;
  }
  return true;
}

fn opt_sess_entry_count(o: Option[Session]) -> Int {
  if !o.is_some {
    return -1;
  }
  let v: Session = o.value;
  return v.entries.len();
}

fn opt_sess_entry_is(o: Option[Session], key: Str, want: Str) -> Bool {
  if !o.is_some {
    return false;
  }
  let v: Session = o.value;
  var i = 0;
  while i < v.entries.len() {
    let e: SessionEntry = v.entries[i];
    if streq(e.key, key) {
      return streq(e.value, want);
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = session_id_valid("0123456789abcdef0123456789abcdef");
  if !session_id_valid("00000000000000000000000000000000") { ok = false; }
  if session_id_valid("") { ok = false; }
  if session_id_valid("0123456789abcdef0123456789abcde") { ok = false; }
  if session_id_valid("0123456789abcdef0123456789abcdef0") { ok = false; }
  if session_id_valid("0123456789abcdef0123456789ABCDEF") { ok = false; }
  if session_id_valid("0123456789abcdef0123456789abcdeg") { ok = false; }
  if session_id_valid("g123456789abcdef0123456789abcdef") { ok = false; }
  return assert(ok, "session_id_valid: exactly 32 lowercase hex characters");
}

fn t2() -> TestResult {
  var s = session_store_new(1500);
  var ok = ttl_of(&mut s) == 1500;
  if cnt(&mut s) != 0 { ok = false; }
  var z = session_store_new(0);
  if ttl_of(&mut z) != 1 { ok = false; }
  var n = session_store_new(-50);
  if ttl_of(&mut n) != 1 { ok = false; }
  return assert(ok, "session_store_new: ttl <= 0 clamps to 1; accessors start empty");
}

fn t3() -> TestResult {
  var s = session_store_new(1000);
  let id1 = res_id(session_create(&mut s, 5000));
  let id2 = res_id(session_create(&mut s, 5000));
  var ok = session_id_valid(id1);
  if !session_id_valid(id2) { ok = false; }
  if streq(id1, id2) { ok = false; }
  if cnt(&mut s) != 2 { ok = false; }
  if !opt_sess_id_is(get_s(&mut s, id1, 5000), id1) { ok = false; }
  if !opt_sess_id_is(get_s(&mut s, id2, 5000), id2) { ok = false; }
  return assert(ok, "session_create: valid unique ids; both retrievable");
}

fn t4() -> TestResult {
  var s = session_store_new(1000);
  let id = res_id(session_create(&mut s, 1000));
  let ok = opt_sess_id_is(get_s(&mut s, id, 1000), id);
  var all = ok;
  if !opt_sess_times_are(get_s(&mut s, id, 1000), 1000, 2000) { all = false; }
  if opt_sess_entry_count(get_s(&mut s, id, 1000)) != 0 { all = false; }
  if !opt_sess_none(get_s(&mut s, "00000000000000000000000000000000", 1000)) { all = false; }
  if !opt_sess_none(get_s(&mut s, "not-an-id", 1000)) { all = false; }
  return assert(all, "session_get: round-trip fields; None for unknown ids");
}

fn t5() -> TestResult {
  var s = session_store_new(1000);
  let id = res_id(session_create(&mut s, 0));
  var ok = opt_sess_some(get_s(&mut s, id, 999));
  if !opt_sess_none(get_s(&mut s, id, 1000)) { ok = false; }
  if !opt_sess_none(get_s(&mut s, id, 1001)) { ok = false; }
  return assert(ok, "expiry boundary: valid at now < expires_ms; expired at now == expires_ms");
}

fn t6() -> TestResult {
  var s = session_store_new(1000);
  let id = res_id(session_create(&mut s, 0));
  var ok = session_set(&mut s, id, "user", "alice", 1);
  if !session_set(&mut s, id, "theme", "dark", 2) { ok = false; }
  if !opt_str_is(val_s(&mut s, id, "user", 3), "alice") { ok = false; }
  if !opt_str_is(val_s(&mut s, id, "theme", 3), "dark") { ok = false; }
  if opt_sess_entry_count(get_s(&mut s, id, 3)) != 2 { ok = false; }
  if !session_set(&mut s, id, "user", "bob", 4) { ok = false; }
  if !opt_str_is(val_s(&mut s, id, "user", 4), "bob") { ok = false; }
  if opt_sess_entry_count(get_s(&mut s, id, 4)) != 2 { ok = false; }
  return assert(ok, "session_set/session_value: insert, overwrite, read latest");
}

fn t7() -> TestResult {
  var s = session_store_new(1000);
  let id = res_id(session_create(&mut s, 0));
  var ok = opt_str_none(val_s(&mut s, id, "missing", 1));
  if !opt_str_none(val_s(&mut s, "00000000000000000000000000000000", "k", 1)) { ok = false; }
  if session_set(&mut s, "00000000000000000000000000000000", "k", "v", 1) { ok = false; }
  if session_set(&mut s, id, "late", "v", 1000) { ok = false; }
  if !opt_str_none(val_s(&mut s, id, "late", 999)) { ok = false; }
  if !opt_str_none(val_s(&mut s, id, "late", 1000)) { ok = false; }
  return assert(ok, "session_set/session_value: false/None on missing key, absent id, expired");
}

fn t8() -> TestResult {
  var s = session_store_new(100);
  let id = res_id(session_create(&mut s, 0));
  var ok = session_set(&mut s, id, "a", "1", 50);
  if !opt_sess_times_are(get_s(&mut s, id, 50), 0, 100) { ok = false; }
  if !opt_str_is(val_s(&mut s, id, "a", 99), "1") { ok = false; }
  if !opt_sess_none(get_s(&mut s, id, 100)) { ok = false; }
  return assert(ok, "session_set never extends expiry; expires_ms stays created + ttl");
}

fn t9() -> TestResult {
  var s = session_store_new(100);
  let id = res_id(session_create(&mut s, 0));
  var ok = session_touch(&mut s, id, 50);
  if !opt_sess_times_are(get_s(&mut s, id, 50), 0, 150) { ok = false; }
  if !session_touch(&mut s, id, 100) { ok = false; }
  if !opt_sess_times_are(get_s(&mut s, id, 100), 0, 200) { ok = false; }
  if session_touch(&mut s, id, 200) { ok = false; }
  if session_touch(&mut s, "00000000000000000000000000000000", 100) { ok = false; }
  return assert(ok, "session_touch: extends expires_ms = now + ttl; false when expired/absent");
}

fn t10() -> TestResult {
  var s = session_store_new(1000);
  let a = res_id(session_create(&mut s, 0));
  let b = res_id(session_create(&mut s, 0));
  let c = res_id(session_create(&mut s, 0));
  var ok = session_remove(&mut s, b);
  if cnt(&mut s) != 2 { ok = false; }
  if session_remove(&mut s, b) { ok = false; }
  if session_remove(&mut s, "00000000000000000000000000000000") { ok = false; }
  if !opt_sess_none(get_s(&mut s, b, 0)) { ok = false; }
  if !opt_sess_some(get_s(&mut s, a, 0)) { ok = false; }
  if !opt_sess_some(get_s(&mut s, c, 0)) { ok = false; }
  return assert(ok, "session_remove: true once; false for repeat and unknown");
}

fn t11() -> TestResult {
  var s = session_store_new(100);
  let id = res_id(session_create(&mut s, 0));
  var ok = cnt(&mut s) == 1;
  if !opt_sess_none(get_s(&mut s, id, 100)) { ok = false; }
  if cnt(&mut s) != 1 { ok = false; }
  if !session_remove(&mut s, id) { ok = false; }
  if cnt(&mut s) != 0 { ok = false; }
  return assert(ok, "session_remove ignores expiry; session_count counts stored entries");
}

fn t12() -> TestResult {
  var s = session_store_new(1000);
  let old = res_id(session_create(&mut s, 100));
  session_set(&mut s, old, "user", "alice", 100);
  session_set(&mut s, old, "theme", "dark", 100);
  let fresh = res_id(session_rotate(&mut s, old, 500));
  var ok = session_id_valid(fresh);
  if streq(fresh, old) { ok = false; }
  if !opt_sess_none(get_s(&mut s, old, 500)) { ok = false; }
  if cnt(&mut s) != 1 { ok = false; }
  if !opt_sess_times_are(get_s(&mut s, fresh, 500), 500, 1500) { ok = false; }
  if !opt_sess_entry_is(get_s(&mut s, fresh, 500), "user", "alice") { ok = false; }
  if !opt_sess_entry_is(get_s(&mut s, fresh, 500), "theme", "dark") { ok = false; }
  if opt_sess_entry_count(get_s(&mut s, fresh, 500)) != 2 { ok = false; }
  return assert(ok, "session_rotate: new id, entries copied, expiry reset, old invalidated");
}

fn t13() -> TestResult {
  var s = session_store_new(100);
  var ok = res_err_is(session_rotate(&mut s, "00000000000000000000000000000000", 0), "session: not found or expired");
  let id = res_id(session_create(&mut s, 0));
  if !res_err_is(session_rotate(&mut s, id, 100), "session: not found or expired") { ok = false; }
  if cnt(&mut s) != 1 { ok = false; }
  return assert(ok, "session_rotate: Err for absent and expired; store unchanged");
}

fn t14() -> TestResult {
  var s = session_store_new(100);
  let a = res_id(session_create(&mut s, 0));
  let b = res_id(session_create(&mut s, 50));
  var ok = session_prune(&mut s, 99) == 0;
  if cnt(&mut s) != 2 { ok = false; }
  if session_prune(&mut s, 100) != 1 { ok = false; }
  if cnt(&mut s) != 1 { ok = false; }
  if !opt_sess_some(get_s(&mut s, b, 100)) { ok = false; }
  if !opt_sess_none(get_s(&mut s, a, 100)) { ok = false; }
  if session_prune(&mut s, 150) != 1 { ok = false; }
  if cnt(&mut s) != 0 { ok = false; }
  return assert(ok, "session_prune: 0 before expiry, removes at the now == expires boundary");
}

fn t15() -> TestResult {
  let h = session_cookie_header("sid", "abc", 3600, false);
  var ok = streq(h, "sid=abc; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600");
  return assert(ok, "cookie header: exact insecure form");
}

fn t16() -> TestResult {
  let h = session_cookie_header("sid", "abc", 3600, true);
  var ok = streq(h, "sid=abc; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600; Secure");
  return assert(ok, "cookie header: Secure appended last");
}

fn t17() -> TestResult {
  var ok = streq(session_cookie_header("s", "i", 0, false), "s=i; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
  if !streq(session_cookie_header("s", "i", -5, false), "s=i; Path=/; HttpOnly; SameSite=Lax; Max-Age=0") { ok = false; }
  if !streq(session_cookie_header("s", "i", 1000000, false), "s=i; Path=/; HttpOnly; SameSite=Lax; Max-Age=1000000") { ok = false; }
  return assert(ok, "cookie header: Max-Age <= 0 clamps to 0; decimal render");
}

fn t18() -> TestResult {
  let h = session_cookie_clear("sid");
  var ok = streq(h, "sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
  return assert(ok, "cookie clear: exact deletion header");
}

fn t19() -> TestResult {
  var s = session_store_new(1000);
  var ok = true;
  var ids = Vec[Str].new();
  var i = 0;
  while i < 64 {
    let id = res_id(session_create(&mut s, i * 10));
    if !session_id_valid(id) { ok = false; }
    ids.push(id);
    i = i + 1;
  }
  if cnt(&mut s) != 64 { ok = false; }
  i = 0;
  while i < 64 {
    let id: Str = ids[i];
    if !opt_sess_id_is(get_s(&mut s, id, i * 10), id) { ok = false; }
    if !opt_sess_times_are(get_s(&mut s, id, i * 10), i * 10, i * 10 + 1000) { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < 64 {
    var j = i + 1;
    while j < 64 {
      let a: Str = ids[i];
      let b: Str = ids[j];
      if streq(a, b) { ok = false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return assert(ok, "64-session store: create/scan determinism and id uniqueness");
}

fn t20() -> TestResult {
  var s = session_store_new(100);
  var ids = Vec[Str].new();
  var i = 0;
  while i < 64 {
    let id = res_id(session_create(&mut s, i * 10));
    ids.push(id);
    i = i + 1;
  }
  var ok = session_prune(&mut s, 300) == 21;
  if cnt(&mut s) != 43 { ok = false; }
  let live: Str = ids[21];
  if !opt_sess_some(get_s(&mut s, live, 300)) { ok = false; }
  let dead: Str = ids[20];
  if !opt_sess_none(get_s(&mut s, dead, 299)) { ok = false; }
  if session_prune(&mut s, 700) != 40 { ok = false; }
  if cnt(&mut s) != 3 { ok = false; }
  if session_prune(&mut s, 1000) != 3 { ok = false; }
  if cnt(&mut s) != 0 { ok = false; }
  return assert(ok, "64-session store: prune counts and boundary survivors");
}

fn t21() -> TestResult {
  let h = session_cookie_header("sid", "", 60, true);
  var ok = streq(h, "sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=60; Secure");
  return assert(ok, "cookie header: raw name/id, no validation");
}

fn t22() -> TestResult {
  var s = session_store_new(1000);
  let a = res_id(session_create(&mut s, 0));
  let b = res_id(session_create(&mut s, 0));
  session_set(&mut s, a, "k", "a-value", 0);
  session_set(&mut s, b, "k", "b-value", 0);
  let r = res_id(session_rotate(&mut s, a, 500));
  var ok = !streq(r, a);
  if !opt_str_is(val_s(&mut s, b, "k", 500), "b-value") { ok = false; }
  if !opt_str_is(val_s(&mut s, r, "k", 500), "a-value") { ok = false; }
  if !session_touch(&mut s, r, 900) { ok = false; }
  if !opt_sess_times_are(get_s(&mut s, r, 900), 500, 1900) { ok = false; }
  if cnt(&mut s) != 2 { ok = false; }
  if !opt_str_is(val_s(&mut s, r, "k", 1000), "a-value") { ok = false; }
  return assert(ok, "composite: rotate/touch/values across two sessions");
}

fn t23() -> TestResult {
  var s = session_store_new(1000);
  var ok = session_prune(&mut s, 9999) == 0;
  if cnt(&mut s) != 0 { ok = false; }
  if !opt_sess_none(get_s(&mut s, "00000000000000000000000000000000", 0)) { ok = false; }
  if session_touch(&mut s, "00000000000000000000000000000000", 0) { ok = false; }
  if session_remove(&mut s, "00000000000000000000000000000000") { ok = false; }
  return assert(ok, "empty store: prune/get/touch/remove are safe no-ops");
}

fn t24() -> TestResult {
  var s = session_store_new(1000);
  let id = res_id(session_create(&mut s, 0));
  var ok = session_set(&mut s, id, "k", "v", 0);
  let snap = get_s(&mut s, id, 10);
  if !session_set(&mut s, id, "k", "w", 11) { ok = false; }
  if !opt_sess_entry_is(snap, "k", "v") { ok = false; }
  if !opt_sess_entry_is(get_s(&mut s, id, 12), "k", "w") { ok = false; }
  return assert(ok, "session_get returns an independent copy of entries");
}

fn main() -> Int {
  io.println("=== xiom.session conformance tests ===");
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
    io.println("xiom.session: all tests passed");
  } else {
    io.println("xiom.session: tests failed");
  }
  return failed;
}
