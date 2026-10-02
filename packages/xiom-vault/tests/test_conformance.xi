// XIOM -- xiom.vault conformance tests (28 checks)
// Port task: prove the pure-XIOM vault model (request/response, JSON lookup,
// KV paths/version state, Shamir/unseal, token/AppRole, policy ACLs) against
// the rules documented in SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 10. Every check is a named
// assert(cond, "name") call, one fn per check, and main returns the failure
// count (0 = green). No external files, no I/O beyond stdout, deterministic.
//
// BUG 17 discipline: all Str equality goes through
// xiom.string.compare.str_compare (never `==`), every Vec[Str] element read
// is bound to a typed local first, and every Vec[UInt8] element read is
// widened with `(x as Int) & 0xFF`.

module vault_tests

use xiom.io;
use xiom.test;
use xiom.vault;
use xiom.vault.core;
use xiom.vault.client;
use xiom.vault.json;
use xiom.vault.kv;
use xiom.vault.unseal;
use xiom.vault.auth;
use xiom.vault.policy;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}


fn iv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn iv2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn iv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn uv1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return v;
}

fn uv2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn strs_of(a: Vec[Str], b: Vec[Str]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Str = a[i];
    let y: Str = b[i];
    if !streq(x, y) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn two_strs(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn kv_err_is(r: Result[VaultKvVersions, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn req_err_is(r: Result[VaultRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn hit_err_is(r: Result[VaultJsonHit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn bytes_eq(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = vault_method_code("GET") == VAULT_METHOD_GET;
  if vault_method_code("post") != VAULT_METHOD_POST { ok = false; }
  if vault_method_code("List") != VAULT_METHOD_LIST { ok = false; }
  if vault_method_code("OPTIONS") != VAULT_METHOD_OPTIONS { ok = false; }
  if vault_method_code("brew") != VAULT_METHOD_UNKNOWN { ok = false; }
  if !streq(vault_method_name(VAULT_METHOD_DELETE), "DELETE") { ok = false; }
  if !streq(vault_method_name(VAULT_METHOD_PATCH), "PATCH") { ok = false; }
  if vault_method_name(0).len() != 0 { ok = false; }
  if vault_method_name(99).len() != 0 { ok = false; }
  return assert(ok, "method table: codes, names, case-insensitive lookup");
}

fn t2() -> TestResult {
  var ok = true;
  let r1 = vault_path_normalize("sys/health");
  if !r1.is_ok { ok = false; } else {
    let p: Str = r1.value;
    if !streq(p, "/sys/health") { ok = false; }
  }
  let r2 = vault_path_normalize("/a//b/");
  if !r2.is_ok { ok = false; } else {
    let p: Str = r2.value;
    if !streq(p, "/a/b") { ok = false; }
  }
  let r3 = vault_path_normalize("/");
  if !r3.is_ok { ok = false; } else {
    let p: Str = r3.value;
    if !streq(p, "/") { ok = false; }
  }
  if !err_is(vault_path_normalize(""), "vault: path is empty") { ok = false; }
  if !err_is(vault_path_normalize("a b"), "vault: path has a control or space byte at offset 1") { ok = false; }
  if !err_is(vault_path_normalize("a\nb"), "vault: path has a control or space byte at offset 1") { ok = false; }
  return assert(ok, "path normalization: leading slash, collapse, trailing strip, errors");
}

fn t3() -> TestResult {
  var ok = true;
  let r = vault_request_new(VAULT_METHOD_GET, "sys/seal-status");
  if !r.is_ok { ok = false; } else {
    let req: VaultRequest = r.value;
    if vault_request_method(&req) != VAULT_METHOD_GET { ok = false; }
    if !streq(vault_request_method_name(&req), "GET") { ok = false; }
    if !streq(vault_request_path(&req), "/sys/seal-status") { ok = false; }
    if !streq(vault_request_target(&req), "/sys/seal-status") { ok = false; }
    if vault_request_header_count(&req) != 0 { ok = false; }
    if vault_request_has_body(&req) { ok = false; }
    if !streq(vault_request_body(&req), "") { ok = false; }
  }
  if !req_err_is(vault_request_new(0, "/x"), "vault: unknown method code") { ok = false; }
  if !req_err_is(vault_request_new(99, "/x"), "vault: method code out of range at offset 99") { ok = false; }
  if !req_err_is(vault_request_new(VAULT_METHOD_GET, ""), "vault: path is empty") { ok = false; }
  return assert(ok, "request construction: method/path accessors and errors");
}

fn t4() -> TestResult {
  var ok = true;
  let r = vault_request_new(VAULT_METHOD_GET, "/secret");
  if !r.is_ok { ok = false; } else {
    var req: VaultRequest = r.value;
    let s1 = vault_request_set_query(&mut req, "?version=2");
    if !s1.is_ok { ok = false; }
    if !streq(vault_request_query(&req), "version=2") { ok = false; }
    if !streq(vault_request_target(&req), "/secret?version=2") { ok = false; }
    let s2 = vault_request_set_query(&mut req, "");
    if !s2.is_ok { ok = false; }
    if !streq(vault_request_target(&req), "/secret") { ok = false; }
    let s3 = vault_request_set_query(&mut req, "a=1&b=2");
    if !s3.is_ok { ok = false; }
    if !streq(vault_request_query(&req), "a=1&b=2") { ok = false; }
    if !int_err_is(vault_request_set_query(&mut req, "a=1&&b=2"), "vault: query has an empty parameter at offset 4") { ok = false; }
    if !int_err_is(vault_request_set_query(&mut req, "a=1&"), "vault: query has an empty parameter at offset 4") { ok = false; }
    if !int_err_is(vault_request_set_query(&mut req, "a#b"), "vault: query contains '?' or '#' at offset 1") { ok = false; }
    if !int_err_is(vault_request_set_query(&mut req, "a b"), "vault: query has a control or space byte at offset 1") { ok = false; }
  }
  return assert(ok, "query: strip '?', clear, canonical target, empty-segment errors");
}

fn t5() -> TestResult {
  var ok = true;
  let r = vault_request_new(VAULT_METHOD_GET, "/sys/mounts");
  if !r.is_ok { ok = false; } else {
    var req: VaultRequest = r.value;
    if vault_request_has_header(&req, "x-vault-token") { ok = false; }
    let h1 = vault_request_set_header(&mut req, "X-Custom", "one");
    if !h1.is_ok { ok = false; }
    let h2 = vault_request_set_header(&mut req, "x-custom", "two");
    if !h2.is_ok { ok = false; }
    if vault_request_header_count(&req) != 1 { ok = false; }
    let g = vault_request_header_get(&req, "X-CUSTOM");
    if !g.is_ok { ok = false; } else {
      let gv: Str = g.value;
      if !streq(gv, "two") { ok = false; }
    }
    if !vault_request_has_header(&req, "X-Custom") { ok = false; }
    if !streq(vault_request_header_name(&req, 0), "X-Custom") { ok = false; }
    if !streq(vault_request_header_value(&req, 0), "two") { ok = false; }
    let tk = vault_request_set_token(&mut req, "s.abc123");
    if !tk.is_ok { ok = false; }
    if !vault_request_has_header(&req, "X-Vault-Token") { ok = false; }
    if vault_request_remove_header(&mut req, "X-CUSTOM") != 1 { ok = false; }
    if vault_request_header_count(&req) != 1 { ok = false; }
    if vault_request_remove_header(&mut req, "nope") != 0 { ok = false; }
    if !int_err_is(vault_request_set_header(&mut req, "", "v"), "vault: header name is empty") { ok = false; }
    if !int_err_is(vault_request_set_header(&mut req, "bad name", "v"), "vault: header name has an invalid character") { ok = false; }
    if !int_err_is(vault_request_set_header(&mut req, "X-A", "a\rb"), "vault: header value has a control byte at offset 1") { ok = false; }
    if !err_is(vault_request_header_get(&req, "Absent"), "vault: header not found: Absent") { ok = false; }
    if !int_err_is(vault_request_set_token(&mut req, ""), "vault: token is empty") { ok = false; }
    if !int_err_is(vault_request_set_token(&mut req, "a\nb"), "vault: token has a control byte at offset 1") { ok = false; }
  }
  return assert(ok, "headers: case-insensitive set/replace/remove, token header, errors");
}

fn t6() -> TestResult {
  var ok = true;
  var b = vault_body_new();
  if vault_body_count(&b) != 0 { ok = false; }
  if !streq(vault_body_render(&b), "{}") { ok = false; }
  let a1 = vault_body_add_str(&mut b, "role_id", "a\"b\\c");
  if !a1.is_ok { ok = false; }
  let a2 = vault_body_add_raw(&mut b, "renewable", "true");
  if !a2.is_ok { ok = false; }
  let a3 = vault_body_add_int(&mut b, "increment", 3600);
  if !a3.is_ok { ok = false; }
  let a4 = vault_body_add_bool(&mut b, "flag", false);
  if !a4.is_ok { ok = false; }
  if vault_body_count(&b) != 4 { ok = false; }
  let rendered = vault_body_render(&b);
  if !streq(rendered, "{\"role_id\":\"a\\\"b\\\\c\",\"renewable\":true,\"increment\":3600,\"flag\":false}") { ok = false; }
  if !int_err_is(vault_body_add_raw(&mut b, "x", "not json"), "vault: body raw value is not a JSON scalar") { ok = false; }
  if !int_err_is(vault_body_add_str(&mut b, "", "v"), "vault: body member name is empty or invalid") { ok = false; }
  if !int_err_is(vault_body_add_str(&mut b, "a b", "v"), "vault: body member name is empty or invalid") { ok = false; }
  if vault_body_clear(&mut b) != 4 { ok = false; }
  if vault_body_count(&b) != 0 { ok = false; }
  if !streq(vault_body_render(&b), "{}") { ok = false; }
  return assert(ok, "body builder: string escaping, raw/int/bool members, errors");
}

fn t7() -> TestResult {
  var ok = true;
  let text = "{\"client_token\":\"s.abc\",\"lease_duration\":3600,\"auth\":{\"nested\":1},\"renewable\":true}";
  let r = vault_json_lookup(text, "lease_duration");
  if !r.is_ok { ok = false; } else {
    let h: VaultJsonHit = r.value;
    if h.kind != VAULT_JSON_NUMBER { ok = false; }
    if !streq(vault_json_get_raw(text, "lease_duration").value, "3600") { ok = false; }
  }
  let r2 = vault_json_lookup(text, "client_token");
  if !r2.is_ok { ok = false; } else {
    let h2: VaultJsonHit = r2.value;
    if h2.kind != VAULT_JSON_STRING { ok = false; }
    if h2.start != 16 { ok = false; }
    if h2.end != 23 { ok = false; }
  }
  let r3 = vault_json_lookup(text, "auth");
  if !r3.is_ok { ok = false; } else {
    let h3: VaultJsonHit = r3.value;
    if h3.kind != VAULT_JSON_OBJECT { ok = false; }
    if !streq(vault_json_get_raw(text, "auth").value, "{\"nested\":1}") { ok = false; }
  }
  if !hit_err_is(vault_json_lookup(text, "missing"), "vault: json key not found: missing") { ok = false; }
  if !hit_err_is(vault_json_lookup("[]", "x"), "vault: json expected object at offset 0") { ok = false; }
  if !hit_err_is(vault_json_lookup("{\"a\":1,}", "b"), "vault: json expected string at offset 7") { ok = false; }
  return assert(ok, "json lookup: kinds, spans, nested skip, missing key, malformed");
}

fn t8() -> TestResult {
  var ok = true;
  let text = "{\"s\":\"a\\\"b\\\\c\\nd\\u0041\"}";
  let r = vault_json_get_str(text, "s");
  if !r.is_ok { ok = false; } else {
    let v: Str = r.value;
    if !streq(v, "a\"b\\c\ndA") { ok = false; }
  }
  if !err_is(vault_json_get_str("{\"s\":\"\\u0000\"}", "s"), "vault: json NUL escape at offset 6") { ok = false; }
  if !err_is(vault_json_get_str("{\"s\":1}", "s"), "vault: json value is not a string") { ok = false; }
  if !err_is(vault_json_get_str("{\"s\":\"\\q\"}", "s"), "vault: json invalid escape at offset 6") { ok = false; }
  if !err_is(vault_json_get_str("{\"s\":\"\\uD800\"}", "s"), "vault: json surrogate escape unsupported at offset 6") { ok = false; }
  let raw = vault_json_get_raw("{\"s\":\"x\"}", "s");
  if !raw.is_ok { ok = false; } else {
    let rv: Str = raw.value;
    if !streq(rv, "\"x\"") { ok = false; }
  }
  return assert(ok, "json strings: escape decode, NUL/surrogate/kind errors, raw quotes");
}

fn t9() -> TestResult {
  var ok = true;
  let r = vault_json_get_int("{\"a\":3600,\"b\":-5}", "a");
  if !r.is_ok { ok = false; } else {
    let v: Int = r.value;
    if v != 3600 { ok = false; }
  }
  let r2 = vault_json_get_int("{\"b\":-5}", "b");
  if !r2.is_ok { ok = false; } else {
    let v2: Int = r2.value;
    if v2 != -5 { ok = false; }
  }
  if !int_err_is(vault_json_get_int("{\"a\":1.5}", "a"), "vault: json value is not an integer") { ok = false; }
  if !int_err_is(vault_json_get_int("{\"a\":\"1\"}", "a"), "vault: json value is not an integer") { ok = false; }
  let r3 = vault_json_get_bool("{\"a\":true,\"b\":false}", "a");
  if !r3.is_ok { ok = false; } else {
    let v3: Bool = r3.value;
    if !v3 { ok = false; }
  }
  let r4 = vault_json_get_bool("{\"b\":false}", "b");
  if !r4.is_ok { ok = false; } else {
    let v4: Bool = r4.value;
    if v4 { ok = false; }
  }
  let r5 = vault_json_get_bool("{\"a\":null}", "a");
  if r5.is_ok {
    ok = false;
  } else {
    if !streq(r5.error, "vault: json value is not a boolean") { ok = false; }
  }
  if !int_err_is(vault_json_get_int("{\"a\":true}", "a"), "vault: json value is not an integer") { ok = false; }
  return assert(ok, "json scalars: signed integers, booleans, kind errors");
}

fn t10() -> TestResult {
  var ok = true;
  let text = "{\"policies\":[\"default\",\"app\\u002dread\"]}";
  let r = vault_json_get_strs(text, "policies");
  if !r.is_ok { ok = false; } else {
    let v: Vec[Str] = r.value;
    if v.len() != 2 { ok = false; }
    if !strs_of(v, two_strs("default", "app-read")) { ok = false; }
  }
  let r2 = vault_json_get_strs("{\"policies\":[]}", "policies");
  if !r2.is_ok { ok = false; } else {
    let v2: Vec[Str] = r2.value;
    if v2.len() != 0 { ok = false; }
  }
  let r3 = vault_json_get_strs("{\"policies\":\"root\"}", "policies");
  if r3.is_ok { ok = false; } else {
    if !streq(r3.error, "vault: json value is not an array") { ok = false; }
  }
  let r4 = vault_json_get_strs("{\"policies\":[\"a\",1]}", "policies");
  if r4.is_ok { ok = false; } else {
    if !streq(r4.error, "vault: json array element is not a string") { ok = false; }
  }
  return assert(ok, "json string arrays: decode, empty array, non-array/non-string errors");
}

fn t11() -> TestResult {
  var ok = true;
  let r = vault_response_new(200, "{\"ok\":true}");
  if !r.is_ok { ok = false; } else {
    let resp: VaultResponse = r.value;
    if vault_response_status(&resp) != 200 { ok = false; }
    if !streq(vault_response_body(&resp), "{\"ok\":true}") { ok = false; }
    if !vault_response_is_success(&resp) { ok = false; }
  }
  let r2 = vault_response_new(503, "");
  if !r2.is_ok { ok = false; } else {
    let resp2: VaultResponse = r2.value;
    if vault_response_is_success(&resp2) { ok = false; }
  }
  let e = vault_response_new(99, "");
  if e.is_ok { ok = false; } else {
    if !streq(e.error, "vault: response status out of range: 99") { ok = false; }
  }
  let e2 = vault_response_new(600, "");
  if e2.is_ok { ok = false; }
  return assert(ok, "response envelope: status range, success predicate, errors");
}

fn t12() -> TestResult {
  var ok = true;
  let r = vault_kv1_path("secret", "app/config");
  if !r.is_ok { ok = false; } else {
    let p: Str = r.value;
    if !streq(p, "secret/app/config") { ok = false; }
  }
  if !err_is(vault_kv1_path("", "key"), "vault: kv mount is empty or invalid") { ok = false; }
  if !err_is(vault_kv1_path("bad mount", "key"), "vault: kv mount is empty or invalid") { ok = false; }
  if !err_is(vault_kv1_path("secret", ""), "vault: kv key is empty or invalid") { ok = false; }
  if !err_is(vault_kv1_path("secret", "/key"), "vault: kv key is empty or invalid") { ok = false; }
  if !err_is(vault_kv1_path("secret", "a//b"), "vault: kv key is empty or invalid") { ok = false; }
  if !err_is(vault_kv1_path("secret", "a b"), "vault: kv key is empty or invalid") { ok = false; }
  let r2 = vault_kv1_path("kv-prod_1", "a.b-c/d_e");
  if !r2.is_ok { ok = false; } else {
    let p2: Str = r2.value;
    if !streq(p2, "kv-prod_1/a.b-c/d_e") { ok = false; }
  }
  return assert(ok, "kv v1 path: joining and mount/key validation");
}

fn t13() -> TestResult {
  var ok = true;
  let a = vault_kv2_data_path("secret", "app/config");
  if !a.is_ok { ok = false; } else {
    let p: Str = a.value;
    if !streq(p, "secret/data/app/config") { ok = false; }
  }
  let b = vault_kv2_metadata_path("secret", "app/config");
  if !b.is_ok { ok = false; } else {
    let p2: Str = b.value;
    if !streq(p2, "secret/metadata/app/config") { ok = false; }
  }
  let c = vault_kv2_delete_path("secret", "app/config");
  if !c.is_ok { ok = false; } else {
    let p3: Str = c.value;
    if !streq(p3, "secret/delete/app/config") { ok = false; }
  }
  let d = vault_kv2_undelete_path("secret", "app/config");
  if !d.is_ok { ok = false; } else {
    let p4: Str = d.value;
    if !streq(p4, "secret/undelete/app/config") { ok = false; }
  }
  let e = vault_kv2_destroy_path("secret", "app/config");
  if !e.is_ok { ok = false; } else {
    let p5: Str = e.value;
    if !streq(p5, "secret/destroy/app/config") { ok = false; }
  }
  return assert(ok, "kv v2 paths: data / metadata / delete / undelete / destroy");
}

fn t14() -> TestResult {
  var ok = true;
  let q = vault_kv2_version_query(2);
  if !q.is_ok { ok = false; } else {
    let qv: Str = q.value;
    if !streq(qv, "version=2") { ok = false; }
  }
  if !err_is(vault_kv2_version_query(0), "vault: kv version out of range: 0") { ok = false; }
  if !err_is(vault_kv2_version_query(1000001), "vault: kv version out of range: 1000001") { ok = false; }
  let r = vault_kv2_read_request("secret", "app/config", 2);
  if !r.is_ok { ok = false; } else {
    let req: VaultRequest = r.value;
    if vault_request_method(&req) != VAULT_METHOD_GET { ok = false; }
    if !streq(vault_request_target(&req), "/secret/data/app/config?version=2") { ok = false; }
  }
  let r2 = vault_kv2_read_request("secret", "app/config", 0);
  if !r2.is_ok { ok = false; } else {
    let req2: VaultRequest = r2.value;
    if !streq(vault_request_target(&req2), "/secret/data/app/config") { ok = false; }
    if !streq(vault_request_query(&req2), "") { ok = false; }
  }
  if !req_err_is(vault_kv2_read_request("secret", "k", 0 - 1), "vault: kv version out of range: -1") { ok = false; }
  return assert(ok, "kv v2 read: version query and target, latest vs pinned");
}

fn t15() -> TestResult {
  var ok = true;
  let w = vault_kv2_write_request("secret", "k");
  if !w.is_ok { ok = false; } else {
    let rw: VaultRequest = w.value;
    if vault_request_method(&rw) != VAULT_METHOD_POST { ok = false; }
    if !streq(vault_request_path(&rw), "/secret/data/k") { ok = false; }
  }
  let m = vault_kv2_metadata_request("secret", "k");
  if !m.is_ok { ok = false; } else {
    let rm: VaultRequest = m.value;
    if vault_request_method(&rm) != VAULT_METHOD_GET { ok = false; }
    if !streq(vault_request_path(&rm), "/secret/metadata/k") { ok = false; }
  }
  let d = vault_kv2_delete_request("secret", "k");
  if !d.is_ok { ok = false; } else {
    let rd: VaultRequest = d.value;
    if vault_request_method(&rd) != VAULT_METHOD_POST { ok = false; }
    if !streq(vault_request_path(&rd), "/secret/delete/k") { ok = false; }
  }
  let u = vault_kv2_undelete_request("secret", "k");
  if !u.is_ok { ok = false; } else {
    let ru: VaultRequest = u.value;
    if vault_request_method(&ru) != VAULT_METHOD_POST { ok = false; }
    if !streq(vault_request_path(&ru), "/secret/undelete/k") { ok = false; }
  }
  let x = vault_kv2_destroy_request("secret", "k");
  if !x.is_ok { ok = false; } else {
    let rx: VaultRequest = x.value;
    if vault_request_method(&rx) != VAULT_METHOD_PUT { ok = false; }
    if !streq(vault_request_path(&rx), "/secret/destroy/k") { ok = false; }
  }
  let versions = iv2(1, 3);
  let vb = vault_kv2_versions_body(&versions);
  if !vb.is_ok { ok = false; } else {
    let body: Str = vb.value;
    if !streq(body, "{\"versions\":[1,3]}") { ok = false; }
  }
  let dv = vault_kv2_delete_versions_request("secret", "k", &versions);
  if !dv.is_ok { ok = false; } else {
    let rdv: VaultRequest = dv.value;
    if !streq(vault_request_body(&rdv), "{\"versions\":[1,3]}") { ok = false; }
    if !vault_request_has_body(&rdv) { ok = false; }
  }
  var none = Vec[Int].new();
  if !err_is(vault_kv2_versions_body(&none), "vault: kv versions list is empty") { ok = false; }
  if !err_is(vault_kv2_versions_body(&iv1(0)), "vault: kv version out of range: 0") { ok = false; }
  return assert(ok, "kv v2 requests: methods/paths and versions body composition");
}

fn t16() -> TestResult {
  var ok = true;
  let r = vault_kv_versions_new(3);
  if !r.is_ok { ok = false; } else {
    let ledger: VaultKvVersions = r.value;
    if vault_kv_versions_state(&ledger, 1) != VAULT_KV_ABSENT { ok = false; }
    if vault_kv_can_read(&ledger, 1) { ok = false; }
    if !streq(vault_kv_state_name(VAULT_KV_SOFT_DELETED), "soft-deleted") { ok = false; }
    if !streq(vault_kv_state_name(VAULT_KV_DESTROYED), "destroyed") { ok = false; }
    if !streq(vault_kv_state_name(VAULT_KV_LIVE), "live") { ok = false; }
    if !streq(vault_kv_state_name(VAULT_KV_ABSENT), "absent") { ok = false; }
    let w = vault_kv_versions_apply(&ledger, VAULT_KV_OP_WRITE, 1);
    if !w.is_ok { ok = false; } else {
      let l1: VaultKvVersions = w.value;
      if vault_kv_versions_state(&l1, 1) != VAULT_KV_LIVE { ok = false; }
      if !vault_kv_can_read(&l1, 1) { ok = false; }
      let rd = vault_kv_versions_apply(&l1, VAULT_KV_OP_READ, 1);
      if !rd.is_ok { ok = false; }
      let del = vault_kv_versions_apply(&l1, VAULT_KV_OP_DELETE, 1);
      if !del.is_ok { ok = false; } else {
        let l2: VaultKvVersions = del.value;
        if vault_kv_versions_state(&l2, 1) != VAULT_KV_SOFT_DELETED { ok = false; }
        if vault_kv_can_read(&l2, 1) { ok = false; }
        let rd2 = vault_kv_versions_apply(&l2, VAULT_KV_OP_READ, 1);
        if rd2.is_ok { ok = false; } else {
          if !streq(rd2.error, "vault: kv version 1 is deleted") { ok = false; }
        }
        let un = vault_kv_versions_apply(&l2, VAULT_KV_OP_UNDELETE, 1);
        if !un.is_ok { ok = false; } else {
          let l3: VaultKvVersions = un.value;
          if vault_kv_versions_state(&l3, 1) != VAULT_KV_LIVE { ok = false; }
          if !vault_kv_can_read(&l3, 1) { ok = false; }
        }
      }
      if vault_kv_versions_state(&l1, 1) != VAULT_KV_LIVE { ok = false; }
    }
  }
  if !streq(vault_kv_state_name(99), "") { ok = false; }
  let nr = vault_kv_versions_new(2);
  if !nr.is_ok { ok = false; } else {
    let base: VaultKvVersions = nr.value;
    let w = vault_kv_versions_apply(&base, VAULT_KV_OP_WRITE, 1);
    if !w.is_ok { ok = false; } else {
      let live: VaultKvVersions = w.value;
      let destroyed = vault_kv_versions_apply(&live, VAULT_KV_OP_DESTROY, 1);
      if !destroyed.is_ok { ok = false; } else {
        let dl: VaultKvVersions = destroyed.value;
        if vault_kv_versions_state(&dl, 1) != VAULT_KV_DESTROYED { ok = false; }
        if !kv_err_is(vault_kv_versions_apply(&dl, VAULT_KV_OP_READ, 1), "vault: kv version 1 is destroyed") { ok = false; }
        if !kv_err_is(vault_kv_versions_apply(&dl, VAULT_KV_OP_WRITE, 1), "vault: kv version 1 is destroyed") { ok = false; }
        if !kv_err_is(vault_kv_versions_apply(&dl, VAULT_KV_OP_DELETE, 1), "vault: kv version 1 is destroyed") { ok = false; }
        if !kv_err_is(vault_kv_versions_apply(&dl, VAULT_KV_OP_UNDELETE, 1), "vault: kv version 1 is destroyed") { ok = false; }
        let dd = vault_kv_versions_apply(&dl, VAULT_KV_OP_DESTROY, 1);
        if !dd.is_ok { ok = false; } else {
          let dl2: VaultKvVersions = dd.value;
          if vault_kv_versions_state(&dl2, 1) != VAULT_KV_DESTROYED { ok = false; }
        }
      }
      let soft = vault_kv_versions_apply(&live, VAULT_KV_OP_DELETE, 1);
      if !soft.is_ok { ok = false; } else {
        let sl: VaultKvVersions = soft.value;
        let again = vault_kv_versions_apply(&sl, VAULT_KV_OP_DELETE, 1);
        if !again.is_ok { ok = false; } else {
          let sl2: VaultKvVersions = again.value;
          if vault_kv_versions_state(&sl2, 1) != VAULT_KV_SOFT_DELETED { ok = false; }
        }
        if !kv_err_is(vault_kv_versions_apply(&sl, VAULT_KV_OP_UNDELETE, 2), "vault: kv version 2 is absent") { ok = false; }
        if vault_kv_versions_state(&live, 1) != VAULT_KV_LIVE { ok = false; }
      }
      if !kv_err_is(vault_kv_versions_apply(&live, VAULT_KV_OP_WRITE, 0), "vault: kv version out of range: 0") { ok = false; }
      if !kv_err_is(vault_kv_versions_apply(&live, 9, 1), "vault: kv unknown op: 9") { ok = false; }
    }
  }
  return assert(ok, "kv version ledger: transitions, destroy terminal, idempotence, errors");
}

fn t17() -> TestResult {
  var ok = true;
  let m1 = vault_gf_mul(2, 27);
  if !m1.is_ok { ok = false; } else {
    let v: Int = m1.value;
    if v != 54 { ok = false; }
  }
  let m2 = vault_gf_mul(3, 3);
  if !m2.is_ok { ok = false; } else {
    let v2: Int = m2.value;
    if v2 != 5 { ok = false; }
  }
  let m3 = vault_gf_mul(0x1B, 2);
  if !m3.is_ok { ok = false; } else {
    let v3: Int = m3.value;
    if v3 != 54 { ok = false; }
  }
  let m4 = vault_gf_mul(0x57, 0x83);
  if !m4.is_ok { ok = false; } else {
    let v4: Int = m4.value;
    if v4 != 193 { ok = false; }
  }
  let i1 = vault_gf_inv(2);
  if !i1.is_ok { ok = false; } else {
    let iv: Int = i1.value;
    if iv != 141 { ok = false; }
  }
  let i2 = vault_gf_inv(1);
  if !i2.is_ok { ok = false; } else {
    let iv2: Int = i2.value;
    if iv2 != 1 { ok = false; }
  }
  if !int_err_is(vault_gf_inv(0), "vault: gf has no inverse for zero") { ok = false; }
  if !int_err_is(vault_gf_mul(256, 1), "vault: gf byte out of range: 256") { ok = false; }
  return assert(ok, "GF(256): AES polynomial products, inverses, range errors");
}

fn t18() -> TestResult {
  var ok = true;
  let secret = uv2(1, 2);
  let coeffs = uv2(3, 4);
  if vault_shamir_share_len(2) != 3 { ok = false; }
  if vault_shamir_share_len(0) != 0 { ok = false; }
  let r = vault_shamir_split_with_coeffs(&secret, 2, 2, &coeffs);
  if !r.is_ok { ok = false; } else {
    let shares: Vec[UInt8] = r.value;
    var w = Vec[UInt8].new();
    w.push(1 as UInt8);
    w.push(2 as UInt8);
    w.push(6 as UInt8);
    w.push(2 as UInt8);
    w.push(7 as UInt8);
    w.push(10 as UInt8);
    if !bytes_eq(shares, w) { ok = false; }
    let back = vault_shamir_combine(&shares, 2);
    if !back.is_ok { ok = false; } else {
      let bv: Vec[UInt8] = back.value;
      if !bytes_eq(bv, secret) { ok = false; }
    }
  }
  if !err_is(vault_shamir_split_with_coeffs(&secret, 2, 2, &uv1(3)), "vault: shamir coefficient count mismatch: 1 (want 2)") { ok = false; }
  if !err_is(vault_shamir_split_with_coeffs(&secret, 1, 1, &uv1(3)), "vault: shamir share count out of range: 1") { ok = false; }
  if !err_is(vault_shamir_split_with_coeffs(&secret, 2, 3, &uv2(3, 4)), "vault: shamir threshold out of range: 3") { ok = false; }
  return assert(ok, "Shamir known answer: threshold-2 split values and reconstruction");
}

fn t19() -> TestResult {
  var ok = true;
  var secret = Vec[UInt8].new();
  secret.push(118 as UInt8);
  secret.push(97 as UInt8);
  secret.push(117 as UInt8);
  secret.push(108 as UInt8);
  secret.push(116 as UInt8);
  let r = vault_shamir_split(&secret, 5, 3, 42);
  if !r.is_ok { ok = false; } else {
    let shares: Vec[UInt8] = r.value;
    if shares.len() != 30 { ok = false; }
    let share_len = 6;
    var s0 = Vec[UInt8].new();
    var s1 = Vec[UInt8].new();
    var s2 = Vec[UInt8].new();
    var i = 0;
    while i < share_len {
      s0.push(shares[i]);
      s1.push(shares[i + share_len]);
      s2.push(shares[i + 2 * share_len]);
      i = i + 1;
    }
    var pick = Vec[UInt8].new();
    i = 0;
    while i < share_len {
      pick.push(s2[i]);
      i = i + 1;
    }
    i = 0;
    while i < share_len {
      pick.push(s0[i]);
      i = i + 1;
    }
    i = 0;
    while i < share_len {
      pick.push(s1[i]);
      i = i + 1;
    }
    let back = vault_shamir_combine(&pick, 5);
    if !back.is_ok { ok = false; } else {
      let bv: Vec[UInt8] = back.value;
      if !bytes_eq(bv, secret) { ok = false; }
    }
    let two_only = vault_shamir_combine(&s0, 5);
    if two_only.is_ok { ok = false; }
    var dup = Vec[UInt8].new();
    i = 0;
    while i < share_len {
      dup.push(s0[i]);
      i = i + 1;
    }
    i = 0;
    while i < share_len {
      dup.push(s0[i]);
      i = i + 1;
    }
    let dr = vault_shamir_combine(&dup, 5);
    if dr.is_ok { ok = false; } else {
      if !streq(dr.error, "vault: shamir duplicate share x coordinate at share 1") { ok = false; }
    }
    var zero = Vec[UInt8].new();
    i = 0;
    while i < share_len {
      zero.push(shares[i]);
      i = i + 1;
    }
    i = 0;
    while i < share_len {
      zero.push(s1[i]);
      i = i + 1;
    }
    zero[0] = 0 as UInt8;
    let zr = vault_shamir_combine(&zero, 5);
    if zr.is_ok { ok = false; } else {
      if !streq(zr.error, "vault: shamir share x coordinate is zero at share 0") { ok = false; }
    }
    let hex = vault_shamir_to_hex(&shares);
    let fr = vault_shamir_from_hex(hex);
    if !fr.is_ok { ok = false; } else {
      let fv: Vec[UInt8] = fr.value;
      if !bytes_eq(fv, shares) { ok = false; }
    }
    if !err_is(vault_shamir_from_hex("xyz"), "vault: shamir invalid hex") { ok = false; }
    if !err_is(vault_shamir_combine(&shares, 6), "vault: shamir share data length mismatch: 30") { ok = false; }
  }
  return assert(ok, "Shamir seeded split: any-threshold reconstruction, duplicates, hex round-trip");
}

fn t20() -> TestResult {
  var ok = true;
  let r = vault_unseal_new(3);
  if !r.is_ok { ok = false; } else {
    var u: VaultUnseal = r.value;
    if vault_unseal_complete(&u) { ok = false; }
    if vault_unseal_remaining(&u) != 3 { ok = false; }
    u = vault_unseal_submit(&u, true);
    if u.progress != 1 { ok = false; }
    u = vault_unseal_submit(&u, true);
    if vault_unseal_remaining(&u) != 1 { ok = false; }
    if vault_unseal_complete(&u) { ok = false; }
    u = vault_unseal_submit(&u, false);
    if u.progress != 0 { ok = false; }
    u = vault_unseal_submit(&u, true);
    u = vault_unseal_submit(&u, true);
    u = vault_unseal_submit(&u, true);
    if !vault_unseal_complete(&u) { ok = false; }
    if vault_unseal_remaining(&u) != 0 { ok = false; }
    let extra = vault_unseal_submit(&u, false);
    if extra.progress != 3 { ok = false; }
    let reset = vault_unseal_reset(&u);
    if reset.progress != 0 { ok = false; }
    if reset.threshold != 3 { ok = false; }
  }
  let e = vault_unseal_new(0);
  if e.is_ok { ok = false; } else {
    if !streq(e.error, "vault: unseal threshold out of range: 0") { ok = false; }
  }
  return assert(ok, "unseal progress: threshold, rejected-share reset, completion, reset");
}

fn t21() -> TestResult {
  var ok = true;
  let text = "{\"client_token\":\"s.abc.def\",\"accessor\":\"acc1\",\"token_type\":\"service\",\"policies\":[\"default\",\"Root\"],\"lease_duration\":3600,\"renewable\":true,\"entity_id\":\"e1\"}";
  let r = vault_token_parse(text);
  if !r.is_ok { ok = false; } else {
    let t: VaultToken = r.value;
    if !streq(t.client_token, "s.abc.def") { ok = false; }
    if !streq(t.accessor, "acc1") { ok = false; }
    if !streq(t.token_type, "service") { ok = false; }
    if t.lease_duration != 3600 { ok = false; }
    if !t.renewable { ok = false; }
    if !streq(t.entity_id, "e1") { ok = false; }
    if !vault_token_has_policy(&t, "default") { ok = false; }
    if !vault_token_has_policy(&t, "rOoT") { ok = false; }
    if !vault_token_is_root(&t) { ok = false; }
    if vault_token_has_policy(&t, "admin") { ok = false; }
  }
  let r2 = vault_token_parse("{\"client_token\":\"x\"}");
  if !r2.is_ok { ok = false; } else {
    let t2: VaultToken = r2.value;
    if !streq(t2.accessor, "") { ok = false; }
    if t2.lease_duration != 0 { ok = false; }
    if t2.renewable { ok = false; }
    if t2.policies.len() != 0 { ok = false; }
    if vault_token_is_root(&t2) { ok = false; }
  }
  if !streq(vault_token_default_policy(), "default") { ok = false; }
  return assert(ok, "token parse: full payload, defaults, policy membership/root");
}

fn t22() -> TestResult {
  var ok = true;
  let e1 = vault_token_parse("{\"accessor\":\"a\"}");
  if e1.is_ok { ok = false; } else {
    if !streq(e1.error, "vault: token response missing client_token") { ok = false; }
  }
  let e2 = vault_token_parse("{\"client_token\":\"\"}");
  if e2.is_ok { ok = false; } else {
    if !streq(e2.error, "vault: token response has empty client_token") { ok = false; }
  }
  let e3 = vault_token_parse("{\"client_token\":\"x\",\"policies\":\"root\"}");
  if e3.is_ok { ok = false; } else {
    if !streq(e3.error, "vault: json value is not an array") { ok = false; }
  }
  let e4 = vault_token_parse("{\"client_token\":\"x\",\"lease_duration\":\"3600\"}");
  if e4.is_ok { ok = false; } else {
    if !streq(e4.error, "vault: json value is not an integer") { ok = false; }
  }
  let e5 = vault_token_parse("{\"client_token\":\"x\",\"renewable\":\"yes\"}");
  if e5.is_ok { ok = false; } else {
    if !streq(e5.error, "vault: json value is not a boolean") { ok = false; }
  }
  return assert(ok, "token parse errors: missing/empty token, malformed optional fields");
}

fn t23() -> TestResult {
  var ok = true;
  let lk = vault_token_lookup_request("s.abc");
  if !lk.is_ok { ok = false; } else {
    let req: VaultRequest = lk.value;
    if vault_request_method(&req) != VAULT_METHOD_GET { ok = false; }
    if !streq(vault_request_path(&req), "/auth/token/lookup-self") { ok = false; }
    let g = vault_request_header_get(&req, "x-vault-token");
    if !g.is_ok { ok = false; } else {
      let gv: Str = g.value;
      if !streq(gv, "s.abc") { ok = false; }
    }
  }
  let rn = vault_token_renew_request("s.abc", 3600);
  if !rn.is_ok { ok = false; } else {
    let req2: VaultRequest = rn.value;
    if vault_request_method(&req2) != VAULT_METHOD_PUT { ok = false; }
    if !streq(vault_request_path(&req2), "/auth/token/renew-self") { ok = false; }
    if !streq(vault_request_body(&req2), "{\"increment\":3600}") { ok = false; }
  }
  let rn0 = vault_token_renew_request("s.abc", 0);
  if !rn0.is_ok { ok = false; } else {
    let req3: VaultRequest = rn0.value;
    if vault_request_has_body(&req3) { ok = false; }
  }
  let rv = vault_token_revoke_request("s.abc");
  if !rv.is_ok { ok = false; } else {
    let req4: VaultRequest = rv.value;
    if vault_request_method(&req4) != VAULT_METHOD_POST { ok = false; }
    if !streq(vault_request_path(&req4), "/auth/token/revoke-self") { ok = false; }
  }
  if !req_err_is(vault_token_lookup_request(""), "vault: token is empty") { ok = false; }
  if !req_err_is(vault_token_renew_request("s.abc", 31536001), "vault: token renew increment out of range: 31536001") { ok = false; }
  return assert(ok, "token requests: lookup/renew/revoke, increment body, errors");
}

fn t24() -> TestResult {
  var ok = true;
  if !vault_approle_role_id_is_valid("123e4567-e89b-12d3-a456-426614174000") { ok = false; }
  if !vault_approle_role_id_is_valid("123E4567-E89B-12D3-A456-426614174000") { ok = false; }
  if vault_approle_role_id_is_valid("123e4567e89b12d3a456426614174000") { ok = false; }
  if vault_approle_role_id_is_valid("123e4567-e89b-12d3-a456-42661417400g") { ok = false; }
  if vault_approle_secret_id_is_valid("") { ok = false; }
  let p = vault_approle_login_path("approle");
  if !p.is_ok { ok = false; } else {
    let pv: Str = p.value;
    if !streq(pv, "auth/approle/login") { ok = false; }
  }
  if !err_is(vault_approle_login_path("bad/mount"), "vault: approle mount is empty or invalid") { ok = false; }
  let r = vault_approle_login_request("approle", "123e4567-e89b-12d3-a456-426614174000", "223e4567-e89b-12d3-a456-426614174111");
  if !r.is_ok { ok = false; } else {
    let req: VaultRequest = r.value;
    if vault_request_method(&req) != VAULT_METHOD_POST { ok = false; }
    if !streq(vault_request_path(&req), "/auth/approle/login") { ok = false; }
    if !streq(vault_request_body(&req), "{\"role_id\":\"123e4567-e89b-12d3-a456-426614174000\",\"secret_id\":\"223e4567-e89b-12d3-a456-426614174111\"}") { ok = false; }
  }
  if !req_err_is(vault_approle_login_request("approle", "nope", "223e4567-e89b-12d3-a456-426614174111"), "vault: approle role_id is not a UUID") { ok = false; }
  let login = "{\"auth\":{\"client_token\":\"s.login\",\"policies\":[\"default\"],\"lease_duration\":60,\"renewable\":false}}";
  let tr = vault_approle_parse_login(login);
  if !tr.is_ok { ok = false; } else {
    let t: VaultToken = tr.value;
    if !streq(t.client_token, "s.login") { ok = false; }
    if t.lease_duration != 60 { ok = false; }
  }
  let bad = vault_approle_parse_login("{\"data\":{}}");
  if bad.is_ok { ok = false; } else {
    if !streq(bad.error, "vault: approle login response missing auth") { ok = false; }
  }
  let bad2 = vault_approle_parse_login("{\"auth\":\"x\"}");
  if bad2.is_ok { ok = false; } else {
    if !streq(bad2.error, "vault: approle login response auth is not an object") { ok = false; }
  }
  return assert(ok, "AppRole: UUID shape, login path/request/body, nested auth parse");
}

fn t25() -> TestResult {
  var ok = true;
  if vault_capability_code("READ") != VAULT_CAP_READ { ok = false; }
  if vault_capability_code("patch") != VAULT_CAP_PATCH { ok = false; }
  if vault_capability_code("bogus") != 0 { ok = false; }
  if !streq(vault_capability_name(VAULT_CAP_SUDO), "sudo") { ok = false; }
  if !streq(vault_capability_name(3), "") { ok = false; }
  let names = two_strs("read", "list");
  let sr = vault_capability_set(&names);
  if !sr.is_ok { ok = false; } else {
    let mask: Int = sr.value;
    if mask != 18 { ok = false; }
    if !vault_capability_set_has(mask, VAULT_CAP_READ) { ok = false; }
    if !vault_capability_set_has(mask, VAULT_CAP_LIST) { ok = false; }
    if vault_capability_set_has(mask, VAULT_CAP_SUDO) { ok = false; }
    if !streq(vault_capability_set_render(mask), "read,list") { ok = false; }
  }
  var empty = Vec[Str].new();
  if !int_err_is(vault_capability_set(&empty), "vault: capability list is empty") { ok = false; }
  if !int_err_is(vault_capability_set(&two_strs("read", "fly")), "vault: unknown capability: fly") { ok = false; }
  if !streq(vault_capability_set_render(VAULT_CAP_CREATE | VAULT_CAP_DENY), "create,deny") { ok = false; }
  return assert(ok, "capability sets: codes, names, masks, render, unknown errors");
}

fn t26() -> TestResult {
  var ok = true;
  if !vault_policy_path_matches("secret/data/app", "secret/data/app") { ok = false; }
  if vault_policy_path_matches("secret/data/app", "secret/data/other") { ok = false; }
  if !vault_policy_path_matches("secret/*", "secret/data/app") { ok = false; }
  if vault_policy_path_matches("secret/*", "secret") { ok = false; }
  if !vault_policy_path_matches("secret/+/config", "secret/team1/config") { ok = false; }
  if vault_policy_path_matches("secret/+/config", "secret/team1/sub/config") { ok = false; }
  if vault_policy_path_matches("secret/+", "secret") { ok = false; }
  if !vault_policy_path_matches("secret/+", "secret/one") { ok = false; }
  if !vault_policy_path_matches("a*b*c", "aXXbYYc") { ok = false; }
  if !vault_policy_path_matches("SECRET", "SECRET") { ok = false; }
  if vault_policy_path_matches("secret", "Secret") { ok = false; }
  if !vault_policy_path_matches("*", "") { ok = false; }
  return assert(ok, "policy glob: exact, prefix star, segment plus, interior stars, case");
}

fn t27() -> TestResult {
  var ok = true;
  var p = vault_policy_new();
  if vault_policy_rule_count(&p) != 0 { ok = false; }
  let a1 = vault_policy_add(&mut p, "secret/*", VAULT_CAP_READ | VAULT_CAP_LIST);
  if !a1.is_ok { ok = false; }
  let a2 = vault_policy_add(&mut p, "secret/data/app", VAULT_CAP_READ | VAULT_CAP_CREATE);
  if !a2.is_ok { ok = false; }
  let a3 = vault_policy_add(&mut p, "secret/+/config", VAULT_CAP_SUDO);
  if !a3.is_ok { ok = false; }
  let a4 = vault_policy_add(&mut p, "secret/data/private", VAULT_CAP_DENY);
  if !a4.is_ok { ok = false; }
  let a5 = vault_policy_add(&mut p, "ab*", VAULT_CAP_READ);
  if !a5.is_ok { ok = false; }
  let a6 = vault_policy_add(&mut p, "a*c", VAULT_CAP_UPDATE);
  if !a6.is_ok { ok = false; }
  if vault_policy_rule_count(&p) != 6 { ok = false; }
  if !streq(vault_policy_pattern(&p, 0), "secret/*") { ok = false; }
  if vault_policy_rule_caps(&p, 1) != (VAULT_CAP_READ | VAULT_CAP_CREATE) { ok = false; }
  if !streq(vault_policy_pattern(&p, 99), "") { ok = false; }
  if vault_policy_rule_caps(&p, 99) != 0 { ok = false; }
  if !vault_policy_can(&p, "secret/data/app", VAULT_CAP_CREATE) { ok = false; }
  if !vault_policy_can(&p, "secret/data/app", VAULT_CAP_READ) { ok = false; }
  if vault_policy_can(&p, "secret/data/app", VAULT_CAP_LIST) { ok = false; }
  if vault_policy_decision(&p, "secret/data/app", VAULT_CAP_LIST) != VAULT_DECISION_DENY { ok = false; }
  if !vault_policy_can(&p, "secret/other", VAULT_CAP_READ) { ok = false; }
  if !vault_policy_can(&p, "secret/other", VAULT_CAP_LIST) { ok = false; }
  if vault_policy_can(&p, "secret/other", VAULT_CAP_SUDO) { ok = false; }
  if !vault_policy_can(&p, "secret/team1/config", VAULT_CAP_SUDO) { ok = false; }
  if vault_policy_can(&p, "secret/team1/sub/config", VAULT_CAP_SUDO) { ok = false; }
  if vault_policy_decision(&p, "secret/data/private", VAULT_CAP_READ) != VAULT_DECISION_DENY { ok = false; }
  if vault_policy_decision(&p, "nowhere", VAULT_CAP_READ) != VAULT_DECISION_NONE { ok = false; }
  if !vault_policy_can(&p, "abc", VAULT_CAP_READ) { ok = false; }
  if !vault_policy_can(&p, "abc", VAULT_CAP_UPDATE) { ok = false; }
  let eff = vault_policy_effective_caps(&p, "abc");
  if eff != (VAULT_CAP_READ | VAULT_CAP_UPDATE) { ok = false; }
  var bad = vault_policy_new();
  if !int_err_is(vault_policy_add(&mut bad, "", VAULT_CAP_READ), "vault: policy pattern is empty or invalid") { ok = false; }
  if !int_err_is(vault_policy_add(&mut bad, "a b", VAULT_CAP_READ), "vault: policy pattern is empty or invalid") { ok = false; }
  if !int_err_is(vault_policy_add(&mut bad, "a*", 0), "vault: policy rule has no capabilities") { ok = false; }
  return assert(ok, "policy rules: longest-prefix wins, tie union, deny, decisions, errors");
}

fn t28() -> TestResult {
  var ok = true;
  let h = vault_health_request();
  if !h.is_ok { ok = false; } else {
    let req: VaultRequest = h.value;
    if vault_request_method(&req) != VAULT_METHOD_GET { ok = false; }
    if !streq(vault_request_path(&req), "/sys/health") { ok = false; }
    if vault_request_header_count(&req) != 0 { ok = false; }
  }
  let s = vault_seal_status_request();
  if !s.is_ok { ok = false; } else {
    let req2: VaultRequest = s.value;
    if !streq(vault_request_target(&req2), "/sys/seal-status") { ok = false; }
  }
  let m = vault_sys_mounts_request("s.tok");
  if !m.is_ok { ok = false; } else {
    let req3: VaultRequest = m.value;
    let g = vault_request_header_get(&req3, "X-Vault-Token");
    if !g.is_ok { ok = false; } else {
      let gv: Str = g.value;
      if !streq(gv, "s.tok") { ok = false; }
    }
  }
  let kvr = vault_kv2_read("secret", "app", 3, "s.tok");
  if !kvr.is_ok { ok = false; } else {
    let req4: VaultRequest = kvr.value;
    if !streq(vault_request_target(&req4), "/secret/data/app?version=3") { ok = false; }
    if !vault_request_has_header(&req4, "x-vault-token") { ok = false; }
  }
  var b = vault_body_new();
  let ab = vault_body_add_str(&mut b, "password", "hunter2");
  if !ab.is_ok { ok = false; }
  let kvw = vault_kv2_write("secret", "app", &b, "s.tok");
  if !kvw.is_ok { ok = false; } else {
    let req5: VaultRequest = kvw.value;
    if !streq(vault_request_path(&req5), "/secret/data/app") { ok = false; }
    if !streq(vault_request_body(&req5), "{\"password\":\"hunter2\"}") { ok = false; }
  }
  var none = Vec[Int].new();
  let sd = vault_kv2_soft_delete("secret", "app", &none, "s.tok");
  if !sd.is_ok { ok = false; } else {
    let req6: VaultRequest = sd.value;
    if !streq(vault_request_path(&req6), "/secret/delete/app") { ok = false; }
    if vault_request_has_body(&req6) { ok = false; }
  }
  let sdv = vault_kv2_soft_delete("secret", "app", &iv2(1, 2), "s.tok");
  if !sdv.is_ok { ok = false; } else {
    let req7: VaultRequest = sdv.value;
    if !streq(vault_request_body(&req7), "{\"versions\":[1,2]}") { ok = false; }
  }
  let ud = vault_kv2_undelete("secret", "app", &iv1(1), "s.tok");
  if !ud.is_ok { ok = false; } else {
    let req8: VaultRequest = ud.value;
    if !streq(vault_request_path(&req8), "/secret/undelete/app") { ok = false; }
  }
  let de = vault_kv2_destroy("secret", "app", &none, "");
  if !de.is_ok { ok = false; } else {
    let req9: VaultRequest = de.value;
    if vault_request_method(&req9) != VAULT_METHOD_PUT { ok = false; }
    if vault_request_has_header(&req9, "X-Vault-Token") { ok = false; }
  }
  let al = vault_approle_login("approle", "123e4567-e89b-12d3-a456-426614174000", "223e4567-e89b-12d3-a456-426614174111");
  if !al.is_ok { ok = false; } else {
    let req10: VaultRequest = al.value;
    if !streq(vault_request_path(&req10), "/auth/approle/login") { ok = false; }
  }
  return assert(ok, "composed client: health/seal/mounts, kv2 CRUD, token header plumbing");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.vault conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.vault: all tests passed");
  } else {
    io.println("xiom.vault: tests failed");
  }
  return failed;
}
