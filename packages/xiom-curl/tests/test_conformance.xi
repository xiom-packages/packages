// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.curl conformance tests (26 checks).
//
// All fixtures are inline strings; no external files. Str equality goes
// through xiom.string.compare.str_compare (BUG 17 / trap 1); Result payloads
// are bound to typed locals before use; every &mut call site is explicit.

module curl_tests
use xiom.io; use xiom.test; use xiom.curl;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn flag(b: Bool) -> Bool {
  if b {
    return true;
  }
  return false;
}

// True when curl_url_parse rejects `s` with an error starting with `prefix`.
fn url_err_starts(s: Str, prefix: Str) -> Bool {
  let r = curl_url_parse(s);
  if r.is_ok { return false; }
  let m: Str = r.error;
  return string.str_starts_with(m, prefix);
}

// --- URL parsing and normalization ----------------------------------------

fn t1() -> TestResult {
  let p = curl_url_parse("HTTP://Example.COM:8080/a/b?x=1#frag");
  if !p.is_ok { return assert(false, "url parse fields"); }
  let u: Url = p.value;
  let ok = streq(u.scheme, "http")
    && streq(u.host, "example.com")
    && u.port == 8080
    && flag(u.port_present)
    && streq(u.path, "/a/b")
    && streq(u.query, "x=1")
    && flag(u.query_present)
    && streq(u.fragment, "frag")
    && flag(u.fragment_present)
    && streq(curl_url_to_string(&u), "http://example.com:8080/a/b?x=1#frag");
  return assert(ok, "url parse fields");
}

fn t2() -> TestResult {
  let p = curl_url_parse("https://example.com");
  let q = curl_url_parse("http://a:80?x#y");
  if !p.is_ok || !q.is_ok { return assert(false, "url parse default port"); }
  let u: Url = p.value;
  let v: Url = q.value;
  let ok = flag(u.port_present) == false
    && u.port == 0
    && streq(u.path, "")
    && curl_url_effective_port(&u) == 443
    && curl_scheme_default_port("http") == 80
    && curl_scheme_default_port("ftp") == 0
    && streq(curl_url_to_string(&u), "https://example.com")
    && flag(v.port_present)
    && v.port == 80
    && streq(v.path, "")
    && streq(v.query, "x")
    && streq(v.fragment, "y");
  return assert(ok, "url parse default port");
}

fn t3() -> TestResult {
  let ok = url_err_starts("", "curl: empty url")
    && url_err_starts("example.com/x", "curl: url must be absolute")
    && url_err_starts("1http://x/", "curl: scheme must start with a letter")
    && url_err_starts("http:///x", "curl: empty host")
    && url_err_starts("http://exa mple/", "curl: invalid host character")
    && url_err_starts("http://h:abc/", "curl: invalid port")
    && url_err_starts("http://h:99999/", "curl: port out of range")
    && url_err_starts("http://u@h/", "curl: userinfo not supported")
    && url_err_starts("http://[::1]/", "curl: IPv6 literals not supported")
    && url_err_starts("http://h/a b", "curl: url path has invalid character")
    && url_err_starts("http://h/?a b", "curl: url query has invalid character")
    && url_err_starts("http://h/#a b", "curl: url fragment has invalid character");
  return assert(ok, "url parse error catalog");
}

fn t4() -> TestResult {
  let enc = curl_percent_encode_component("Az09-._~");
  let sp = curl_percent_encode_component("a b");
  let res = curl_percent_encode_component("/?#&=+");
  let utf = curl_percent_encode_component("\u{00E9}");
  let ok = streq(enc, "Az09-._~")
    && streq(sp, "a%20b")
    && streq(res, "%2F%3F%23%26%3D%2B")
    && streq(utf, "%C3%A9");
  return assert(ok, "percent encode");
}

fn t5() -> TestResult {
  let d1 = curl_percent_decode_component("a%20b%2Fc");
  let d2 = curl_percent_decode_component("%4a%6b");
  let e1 = curl_percent_decode_component("%");
  let e2 = curl_percent_decode_component("a%0");
  let e3 = curl_percent_decode_component("%ZZ");
  let e4 = curl_percent_decode_component("%00");
  if !d1.is_ok || !d2.is_ok { return assert(false, "percent decode"); }
  if e1.is_ok || e2.is_ok || e3.is_ok || e4.is_ok {
    return assert(false, "percent decode errors");
  }
  let s1: Str = d1.value;
  let s2: Str = d2.value;
  let m1: Str = e1.error;
  let m2: Str = e2.error;
  let m3: Str = e3.error;
  let m4: Str = e4.error;
  let ok = streq(s1, "a b/c")
    && streq(s2, "Jk")
    && streq(m1, "curl: truncated percent escape at offset 0")
    && streq(m2, "curl: truncated percent escape at offset 1")
    && streq(m3, "curl: bad percent escape at offset 0")
    && streq(m4, "curl: percent escape decodes to NUL at offset 0");
  return assert(ok, "percent decode errors");
}

fn t6() -> TestResult {
  let a = curl_url_parse("http://EXAMPLE.com:80");
  let b = curl_url_parse("https://Host:443/a/./b/../c");
  let c = curl_url_parse("http://host:8080/x?q=1#");
  if !a.is_ok || !b.is_ok || !c.is_ok { return assert(false, "url normalize"); }
  let ua: Url = a.value;
  let ub: Url = b.value;
  let uc: Url = c.value;
  let na = curl_url_normalize(&ua);
  let nb = curl_url_normalize(&ub);
  let nc = curl_url_normalize(&uc);
  let ok = streq(curl_url_to_string(&na), "http://example.com/")
    && streq(curl_url_to_string(&nb), "https://host/a/c")
    && streq(curl_url_to_string(&nc), "http://host:8080/x?q=1")
    && flag(nb.port_present) == false;
  return assert(ok, "url normalize");
}

fn t7() -> TestResult {
  let ok = streq(curl_url_remove_dot_segments("/a/b/c/./../../g"), "/a/g")
    && streq(curl_url_remove_dot_segments("/../x"), "/x")
    && streq(curl_url_remove_dot_segments("/a/b/.."), "/a/")
    && streq(curl_url_remove_dot_segments("/./a/"), "/a/")
    && streq(curl_url_remove_dot_segments("a/../b"), "/b")
    && streq(curl_url_remove_dot_segments("/a/./b"), "/a/b");
  return assert(ok, "dot segment removal");
}

fn t8() -> TestResult {
  let base = curl_url_parse("http://a/b/c/d;p?q");
  if !base.is_ok { return assert(false, "url resolve"); }
  let bu: Url = base.value;
  let r1 = curl_url_resolve(&bu, "g");
  let r2 = curl_url_resolve(&bu, "../g");
  let r3 = curl_url_resolve(&bu, "/g");
  let r4 = curl_url_resolve(&bu, "?y");
  let r5 = curl_url_resolve(&bu, "#s");
  let r6 = curl_url_resolve(&bu, "");
  let r7 = curl_url_resolve(&bu, "//g");
  let r8 = curl_url_resolve(&bu, "https://x/y");
  if !r1.is_ok || !r2.is_ok || !r3.is_ok || !r4.is_ok || !r5.is_ok || !r6.is_ok || !r7.is_ok || !r8.is_ok {
    return assert(false, "url resolve");
  }
  let u1: Url = r1.value;
  let u2: Url = r2.value;
  let u3: Url = r3.value;
  let u4: Url = r4.value;
  let u5: Url = r5.value;
  let u6: Url = r6.value;
  let u7: Url = r7.value;
  let u8: Url = r8.value;
  let ok = streq(curl_url_to_string(&u1), "http://a/b/c/g")
    && streq(curl_url_to_string(&u2), "http://a/b/g")
    && streq(curl_url_to_string(&u3), "http://a/g")
    && streq(curl_url_to_string(&u4), "http://a/b/c/d;p?y")
    && streq(curl_url_to_string(&u5), "http://a/b/c/d;p?q#s")
    && streq(curl_url_to_string(&u6), "http://a/b/c/d;p?q")
    && streq(curl_url_to_string(&u7), "http://g/")
    && streq(curl_url_to_string(&u8), "https://x/y");
  return assert(ok, "url resolve");
}

fn t9() -> TestResult {
  let a = curl_url_parse("http://a:80/x");
  let b = curl_url_parse("http://a/y");
  let c = curl_url_parse("https://a/y");
  let d = curl_url_parse("http://a:8080/y");
  if !a.is_ok || !b.is_ok || !c.is_ok || !d.is_ok { return assert(false, "same origin"); }
  let ua: Url = a.value;
  let ub: Url = b.value;
  let uc: Url = c.value;
  let ud: Url = d.value;
  let ok = flag(curl_url_same_origin(&ua, &ub))
    && flag(curl_url_same_origin(&ua, &uc)) == false
    && flag(curl_url_same_origin(&ua, &ud)) == false
    && curl_url_effective_port(&ua) == 80
    && curl_url_effective_port(&uc) == 443;
  return assert(ok, "same origin");
}

// --- methods, headers, requests -------------------------------------------

fn t10() -> TestResult {
  let c1 = curl_method_canonical("get");
  let c2 = curl_method_canonical("PoSt");
  let c3 = curl_method_canonical("M-SEARCH");
  let e1 = curl_method_canonical("");
  let e2 = curl_method_canonical("G ET");
  if !c1.is_ok || !c2.is_ok || !c3.is_ok { return assert(false, "method canonical"); }
  if e1.is_ok || e2.is_ok { return assert(false, "method canonical"); }
  let s1: Str = c1.value;
  let s2: Str = c2.value;
  let s3: Str = c3.value;
  let m2: Str = e2.error;
  let ok = streq(s1, "GET")
    && streq(s2, "POST")
    && streq(s3, "M-SEARCH")
    && flag(curl_method_is_valid("GET"))
    && flag(curl_method_is_valid("G ET")) == false
    && flag(curl_method_is_safe("head"))
    && flag(curl_method_is_safe("POST")) == false
    && flag(curl_method_is_idempotent("PUT"))
    && flag(curl_method_is_idempotent("PATCH")) == false
    && streq(m2, "curl: method has invalid character at offset 1");
  return assert(ok, "method canonical");
}

fn t11() -> TestResult {
  var h = curl_headers_new();
  let a1 = curl_headers_add(&mut h, "Host", "example.com");
  let a2 = curl_headers_add(&mut h, "User-Agent", "xiom");
  let a3 = curl_headers_add(&mut h, "Accept", "*/*");
  let a4 = curl_headers_add(&mut h, "Accept", "text/html");
  let e1 = curl_headers_add(&mut h, "", "x");
  let e2 = curl_headers_add(&mut h, "Bad Name", "x");
  let e3 = curl_headers_add(&mut h, "X-Test", "a\rb");
  if !a1.is_ok || !a2.is_ok || !a3.is_ok || !a4.is_ok {
    return assert(false, "headers add and lookup");
  }
  if e1.is_ok || e2.is_ok || e3.is_ok { return assert(false, "headers add and lookup"); }
  let m1: Str = e1.error;
  let m2: Str = e2.error;
  let m3: Str = e3.error;
  let g = curl_headers_get(&h, "host");
  if !g.is_ok { return assert(false, "headers add and lookup"); }
  let gv: Str = g.value;
  let count_before = curl_headers_count(&h);
  let removed = curl_headers_remove(&mut h, "accept");
  let ok = count_before == 4
    && streq(gv, "example.com")
    && flag(curl_headers_has(&h, "USER-AGENT"))
    && streq(curl_headers_name_at(&h, 0), "Host")
    && streq(curl_headers_value_at(&h, 1), "xiom")
    && removed == 2
    && curl_headers_count(&h) == 2
    && flag(curl_headers_consistent(&h))
    && streq(m1, "curl: empty header name")
    && streq(m2, "curl: header name has invalid character at offset 3")
    && streq(m3, "curl: header value has invalid character at offset 1");
  return assert(ok, "headers add and lookup");
}

fn t12() -> TestResult {
  let p = curl_url_parse("http://example.com/a?b=1");
  if !p.is_ok { return assert(false, "request build and encode"); }
  let u: Url = p.value;
  let rq = curl_request_new("post", u, "HTTP/1.1");
  if !rq.is_ok { return assert(false, "request build and encode"); }
  var req: Request = rq.value;
  let h1 = curl_request_add_header(&mut req, "Host", "example.com");
  if !h1.is_ok { return assert(false, "request build and encode"); }
  curl_request_set_body(&mut req, "hello");
  let enc = curl_request_encode(&req);
  let ok = streq(curl_request_method(&req), "POST")
    && streq(curl_request_target(&req), "/a?b=1")
    && curl_request_body_len(&req) == 5
    && flag(curl_request_has_body(&req))
    && flag(curl_request_consistent(&req))
    && streq(enc, "POST /a?b=1 HTTP/1.1\r\nHost: example.com\r\n\r\nhello")
    && streq(curl_request_version(&req), "HTTP/1.1");
  let bad = curl_request_new("GET", curl_request_url(&req), "HTTP/2");
  if bad.is_ok { return assert(false, "request build and encode"); }
  return assert(ok, "request build and encode");
}

// --- redirects -------------------------------------------------------------

fn t13() -> TestResult {
  let ok = streq(curl_redirect_rewrite_method(301, "POST"), "GET")
    && streq(curl_redirect_rewrite_method(302, "POST"), "GET")
    && streq(curl_redirect_rewrite_method(302, "PUT"), "PUT")
    && streq(curl_redirect_rewrite_method(303, "POST"), "GET")
    && streq(curl_redirect_rewrite_method(303, "HEAD"), "HEAD")
    && streq(curl_redirect_rewrite_method(307, "POST"), "POST")
    && streq(curl_redirect_rewrite_method(308, "DELETE"), "DELETE")
    && flag(curl_redirect_is_followable(301))
    && flag(curl_redirect_is_followable(308))
    && flag(curl_redirect_is_followable(300)) == false
    && flag(curl_redirect_is_followable(200)) == false
    && flag(curl_redirect_keeps_body(307))
    && flag(curl_redirect_keeps_body(308))
    && flag(curl_redirect_keeps_body(301)) == false;
  return assert(ok, "redirect method rewriting");
}

fn t14() -> TestResult {
  let r1 = curl_redirect_next_method(302, "POST", 0, CURL_MAX_REDIRECTS);
  let e1 = curl_redirect_next_method(302, "POST", 10, CURL_MAX_REDIRECTS);
  let e2 = curl_redirect_next_method(200, "GET", 0, CURL_MAX_REDIRECTS);
  if !r1.is_ok { return assert(false, "redirect depth and errors"); }
  if e1.is_ok || e2.is_ok { return assert(false, "redirect depth and errors"); }
  let m1: Str = r1.value;
  let m2: Str = e1.error;
  let m3: Str = e2.error;
  let ok = streq(m1, "GET")
    && streq(m2, "curl: redirect depth exceeded (max 10)")
    && streq(m3, "curl: status is not a redirect: 200")
    && CURL_MAX_REDIRECTS == 10;
  return assert(ok, "redirect depth and errors");
}

// --- cookies ---------------------------------------------------------------

fn t15() -> TestResult {
  let c1 = curl_cookie_parse("sid=abc; Domain=.Example.COM; Path=/app; Max-Age=3600; Secure; HttpOnly",
    "www.example.com", "/app/x", 1000);
  let c2 = curl_cookie_parse("a=1", "h.example.org", "/dir/page", 7);
  let c3 = curl_cookie_parse("b=2; Path=relative", "h.example.org", "/dir/page", 7);
  if !c1.is_ok || !c2.is_ok || !c3.is_ok { return assert(false, "cookie parse attributes"); }
  let k1: Cookie = c1.value;
  let k2: Cookie = c2.value;
  let k3: Cookie = c3.value;
  let ok = streq(k1.name, "sid")
    && streq(k1.value, "abc")
    && streq(k1.domain, "example.com")
    && flag(k1.host_only) == false
    && streq(k1.path, "/app")
    && flag(k1.secure)
    && flag(k1.http_only)
    && k1.max_age == 3600
    && flag(k1.max_age_present)
    && k1.created_at == 1000
    && streq(k2.domain, "h.example.org")
    && flag(k2.host_only)
    && flag(k2.secure) == false
    && flag(k2.max_age_present) == false
    && streq(k2.path, "/dir")
    && streq(k3.path, "/dir");
  return assert(ok, "cookie parse attributes");
}

fn t16() -> TestResult {
  let e1 = curl_cookie_parse("", "example.com", "/", 0);
  let e2 = curl_cookie_parse("nopair", "example.com", "/", 0);
  let e3 = curl_cookie_parse("=v", "example.com", "/", 0);
  let e4 = curl_cookie_parse("na me=1", "example.com", "/", 0);
  let e5 = curl_cookie_parse("a=1 2", "example.com", "/", 0);
  let e6 = curl_cookie_parse("a=1; Domain=other.com", "example.com", "/", 0);
  let e7 = curl_cookie_parse("a=1; Max-Age=xx", "example.com", "/", 0);
  if e1.is_ok || e2.is_ok || e3.is_ok || e4.is_ok || e5.is_ok || e6.is_ok || e7.is_ok {
    return assert(false, "cookie parse error catalog");
  }
  let m1: Str = e1.error;
  let m2: Str = e2.error;
  let m4: Str = e4.error;
  let m5: Str = e5.error;
  let m6: Str = e6.error;
  let m7: Str = e7.error;
  let ok = streq(m1, "curl: empty set-cookie")
    && streq(m2, "curl: set-cookie must be name=value")
    && streq(m4, "curl: cookie name has invalid character at offset 2")
    && streq(m5, "curl: cookie value has invalid character at offset 3")
    && streq(m6, "curl: cookie domain does not match host: other.com")
    && streq(m7, "curl: invalid Max-Age")
    && streq(curl_cookie_default_path("/dir/page"), "/dir")
    && streq(curl_cookie_default_path("dir"), "/")
    && streq(curl_cookie_default_path("/"), "/");
  return assert(ok, "cookie parse error catalog");
}

fn t17() -> TestResult {
  let c1 = curl_cookie_parse("id=1; Domain=example.com; Path=/a", "www.example.com", "/a/b", 0);
  let c2 = curl_cookie_parse("s=1; Secure", "example.com", "/", 0);
  let c3 = curl_cookie_parse("h=1", "example.com", "/", 0);
  let c4 = curl_cookie_parse("e=1; Max-Age=10", "example.com", "/", 100);
  let c5 = curl_cookie_parse("z=1; Max-Age=0", "example.com", "/", 100);
  let c6 = curl_cookie_parse("n=1; Max-Age=-5", "example.com", "/", 100);
  if !c1.is_ok || !c2.is_ok || !c3.is_ok || !c4.is_ok || !c5.is_ok || !c6.is_ok {
    return assert(false, "cookie matching and expiry");
  }
  let k1: Cookie = c1.value;
  let k2: Cookie = c2.value;
  let k3: Cookie = c3.value;
  let k4: Cookie = c4.value;
  let k5: Cookie = c5.value;
  let k6: Cookie = c6.value;
  let ok = flag(curl_cookie_domain_match(&k1, "www.example.com"))
    && flag(curl_cookie_domain_match(&k1, "example.com"))
    && flag(curl_cookie_path_match(&k1, "/a/b"))
    && flag(curl_cookie_path_match(&k1, "/ab")) == false
    && flag(curl_cookie_path_match(&k1, "/a")) == true
    && flag(curl_cookie_matches(&k1, "www.example.com", "/a/b", 0))
    && flag(curl_cookie_sendable(&k2, "example.com", "/", "http", 0)) == false
    && flag(curl_cookie_sendable(&k2, "example.com", "/", "https", 0))
    && flag(curl_cookie_domain_match(&k3, "example.com"))
    && flag(curl_cookie_domain_match(&k3, "sub.example.com")) == false
    && flag(curl_cookie_is_expired(&k4, 105)) == false
    && flag(curl_cookie_is_expired(&k4, 110))
    && flag(curl_cookie_is_expired(&k5, 100))
    && flag(curl_cookie_is_expired(&k6, 100));
  return assert(ok, "cookie matching and expiry");
}

fn t18() -> TestResult {
  let c = curl_cookie_parse("sid=abc; Domain=.Example.COM; Path=/app; Max-Age=3600; Secure; HttpOnly",
    "www.example.com", "/app/x", 1000);
  if !c.is_ok { return assert(false, "cookie render and round-trip"); }
  let k: Cookie = c.value;
  let text = curl_cookie_to_string(&k);
  let back = curl_cookie_parse(text, "www.example.com", "/app/x", 1000);
  if !back.is_ok { return assert(false, "cookie render and round-trip"); }
  let k2: Cookie = back.value;
  let ok = streq(text, "sid=abc; Domain=example.com; Path=/app; Max-Age=3600; Secure; HttpOnly")
    && streq(k2.name, k.name)
    && streq(k2.value, k.value)
    && streq(k2.domain, k.domain)
    && streq(k2.path, k.path)
    && flag(k2.secure)
    && flag(k2.http_only)
    && k2.max_age == k.max_age;
  return assert(ok, "cookie render and round-trip");
}

fn t19() -> TestResult {
  var j = curl_jar_new();
  let c1 = curl_cookie_parse("a=1; Path=/", "example.com", "/", 0);
  let c2 = curl_cookie_parse("b=2; Path=/; Max-Age=100", "example.com", "/", 0);
  let c3 = curl_cookie_parse("s=9; Path=/; Secure", "example.com", "/", 0);
  let c4 = curl_cookie_parse("a=9; Path=/", "example.com", "/", 0);
  if !c1.is_ok || !c2.is_ok || !c3.is_ok || !c4.is_ok { return assert(false, "cookie jar"); }
  let k1: Cookie = c1.value;
  let k2: Cookie = c2.value;
  let k3: Cookie = c3.value;
  let k4: Cookie = c4.value;
  curl_jar_add(&mut j, &k1);
  curl_jar_add(&mut j, &k2);
  curl_jar_add(&mut j, &k3);
  let h1 = curl_jar_cookie_header(&j, "example.com", "/", "http", 10);
  curl_jar_add(&mut j, &k4);
  let h2 = curl_jar_cookie_header(&j, "example.com", "/", "http", 10);
  let removed = curl_jar_remove_expired(&mut j, 100);
  let h3 = curl_jar_cookie_header(&j, "example.com", "/", "https", 10);
  let ok = curl_jar_count(&j) == 2
    && flag(curl_jar_consistent(&j))
    && curl_jar_slots(&j) == 4
    && flag(curl_jar_alive_at(&j, 0)) == false
    && streq(curl_jar_name_at(&j, 2), "s")
    && streq(curl_jar_name_at(&j, 3), "a")
    && streq(curl_jar_value_at(&j, 3), "9")
    && streq(h1, "a=1; b=2")
    && streq(h2, "b=2; a=9")
    && removed == 1
    && streq(h3, "s=9; a=9")
    && flag(curl_jar_secure_at(&j, 3)) == false;
  return assert(ok, "cookie jar");
}

// --- auth ------------------------------------------------------------------

fn t20() -> TestResult {
  let b = curl_auth_basic_header("user", "pass");
  let e1 = curl_auth_basic_header("us:er", "p");
  let e2 = curl_auth_bearer_header("");
  let e3 = curl_auth_bearer_header("a b");
  let be = curl_auth_bearer_header("tok123");
  if !b.is_ok || !be.is_ok { return assert(false, "auth basic and bearer"); }
  if e1.is_ok || e2.is_ok || e3.is_ok { return assert(false, "auth basic and bearer"); }
  let hv: Str = b.value;
  let bv: Str = be.value;
  let d = curl_auth_basic_decode(hv);
  if !d.is_ok { return assert(false, "auth basic and bearer"); }
  let creds: Str = d.value;
  let wrong = curl_auth_basic_decode(bv);
  let m1: Str = e1.error;
  let ok = streq(hv, "Basic dXNlcjpwYXNz")
    && streq(bv, "Bearer tok123")
    && streq(creds, "user:pass")
    && streq(curl_auth_basic_user(creds), "user")
    && streq(curl_auth_basic_password(creds), "pass")
    && streq(curl_auth_scheme(hv), "Basic")
    && streq(curl_auth_token(hv), "dXNlcjpwYXNz")
    && flag(curl_auth_header_is_basic(hv))
    && flag(curl_auth_header_is_bearer(bv))
    && flag(wrong.is_ok) == false
    && streq(m1, "curl: basic user has invalid character at offset 2");
  return assert(ok, "auth basic and bearer");
}

// --- retry and pool --------------------------------------------------------

fn t21() -> TestResult {
  let p = curl_retry_default();
  let d1 = curl_retry_delay_ms(&p, 1);
  let d2 = curl_retry_delay_ms(&p, 2);
  let d3 = curl_retry_delay_ms(&p, 3);
  let d10 = curl_retry_delay_ms(&p, 10);
  let d0 = curl_retry_delay_ms(&p, 0);
  let ra = curl_retry_parse_retry_after("120");
  let e1 = curl_retry_parse_retry_after("-1");
  let e2 = curl_retry_parse_retry_after("");
  let e3 = curl_retry_parse_retry_after("120s");
  if !ra.is_ok { return assert(false, "retry policy"); }
  if e1.is_ok || e2.is_ok || e3.is_ok { return assert(false, "retry policy"); }
  let rav: Int = ra.value;
  let ok = p.max_attempts == 3
    && p.base_delay_ms == 200
    && p.max_delay_ms == 10000
    && p.honor_retry_after == 1
    && flag(curl_retry_should_retry(&p, 500, 1))
    && flag(curl_retry_should_retry(&p, 500, 2))
    && flag(curl_retry_should_retry(&p, 500, 3)) == false
    && flag(curl_retry_should_retry(&p, 404, 1)) == false
    && flag(curl_retry_should_retry(&p, 429, 1))
    && flag(curl_retry_should_retry(&p, 408, 1))
    && flag(curl_retry_status_retryable(&p, 501))
    && d1 == 200 && d2 == 400 && d3 == 800 && d10 == 10000 && d0 == 0
    && rav == 120
    && curl_retry_effective_delay(&p, 2, 1000, true) == 1000
    && curl_retry_effective_delay(&p, 2, 100, true) == 400
    && curl_retry_effective_delay(&p, 2, 1000, false) == 400;
  return assert(ok, "retry policy");
}

fn t22() -> TestResult {
  var p = curl_pool_new(2, 4);
  let a1 = curl_pool_acquire(&mut p, "http", "h", 80);
  let a2 = curl_pool_acquire(&mut p, "http", "h", 80);
  let r1 = curl_pool_release(&mut p, "http", "h", 80);
  let a3 = curl_pool_acquire(&mut p, "http", "h", 80);
  let r2 = curl_pool_release(&mut p, "http", "h", 80);
  let r3 = curl_pool_release(&mut p, "http", "h", 80);
  let r4 = curl_pool_release(&mut p, "http", "h", 80);
  let b1 = curl_pool_acquire(&mut p, "http", "b", 80);
  let c1 = curl_pool_acquire(&mut p, "http", "c", 80);
  let d1 = curl_pool_acquire(&mut p, "http", "d", 80);
  let ka_before = curl_pool_keep_alive(&p, "http", "h", 80);
  let idle_before = curl_pool_idle(&p, "http", "h", 80);
  let act_before = curl_pool_active(&p, "http", "h", 80);
  let closed = curl_pool_close_idle(&mut p);
  let idle_after = curl_pool_idle(&p, "http", "h", 80);
  let ok = a1 == 0 && a2 == 0 && r1 == 1 && a3 == 1 && r2 == 1 && r3 == 1 && r4 == 0
    && flag(ka_before) == false
    && idle_before == 2
    && act_before == 0
    && b1 == 0 && c1 == 0 && d1 == -1
    && curl_pool_slot_count(&p) == 3
    && curl_pool_total(&p) == 2
    && closed == 2
    && idle_after == 0
    && curl_pool_idle_total(&p) == 0
    && curl_pool_active_total(&p) == 2
    && flag(curl_pool_consistent(&p));
  var q = curl_pool_new(1, 2);
  let q1 = curl_pool_acquire(&mut q, "http", "h", 80);
  let q2 = curl_pool_acquire(&mut q, "http", "b", 80);
  let q3 = curl_pool_acquire(&mut q, "http", "c", 80);
  return assert(ok && q1 == 0 && q2 == 0 && q3 == -1, "connection pool accounting");
}

// --- response model --------------------------------------------------------

fn t23() -> TestResult {
  let r = curl_response_new("HTTP/1.1", 200, "OK");
  if !r.is_ok { return assert(false, "response build and encode"); }
  var resp: Response = r.value;
  let h1 = curl_response_add_header(&mut resp, "Content-Length", "5");
  let h2 = curl_response_add_header(&mut resp, "Content-Type", "text/plain");
  if !h1.is_ok || !h2.is_ok { return assert(false, "response build and encode"); }
  curl_response_set_body(&mut resp, "hello");
  let cl = curl_response_content_length(&resp);
  let rem = curl_response_remove_header(&mut resp, "content-type");
  let bad = curl_response_new("HTTP/2", 200, "OK");
  let bad2 = curl_response_new("HTTP/1.1", 700, "X");
  if !cl.is_ok { return assert(false, "response build and encode"); }
  if bad.is_ok || bad2.is_ok { return assert(false, "response build and encode"); }
  let clv: Int = cl.value;
  let enc = curl_response_encode(&resp);
  let ok = curl_response_status(&resp) == 200
    && streq(curl_response_reason(&resp), "OK")
    && streq(curl_response_version(&resp), "HTTP/1.1")
    && streq(curl_response_body(&resp), "hello")
    && curl_response_body_len(&resp) == 5
    && clv == 5
    && flag(curl_response_is_keep_alive(&resp))
    && flag(curl_response_reusable(&resp))
    && flag(curl_response_consistent(&resp))
    && rem == 1
    && curl_response_headers_count(&resp) == 1
    && streq(curl_response_header_value_at(&resp, 0), "5")
    && streq(enc, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello");
  return assert(ok, "response build and encode");
}

fn t24() -> TestResult {
  let p1 = curl_response_parse("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX-Test: a\r\n\r\nhello");
  let p2 = curl_response_parse("HTTP/1.0 204 No Content\r\nConnection: keep-alive\r\n\r\n");
  let p3 = curl_response_parse("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n");
  let e1 = curl_response_parse("garbage");
  let e2 = curl_response_parse("HTTP/2 200 OK\r\n\r\n");
  let e3 = curl_response_parse("HTTP/1.1 abc X\r\n\r\n");
  let e4 = curl_response_parse("HTTP/1.1 200 OK\r\nBad Header: x\r\n\r\n");
  let e5 = curl_response_parse("HTTP/1.1 200 OK\r\nX: y");
  let e6 = curl_response_parse("HTTP/1.1 200 OK\r\n\tfolded\r\n\r\n");
  if !p1.is_ok || !p2.is_ok || !p3.is_ok { return assert(false, "response parse"); }
  if e1.is_ok || e2.is_ok || e3.is_ok || e4.is_ok || e5.is_ok || e6.is_ok {
    return assert(false, "response parse");
  }
  let r1: Response = p1.value;
  let r2: Response = p2.value;
  let r3: Response = p3.value;
  let g = curl_response_header_get(&r1, "x-test");
  let cl = curl_response_content_length(&r1);
  if !g.is_ok || !cl.is_ok { return assert(false, "response parse"); }
  let gv: Str = g.value;
  let clv: Int = cl.value;
  let m1: Str = e1.error;
  let m2: Str = e2.error;
  let m4: Str = e4.error;
  let m6: Str = e6.error;
  let ok = curl_response_status(&r1) == 200
    && streq(curl_response_reason(&r1), "OK")
    && streq(curl_response_body(&r1), "hello")
    && curl_response_headers_count(&r1) == 2
    && streq(gv, "a")
    && clv == 5
    && flag(curl_response_is_keep_alive(&r2))
    && flag(curl_response_is_keep_alive(&r3)) == false
    && streq(m1, "curl: response status line malformed")
    && streq(m2, "curl: unsupported version: HTTP/2")
    && streq(m4, "curl: header name has invalid character at offset 3")
    && streq(m6, "curl: header folding not supported at offset 17");
  return assert(ok, "response parse");
}

fn t25() -> TestResult {
  let ok = curl_status_class(100) == 1
    && curl_status_class(200) == 2
    && curl_status_class(301) == 3
    && curl_status_class(404) == 4
    && curl_status_class(503) == 5
    && curl_status_class(99) == 0
    && curl_status_class(600) == 0
    && flag(curl_status_is_success(204))
    && flag(curl_status_is_redirect(304))
    && flag(curl_status_is_client_error(404))
    && flag(curl_status_is_server_error(500))
    && flag(curl_status_is_informational(100))
    && flag(curl_status_is_retryable(503))
    && flag(curl_status_is_retryable(404)) == false
    && streq(curl_status_class_name(404), "client error")
    && streq(curl_status_class_name(99), "unknown")
    && curl_envelope_class(200) == CURL_ENV_SUCCESS
    && curl_envelope_class(301) == CURL_ENV_REDIRECT
    && curl_envelope_class(503) == CURL_ENV_SERVER_ERROR
    && curl_envelope_class(99) == CURL_ENV_NONE
    && streq(curl_envelope_name(CURL_ENV_SERVER_ERROR), "server error")
    && streq(curl_envelope_name(CURL_ENV_NONE), "none");
  return assert(ok, "status and envelope classification");
}

fn t26() -> TestResult {
  let p = curl_url_parse("http://example.com/x");
  if !p.is_ok { return assert(false, "accessors and version"); }
  let u: Url = p.value;
  let rq = curl_request_new("GET", u, curl_version_http_1_1());
  if !rq.is_ok { return assert(false, "accessors and version"); }
  var req: Request = rq.value;
  let body0 = curl_request_body(&req);
  curl_request_set_body(&mut req, "x");
  curl_request_clear_body(&mut req);
  let url2 = curl_request_url(&req);
  let ok = streq(curl_version(), "0.1.0")
    && streq(curl_method_get(), "GET")
    && streq(curl_method_head(), "HEAD")
    && streq(curl_method_post(), "POST")
    && streq(curl_method_put(), "PUT")
    && streq(curl_method_delete(), "DELETE")
    && streq(curl_method_patch(), "PATCH")
    && streq(curl_method_options(), "OPTIONS")
    && streq(curl_method_trace(), "TRACE")
    && streq(curl_version_http_1_0(), "HTTP/1.0")
    && flag(curl_version_is_supported("HTTP/1.1"))
    && flag(curl_version_is_supported("HTTP/2")) == false
    && streq(body0, "")
    && flag(curl_request_has_body(&req)) == false
    && streq(url2.host, "example.com")
    && curl_request_headers_count(&req) == 0
    && CURL_DEFAULT_PORT_HTTP == 80
    && CURL_DEFAULT_PORT_HTTPS == 443
    && CURL_ENV_SUCCESS == 2;
  return assert(ok, "accessors and version");
}

fn main() -> Int {
  io.println("=== xiom.curl conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.curl: all tests passed");
  } else {
    io.println("xiom.curl: tests failed");
  }
  return failed;
}
