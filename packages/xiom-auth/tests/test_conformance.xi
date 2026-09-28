// XIOM -- xiom.auth conformance tests (24 checks)
// Port task: prove the HTTP authentication header codecs (RFC 7235 / 7617 /
// 7616 / 6750) against the rules documented in SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 9. Every check is a named
// assert(cond, "name") call, one fn per check, and main returns the failure
// count (0 = green).
//
// BUG 17 discipline: all Str equality goes through
// xiom.string.compare.str_compare (never `==`), every Vec[Str] element read
// is bound to a typed local first, and every Vec[UInt8] element read is
// widened with `(x as Int) & 0xFF`.

module auth_tests
use xiom.io; use xiom.test; use xiom.auth;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn strs_eq(a: Vec[Str], b: Vec[Str]) -> Bool {
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

fn one(s: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(s);
  return v;
}

fn two(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn three(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn hdr_of(v: Str) -> Result[AuthHeader, Str] {
  return auth_parse_authorization(v);
}

fn hdr_err_is(r: Result[AuthHeader, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn cls_err_is(r: Result[AuthChallenges, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn ok_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

fn basic_err_is(r: Result[BasicCredentials, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn dc_err_is(r: Result[DigestChallenge, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn dr_err_is(r: Result[DigestResponse, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn bc_err_is(r: Result[BearerChallenge, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn strs_err_is(r: Result[Vec[Str], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn dc_new(realm: Str, nonce: Str) -> DigestChallenge {
  return DigestChallenge{
    realm: realm,
    nonce: nonce,
    algorithm: "",
    qop: Vec[Str].new(),
    opaque: "",
    stale: 0,
    domain: Vec[Str].new(),
    userhash: 0,
    charset: ""
  };
}

fn dr_new(username: Str, realm: Str, nonce: Str, uri: Str, digest: Str) -> DigestResponse {
  return DigestResponse{
    username: username,
    username_star: 0,
    realm: realm,
    realm_star: 0,
    nonce: nonce,
    nonce_star: 0,
    uri: uri,
    response: digest,
    algorithm: "",
    qop: "",
    nc: "",
    cnonce: "",
    opaque: "",
    userhash: 0
  };
}

fn bc_new(realm: Str) -> BearerChallenge {
  return BearerChallenge{
    realm: realm,
    scope: Vec[Str].new(),
    error: "",
    error_present: 0,
    error_description: "",
    error_uri: ""
  };
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = ok_str_is(auth_basic_encode("user", "pass"), "Basic dXNlcjpwYXNz");
  if !ok_str_is(auth_basic_encode("a", "b"), "Basic YTpi") { ok = false; }
  if !ok_str_is(auth_basic_encode("ab", "c"), "Basic YWI6Yw==") { ok = false; }
  if !ok_str_is(auth_basic_encode("abc", "d"), "Basic YWJjOmQ=") { ok = false; }
  return assert(ok, "basic encode: none/one/two padding variants");
}

fn t2() -> TestResult {
  var ok = true;
  let r1 = auth_basic_decode("dXNlcjpwYXNz");
  if !r1.is_ok { ok = false; } else {
    let c: BasicCredentials = r1.value;
    if !streq(c.user, "user") { ok = false; }
    if !streq(c.password, "pass") { ok = false; }
  }
  let r2 = auth_basic_decode("YTpi");
  if !r2.is_ok { ok = false; } else {
    let c2: BasicCredentials = r2.value;
    if !streq(c2.user, "a") { ok = false; }
    if !streq(c2.password, "b") { ok = false; }
  }
  let r3 = auth_basic_decode("YWI6Yw==");
  if !r3.is_ok { ok = false; } else {
    let c3: BasicCredentials = r3.value;
    if !streq(c3.user, "ab") { ok = false; }
    if !streq(c3.password, "c") { ok = false; }
  }
  let r4 = auth_basic_decode("YWJjOmQ=");
  if !r4.is_ok { ok = false; } else {
    let c4: BasicCredentials = r4.value;
    if !streq(c4.user, "abc") { ok = false; }
    if !streq(c4.password, "d") { ok = false; }
  }
  return assert(ok, "basic decode: round-trips all padding variants");
}

fn t3() -> TestResult {
  var ok = basic_err_is(auth_basic_decode("dXNlcg=="), "auth: basic credentials missing colon separator");
  if !basic_err_is(auth_basic_decode("!!!!"), "auth: basic invalid base64") { ok = false; }
  if !str_err_is(auth_basic_encode("us:er", "pw"), "auth: basic user-id contains ':' at offset 2") { ok = false; }
  if !str_err_is(auth_basic_encode("u\n", "pw"), "auth: basic user-id contains control character at offset 1") { ok = false; }
  let tol = auth_basic_decode("YTpiOmM=");
  if !tol.is_ok { ok = false; } else {
    let c: BasicCredentials = tol.value;
    if !streq(c.user, "a") { ok = false; }
    if !streq(c.password, "b:c") { ok = false; }
  }
  if !basic_err_is(auth_basic_decode_strict("YTpiOmM="), "auth: basic password contains ':' (strict) at offset 1") { ok = false; }
  if !auth_basic_decode_strict("YTpi").is_ok { ok = false; }
  return assert(ok, "basic colon rules: missing colon, user colon, extra colon, CTL");
}

fn t4() -> TestResult {
  var ok = false;
  let r = auth_basic_parse("Basic dXNlcjpwYXNz");
  if r.is_ok {
    let c: BasicCredentials = r.value;
    if streq(c.user, "user") {
      if streq(c.password, "pass") {
        ok = true;
      }
    }
  }
  let r2 = auth_basic_parse("bAsIc YTpi");
  if !r2.is_ok { ok = false; } else {
    let c2: BasicCredentials = r2.value;
    if !streq(c2.user, "a") { ok = false; }
  }
  if !basic_err_is(auth_basic_parse("Basic"), "auth: Basic credentials must be a token68") { ok = false; }
  if !basic_err_is(auth_basic_parse("Basic realm=\"x\""), "auth: Basic credentials must be a token68") { ok = false; }
  if !basic_err_is(auth_basic_parse("Bearer abc"), "auth: authorization scheme is not Basic") { ok = false; }
  return assert(ok, "basic parse: full header, case-insensitive scheme, token68 required");
}

fn t5() -> TestResult {
  var ok = streq(auth_basic_charset_default(), "UTF-8");
  let hr = auth_parse_authorization("Basic realm=\"x\", charset=\"UTF-8\"");
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    if !streq(auth_basic_charset(&h), "UTF-8") { ok = false; }
    if !auth_basic_charset_ok(&h) { ok = false; }
  }
  let hr2 = auth_parse_authorization("Basic realm=\"x\", charset=\"utf-8\"");
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    if !auth_basic_charset_ok(&h2) { ok = false; }
  }
  let hr3 = auth_parse_authorization("Basic realm=\"x\", charset=ISO-8859-1");
  if !hr3.is_ok { ok = false; } else {
    let h3: AuthHeader = hr3.value;
    if auth_basic_charset_ok(&h3) { ok = false; }
    if !streq(auth_basic_charset(&h3), "ISO-8859-1") { ok = false; }
  }
  let hr4 = auth_parse_authorization("Basic realm=\"x\"");
  if !hr4.is_ok { ok = false; } else {
    let h4: AuthHeader = hr4.value;
    if !streq(auth_basic_charset(&h4), "UTF-8") { ok = false; }
  }
  return assert(ok, "basic charset: UTF-8 default, case-insensitive, other rejected");
}

fn t6() -> TestResult {
  var ok = true;
  let v = "Basic dXNlcjpwYXNz";
  let hr = hdr_of(v);
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    if !streq(auth_header_scheme(&h), "Basic") { ok = false; }
    if auth_header_scheme_offset(&h) != 0 { ok = false; }
    if auth_header_start(&h) != 0 { ok = false; }
    if auth_header_end(&h) != 18 { ok = false; }
    if auth_header_consumed(&h) != 18 { ok = false; }
    if !auth_header_uses_token68(&h) { ok = false; }
    if !streq(auth_header_token68(&h), "dXNlcjpwYXNz") { ok = false; }
    if auth_header_token68_offset(&h) != 6 { ok = false; }
    if auth_header_param_count(&h) != 0 { ok = false; }
    if !streq(auth_header_slice(v, &h), v) { ok = false; }
    if !streq(auth_header_cred_slice(v, &h), "dXNlcjpwYXNz") { ok = false; }
  }
  let v2 = "Digest username=\"Mufasa\", realm=\"testrealm@host.com\"";
  let hr2 = hdr_of(v2);
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    if auth_header_param_count(&h2) != 2 { ok = false; }
    if !streq(auth_header_param_name(&h2, 0), "username") { ok = false; }
    if !streq(auth_header_param_value(&h2, 0), "Mufasa") { ok = false; }
    if !auth_header_param_is_quoted(&h2, 0) { ok = false; }
    if auth_header_param_offset(&h2, 0) != 7 { ok = false; }
    if auth_header_param_value_start(&h2, 0) != 16 { ok = false; }
    if auth_header_param_value_end(&h2, 0) != 24 { ok = false; }
    if !streq(auth_header_param_name(&h2, 1), "realm") { ok = false; }
    if auth_header_param_offset(&h2, 1) != 26 { ok = false; }
    if !auth_header_param_has(&h2, "USERNAME") { ok = false; }
    let g = auth_header_param_get(&h2, "Realm");
    if !g.is_ok { ok = false; } else {
      let gv: Str = g.value;
      if !streq(gv, "testrealm@host.com") { ok = false; }
    }
    if !streq(auth_header_slice(v2, &h2), v2) { ok = false; }
    if !streq(auth_header_cred_slice(v2, &h2), "username=\"Mufasa\", realm=\"testrealm@host.com\"") { ok = false; }
  }
  if !hdr_err_is(hdr_of("Basic abc def"), "auth: unexpected trailing characters at offset 10") { ok = false; }
  return assert(ok, "generic grammar: token68, params, spans, case-insensitive lookup");
}

fn t7() -> TestResult {
  var ok = true;
  let v = "Digest realm=\"a\\\"b\", nonce=\"c\\\\d\"";
  let hr = hdr_of(v);
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    if !streq(auth_header_param_value(&h, 0), "a\"b") { ok = false; }
    if !streq(auth_header_param_value(&h, 1), "c\\d") { ok = false; }
    if auth_header_param_value_start(&h, 0) != 13 { ok = false; }
    if auth_header_param_value_end(&h, 0) != 19 { ok = false; }
    if !auth_header_param_is_quoted(&h, 1) { ok = false; }
  }
  if !hdr_err_is(hdr_of("Digest realm=\"abc"), "auth: unterminated quoted-string at offset 13") { ok = false; }
  if !hdr_err_is(hdr_of("Digest realm=\"a\\"), "auth: truncated quoted-pair at offset 15") { ok = false; }
  if !hdr_err_is(hdr_of("Digest realm=\"a\nb\""), "auth: invalid character in quoted-string at offset 15") { ok = false; }
  return assert(ok, "quoted-string: escaped quote/backslash decode; malformed forms error");
}

fn t8() -> TestResult {
  var ok = hdr_err_is(hdr_of("Digest realm\"x"), "auth: expected '=' after parameter name at offset 12");
  if !hdr_err_is(hdr_of("Digest realm = "), "auth: expected parameter value at offset 15") { ok = false; }
  if !hdr_err_is(hdr_of("Digest =x"), "auth: expected parameter name at offset 7") { ok = false; }
  if !hdr_err_is(hdr_of("Digest realm=\"a\" junk"), "auth: expected ',' between parameters at offset 17") { ok = false; }
  if !hdr_err_is(hdr_of(""), "auth: expected auth-scheme at offset 0") { ok = false; }
  if !hdr_err_is(hdr_of("   "), "auth: expected auth-scheme at offset 3") { ok = false; }
  if !hdr_err_is(hdr_of("Digest realm=\"a\","), "auth: expected parameter name at offset 17") { ok = false; }
  let r0 = hdr_of("Digest realm");
  if !r0.is_ok { ok = false; } else {
    let h0: AuthHeader = r0.value;
    if !auth_header_uses_token68(&h0) { ok = false; }
    if !streq(auth_header_token68(&h0), "realm") { ok = false; }
  }
  let r1 = hdr_of("Basic abc=def");
  if !r1.is_ok { ok = false; } else {
    let h1: AuthHeader = r1.value;
    if auth_header_uses_token68(&h1) { ok = false; }
    if auth_header_param_count(&h1) != 1 { ok = false; }
    if !streq(auth_header_param_value(&h1, 0), "def") { ok = false; }
  }
  let r2 = hdr_of("Basic abc==");
  if !r2.is_ok { ok = false; } else {
    let h2: AuthHeader = r2.value;
    if !auth_header_uses_token68(&h2) { ok = false; }
    if !streq(auth_header_token68(&h2), "abc==") { ok = false; }
  }
  let r3 = hdr_of("Basic abc=");
  if !r3.is_ok { ok = false; } else {
    let h3: AuthHeader = r3.value;
    if !streq(auth_header_token68(&h3), "abc=") { ok = false; }
  }
  let r4 = hdr_of("Basic realm = \"x\"");
  if !r4.is_ok { ok = false; } else {
    let h4: AuthHeader = r4.value;
    if auth_header_param_count(&h4) != 1 { ok = false; }
    if !streq(auth_header_param_value(&h4, 0), "x") { ok = false; }
  }
  return assert(ok, "parameter errors carry offsets; token68/param disambiguation");
}

fn t9() -> TestResult {
  var ok = true;
  let v = "Newauth realm=\"apps\", type=1, title=\"Login to \\\"apps\\\"\", Basic realm=\"simple\"";
  let cr = auth_parse_www_authenticate(v);
  if !cr.is_ok { ok = false; } else {
    let l: AuthChallenges = cr.value;
    if auth_challenge_count(&l) != 2 { ok = false; }
    if !streq(auth_challenge_scheme(&l, 0), "Newauth") { ok = false; }
    if auth_challenge_param_count(&l, 0) != 3 { ok = false; }
    if !streq(auth_challenge_param_name(&l, 0, 1), "type") { ok = false; }
    if !streq(auth_challenge_param_value(&l, 0, 1), "1") { ok = false; }
    if !streq(auth_challenge_param_value(&l, 0, 2), "Login to \"apps\"") { ok = false; }
    if !streq(auth_challenge_slice(v, &l, 0), "Newauth realm=\"apps\", type=1, title=\"Login to \\\"apps\\\"\"") { ok = false; }
    if !streq(auth_challenge_scheme(&l, 1), "Basic") { ok = false; }
    if auth_challenge_param_count(&l, 1) != 1 { ok = false; }
    if !streq(auth_challenge_param_value(&l, 1, 0), "simple") { ok = false; }
    if !streq(auth_challenge_slice(v, &l, 1), "Basic realm=\"simple\"") { ok = false; }
    if auth_challenge_pick(&l, "Basic") != 1 { ok = false; }
    if auth_challenge_pick(&l, "basic") != 1 { ok = false; }
    if auth_challenge_pick(&l, "Digest") != -1 { ok = false; }
    let g = auth_challenge_param_get(&l, 0, "TYPE");
    if !g.is_ok { ok = false; } else {
      let gv: Str = g.value;
      if !streq(gv, "1") { ok = false; }
    }
    if auth_challenge_consumed(&l, 1) != 20 { ok = false; }
  }
  return assert(ok, "www-authenticate: RFC 7235 example splits into two challenges");
}

fn t10() -> TestResult {
  var ok = true;
  let c1 = auth_parse_www_authenticate("Basic realm=\"a\", stale = true");
  if !c1.is_ok { ok = false; } else {
    let l1: AuthChallenges = c1.value;
    if auth_challenge_count(&l1) != 1 { ok = false; }
    if auth_challenge_param_count(&l1, 0) != 2 { ok = false; }
    if !streq(auth_challenge_param_name(&l1, 0, 1), "stale") { ok = false; }
    if !streq(auth_challenge_param_value(&l1, 0, 1), "true") { ok = false; }
  }
  let c2 = auth_parse_www_authenticate("Negotiate abc, Basic realm=\"x\"");
  if !c2.is_ok { ok = false; } else {
    let l2: AuthChallenges = c2.value;
    if auth_challenge_count(&l2) != 2 { ok = false; }
    if !auth_challenge_uses_token68(&l2, 0) { ok = false; }
    if !streq(auth_challenge_token68(&l2, 0), "abc") { ok = false; }
    if !streq(auth_challenge_scheme(&l2, 1), "Basic") { ok = false; }
  }
  let c3 = auth_parse_www_authenticate("Negotiate, NTLM");
  if !c3.is_ok { ok = false; } else {
    let l3: AuthChallenges = c3.value;
    if auth_challenge_count(&l3) != 2 { ok = false; }
    if auth_challenge_uses_token68(&l3, 0) { ok = false; }
    if !streq(auth_challenge_scheme(&l3, 1), "NTLM") { ok = false; }
  }
  let c4 = auth_parse_www_authenticate("Digest realm=\"a\", qop = \"auth\"");
  if !c4.is_ok { ok = false; } else {
    let l4: AuthChallenges = c4.value;
    if auth_challenge_count(&l4) != 1 { ok = false; }
    if auth_challenge_param_count(&l4, 0) != 2 { ok = false; }
    if !streq(auth_challenge_param_value(&l4, 0, 1), "auth") { ok = false; }
  }
  let c5 = auth_parse_www_authenticate("Basic realm=\"a\", Basic realm=\"b\"");
  if !c5.is_ok { ok = false; } else {
    let l5: AuthChallenges = c5.value;
    if auth_challenge_count(&l5) != 2 { ok = false; }
  }
  if !cls_err_is(auth_parse_www_authenticate(""), "auth: expected challenge at offset 0") { ok = false; }
  if !cls_err_is(auth_parse_www_authenticate("Basic realm=\"a\","), "auth: expected parameter name at offset 16") { ok = false; }
  return assert(ok, "challenge boundaries: token SP credentials vs parameter continuation");
}

fn t11() -> TestResult {
  var ok = true;
  let v = "Digest realm=\"testrealm@host.com\", qop=\"auth,auth-int\", nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\", opaque=\"5ccc069c403ebaf9f0171e9517f40e41\", algorithm=SHA-256, stale=true, domain=\"a.example b.example\", userhash=true, charset=UTF-8";
  let hr = auth_parse_authorization(v);
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    let cr = auth_digest_parse_challenge(&h);
    if !cr.is_ok { ok = false; } else {
      let c: DigestChallenge = cr.value;
      if !streq(c.realm, "testrealm@host.com") { ok = false; }
      if !streq(c.nonce, "dcd98b7102dd2f0e8b11d0f600bfb0c093") { ok = false; }
      if !strs_eq(c.qop, two("auth", "auth-int")) { ok = false; }
      if !streq(c.algorithm, "SHA-256") { ok = false; }
      if !streq(c.opaque, "5ccc069c403ebaf9f0171e9517f40e41") { ok = false; }
      if c.stale != 1 { ok = false; }
      if !strs_eq(c.domain, two("a.example", "b.example")) { ok = false; }
      if c.userhash != 1 { ok = false; }
      if !streq(c.charset, "UTF-8") { ok = false; }
    }
  }
  let hr2 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", qop=\"auth, auth-int\"");
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    let cr2 = auth_digest_parse_challenge(&h2);
    if !cr2.is_ok { ok = false; } else {
      let c2: DigestChallenge = cr2.value;
      if c2.qop.len() != 2 { ok = false; }
    }
  }
  let hr3 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\"");
  if !hr3.is_ok { ok = false; } else {
    let h3: AuthHeader = hr3.value;
    let cr3 = auth_digest_parse_challenge(&h3);
    if !cr3.is_ok { ok = false; } else {
      let c3: DigestChallenge = cr3.value;
      if c3.algorithm.len() != 0 { ok = false; }
      if c3.qop.len() != 0 { ok = false; }
      if c3.stale != 0 { ok = false; }
      if c3.charset.len() != 0 { ok = false; }
    }
  }
  let hr4 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", algorithm=SHA-512");
  if !hr4.is_ok { ok = false; } else {
    let h4: AuthHeader = hr4.value;
    if !dc_err_is(auth_digest_parse_challenge(&h4), "auth: digest unknown algorithm: SHA-512") { ok = false; }
  }
  let hr5 = auth_parse_authorization("Digest nonce=\"n\"");
  if !hr5.is_ok { ok = false; } else {
    let h5: AuthHeader = hr5.value;
    if !dc_err_is(auth_digest_parse_challenge(&h5), "auth: digest challenge missing realm") { ok = false; }
  }
  let hr6 = auth_parse_authorization("Digest realm=\"r\"");
  if !hr6.is_ok { ok = false; } else {
    let h6: AuthHeader = hr6.value;
    if !dc_err_is(auth_digest_parse_challenge(&h6), "auth: digest challenge missing nonce") { ok = false; }
  }
  let hr7 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", stale=maybe");
  if !hr7.is_ok { ok = false; } else {
    let h7: AuthHeader = hr7.value;
    if !dc_err_is(auth_digest_parse_challenge(&h7), "auth: digest invalid stale value: maybe") { ok = false; }
  }
  let hr8 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", qop=\"\"");
  if !hr8.is_ok { ok = false; } else {
    let h8: AuthHeader = hr8.value;
    if !dc_err_is(auth_digest_parse_challenge(&h8), "auth: digest qop list is empty") { ok = false; }
  }
  let hr9 = auth_parse_authorization("Basic realm=\"r\"");
  if !hr9.is_ok { ok = false; } else {
    let h9: AuthHeader = hr9.value;
    if !dc_err_is(auth_digest_parse_challenge(&h9), "auth: challenge scheme is not Digest") { ok = false; }
  }
  return assert(ok, "digest challenge: full, minimal, spaces, errors");
}

fn t12() -> TestResult {
  var ok = auth_digest_algorithm_is_valid("MD5");
  if !auth_digest_algorithm_is_valid("md5-sess") { ok = false; }
  if !auth_digest_algorithm_is_valid("SHA-256") { ok = false; }
  if !auth_digest_algorithm_is_valid("sha-256-SESS") { ok = false; }
  if !auth_digest_algorithm_is_valid("SHA-512-256") { ok = false; }
  if !auth_digest_algorithm_is_valid("SHA-512-256-sess") { ok = false; }
  if auth_digest_algorithm_is_valid("SHA-512") { ok = false; }
  if !streq(auth_digest_algorithm_canonical("sha-512-256-sess"), "SHA-512-256-sess") { ok = false; }
  if !streq(auth_digest_algorithm_canonical("Md5"), "MD5") { ok = false; }
  if !streq(auth_digest_algorithm_canonical("SHA-512"), "") { ok = false; }
  if !auth_digest_algorithm_is_sess("MD5-sess") { ok = false; }
  if auth_digest_algorithm_is_sess("MD5") { ok = false; }
  if auth_digest_response_hex_len("MD5") != 32 { ok = false; }
  if auth_digest_response_hex_len("SHA-256") != 64 { ok = false; }
  if auth_digest_response_hex_len("SHA-512-256-sess") != 64 { ok = false; }
  if auth_digest_response_hex_len("bogus") != 0 { ok = false; }
  if !streq(auth_digest_algorithm_default(), "MD5") { ok = false; }
  if !auth_digest_qop_is_valid("auth") { ok = false; }
  if !auth_digest_qop_is_valid("auth-int") { ok = false; }
  if auth_digest_qop_is_valid("auth-conf") { ok = false; }
  return assert(ok, "digest algorithm table: six names, canonical, sess, hex lengths");
}

fn t13() -> TestResult {
  var ok = true;
  let hr = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", qop=\"auth,auth-int\"");
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    let cr = auth_digest_parse_challenge(&h);
    if !cr.is_ok { ok = false; } else {
      let c: DigestChallenge = cr.value;
      if !auth_digest_qop_offered(&c, "auth-int") { ok = false; }
      if auth_digest_qop_offered(&c, "bogus") { ok = false; }
      if !ok_str_is(auth_digest_pick_qop(&c, two("auth-int", "auth")), "auth-int") { ok = false; }
      if !ok_str_is(auth_digest_pick_qop(&c, one("AUTH")), "AUTH") { ok = false; }
      if !str_err_is(auth_digest_pick_qop(&c, one("bogus")), "auth: digest no preferred qop is offered") { ok = false; }
    }
  }
  let hr2 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\"");
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    let cr2 = auth_digest_parse_challenge(&h2);
    if !cr2.is_ok { ok = false; } else {
      let c2: DigestChallenge = cr2.value;
      if !str_err_is(auth_digest_pick_qop(&c2, one("auth")), "auth: digest challenge offers no qop") { ok = false; }
    }
  }
  let qr = auth_digest_qop_tokens("auth, auth-int");
  if !qr.is_ok { ok = false; } else {
    let qv: Vec[Str] = qr.value;
    if !strs_eq(qv, two("auth", "auth-int")) { ok = false; }
  }
  if !strs_err_is(auth_digest_qop_tokens("auth,,auth-int"), "auth: digest qop token is empty at offset 5") { ok = false; }
  return assert(ok, "digest qop: offer list parse, pick-one rule, errors");
}

fn t14() -> TestResult {
  var ok = true;
  var c = dc_new("test", "abc");
  c.algorithm = "MD5";
  c.qop = one("auth");
  if !ok_str_is(auth_digest_challenge_build(&c), "Digest realm=\"test\", nonce=\"abc\", algorithm=MD5, qop=\"auth\"") { ok = false; }
  let hr = auth_parse_authorization("Digest realm=\"a\\\"b\\\\c\", nonce=\"n\"");
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    let cr = auth_digest_parse_challenge(&h);
    if !cr.is_ok { ok = false; } else {
      let c2: DigestChallenge = cr.value;
      let br2 = auth_digest_challenge_build(&c2);
      if !br2.is_ok { ok = false; } else {
        let v2: Str = br2.value;
        let hr2 = auth_parse_authorization(v2);
        if !hr2.is_ok { ok = false; } else {
          let h2: AuthHeader = hr2.value;
          let cr2 = auth_digest_parse_challenge(&h2);
          if !cr2.is_ok { ok = false; } else {
            let c3: DigestChallenge = cr2.value;
            if !streq(c3.realm, "a\"b\\c") { ok = false; }
            if !streq(c3.nonce, "n") { ok = false; }
          }
        }
      }
    }
  }
  var bad = dc_new("", "n");
  if !str_err_is(auth_digest_challenge_build(&bad), "auth: digest challenge realm is empty") { ok = false; }
  var bad_alg = dc_new("r", "n");
  bad_alg.algorithm = "BOGUS";
  if !str_err_is(auth_digest_challenge_build(&bad_alg), "auth: digest unknown algorithm: BOGUS") { ok = false; }
  var domc = dc_new("r", "n");
  domc.domain = one("a b");
  if !str_err_is(auth_digest_challenge_build(&domc), "auth: digest domain element is empty or contains a space") { ok = false; }
  var full = dc_new("realm x", "nonce y");
  full.algorithm = "SHA-512-256-sess";
  full.qop = two("auth-int", "auth");
  full.opaque = "opaque z";
  full.stale = 1;
  full.domain = two("https://a.example", "https://b.example");
  full.userhash = 1;
  full.charset = "UTF-8";
  let fbr = auth_digest_challenge_build(&full);
  if !fbr.is_ok { ok = false; } else {
    let fv: Str = fbr.value;
    let fhr = auth_parse_authorization(fv);
    if !fhr.is_ok { ok = false; } else {
      let fh: AuthHeader = fhr.value;
      let fcr = auth_digest_parse_challenge(&fh);
      if !fcr.is_ok { ok = false; } else {
        let fc: DigestChallenge = fcr.value;
        if !streq(fc.realm, "realm x") { ok = false; }
        if !streq(fc.algorithm, "SHA-512-256-sess") { ok = false; }
        if !strs_eq(fc.qop, two("auth-int", "auth")) { ok = false; }
        if !streq(fc.opaque, "opaque z") { ok = false; }
        if fc.stale != 1 { ok = false; }
        if !strs_eq(fc.domain, two("https://a.example", "https://b.example")) { ok = false; }
        if fc.userhash != 1 { ok = false; }
        if !streq(fc.charset, "UTF-8") { ok = false; }
      }
    }
  }
  return assert(ok, "digest challenge build: quotes, escapes, full round-trip");
}

fn t15() -> TestResult {
  var ok = true;
  let v = "Digest username=\"Mufasa\", realm=\"http-auth@example.org\", uri=\"/dir/index.html\", algorithm=SHA-256, nonce=\"7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v\", nc=00000001, cnonce=\"f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ\", qop=auth, response=\"753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1\", opaque=\"FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS\"";
  let hr = auth_parse_authorization(v);
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    let rr = auth_digest_parse_response(&h);
    if !rr.is_ok { ok = false; } else {
      let r: DigestResponse = rr.value;
      if !streq(r.username, "Mufasa") { ok = false; }
      if !streq(r.realm, "http-auth@example.org") { ok = false; }
      if !streq(r.uri, "/dir/index.html") { ok = false; }
      if !streq(r.algorithm, "SHA-256") { ok = false; }
      if !streq(r.qop, "auth") { ok = false; }
      if !streq(r.nc, "00000001") { ok = false; }
      if !streq(r.cnonce, "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ") { ok = false; }
      if r.username_star != 0 { ok = false; }
      if !streq(r.opaque, "FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS") { ok = false; }
      if !auth_digest_response_check(&r).is_ok { ok = false; }
    }
  }
  let hr2 = auth_parse_authorization("Digest username*=UTF-8''Ju%20rgen, realm=\"r\", nonce=\"n\", uri=\"/\", response=\"6629fae49393a05397450978507c4ef1\"");
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    let rr2 = auth_digest_parse_response(&h2);
    if !rr2.is_ok { ok = false; } else {
      let r2: DigestResponse = rr2.value;
      if r2.username_star != 1 { ok = false; }
      if !ok_str_is(auth_digest_ext_decode(r2.username), "Ju rgen") { ok = false; }
    }
  }
  let hr3 = auth_parse_authorization("Digest username=\"x\", username*=\"y\", realm=\"r\", nonce=\"n\", uri=\"/\", response=\"6629fae49393a05397450978507c4ef1\"");
  if !hr3.is_ok { ok = false; } else {
    let h3: AuthHeader = hr3.value;
    if !dr_err_is(auth_digest_parse_response(&h3), "auth: digest response has both username and username*") { ok = false; }
  }
  let hr4 = auth_parse_authorization("Digest username=\"x\", realm=\"r\", nonce=\"n\", response=\"6629fae49393a05397450978507c4ef1\"");
  if !hr4.is_ok { ok = false; } else {
    let h4: AuthHeader = hr4.value;
    if !dr_err_is(auth_digest_parse_response(&h4), "auth: digest response missing uri") { ok = false; }
  }
  let hr5 = auth_parse_authorization("Digest username=\"x\", realm=\"r\", nonce=\"n\", uri=\"/\", qop=\"auth,auth-int\", response=\"6629fae49393a05397450978507c4ef1\"");
  if !hr5.is_ok { ok = false; } else {
    let h5: AuthHeader = hr5.value;
    if !dr_err_is(auth_digest_parse_response(&h5), "auth: digest response qop must be a single token") { ok = false; }
  }
  return assert(ok, "digest response: full example, extended username*, errors");
}

fn t16() -> TestResult {
  var ok = true;
  let good = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  if !auth_digest_response_check(&good).is_ok { ok = false; }
  let bad_uri = dr_new("u", "r", "n", "", "d41d8cd98f00b204e9800998ecf8427e");
  if !str_err_is(auth_digest_response_check(&bad_uri), "auth: digest response missing uri") { ok = false; }
  var bad_nc = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  bad_nc.nc = "123";
  if !str_err_is(auth_digest_response_check(&bad_nc), "auth: digest nc must be 8 hex digits") { ok = false; }
  var nc_letters = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  nc_letters.nc = "0000000z";
  if !str_err_is(auth_digest_response_check(&nc_letters), "auth: digest nc must be 8 hex digits") { ok = false; }
  var qop_nc = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  qop_nc.qop = "auth";
  qop_nc.cnonce = "c";
  if !str_err_is(auth_digest_response_check(&qop_nc), "auth: digest nc required with qop") { ok = false; }
  var qop_cn = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  qop_cn.qop = "auth";
  qop_cn.nc = "00000001";
  if !str_err_is(auth_digest_response_check(&qop_cn), "auth: digest cnonce required with qop") { ok = false; }
  var qop_bad = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  qop_bad.qop = "bogus";
  qop_bad.nc = "00000001";
  qop_bad.cnonce = "c";
  if !str_err_is(auth_digest_response_check(&qop_bad), "auth: digest unknown qop: bogus") { ok = false; }
  var sha_short = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  sha_short.algorithm = "SHA-256";
  if !str_err_is(auth_digest_response_check(&sha_short), "auth: digest response digest length mismatch") { ok = false; }
  let non_hex = dr_new("u", "r", "n", "/", "z41d8cd98f00b204e9800998ecf8427e");
  if !str_err_is(auth_digest_response_check(&non_hex), "auth: digest response digest is not hexadecimal") { ok = false; }
  let missing = dr_new("", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
  if !str_err_is(auth_digest_response_check(&missing), "auth: digest response missing username") { ok = false; }
  return assert(ok, "digest response check: required fields, nc shape, qop rules");
}

fn t17() -> TestResult {
  var ok = true;
  let hr = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", qop=\"auth\", algorithm=MD5");
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    let cr = auth_digest_parse_challenge(&h);
    if !cr.is_ok { ok = false; } else {
      let c: DigestChallenge = cr.value;
      var r = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      r.qop = "auth";
      r.nc = "00000001";
      r.cnonce = "abc";
      if !auth_digest_validate_response(&r, &c).is_ok { ok = false; }
      var r_realm = dr_new("u", "other", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      r_realm.qop = "auth";
      r_realm.nc = "00000001";
      r_realm.cnonce = "abc";
      if !str_err_is(auth_digest_validate_response(&r_realm, &c), "auth: digest response realm mismatch") { ok = false; }
      var r_nonce = dr_new("u", "r", "x", "/", "d41d8cd98f00b204e9800998ecf8427e");
      r_nonce.qop = "auth";
      r_nonce.nc = "00000001";
      r_nonce.cnonce = "abc";
      if !str_err_is(auth_digest_validate_response(&r_nonce, &c), "auth: digest response nonce mismatch") { ok = false; }
      var r_algo = dr_new("u", "r", "n", "/", "753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1");
      r_algo.algorithm = "SHA-256";
      r_algo.qop = "auth";
      r_algo.nc = "00000001";
      r_algo.cnonce = "abc";
      if !str_err_is(auth_digest_validate_response(&r_algo, &c), "auth: digest algorithm mismatch") { ok = false; }
      let r_noqop = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      if !str_err_is(auth_digest_validate_response(&r_noqop, &c), "auth: digest qop required: challenge offered qop") { ok = false; }
      var r_other = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      r_other.qop = "auth-int";
      r_other.nc = "00000001";
      r_other.cnonce = "abc";
      if !str_err_is(auth_digest_validate_response(&r_other, &c), "auth: digest qop not offered: auth-int") { ok = false; }
      var r_uh = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      r_uh.qop = "auth";
      r_uh.nc = "00000001";
      r_uh.cnonce = "abc";
      r_uh.userhash = 1;
      if !str_err_is(auth_digest_validate_response(&r_uh, &c), "auth: digest userhash not offered") { ok = false; }
    }
  }
  let hr2 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\"");
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    let cr2 = auth_digest_parse_challenge(&h2);
    if !cr2.is_ok { ok = false; } else {
      let c2: DigestChallenge = cr2.value;
      let r2 = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      if !auth_digest_validate_response(&r2, &c2).is_ok { ok = false; }
      var r2q = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      r2q.qop = "auth";
      r2q.nc = "00000001";
      r2q.cnonce = "abc";
      if !str_err_is(auth_digest_validate_response(&r2q, &c2), "auth: digest qop sent but challenge offered none") { ok = false; }
    }
  }
  let hr3 = auth_parse_authorization("Digest realm=\"r\", nonce=\"n\", userhash=true");
  if !hr3.is_ok { ok = false; } else {
    let h3: AuthHeader = hr3.value;
    let cr3 = auth_digest_parse_challenge(&h3);
    if !cr3.is_ok { ok = false; } else {
      let c3: DigestChallenge = cr3.value;
      let r3 = dr_new("u", "r", "n", "/", "d41d8cd98f00b204e9800998ecf8427e");
      if !str_err_is(auth_digest_validate_response(&r3, &c3), "auth: digest userhash required") { ok = false; }
    }
  }
  return assert(ok, "digest validate: realm/nonce/algorithm/qop/userhash against challenge");
}

fn t18() -> TestResult {
  var ok = ok_str_is(auth_bearer_token("Bearer YWJjZA=="), "YWJjZA==");
  if !ok_str_is(auth_bearer_token("bearer abc"), "abc") { ok = false; }
  if !str_err_is(auth_bearer_token("Bearer"), "auth: Bearer credentials must be a token68") { ok = false; }
  if !str_err_is(auth_bearer_token("Basic abc"), "auth: authorization scheme is not Bearer") { ok = false; }
  if !ok_str_is(auth_bearer_authorization("YWJjZA=="), "Bearer YWJjZA==") { ok = false; }
  if !str_err_is(auth_bearer_authorization(""), "auth: bearer token is empty") { ok = false; }
  if !str_err_is(auth_bearer_authorization("a b"), "auth: bearer token has invalid character at offset 1") { ok = false; }
  if !auth_bearer_token_check("a=").is_ok { ok = false; }
  if !str_err_is(auth_bearer_token_check("=a"), "auth: bearer token is not a token68") { ok = false; }
  return assert(ok, "bearer credentials: token68 parse/build and errors");
}

fn t19() -> TestResult {
  var ok = true;
  let hr = auth_parse_authorization("Bearer realm=\"example\"");
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    let br = auth_bearer_parse_challenge(&h);
    if !br.is_ok { ok = false; } else {
      let b: BearerChallenge = br.value;
      if !streq(b.realm, "example") { ok = false; }
      if b.error_present != 0 { ok = false; }
      if b.scope.len() != 0 { ok = false; }
    }
  }
  let hr2 = auth_parse_authorization("Bearer realm=\"example\", error=\"invalid_token\", error_description=\"The access token expired\", error_uri=\"https://example.com/errors\"");
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    let br2 = auth_bearer_parse_challenge(&h2);
    if !br2.is_ok { ok = false; } else {
      let b2: BearerChallenge = br2.value;
      if !streq(b2.error, "invalid_token") { ok = false; }
      if b2.error_present != 1 { ok = false; }
      if !streq(b2.error_description, "The access token expired") { ok = false; }
      if !streq(b2.error_uri, "https://example.com/errors") { ok = false; }
    }
  }
  let hr3 = auth_parse_authorization("Bearer scope=\"openid profile email\"");
  if !hr3.is_ok { ok = false; } else {
    let h3: AuthHeader = hr3.value;
    let br3 = auth_bearer_parse_challenge(&h3);
    if !br3.is_ok { ok = false; } else {
      let b3: BearerChallenge = br3.value;
      if !strs_eq(b3.scope, three("openid", "profile", "email")) { ok = false; }
    }
  }
  let hr4 = auth_parse_authorization("Bearer error=\"bogus\"");
  if !hr4.is_ok { ok = false; } else {
    let h4: AuthHeader = hr4.value;
    if !bc_err_is(auth_bearer_parse_challenge(&h4), "auth: bearer unknown error code: bogus") { ok = false; }
  }
  let hr5 = auth_parse_authorization("Bearer error_description=\"x\"");
  if !hr5.is_ok { ok = false; } else {
    let h5: AuthHeader = hr5.value;
    if !bc_err_is(auth_bearer_parse_challenge(&h5), "auth: bearer error_description without error") { ok = false; }
  }
  let hr6 = auth_parse_authorization("Bearer scope=\"openid  profile\"");
  if !hr6.is_ok { ok = false; } else {
    let h6: AuthHeader = hr6.value;
    if !bc_err_is(auth_bearer_parse_challenge(&h6), "auth: bearer scope has empty element at offset 7") { ok = false; }
  }
  let hr7 = auth_parse_authorization("Basic realm=\"x\"");
  if !hr7.is_ok { ok = false; } else {
    let h7: AuthHeader = hr7.value;
    if !bc_err_is(auth_bearer_parse_challenge(&h7), "auth: challenge scheme is not Bearer") { ok = false; }
  }
  return assert(ok, "bearer challenge: realm/scope/error forms and errors");
}

fn t20() -> TestResult {
  var ok = true;
  let c = bc_new("example");
  if !ok_str_is(auth_bearer_challenge_build(&c), "Bearer realm=\"example\"") { ok = false; }
  var full = bc_new("example");
  full.scope = two("openid", "profile");
  full.error = "insufficient_scope";
  full.error_present = 1;
  full.error_description = "Need more scope";
  full.error_uri = "https://example.com/scopes";
  let br = auth_bearer_challenge_build(&full);
  if !br.is_ok { ok = false; } else {
    let bv: Str = br.value;
    let hr = auth_parse_authorization(bv);
    if !hr.is_ok { ok = false; } else {
      let h: AuthHeader = hr.value;
      let brr = auth_bearer_parse_challenge(&h);
      if !brr.is_ok { ok = false; } else {
        let b2: BearerChallenge = brr.value;
        if !streq(b2.realm, "example") { ok = false; }
        if !strs_eq(b2.scope, two("openid", "profile")) { ok = false; }
        if !streq(b2.error, "insufficient_scope") { ok = false; }
        if !streq(b2.error_description, "Need more scope") { ok = false; }
        if !streq(b2.error_uri, "https://example.com/scopes") { ok = false; }
      }
    }
  }
  var desc = bc_new("r");
  desc.error_description = "x";
  if !str_err_is(auth_bearer_challenge_build(&desc), "auth: bearer error_description without error") { ok = false; }
  var uri = bc_new("r");
  uri.error_uri = "https://x";
  if !str_err_is(auth_bearer_challenge_build(&uri), "auth: bearer error_uri without error") { ok = false; }
  var badscope = bc_new("r");
  badscope.scope = one("");
  if !str_err_is(auth_bearer_challenge_build(&badscope), "auth: bearer scope token is empty or contains a space") { ok = false; }
  var badcode = bc_new("r");
  badcode.error = "bogus";
  badcode.error_present = 1;
  if !str_err_is(auth_bearer_challenge_build(&badcode), "auth: bearer unknown error code: bogus") { ok = false; }
  return assert(ok, "bearer challenge build: round-trip and validation errors");
}

fn t21() -> TestResult {
  var ok = true;
  let v = "Negotiate a87421000492aa874209af8bc028";
  let hr = hdr_of(v);
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    if !auth_header_uses_token68(&h) { ok = false; }
    if !streq(auth_header_token68(&h), "a87421000492aa874209af8bc028") { ok = false; }
    if !streq(auth_header_slice(v, &h), v) { ok = false; }
  }
  let v2 = "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-date, Signature=fe5f80f77d5fa3beca038a248ff027d0445342fe2855ddc963176630326f1024";
  let hr2 = hdr_of(v2);
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    if !streq(auth_header_scheme(&h2), "AWS4-HMAC-SHA256") { ok = false; }
    if auth_header_param_count(&h2) != 3 { ok = false; }
    if !streq(auth_header_param_name(&h2, 0), "Credential") { ok = false; }
    if !streq(auth_header_param_value(&h2, 0), "AKIDEXAMPLE/20130524/us-east-1/s3/aws4_request") { ok = false; }
    if auth_header_param_kind(&h2, 0) != 2 { ok = false; }
    if !streq(auth_header_param_value(&h2, 1), "host;range;x-amz-date") { ok = false; }
    if !streq(auth_header_slice(v2, &h2), v2) { ok = false; }
    if !streq(auth_header_cred_slice(v2, &h2), "Credential=AKIDEXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-date, Signature=fe5f80f77d5fa3beca038a248ff027d0445342fe2855ddc963176630326f1024") { ok = false; }
  }
  let hr3 = hdr_of("OtherScheme param=value");
  if !hr3.is_ok { ok = false; } else {
    let h3: AuthHeader = hr3.value;
    if !streq(auth_header_param_value(&h3, 0), "value") { ok = false; }
    if auth_header_param_kind(&h3, 0) != 0 { ok = false; }
  }
  return assert(ok, "other schemes preserved: token68 raw and relaxed AWS4 params");
}

fn t22() -> TestResult {
  var ok = true;
  let hr = hdr_of("Digest");
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    if auth_header_consumed(&h) != 6 { ok = false; }
    if auth_header_param_count(&h) != 0 { ok = false; }
    if auth_header_uses_token68(&h) { ok = false; }
  }
  if !hdr_err_is(hdr_of("@bad x"), "auth: expected auth-scheme at offset 0") { ok = false; }
  if !hdr_err_is(hdr_of("Digest realm=\"a\"x"), "auth: expected ',' between parameters at offset 16") { ok = false; }
  if !hdr_err_is(hdr_of("Basic abc\"def"), "auth: expected '=' after parameter name at offset 9") { ok = false; }
  let v = "Negotiate abc, Basic realm=\"x\"";
  let pa = auth_parse_header_at(v, 0);
  if !pa.is_ok { ok = false; } else {
    let h2: AuthHeader = pa.value;
    if auth_header_consumed(&h2) != 13 { ok = false; }
    if !streq(auth_header_token68(&h2), "abc") { ok = false; }
  }
  let pb = auth_parse_header_at(v, 15);
  if !pb.is_ok { ok = false; } else {
    let h3: AuthHeader = pb.value;
    if !streq(auth_header_scheme(&h3), "Basic") { ok = false; }
    if auth_header_consumed(&h3) != 15 { ok = false; }
  }
  if !hdr_err_is(auth_parse_header_at(v, 13), "auth: expected auth-scheme at offset 13") { ok = false; }
  if !hdr_err_is(auth_parse_header_at(v, 99), "auth: start offset out of range at offset 99") { ok = false; }
  return assert(ok, "parse-one header: consumed counts and offset errors");
}

fn t23() -> TestResult {
  var ok = true;
  let hr = hdr_of("Digest REALM=\"r\", Nonce=\"n\"");
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    if auth_header_param_index(&h, "realm") != 0 { ok = false; }
    if auth_header_param_index(&h, "NONCE") != 1 { ok = false; }
    if auth_header_param_index(&h, "opaque") != -1 { ok = false; }
    let g = auth_header_param_get(&h, "noNcE");
    if !g.is_ok { ok = false; } else {
      let gv: Str = g.value;
      if !streq(gv, "n") { ok = false; }
    }
  }
  let hr2 = hdr_of("Digest realm=abc");
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    if auth_header_param_kind(&h2, 0) != 0 { ok = false; }
    if auth_header_param_is_quoted(&h2, 0) { ok = false; }
  }
  return assert(ok, "parameter lookup is case-insensitive; kinds distinguish token/quoted/raw");
}

fn t24() -> TestResult {
  var ok = true;
  let v = "Basic dXNlcjpwYXNz  ";
  let hr = hdr_of(v);
  if !hr.is_ok { ok = false; } else {
    let h: AuthHeader = hr.value;
    if auth_header_start(&h) != 0 { ok = false; }
    if auth_header_end(&h) != 18 { ok = false; }
    if auth_header_consumed(&h) != 18 { ok = false; }
  }
  let v2 = "  Basic YTpi";
  let hr2 = hdr_of(v2);
  if !hr2.is_ok { ok = false; } else {
    let h2: AuthHeader = hr2.value;
    if auth_header_start(&h2) != 2 { ok = false; }
    if auth_header_consumed(&h2) != 10 { ok = false; }
    if !streq(auth_header_slice(v2, &h2), "Basic YTpi") { ok = false; }
  }
  let hr3 = hdr_of("Basic   ");
  if !hr3.is_ok { ok = false; } else {
    let h3: AuthHeader = hr3.value;
    if auth_header_consumed(&h3) != 5 { ok = false; }
    if auth_header_uses_token68(&h3) { ok = false; }
  }
  return assert(ok, "consumed counts exclude leading/trailing OWS; scheme-only is valid");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.auth conformance tests ===");
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
    io.println("xiom.auth: all tests passed");
  } else {
    io.println("xiom.auth: tests failed");
  }
  return failed;
}
