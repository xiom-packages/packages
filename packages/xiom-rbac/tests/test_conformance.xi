// XIOM -- xiom.rbac conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.rbac module against its documented rule
// model and deny-override evaluation.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 5. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison), and read-only API
// calls are wrapped in `&mut`-taking helpers so a `&local` read call is never
// followed by a `&mut local` call in the same test body (advisory E001).

module rbac_tests
use xiom.io; use xiom.test; use xiom.rbac;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn vec_str_eq(v: &Vec[Str], want: &Vec[Str]) -> Bool {
  if v.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < v.len() {
    let a: Str = v[i];
    let b: Str = want[i];
    if !streq(a, b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn allows_of(p: &mut RolePolicy, role: Str, action: Str, resource: Str) -> Bool {
  return rbac_allows(p, role, action, resource);
}

fn roles_of(p: &mut RolePolicy) -> Vec[Str] {
  return rbac_roles(p);
}

fn rules_of(p: &mut RolePolicy, role: Str) -> Vec[Str] {
  return rbac_role_rules(p, role);
}

fn count_of(p: &mut RolePolicy) -> Int {
  return rbac_rule_count(p);
}

fn actions_of(p: &mut RolePolicy, role: Str, resource: Str) -> Vec[Str] {
  return rbac_allowed_actions(p, role, resource);
}

fn t1() -> TestResult {
  var p = rbac_new();
  var roles = roles_of(&mut p);
  var ok = count_of(&mut p) == 0;
  if roles.len() != 0 { ok = false; }
  if allows_of(&mut p, "admin", "read", "doc") { ok = false; }
  var acts = actions_of(&mut p, "admin", "doc");
  if acts.len() != 0 { ok = false; }
  return assert(ok, "empty policy has no rules and denies every request");
}

fn t2() -> TestResult {
  var ok = rbac_matches("read", "read");
  if rbac_matches("read", "write") { ok = false; }
  if rbac_matches("read", "") { ok = false; }
  if !rbac_matches("", "") { ok = false; }
  if rbac_matches("Read", "read") { ok = false; }
  return assert(ok, "matches: byte-exact equality, case-sensitive");
}

fn t3() -> TestResult {
  var ok = rbac_matches("*", "read");
  if !rbac_matches("*", "") { ok = false; }
  if !rbac_matches("*", "any token") { ok = false; }
  if rbac_matches("re*", "read") { ok = false; }
  if rbac_matches("*read", "read") { ok = false; }
  if rbac_matches("read", "*") { ok = false; }
  return assert(ok, "matches: '*' matches any value, nothing else is a glob");
}

fn t4() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  var ok = allows_of(&mut p, "editor", "read", "doc");
  if allows_of(&mut p, "viewer", "read", "doc") { ok = false; }
  if allows_of(&mut p, "editor", "write", "doc") { ok = false; }
  if allows_of(&mut p, "editor", "read", "other") { ok = false; }
  return assert(ok, "allow rule permits its triple and nothing else");
}

fn t5() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_deny(&mut p, "editor", "read", "doc");
  var ok = !allows_of(&mut p, "editor", "read", "doc");
  return assert(ok, "deny overrides an identical allow");
}

fn t6() -> TestResult {
  var p = rbac_new();
  rbac_deny(&mut p, "editor", "read", "secret");
  rbac_allow(&mut p, "editor", "read", "secret");
  rbac_allow(&mut p, "editor", "read", "doc");
  var ok = !allows_of(&mut p, "editor", "read", "secret");
  if !allows_of(&mut p, "editor", "read", "doc") { ok = false; }
  return assert(ok, "deny wins regardless of position and stays resource-scoped");
}

fn t7() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "admin", "*", "*");
  var ok = allows_of(&mut p, "admin", "read", "doc");
  if !allows_of(&mut p, "admin", "delete", "everything") { ok = false; }
  if allows_of(&mut p, "user", "read", "doc") { ok = false; }
  return assert(ok, "wildcard allow covers every action and resource for one role");
}

fn t8() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "editor", "read", "notes");
  rbac_deny(&mut p, "editor", "*", "doc");
  var ok = !allows_of(&mut p, "editor", "read", "doc");
  if !allows_of(&mut p, "editor", "read", "notes") { ok = false; }
  var acts = actions_of(&mut p, "editor", "notes");
  if acts.len() != 1 { ok = false; }
  return assert(ok, "wildcard deny blocks its resource without touching others");
}

fn t9() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "admin", "read", "doc");
  rbac_allow(&mut p, "reader", "read", "doc");
  rbac_allow(&mut p, "admin", "write", "doc");
  rbac_deny(&mut p, "ops", "deploy", "prod");
  rbac_allow(&mut p, "reader", "read", "notes");
  var want = Vec[Str].new();
  want.push("admin");
  want.push("reader");
  want.push("ops");
  var got = roles_of(&mut p);
  var ok = vec_str_eq(&got, &want);
  return assert(ok, "roles: distinct tokens in first-seen rule order");
}

fn t10() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_deny(&mut p, "editor", "write", "prod");
  rbac_allow(&mut p, "editor", "*", "notes");
  var want = Vec[Str].new();
  want.push("allow:read:doc");
  want.push("deny:write:prod");
  want.push("allow:*:notes");
  var got = rules_of(&mut p, "editor");
  var ok = vec_str_eq(&got, &want);
  return assert(ok, "role_rules lists allow:/deny: text in rule order");
}

fn t11() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "admin", "read", "doc");
  rbac_allow(&mut p, "*", "ping", "health");
  rbac_deny(&mut p, "ops", "deploy", "prod");
  var for_user = rules_of(&mut p, "user");
  var ok = for_user.len() == 1;
  if for_user.len() == 1 {
    if !streq(for_user[0], "allow:ping:health") { ok = false; }
  }
  var for_admin = rules_of(&mut p, "admin");
  if for_admin.len() != 2 { ok = false; }
  var for_star = rules_of(&mut p, "*");
  if for_star.len() != 1 { ok = false; }
  if for_star.len() == 1 {
    if !streq(for_star[0], "allow:ping:health") { ok = false; }
  }
  return assert(ok, "role_rules includes wildcard-role rules for concrete queries");
}

fn t12() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "editor", "write", "doc");
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "editor", "delete", "other");
  rbac_deny(&mut p, "editor", "archive", "doc");
  var want = Vec[Str].new();
  want.push("read");
  want.push("write");
  var got = actions_of(&mut p, "editor", "doc");
  var ok = vec_str_eq(&got, &want);
  return assert(ok, "allowed_actions: distinct allow actions for the resource");
}

fn t13() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "*", "doc");
  rbac_allow(&mut p, "editor", "read", "*");
  var want = Vec[Str].new();
  want.push("*");
  want.push("read");
  var got = actions_of(&mut p, "editor", "doc");
  var ok = vec_str_eq(&got, &want);
  var wild = actions_of(&mut p, "editor", "*");
  if wild.len() != 1 { ok = false; }
  if wild.len() == 1 {
    if !streq(wild[0], "read") { ok = false; }
  }
  return assert(ok, "allowed_actions keeps '*' literal and matches rule-side wildcards");
}

fn t14() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "viewer", "read", "doc");
  rbac_deny(&mut p, "editor", "write", "doc");
  rbac_allow(&mut p, "editor", "read", "notes");
  var removed = rbac_clear_role(&mut p, "editor");
  var ok = removed == 3;
  if count_of(&mut p) != 1 { ok = false; }
  if allows_of(&mut p, "editor", "read", "doc") { ok = false; }
  if !allows_of(&mut p, "viewer", "read", "doc") { ok = false; }
  var want = Vec[Str].new();
  want.push("viewer");
  var roles = roles_of(&mut p);
  if !vec_str_eq(&roles, &want) { ok = false; }
  return assert(ok, "clear_role removes its rules and reports the count");
}

fn t15() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  var first = rbac_clear_role(&mut p, "editor");
  var second = rbac_clear_role(&mut p, "editor");
  var unknown = rbac_clear_role(&mut p, "ghost");
  var ok = first == 1;
  if second != 0 { ok = false; }
  if unknown != 0 { ok = false; }
  if count_of(&mut p) != 0 { ok = false; }
  return assert(ok, "clear_role is idempotent and unknown roles remove nothing");
}

fn t16() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "*", "ping", "health");
  var removed = rbac_clear_role(&mut p, "*");
  var ok = removed == 1;
  if count_of(&mut p) != 1 { ok = false; }
  if !allows_of(&mut p, "editor", "read", "doc") { ok = false; }
  var gone = rules_of(&mut p, "editor");
  if gone.len() != 1 { ok = false; }
  return assert(ok, "clear_role '*' clears only rules recorded under '*'");
}

fn t17() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "editor", "read", "doc");
  var ok = count_of(&mut p) == 3;
  var roles = roles_of(&mut p);
  if roles.len() != 1 { ok = false; }
  var rules = rules_of(&mut p, "editor");
  if rules.len() != 3 { ok = false; }
  var removed = rbac_clear_role(&mut p, "editor");
  if removed != 3 { ok = false; }
  if count_of(&mut p) != 0 { ok = false; }
  return assert(ok, "duplicate rules append, are listed, and clear together");
}

fn t18() -> TestResult {
  var p = rbac_new();
  var i = 0;
  while i < 12 {
    rbac_allow(&mut p, "editor", "read", "doc");
    i = i + 1;
  }
  rbac_allow(&mut p, "viewer", "read", "doc");
  rbac_deny(&mut p, "editor", "read", "classified");
  var ok = count_of(&mut p) == 14;
  if !allows_of(&mut p, "editor", "read", "doc") { ok = false; }
  if allows_of(&mut p, "editor", "read", "classified") { ok = false; }
  if !allows_of(&mut p, "viewer", "read", "doc") { ok = false; }
  var roles = roles_of(&mut p);
  if roles.len() != 2 { ok = false; }
  var cleared = rbac_clear_role(&mut p, "editor");
  if cleared != 13 { ok = false; }
  return assert(ok, "many-rule policy: deny wins and clearing counts every copy");
}

fn t19() -> TestResult {
  var p = rbac_new();
  var i = 0;
  while i < 40 {
    rbac_allow(&mut p, "bulk", "read", "doc");
    i = i + 1;
  }
  var ok = count_of(&mut p) == 40;
  var acts = actions_of(&mut p, "bulk", "doc");
  if acts.len() != 1 { ok = false; }
  var removed = rbac_clear_role(&mut p, "bulk");
  if removed != 40 { ok = false; }
  if count_of(&mut p) != 0 { ok = false; }
  if allows_of(&mut p, "bulk", "read", "doc") { ok = false; }
  return assert(ok, "large policy compacts to empty in one clear");
}

fn t20() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_clear_role(&mut p, "editor");
  var denied_after_clear = !allows_of(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "editor", "read", "doc");
  var ok = denied_after_clear;
  if !allows_of(&mut p, "editor", "read", "doc") { ok = false; }
  if count_of(&mut p) != 1 { ok = false; }
  return assert(ok, "policy stays usable after clear_role");
}

fn t21() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "*", "read", "doc");
  rbac_deny(&mut p, "contractor", "read", "doc");
  var ok = !allows_of(&mut p, "contractor", "read", "doc");
  if !allows_of(&mut p, "employee", "read", "doc") { ok = false; }
  if allows_of(&mut p, "contractor", "write", "doc") { ok = false; }
  return assert(ok, "wildcard allow with a targeted deny isolates role and action");
}

fn t22() -> TestResult {
  var p = rbac_new();
  rbac_allow(&mut p, "a", "read", "x");
  rbac_deny(&mut p, "b", "write", "y");
  var ok = count_of(&mut p) == 2;
  var roles = roles_of(&mut p);
  if roles.len() != 2 { ok = false; }
  var none = rules_of(&mut p, "c");
  if none.len() != 0 { ok = false; }
  var acts = actions_of(&mut p, "c", "x");
  if acts.len() != 0 { ok = false; }
  return assert(ok, "rule_count matches appended rules; unknown queries list nothing");
}

fn main() -> Int {
  io.println("=== xiom.rbac conformance tests ===");
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
    io.println("xiom.rbac: all tests passed");
  } else {
    io.println("xiom.rbac: tests failed");
  }
  return failed;
}
