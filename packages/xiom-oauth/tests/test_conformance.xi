// XIOM -- xiom.oauth conformance tests (25 checks)
// Port task: prove the OAuth 2.0 / PKCE structure codec against the rules
// documented in SPEC.md. Every check is a named assert(cond, "name") call,
// one fn per check, and main returns the failure count (0 = green).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// BUG 17 discipline: all Str equality goes through
// xiom.string.compare.str_compare (never `==`, which lowers to a pointer
// comparison for Str values read from a Vec), every Vec element read is
// widened with `(x as Int) & 0xFF`, and every Str read out of a Struct or
// Result field is bound to a typed local first.

module oauth_tests
use xiom.io; use xiom.test; use xiom.oauth;
use xiom.string; use xiom.string.builder; use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Raw bytes of a Str (one byte per index).
fn sb(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Byte i of v widened to Int space (0..255).
fn vbyte(v: Vec[UInt8], i: Int) -> Int {
  return (v[i] as Int) & 0xFF;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if vbyte(a, i) != vbyte(b, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when r is Ok(text) equal to `want`.
fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

// True when r is Err with exactly the message `want`.
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

// True when r is Ok(v) with v == want.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// `c` repeated `n` times.
fn repeat_str(c: Str, n: Int) -> Str {
  var s = "";
  var i = 0;
  while i < n {
    s = s + c;
    i = i + 1;
  }
  return s;
}

// True when a scope Vec[Str] has exactly the two tokens a and b.
fn scope_is2(sc: &Vec[Str], a: Str, b: Str) -> Bool {
  if sc.len() != 2 {
    return false;
  }
  let t0: Str = sc[0];
  let t1: Str = sc[1];
  if !streq(t0, a) {
    return false;
  }
  return streq(t1, b);
}

// True when a scope Vec[Str] has exactly the two tokens "read" and "write".
fn scope_is_read_write(sc: &Vec[Str]) -> Bool {
  return scope_is2(sc, "read", "write");
}

// The S256 challenge of the RFC 7636 appendix B example verifier
// "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk".
const RFC7636_S256: Str = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = streq(oauth_form_encode(""), "");
  if !streq(oauth_form_encode("a b"), "a+b") { ok = false; }
  if !streq(oauth_form_encode("a+b"), "a%2Bb") { ok = false; }
  if !streq(oauth_form_encode("a=b&c"), "a%3Db%26c") { ok = false; }
  if !streq(oauth_form_encode("-._~"), "-._~") { ok = false; }
  if !streq(oauth_form_encode("AZaz09"), "AZaz09") { ok = false; }
  if !streq(oauth_form_encode("%"), "%25") { ok = false; }
  if !streq(oauth_form_encode("!*'()"), "%21%2A%27%28%29") { ok = false; }
  if !streq(oauth_form_encode("Grüße"), "Gr%C3%BC%C3%9Fe") { ok = false; }
  if !streq(oauth_form_encode("a/b:c"), "a%2Fb%3Ac") { ok = false; }
  return assert(ok, "form encode: unreserved literal, space as +, %XX uppercase");
}

fn t2() -> TestResult {
  var ok = str_ok_is(oauth_form_decode(""), "");
  if !str_ok_is(oauth_form_decode("a+b"), "a b") { ok = false; }
  if !str_ok_is(oauth_form_decode("a%20b"), "a b") { ok = false; }
  if !str_ok_is(oauth_form_decode("%2B"), "+") { ok = false; }
  if !str_ok_is(oauth_form_decode("%2b"), "+") { ok = false; }
  if !str_ok_is(oauth_form_decode("a%3Db%26c"), "a=b&c") { ok = false; }
  if !str_ok_is(oauth_form_decode("%41"), "A") { ok = false; }
  if !str_ok_is(oauth_form_decode("Gr%C3%BC%C3%9Fe"), "Grüße") { ok = false; }
  if !str_ok_is(oauth_form_decode("++"), "  ") { ok = false; }
  return assert(ok, "form decode: + as space, lowercase hex, %20");
}

fn t3() -> TestResult {
  var cases = Vec[Str].new();
  cases.push("");
  cases.push("a b+c=d&e");
  cases.push("100%");
  cases.push("Grüße ✓");
  cases.push("~-._");
  cases.push("x/y:z?w");
  cases.push("a  b");
  cases.push("tab\there");
  var ok = true;
  var i = 0;
  while i < cases.len() {
    let s: Str = cases[i];
    let enc = oauth_form_encode(s);
    let back = oauth_form_decode(enc);
    if !back.is_ok { ok = false; }
    if back.is_ok {
      let bv: Str = back.value;
      if !streq(bv, s) { ok = false; }
      // encoding is canonical: re-encoding the decoded text is identical
      let enc2 = oauth_form_encode(bv);
      if !streq(enc2, enc) { ok = false; }
    }
    i = i + 1;
  }
  return assert(ok, "form round-trip: encode/decode is exact and canonical");
}

fn t4() -> TestResult {
  var ok = str_err_is(oauth_form_decode("%"), "oauth: truncated percent escape at offset 0");
  if !str_err_is(oauth_form_decode("a%2"), "oauth: truncated percent escape at offset 1") { ok = false; }
  if !str_err_is(oauth_form_decode("a%ZZ"), "oauth: bad percent escape at offset 1") { ok = false; }
  if !str_err_is(oauth_form_decode("%4G"), "oauth: bad percent escape at offset 0") { ok = false; }
  if !str_err_is(oauth_form_decode("100%"), "oauth: truncated percent escape at offset 3") { ok = false; }
  if !str_err_is(oauth_form_decode("%00"), "oauth: percent escape decodes to NUL at offset 0") { ok = false; }
  if !str_err_is(oauth_form_decode("a=%00"), "oauth: percent escape decodes to NUL at offset 2") { ok = false; }
  return assert(ok, "form decode errors: bad/truncated escape and NUL carry offsets");
}

fn t5() -> TestResult {
  let pr = oauth_params_parse("a=1&b=2");
  var ok = pr.is_ok;
  if pr.is_ok {
    let p = pr.value;
    if oauth_params_count(&p) != 2 { ok = false; }
    let n0: Str = oauth_params_name_at(&p, 0);
    let v0: Str = oauth_params_value_at(&p, 0);
    if !streq(n0, "a") { ok = false; }
    if !streq(v0, "1") { ok = false; }
    if !oauth_params_has(&p, "b") { ok = false; }
    if oauth_params_has(&p, "c") { ok = false; }
    let g = oauth_params_get(&p, "b");
    if !g.is_ok { ok = false; }
    if g.is_ok {
      let gv: Str = g.value;
      if !streq(gv, "2") { ok = false; }
    }
    let miss = oauth_params_get(&p, "c");
    if miss.is_ok { ok = false; }
    if !miss.is_ok {
      let mm: Str = miss.error;
      if !streq(mm, "oauth: parameter not found: c") { ok = false; }
    }
  }
  let pr2 = oauth_params_parse("a");
  if !pr2.is_ok { ok = false; }
  if pr2.is_ok {
    let p2 = pr2.value;
    if oauth_params_count(&p2) != 1 { ok = false; }
    let v1: Str = oauth_params_value_at(&p2, 0);
    if !streq(v1, "") { ok = false; }
  }
  let pr3 = oauth_params_parse("a=1&a=2");
  if !pr3.is_ok { ok = false; }
  if pr3.is_ok {
    let p3 = pr3.value;
    if oauth_params_count(&p3) != 2 { ok = false; }
    let last: Str = oauth_params_value_at(&p3, 1);
    if !streq(last, "2") { ok = false; }
  }
  let pr4 = oauth_params_parse("x%20y=z%2Bw");
  if !pr4.is_ok { ok = false; }
  if pr4.is_ok {
    let p4 = pr4.value;
    let n4: Str = oauth_params_name_at(&p4, 0);
    let v4: Str = oauth_params_value_at(&p4, 0);
    if !streq(n4, "x y") { ok = false; }
    if !streq(v4, "z+w") { ok = false; }
    if !streq(oauth_params_encode(&p4), "x+y=z%2Bw") { ok = false; }
  }
  var pb = oauth_params_new();
  if oauth_params_count(&pb) != 0 { ok = false; }
  oauth_params_add(&mut pb, "k1", "v1");
  oauth_params_add(&mut pb, "k2", "v 2");
  if oauth_params_count(&pb) != 2 { ok = false; }
  if !streq(oauth_params_encode(&pb), "k1=v1&k2=v+2") { ok = false; }
  let pbk = oauth_params_parse("k1=v1&k2=v%202");
  if !pbk.is_ok { ok = false; }
  if pbk.is_ok {
    let pbv = pbk.value;
    if !streq(oauth_params_encode(&pbv), "k1=v1&k2=v+2") { ok = false; }
  }
  let pr5 = oauth_params_parse("");
  if !pr5.is_ok { ok = false; }
  if pr5.is_ok {
    let p5 = pr5.value;
    if oauth_params_count(&p5) != 0 { ok = false; }
    if !streq(oauth_params_encode(&p5), "") { ok = false; }
  }
  return assert(ok, "params: ordered pairs, duplicates, empty value, encode round-trip");
}

fn t6() -> TestResult {
  var ok = true;
  let pe = oauth_params_parse("&a=1");
  if pe.is_ok { ok = false; } else { let m: Str = pe.error; if !streq(m, "oauth: empty parameter at offset 0") { ok = false; } }
  let pe2 = oauth_params_parse("a=1&");
  if pe2.is_ok { ok = false; } else { let m2: Str = pe2.error; if !streq(m2, "oauth: empty parameter at offset 3") { ok = false; } }
  let pe3 = oauth_params_parse("a=1&&b=2");
  if pe3.is_ok { ok = false; } else { let m3: Str = pe3.error; if !streq(m3, "oauth: empty parameter at offset 4") { ok = false; } }
  let pe4 = oauth_params_parse("=v");
  if pe4.is_ok { ok = false; } else { let m4: Str = pe4.error; if !streq(m4, "oauth: empty parameter name at offset 0") { ok = false; } }
  let pe5 = oauth_params_parse("%00=v");
  if pe5.is_ok { ok = false; } else { let m5: Str = pe5.error; if !streq(m5, "oauth: percent escape decodes to NUL at offset 0") { ok = false; } }
  let pe6 = oauth_params_parse("a=1&%GG=2");
  if pe6.is_ok { ok = false; } else { let m6: Str = pe6.error; if !streq(m6, "oauth: bad percent escape at offset 4") { ok = false; } }
  return assert(ok, "params errors: empty pair/name and decode errors with offsets");
}

fn t7() -> TestResult {
  var scope = Vec[Str].new();
  scope.push("read");
  scope.push("write");
  let rr = oauth_authz_request("code", "client-1", "https://app.example/cb", &scope, "xyz", "", "");
  var ok = rr.is_ok;
  if !rr.is_ok {
    return assert(ok, "authz request: build, extras and exact wire encoding");
  }
  var req = rr.value;
  let xe = oauth_authz_request_add_extra(&mut req, "prompt", "consent");
  if !xe.is_ok { ok = false; }
  let bad = oauth_authz_request_add_extra(&mut req, "client_id", "x");
  if bad.is_ok { ok = false; }
  if !bad.is_ok {
    let bm: Str = bad.error;
    if !streq(bm, "oauth: reserved parameter: client_id") { ok = false; }
  }
  let bad2 = oauth_authz_request_add_extra(&mut req, "", "x");
  if bad2.is_ok { ok = false; }
  let enc = oauth_authz_request_encode(&req);
  let want = "response_type=code&client_id=client-1&redirect_uri=https%3A%2F%2Fapp.example%2Fcb&scope=read+write&state=xyz&prompt=consent";
  if !enc.is_ok { ok = false; }
  if enc.is_ok {
    let ev: Str = enc.value;
    if !streq(ev, want) { ok = false; }
  }
  return assert(ok, "authz request: build, extras and exact wire encoding");
}

fn t8() -> TestResult {
  let q = "response_type=code&client_id=client-1&redirect_uri=https%3A%2F%2Fapp.example%2Fcb&scope=read+write&state=xyz&prompt=consent";
  let pr = oauth_authz_request_parse(q);
  var ok = pr.is_ok;
  if pr.is_ok {
    let req = pr.value;
    let rt: Str = req.response_type;
    let cid: Str = req.client_id;
    let ru: Str = req.redirect_uri;
    let st: Str = req.state;
    if !streq(rt, "code") { ok = false; }
    if !streq(cid, "client-1") { ok = false; }
    if !streq(ru, "https://app.example/cb") { ok = false; }
    if !streq(st, "xyz") { ok = false; }
    let sc: Vec[Str] = req.scope;
    if !scope_is_read_write(&sc) { ok = false; }
    let ex: OAuthParams = req.extra;
    if oauth_params_count(&ex) != 1 { ok = false; }
    let en: Str = oauth_params_name_at(&ex, 0);
    let ev: Str = oauth_params_value_at(&ex, 0);
    if !streq(en, "prompt") { ok = false; }
    if !streq(ev, "consent") { ok = false; }
  }
  return assert(ok, "authz request: parse fields, scope list, extras preserved");
}

fn t9() -> TestResult {
  var ok = true;
  let d = oauth_authz_request_parse("response_type=code&client_id=c&response_type=token");
  if d.is_ok { ok = false; } else { let m: Str = d.error; if !streq(m, "oauth: duplicate parameter: response_type") { ok = false; } }
  let m1 = oauth_authz_request_parse("client_id=c");
  if m1.is_ok { ok = false; } else { let m: Str = m1.error; if !streq(m, "oauth: missing parameter: response_type") { ok = false; } }
  let m2 = oauth_authz_request_parse("response_type=code");
  if m2.is_ok { ok = false; } else { let m: Str = m2.error; if !streq(m, "oauth: missing parameter: client_id") { ok = false; } }
  let m3 = oauth_authz_request_parse("response_type=foo&client_id=c");
  if m3.is_ok { ok = false; } else { let m: Str = m3.error; if !streq(m, "oauth: unsupported response_type: foo") { ok = false; } }
  let m4 = oauth_authz_request_parse("response_type=code&client_id=");
  if m4.is_ok { ok = false; } else { let m: Str = m4.error; if !streq(m, "oauth: empty client_id") { ok = false; } }
  let m5 = oauth_authz_request_parse("response_type=token&client_id=c&scope=read&foo=1&bar=2");
  if !m5.is_ok { ok = false; }
  if m5.is_ok {
    let req5 = m5.value;
    let ex5: OAuthParams = req5.extra;
    if oauth_params_count(&ex5) != 2 { ok = false; }
    let n0: Str = oauth_params_name_at(&ex5, 0);
    let n1: Str = oauth_params_name_at(&ex5, 1);
    if !streq(n0, "foo") { ok = false; }
    if !streq(n1, "bar") { ok = false; }
  }
  return assert(ok, "authz request errors: duplicates, missing required, bad type, extras order");
}

fn t10() -> TestResult {
  var ok = true;
  let v43 = repeat_str("a", 43);
  let q1 = "response_type=code&client_id=c&code_challenge=" + v43;
  let p1 = oauth_authz_request_parse(q1);
  if !p1.is_ok { ok = false; }
  if p1.is_ok {
    let r1 = p1.value;
    let cc: Str = r1.code_challenge;
    let cm: Str = r1.code_challenge_method;
    if !streq(cc, v43) { ok = false; }
    if !streq(cm, "") { ok = false; }
  }
  let q2 = "response_type=code&client_id=c&code_challenge=" + RFC7636_S256 + "&code_challenge_method=S256";
  let p2 = oauth_authz_request_parse(q2);
  if !p2.is_ok { ok = false; }
  if p2.is_ok {
    let r2 = p2.value;
    let cm2: Str = r2.code_challenge_method;
    if !streq(cm2, "S256") { ok = false; }
  }
  let e1 = oauth_authz_request_parse("response_type=code&client_id=c&code_challenge_method=S256");
  if e1.is_ok { ok = false; } else { let m: Str = e1.error; if !streq(m, "oauth: code_challenge_method without code_challenge") { ok = false; } }
  let e2 = oauth_authz_request_parse("response_type=code&client_id=c&code_challenge=" + v43 + "&code_challenge_method=S512");
  if e2.is_ok { ok = false; } else { let m: Str = e2.error; if !streq(m, "oauth: unsupported code_challenge_method: S512") { ok = false; } }
  let short_c = repeat_str("a", 42);
  let e3 = oauth_authz_request_parse("response_type=code&client_id=c&code_challenge=" + short_c + "&code_challenge_method=S256");
  if e3.is_ok { ok = false; } else { let m: Str = e3.error; if !streq(m, "oauth: pkce s256 challenge length must be 43") { ok = false; } }
  let e4 = oauth_authz_request_parse("response_type=code&client_id=c&code_challenge=" + repeat_str("a", 42));
  if e4.is_ok { ok = false; } else { let m: Str = e4.error; if !streq(m, "oauth: pkce verifier length out of range (43..128)") { ok = false; } }
  let badc = repeat_str("a", 42) + "+";
  let e5 = oauth_authz_request_parse("response_type=code&client_id=c&code_challenge=" + badc + "&code_challenge_method=S256");
  if e5.is_ok { ok = false; } else { let m: Str = e5.error; if !streq(m, "oauth: pkce s256 challenge bad character at offset 42") { ok = false; } }
  return assert(ok, "authz request PKCE: default plain, S256 validation with offsets");
}

fn t11() -> TestResult {
  var ok = true;
  let e1 = oauth_authz_request_parse("response_type=code&client_id=c&scope=read++write");
  if e1.is_ok { ok = false; } else { let m: Str = e1.error; if !streq(m, "oauth: empty scope token at offset 5") { ok = false; } }
  let e2 = oauth_authz_request_parse("response_type=code&client_id=c&scope=a%22b");
  if e2.is_ok { ok = false; } else { let m: Str = e2.error; if !streq(m, "oauth: scope token has invalid character at offset 1") { ok = false; } }
  let e3 = oauth_authz_request_parse("response_type=code&client_id=c&scope=a&scope=b");
  if e3.is_ok { ok = false; } else { let m: Str = e3.error; if !streq(m, "oauth: duplicate parameter: scope") { ok = false; } }
  let p1 = oauth_authz_request_parse("response_type=code&client_id=c&scope=");
  if !p1.is_ok { ok = false; }
  if p1.is_ok {
    let r1 = p1.value;
    let sc: Vec[Str] = r1.scope;
    if sc.len() != 0 { ok = false; }
  }
  var empty_scope = Vec[Str].new();
  empty_scope.push("");
  let b1 = oauth_authz_request("code", "c", "", &empty_scope, "", "", "");
  if b1.is_ok { ok = false; } else { let m: Str = b1.error; if !streq(m, "oauth: empty scope token") { ok = false; } }
  var spaced = Vec[Str].new();
  spaced.push("a b");
  let b2 = oauth_authz_request("code", "c", "", &spaced, "", "", "");
  if b2.is_ok { ok = false; } else { let m2: Str = b2.error; if !streq(m2, "oauth: scope token has invalid character") { ok = false; } }
  var quoted = Vec[Str].new();
  quoted.push("a\"b");
  let b3 = oauth_authz_request("code", "c", "", &quoted, "", "", "");
  if b3.is_ok { ok = false; }
  return assert(ok, "scope lists: empty/space/quote rejected, empty scope on the wire is empty");
}

fn t12() -> TestResult {
  var ok = true;
  let s = oauth_authz_response_parse("code=S1&state=xyz");
  if !s.is_ok { ok = false; }
  if s.is_ok {
    let r = s.value;
    let code: Str = r.code;
    let st: Str = r.state;
    let err: Str = r.error;
    if !streq(code, "S1") { ok = false; }
    if !streq(st, "xyz") { ok = false; }
    if !streq(err, "") { ok = false; }
  }
  let e = oauth_authz_response_parse("error=access_denied&error_description=user+said+no&error_uri=https%3A%2F%2Fe.example%2Fhelp&state=s1");
  if !e.is_ok { ok = false; }
  if e.is_ok {
    let r2 = e.value;
    let code2: Str = r2.code;
    let err2: Str = r2.error;
    let d2: Str = r2.error_description;
    let u2: Str = r2.error_uri;
    let st2: Str = r2.state;
    if !streq(code2, "") { ok = false; }
    if !streq(err2, "access_denied") { ok = false; }
    if !streq(d2, "user said no") { ok = false; }
    if !streq(u2, "https://e.example/help") { ok = false; }
    if !streq(st2, "s1") { ok = false; }
  }
  let x = oauth_authz_response_parse("code=S2&iss=extra");
  if !x.is_ok { ok = false; }
  if x.is_ok {
    let r3 = x.value;
    let ex3: OAuthParams = r3.extra;
    if oauth_params_count(&ex3) != 1 { ok = false; }
    let n3: Str = oauth_params_name_at(&ex3, 0);
    if !streq(n3, "iss") { ok = false; }
  }
  return assert(ok, "authz response: code+state success, error triple, extras");
}

fn t13() -> TestResult {
  var ok = true;
  var codes = Vec[Str].new();
  codes.push("invalid_request");
  codes.push("unauthorized_client");
  codes.push("access_denied");
  codes.push("unsupported_response_type");
  codes.push("invalid_scope");
  codes.push("server_error");
  codes.push("temporarily_unavailable");
  var i = 0;
  while i < codes.len() {
    let c: Str = codes[i];
    if !oauth_authz_error_is_valid(c) { ok = false; }
    let q = "error=" + c;
    let r = oauth_authz_response_parse(q);
    if !r.is_ok { ok = false; }
    if r.is_ok {
      let resp = r.value;
      let ev: Str = resp.error;
      if !streq(ev, c) { ok = false; }
    }
    i = i + 1;
  }
  let e1 = oauth_authz_response_parse("error=boom");
  if e1.is_ok { ok = false; } else { let m: Str = e1.error; if !streq(m, "oauth: unsupported error code: boom") { ok = false; } }
  let e2 = oauth_authz_response_parse("code=S1&error=access_denied");
  if e2.is_ok { ok = false; } else { let m2: Str = e2.error; if !streq(m2, "oauth: code with error") { ok = false; } }
  let e3 = oauth_authz_response_parse("state=s");
  if e3.is_ok { ok = false; } else { let m3: Str = e3.error; if !streq(m3, "oauth: missing parameter: code") { ok = false; } }
  let e4 = oauth_authz_response_parse("code=");
  if e4.is_ok { ok = false; } else { let m4: Str = e4.error; if !streq(m4, "oauth: empty code") { ok = false; } }
  let e5 = oauth_authz_response_parse("error=");
  if e5.is_ok { ok = false; } else { let m5: Str = e5.error; if !streq(m5, "oauth: empty error code") { ok = false; } }
  let e6 = oauth_authz_response_parse("code=a&code=b");
  if e6.is_ok { ok = false; } else { let m6: Str = e6.error; if !streq(m6, "oauth: duplicate parameter: code") { ok = false; } }
  return assert(ok, "authz response: all 7 error codes, exclusivity, malformed cases");
}

fn t14() -> TestResult {
  var scope = Vec[Str].new();
  let e = Vec[Str].new();
  let rr = oauth_token_request("authorization_code", "S1", "https://app.example/cb", "", &e, "client-1", "s3cret");
  var ok = rr.is_ok;
  if !rr.is_ok {
    return assert(ok, "token request authorization_code: build, exact wire, parse");
  }
  let req = rr.value;
  let enc = oauth_token_request_encode(&req);
  let want = "grant_type=authorization_code&code=S1&redirect_uri=https%3A%2F%2Fapp.example%2Fcb&client_id=client-1&client_secret=s3cret";
  if !enc.is_ok { ok = false; }
  if enc.is_ok {
    let ev: Str = enc.value;
    if !streq(ev, want) { ok = false; }
  }
  let pr = oauth_token_request_parse(want);
  if !pr.is_ok { ok = false; }
  if pr.is_ok {
    let p = pr.value;
    let gt: Str = p.grant_type;
    let code: Str = p.code;
    let ru: Str = p.redirect_uri;
    let rtok: Str = p.refresh_token;
    let cid: Str = p.client_id;
    let csec: Str = p.client_secret;
    if !streq(gt, "authorization_code") { ok = false; }
    if !streq(code, "S1") { ok = false; }
    if !streq(ru, "https://app.example/cb") { ok = false; }
    if !streq(rtok, "") { ok = false; }
    if !streq(cid, "client-1") { ok = false; }
    if !streq(csec, "s3cret") { ok = false; }
  }
  let e1 = oauth_token_request("authorization_code", "", "", "", &e, "c", "");
  if e1.is_ok { ok = false; } else { let m: Str = e1.error; if !streq(m, "oauth: missing code") { ok = false; } }
  var s1 = Vec[Str].new();
  s1.push("read");
  s1.push("write");
  let e2 = oauth_token_request("authorization_code", "S1", "", "", &s1, "c", "");
  if !e2.is_ok { ok = false; }
  if e2.is_ok {
    let r2 = e2.value;
    let sc2: Vec[Str] = r2.scope;
    if !scope_is_read_write(&sc2) { ok = false; }
    let enc2 = oauth_token_request_encode(&r2);
    if !enc2.is_ok { ok = false; }
    if enc2.is_ok {
      let ev2: Str = enc2.value;
      if !streq(ev2, "grant_type=authorization_code&code=S1&scope=read+write&client_id=c") { ok = false; }
    }
  }
  return assert(ok, "token request authorization_code: build, exact wire, parse");
}

fn t15() -> TestResult {
  var ok = true;
  let e = Vec[Str].new();
  let r2 = oauth_token_request("refresh_token", "", "", "R1", &e, "cid", "");
  if !r2.is_ok { ok = false; }
  if r2.is_ok {
    let req = r2.value;
    let enc = oauth_token_request_encode(&req);
    if !enc.is_ok { ok = false; }
    if enc.is_ok {
      let ev: Str = enc.value;
      if !streq(ev, "grant_type=refresh_token&refresh_token=R1&client_id=cid") { ok = false; }
      let pr = oauth_token_request_parse(ev);
      if !pr.is_ok { ok = false; }
      if pr.is_ok {
        let p = pr.value;
        let gt: Str = p.grant_type;
        let rt: Str = p.refresh_token;
        if !streq(gt, "refresh_token") { ok = false; }
        if !streq(rt, "R1") { ok = false; }
      }
    }
  }
  let e1 = oauth_token_request("refresh_token", "", "", "", &e, "c", "");
  if e1.is_ok { ok = false; } else { let m: Str = e1.error; if !streq(m, "oauth: missing refresh_token") { ok = false; } }
  let e2 = oauth_token_request("refresh_token", "S1", "", "R1", &e, "c", "");
  if e2.is_ok { ok = false; } else { let m2: Str = e2.error; if !streq(m2, "oauth: unexpected code") { ok = false; } }
  var s1 = Vec[Str].new();
  s1.push("read");
  s1.push("write");
  let c1 = oauth_token_request("client_credentials", "", "", "", &s1, "cid", "sec");
  if !c1.is_ok { ok = false; }
  if c1.is_ok {
    let req = c1.value;
    let enc = oauth_token_request_encode(&req);
    if !enc.is_ok { ok = false; }
    if enc.is_ok {
      let ev: Str = enc.value;
      if !streq(ev, "grant_type=client_credentials&scope=read+write&client_id=cid&client_secret=sec") { ok = false; }
    }
  }
  let c2 = oauth_token_request("client_credentials", "", "https://cb", "", &e, "c", "");
  if c2.is_ok { ok = false; } else { let m3: Str = c2.error; if !streq(m3, "oauth: unexpected redirect_uri") { ok = false; } }
  let c3 = oauth_token_request("client_credentials", "", "", "R1", &e, "c", "");
  if c3.is_ok { ok = false; } else { let m4: Str = c3.error; if !streq(m4, "oauth: unexpected refresh_token") { ok = false; } }
  let p1 = oauth_token_request_parse("grant_type=client_credentials&code=x");
  if p1.is_ok { ok = false; } else { let m5: Str = p1.error; if !streq(m5, "oauth: unexpected code") { ok = false; } }
  let p2 = oauth_token_request_parse("code=S1");
  if p2.is_ok { ok = false; } else { let m6: Str = p2.error; if !streq(m6, "oauth: missing parameter: grant_type") { ok = false; } }
  let p3 = oauth_token_request_parse("grant_type=password&username=u&password=p");
  if p3.is_ok { ok = false; } else { let m7: Str = p3.error; if !streq(m7, "oauth: unsupported grant_type: password") { ok = false; } }
  return assert(ok, "token request: refresh/client_credentials grants and grant-specific rules");
}

fn t16() -> TestResult {
  var ok = true;
  let payload = sb("{\"access_token\":\"abc\",\"expires_in\":3600}");
  if !oauth_json_has(&payload, "access_token") { ok = false; }
  if oauth_json_has(&payload, "missing") { ok = false; }
  let sr = oauth_json_str(&payload, "access_token");
  if !str_ok_is(sr, "abc") { ok = false; }
  let ir = oauth_json_int(&payload, "expires_in");
  if !int_ok_is(ir, 3600) { ok = false; }
  let sp = oauth_json_span(&payload, "access_token");
  if !sp.is_ok { ok = false; }
  if sp.is_ok {
    let span = sp.value;
    let a: Int = span.0;
    let b: Int = span.1;
    if b - a != 5 { ok = false; }
    var quoted = Vec[UInt8].new();
    quoted.push(34 as UInt8);
    quoted.push(97 as UInt8);
    quoted.push(98 as UInt8);
    quoted.push(99 as UInt8);
    quoted.push(34 as UInt8);
    if !bytes_equal(sb(string.str_slice("{\"access_token\":\"abc\",\"expires_in\":3600}", a, b)), quoted) { ok = false; }
  }
  let neg = sb("{\"e\":-5}");
  let nr = oauth_json_int(&neg, "e");
  if !int_ok_is(nr, 0 - 5) { ok = false; }
  let mx = sb("{\"e\":2147483647}");
  let mr = oauth_json_int(&mx, "e");
  if !int_ok_is(mr, 2147483647) { ok = false; }
  let ov = sb("{\"e\":2147483648}");
  let orr = oauth_json_int(&ov, "e");
  if orr.is_ok { ok = false; }
  let notint = sb("{\"e\":1.5}");
  if oauth_json_int(&notint, "e").is_ok { ok = false; }
  return assert(ok, "json lookup: has/str/int/span, negative and bounded integers");
}

fn t17() -> TestResult {
  var ok = true;
  let esc = sb("{\"a\":\"x\\\"y\"}");
  let er = oauth_json_str(&esc, "a");
  if !str_ok_is(er, "x\\\"y") { ok = false; }
  let inner = sb("{\"v\":\"access_token\",\"access_token\":\"tok\"}");
  let ir = oauth_json_str(&inner, "access_token");
  if !str_ok_is(ir, "tok") { ok = false; }
  let prefix = sb("{\"xaccess_token\":\"no\"}");
  if oauth_json_has(&prefix, "access_token") { ok = false; }
  let comp = sb("{\"a\":{\"b\":1},\"c\":2}");
  if oauth_json_has(&comp, "a") { ok = false; }
  let cr = oauth_json_str(&comp, "a");
  if cr.is_ok { ok = false; } else { let m: Str = cr.error; if !streq(m, "oauth: json bad value: a") { ok = false; } }
  let arr = sb("{\"a\":[1,2]}");
  if oauth_json_has(&arr, "a") { ok = false; }
  let missing = oauth_json_str(&comp, "zz");
  if missing.is_ok { ok = false; } else { let m2: Str = missing.error; if !streq(m2, "oauth: json key not found: zz") { ok = false; } }
  let ek = oauth_json_span(&comp, "");
  if ek.is_ok { ok = false; } else { let m3: Str = ek.error; if !streq(m3, "oauth: json empty key") { ok = false; } }
  var nulp = Vec[UInt8].new();
  builder.sb_push_str(&mut nulp, "{\"a\":\"x");
  nulp.push(0 as UInt8);
  builder.sb_push_str(&mut nulp, "\"}");
  let nlr = oauth_json_str(&nulp, "a");
  if nlr.is_ok { ok = false; } else { let m4: Str = nlr.error; if !streq(m4, "oauth: json control byte at offset 7") { ok = false; } }
  let unterm = sb("{\"access_token\":\"abc}");
  let ur = oauth_json_str(&unterm, "access_token");
  if ur.is_ok { ok = false; } else { let m5: Str = ur.error; if !streq(m5, "oauth: json bad value: access_token") { ok = false; } }
  return assert(ok, "json lookup: escape-aware, boundary keys, composite/NUL/unterminated errors");
}

fn t18() -> TestResult {
  var ok = true;
  let j = "{\"access_token\":\"2YotnFZFEjr1zCsicMWpAA\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"refresh_token\":\"tGzv3JOkF0XG5Qx2TlKWIA\",\"scope\":\"read write\"}";
  let r = oauth_token_response_parse(j);
  if !r.is_ok { ok = false; }
  if r.is_ok {
    let t = r.value;
    let at: Str = t.access_token;
    let tt: Str = t.token_type;
    let rf: Str = t.refresh_token;
    if !streq(at, "2YotnFZFEjr1zCsicMWpAA") { ok = false; }
    if !streq(tt, "Bearer") { ok = false; }
    if !t.expires_in_present { ok = false; }
    if t.expires_in != 3600 { ok = false; }
    if !streq(rf, "tGzv3JOkF0XG5Qx2TlKWIA") { ok = false; }
    let sc: Vec[Str] = t.scope;
    if !scope_is_read_write(&sc) { ok = false; }
  }
  let lower = "{\"access_token\":\"a\",\"token_type\":\"bearer\"}";
  let r2 = oauth_token_response_parse(lower);
  if !r2.is_ok { ok = false; }
  if r2.is_ok {
    let t2 = r2.value;
    let tt2: Str = t2.token_type;
    if !streq(tt2, "bearer") { ok = false; }
    if t2.expires_in_present { ok = false; }
  }
  let upper = "{\"access_token\":\"a\",\"token_type\":\"BEARER\"}";
  if !oauth_token_response_parse(upper).is_ok { ok = false; }
  let spaced = "  {\"access_token\":\"a\",\"token_type\":\"Bearer\"}\r\n";
  if !oauth_token_response_parse(spaced).is_ok { ok = false; }
  let emptyscope = "{\"access_token\":\"a\",\"token_type\":\"Bearer\",\"scope\":\"\"}";
  let r3 = oauth_token_response_parse(emptyscope);
  if !r3.is_ok { ok = false; }
  if r3.is_ok {
    let t3 = r3.value;
    let sc3: Vec[Str] = t3.scope;
    if sc3.len() != 0 { ok = false; }
  }
  return assert(ok, "token response: success fields, Bearer case-insensitive, absent expires_in");
}

fn t19() -> TestResult {
  var ok = true;
  var codes = Vec[Str].new();
  codes.push("invalid_request");
  codes.push("invalid_client");
  codes.push("invalid_grant");
  codes.push("unauthorized_client");
  codes.push("unsupported_grant_type");
  codes.push("invalid_scope");
  var i = 0;
  while i < codes.len() {
    let c: Str = codes[i];
    if !oauth_token_error_is_valid(c) { ok = false; }
    let j = "{\"error\":\"" + c + "\"}";
    let r = oauth_token_response_parse(j);
    if !r.is_ok { ok = false; }
    if r.is_ok {
      let t = r.value;
      let ev: Str = t.error;
      if !streq(ev, c) { ok = false; }
    }
    i = i + 1;
  }
  let ed = "{\"error\":\"invalid_grant\",\"error_description\":\"code expired\"}";
  let r2 = oauth_token_response_parse(ed);
  if !r2.is_ok { ok = false; }
  if r2.is_ok {
    let t2 = r2.value;
    let d2: Str = t2.error_description;
    if !streq(d2, "code expired") { ok = false; }
  }
  let e1 = oauth_token_response_parse("{\"error\":\"nope\"}");
  if e1.is_ok { ok = false; } else { let m: Str = e1.error; if !streq(m, "oauth: unsupported error code: nope") { ok = false; } }
  let e2 = oauth_token_response_parse("{\"error\":\"invalid_request\",\"access_token\":\"x\"}");
  if e2.is_ok { ok = false; } else { let m2: Str = e2.error; if !streq(m2, "oauth: access_token with error") { ok = false; } }
  let e3 = oauth_token_response_parse("{\"error\":\"\"}");
  if e3.is_ok { ok = false; } else { let m3: Str = e3.error; if !streq(m3, "oauth: empty error code") { ok = false; } }
  return assert(ok, "token response errors: all 6 codes, description, exclusivity");
}

fn t20() -> TestResult {
  var ok = true;
  let m1 = oauth_token_response_parse("{\"token_type\":\"Bearer\"}");
  if m1.is_ok { ok = false; } else { let m: Str = m1.error; if !streq(m, "oauth: missing access_token") { ok = false; } }
  let m2 = oauth_token_response_parse("{\"access_token\":\"a\"}");
  if m2.is_ok { ok = false; } else { let mm: Str = m2.error; if !streq(mm, "oauth: missing token_type") { ok = false; } }
  let m3 = oauth_token_response_parse("{\"access_token\":\"a\",\"token_type\":\"mac\"}");
  if m3.is_ok { ok = false; } else { let mm3: Str = m3.error; if !streq(mm3, "oauth: unsupported token_type: mac") { ok = false; } }
  let m4 = oauth_token_response_parse("{\"access_token\":\"\",\"token_type\":\"Bearer\"}");
  if m4.is_ok { ok = false; } else { let mm4: Str = m4.error; if !streq(mm4, "oauth: empty access_token") { ok = false; } }
  let m5 = oauth_token_response_parse("{\"access_token\":\"a\",\"token_type\":\"Bearer\",\"expires_in\":\"1.5\"}");
  if m5.is_ok { ok = false; } else { let mm5: Str = m5.error; if !streq(mm5, "oauth: invalid expires_in") { ok = false; } }
  let m6 = oauth_token_response_parse("{\"access_token\":\"a\",\"token_type\":\"Bearer\",\"expires_in\":-1}");
  if m6.is_ok { ok = false; } else { let mm6: Str = m6.error; if !streq(mm6, "oauth: invalid expires_in") { ok = false; } }
  let m7 = oauth_token_response_parse("{\"access_token\":\"a\",\"token_type\":\"Bearer\",\"expires_in\":\"abc\"}");
  if m7.is_ok { ok = false; } else { let mm7: Str = m7.error; if !streq(mm7, "oauth: invalid expires_in") { ok = false; } }
  let m8 = oauth_token_response_parse("{\"access_token\":\"a\",\"token_type\":\"Bearer\",\"expires_in\":2147483648}");
  if m8.is_ok { ok = false; } else { let mm8: Str = m8.error; if !streq(mm8, "oauth: invalid expires_in") { ok = false; } }
  let m9 = oauth_token_response_parse("[]");
  if m9.is_ok { ok = false; } else { let mm9: Str = m9.error; if !streq(mm9, "oauth: json not an object") { ok = false; } }
  let m10 = oauth_token_response_parse("");
  if m10.is_ok { ok = false; } else { let mm10: Str = m10.error; if !streq(mm10, "oauth: json not an object") { ok = false; } }
  let m11 = oauth_token_response_parse("{\"access_token\":42,\"token_type\":\"Bearer\"}");
  if m11.is_ok { ok = false; } else { let mm11: Str = m11.error; if !streq(mm11, "oauth: json bad value: access_token") { ok = false; } }
  return assert(ok, "token response malformed: required fields, token_type, expires_in, non-object");
}

fn t21() -> TestResult {
  var ok = true;
  let v42 = repeat_str("a", 42);
  let v43 = repeat_str("a", 43);
  let v128 = repeat_str("a", 128);
  let v129 = repeat_str("a", 129);
  if oauth_pkce_verifier_is_valid(v42) { ok = false; }
  if !oauth_pkce_verifier_is_valid(v43) { ok = false; }
  if !oauth_pkce_verifier_is_valid(v128) { ok = false; }
  if oauth_pkce_verifier_is_valid(v129) { ok = false; }
  if !str_err_is(oauth_pkce_verifier_check(v42), "oauth: pkce verifier length out of range (43..128)") { ok = false; }
  if !str_err_is(oauth_pkce_verifier_check(v129), "oauth: pkce verifier length out of range (43..128)") { ok = false; }
  let mixed = repeat_str("AZaz09-._~", 4) + "AZa";
  if mixed.len() != 43 { ok = false; }
  if !oauth_pkce_verifier_is_valid(mixed) { ok = false; }
  let sp = repeat_str("a", 10) + " " + repeat_str("a", 32);
  if oauth_pkce_verifier_is_valid(sp) { ok = false; }
  if !str_err_is(oauth_pkce_verifier_check(sp), "oauth: pkce verifier bad character at offset 10") { ok = false; }
  let tb = "a\t" + repeat_str("b", 41);
  if oauth_pkce_verifier_is_valid(tb) { ok = false; }
  if oauth_pkce_verifier_min() != 43 { ok = false; }
  if oauth_pkce_verifier_max() != 128 { ok = false; }
  if oauth_pkce_s256_hash_len() != 32 { ok = false; }
  return assert(ok, "pkce verifier: 42/43/128/129 boundaries, charset, no whitespace");
}

fn t22() -> TestResult {
  var ok = true;
  let v = repeat_str("a", 43);
  let pc = oauth_pkce_plain_challenge(v);
  if !pc.is_ok { ok = false; }
  if pc.is_ok {
    let pv: Str = pc.value;
    if !streq(pv, v) { ok = false; }
  }
  if oauth_pkce_plain_challenge("short").is_ok { ok = false; }
  if !oauth_pkce_plain_matches(v, v) { ok = false; }
  let other = repeat_str("b", 43);
  if oauth_pkce_plain_matches(v, other) { ok = false; }
  let badv = repeat_str("a", 10) + " " + repeat_str("a", 32);
  if oauth_pkce_plain_matches(badv, badv) { ok = false; }
  if !oauth_pkce_challenge_is_valid(v, "") { ok = false; }
  if !oauth_pkce_challenge_is_valid(v, "plain") { ok = false; }
  if !oauth_pkce_challenge_is_valid(RFC7636_S256, "S256") { ok = false; }
  if oauth_pkce_challenge_is_valid(RFC7636_S256, "S512") { ok = false; }
  if oauth_pkce_challenge_is_valid("", "plain") { ok = false; }
  let bads = repeat_str("a", 42) + "+";
  if oauth_pkce_challenge_is_valid(bads, "S256") { ok = false; }
  return assert(ok, "pkce plain: challenge equality helper and method-aware validity");
}

fn t23() -> TestResult {
  var ok = true;
  var hash = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    hash.push(i as UInt8);
    i = i + 1;
  }
  let r = oauth_pkce_s256_challenge(&hash);
  let want1 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
  if !r.is_ok { ok = false; }
  if r.is_ok {
    let cv: Str = r.value;
    if !streq(cv, want1) { ok = false; }
    if cv.len() != 43 { ok = false; }
  }
  var ones = Vec[UInt8].new();
  var k = 0;
  while k < 32 {
    ones.push(255 as UInt8);
    k = k + 1;
  }
  let r2 = oauth_pkce_s256_challenge(&ones);
  let want2 = repeat_str("_", 42) + "8";
  if !r2.is_ok { ok = false; }
  if r2.is_ok {
    let cv2: Str = r2.value;
    if !streq(cv2, want2) { ok = false; }
  }
  var h31 = Vec[UInt8].new();
  var j = 0;
  while j < 31 {
    h31.push(7 as UInt8);
    j = j + 1;
  }
  let r3 = oauth_pkce_s256_challenge(&h31);
  if r3.is_ok { ok = false; } else { let m: Str = r3.error; if !streq(m, "oauth: pkce s256 hash must be 32 bytes") { ok = false; } }
  var h33 = Vec[UInt8].new();
  var q = 0;
  while q < 33 {
    h33.push(7 as UInt8);
    q = q + 1;
  }
  if oauth_pkce_s256_challenge(&h33).is_ok { ok = false; }
  if !oauth_pkce_s256_challenge(&hash).is_ok { ok = false; }
  return assert(ok, "pkce S256: 32-byte digest to unpadded base64url, length guard");
}

fn t24() -> TestResult {
  var ok = true;
  if !oauth_response_type_is_valid("code") { ok = false; }
  if !oauth_response_type_is_valid("token") { ok = false; }
  if oauth_response_type_is_valid("Code") { ok = false; }
  if oauth_response_type_is_valid("") { ok = false; }
  if !oauth_grant_type_is_valid("authorization_code") { ok = false; }
  if !oauth_grant_type_is_valid("refresh_token") { ok = false; }
  if !oauth_grant_type_is_valid("client_credentials") { ok = false; }
  if oauth_grant_type_is_valid("password") { ok = false; }
  if !oauth_challenge_method_is_valid("plain") { ok = false; }
  if !oauth_challenge_method_is_valid("S256") { ok = false; }
  if oauth_challenge_method_is_valid("s256") { ok = false; }
  if oauth_authz_error_is_valid("invalid_grant") { ok = false; }
  if oauth_token_error_is_valid("server_error") { ok = false; }
  if !oauth_authz_error_is_valid("server_error") { ok = false; }
  if !oauth_token_error_is_valid("invalid_grant") { ok = false; }
  if oauth_max_json_bytes() != 65536 { ok = false; }
  let ver = oauth_version();
  if !streq(ver, "0.1.0") { ok = false; }
  return assert(ok, "predicates and limits: registered values, accessors, version");
}

fn t25() -> TestResult {
  var ok = true;
  var scope = Vec[Str].new();
  scope.push("read");
  let rr = oauth_authz_request("token", "cid", "", &scope, "st", RFC7636_S256, "S256");
  if !rr.is_ok { ok = false; }
  if rr.is_ok {
    let req = rr.value;
    let enc = oauth_authz_request_encode(&req);
    let want = "response_type=token&client_id=cid&scope=read&state=st&code_challenge=" + RFC7636_S256 + "&code_challenge_method=S256";
    if !enc.is_ok { ok = false; }
    if enc.is_ok {
      let ev: Str = enc.value;
      if !streq(ev, want) { ok = false; }
      let back = oauth_authz_request_parse(ev);
      if !back.is_ok { ok = false; }
      if back.is_ok {
        let r2 = back.value;
        let rt2: Str = r2.response_type;
        let cc2: Str = r2.code_challenge;
        let cm2: Str = r2.code_challenge_method;
        if !streq(rt2, "token") { ok = false; }
        if !streq(cc2, RFC7636_S256) { ok = false; }
        if !streq(cm2, "S256") { ok = false; }
      }
    }
  }
  let e1 = oauth_authz_request("code", "", "", &scope, "", "", "");
  if e1.is_ok { ok = false; } else { let m: Str = e1.error; if !streq(m, "oauth: empty client_id") { ok = false; } }
  let e2 = oauth_authz_request("code", "c", "", &scope, "", RFC7636_S256, "S512");
  if e2.is_ok { ok = false; } else { let m2: Str = e2.error; if !streq(m2, "oauth: unsupported code_challenge_method: S512") { ok = false; } }
  let e3 = oauth_authz_request("c0de", "c", "", &scope, "", "", "");
  if e3.is_ok { ok = false; } else { let m3: Str = e3.error; if !streq(m3, "oauth: unsupported response_type: c0de") { ok = false; } }
  var sc2 = Vec[Str].new();
  let rr2 = oauth_token_request("client_credentials", "", "", "", &sc2, "", "");
  if !rr2.is_ok { ok = false; }
  if rr2.is_ok {
    var req2 = rr2.value;
    let xe = oauth_token_request_add_extra(&mut req2, "audience", "api");
    if !xe.is_ok { ok = false; }
    let xe2 = oauth_token_request_add_extra(&mut req2, "grant_type", "x");
    if xe2.is_ok { ok = false; }
    let enc2 = oauth_token_request_encode(&req2);
    if !enc2.is_ok { ok = false; }
    if enc2.is_ok {
      let ev2: Str = enc2.value;
      if !streq(ev2, "grant_type=client_credentials&audience=api") { ok = false; }
      let back2 = oauth_token_request_parse(ev2);
      if !back2.is_ok { ok = false; }
      if back2.is_ok {
        let p2 = back2.value;
        let ex2: OAuthParams = p2.extra;
        if oauth_params_count(&ex2) != 1 { ok = false; }
        let n2: Str = oauth_params_name_at(&ex2, 0);
        let v2: Str = oauth_params_value_at(&ex2, 0);
        if !streq(n2, "audience") { ok = false; }
        if !streq(v2, "api") { ok = false; }
      }
    }
  }
  sc2.push("read");
  let rr3 = oauth_authz_request("code", "cid", "", &sc2, "", "", "");
  if !rr3.is_ok { ok = false; }
  if rr3.is_ok {
    let req3 = rr3.value;
    let sc3: Vec[Str] = req3.scope;
    if sc3.len() != 1 { ok = false; }
    if sc3.len() == 1 {
      let t0: Str = sc3[0];
      if !streq(t0, "read") { ok = false; }
    }
    sc2.push("late");
    if sc3.len() != 1 { ok = false; }
    let sc4: Vec[Str] = req3.scope;
    if sc4.len() != 1 { ok = false; }
  }
  return assert(ok, "builders own their scope: constructor/parse copies, extras round-trip");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.oauth conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.oauth: all tests passed");
  } else {
    io.println("xiom.oauth: tests failed");
  }
  return failed;
}
