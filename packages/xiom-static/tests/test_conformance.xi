// XIOM -- xiom.static conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 8. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through compare.str_compare via the local streq
// helper (`==` on Str values is never used). Every Vec element read is bound
// to a typed local first, and struct/Result Vec payloads are copied to typed
// locals before taking `&` references (struct-field-vec discipline).
//
// The file-backed checks create fixtures under fs.fs_temp_dir() with
// fs_write / fs_write_text, serve them through static_serve and remove them
// with io.remove_file. The binary fixture deliberately contains 0x00, 0x7B,
// 0x80 and 0xFF to pin byte preservation (no Str bridge).

module static_tests

use xiom.io; use xiom.test; use xiom.static;
use xiom.io.fs;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is Ok(v) with v equal to want.
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

// Byte-exact vector equality (widened reads, never raw UInt8 compares).
fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
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

// UTF-8 bytes of a string (test helper for expected bodies).
fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

// Element-wise Int vector equality.
fn int_list_equal(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Value of the first header named `name`, or "" when absent.
fn header_value(headers: &Vec[StaticHeader], name: Str) -> Str {
  var i = 0;
  while i < headers.len() {
    let h: StaticHeader = headers[i];
    if streq(h.name, name) {
      return h.value;
    }
    i = i + 1;
  }
  return "";
}

fn policy_default() -> StaticPolicy {
  return StaticPolicy{ max_age: 3600; immutable: false; must_revalidate: false; no_store: false };
}

// The binary fixture: 10 bytes covering >0x7A, high bytes and NUL.
fn fixture_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(65 as UInt8);
  v.push(66 as UInt8);
  v.push(67 as UInt8);
  v.push(0 as UInt8);
  v.push(123 as UInt8);
  v.push(200 as UInt8);
  v.push(255 as UInt8);
  v.push(128 as UInt8);
  v.push(10 as UInt8);
  v.push(34 as UInt8);
  return v;
}

fn fixture_ints() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(65);
  v.push(66);
  v.push(67);
  v.push(0);
  v.push(123);
  v.push(200);
  v.push(255);
  v.push(128);
  v.push(10);
  v.push(34);
  return v;
}

// Inclusive byte subrange [start, end].
fn sub_bytes(v: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i <= end {
    let b: UInt8 = v[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn write_bytes(path: Str, data: &Vec[UInt8]) -> Bool {
  let r = fs.fs_write(path, data);
  return r.is_ok;
}

fn write_text(path: Str, s: Str) -> Bool {
  let r = fs.fs_write_text(path, s);
  return r.is_ok;
}

// True when r carries exactly the given StaticRange outcome.
fn range_is(r: StaticRange, valid: Bool, unsat: Bool, start: Int, end: Int) -> Bool {
  if r.valid != valid {
    return false;
  }
  if r.unsatisfiable != unsat {
    return false;
  }
  if r.start != start {
    return false;
  }
  if r.end != end {
    return false;
  }
  return true;
}

// True when the header parses as a malformed range (ignore -> 200).
fn range_invalid(header: Str, size: Int) -> Bool {
  let r = static_range_parse(header, size);
  if r.valid {
    return false;
  }
  if r.unsatisfiable {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Pure checks
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = streq(static_mime_of("index.html"), "text/html");
  if !streq(static_mime_of("style.css"), "text/css") { ok = false; }
  if !streq(static_mime_of("photo.jpeg"), "image/jpeg") { ok = false; }
  if !streq(static_mime_of("app.js"), "application/javascript") { ok = false; }
  if !streq(static_mime_of("data.json"), "application/json") { ok = false; }
  if !streq(static_mime_of("blob.bin"), "application/octet-stream") { ok = false; }
  if !streq(static_mime_of("README"), "application/octet-stream") { ok = false; }
  return assert(ok, "mime: extension mapping with octet-stream fallback");
}

fn t2() -> TestResult {
  var ok = streq(static_etag_stat(123, 456), "\"123-456\"");
  if !streq(static_etag_stat(0, 0), "\"0-0\"") { ok = false; }
  if !streq(static_etag_stat(10, 784111777), "\"10-784111777\"") { ok = false; }
  return assert(ok, "etag_stat: quoted <size>-<mtime> format");
}

fn t3() -> TestResult {
  let data = bytes_of("abc");
  let et = static_etag_sha256(&data);
  var ok = streq(et, "\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"");
  if et.len() != 66 { ok = false; }
  let data2 = bytes_of("abc");
  let et2 = static_etag_sha256(&data2);
  if !streq(et, et2) { ok = false; }
  return assert(ok, "etag_sha256: quoted lowercase SHA-256 hex for \"abc\"");
}

fn t4() -> TestResult {
  let et = "\"abc\"";
  var ok = static_etag_matches(et, "\"abc\"");
  if !static_etag_matches(et, "*") { ok = false; }
  if !static_etag_matches(et, "W/\"abc\"") { ok = false; }
  if !static_etag_matches(et, "\"x\", \"abc\"") { ok = false; }
  if !static_etag_matches(et, "  \"abc\"  ") { ok = false; }
  if static_etag_matches(et, "\"x\"") { ok = false; }
  if static_etag_matches(et, "") { ok = false; }
  return assert(ok, "etag_matches: exact, star, W/ prefix, comma list, whitespace, miss");
}

fn t5() -> TestResult {
  var ok = streq(static_http_date(0), "Thu, 01 Jan 1970 00:00:00 GMT");
  if !streq(static_http_date(784111777), "Sun, 06 Nov 1994 08:49:37 GMT") { ok = false; }
  if !streq(static_http_date(-5), "Thu, 01 Jan 1970 00:00:00 GMT") { ok = false; }
  if !streq(static_http_date(1600000000), "Sun, 13 Sep 2020 12:26:40 GMT") { ok = false; }
  return assert(ok, "http_date: RFC 1123 KATs (epoch 0, 784111777, 1600000000) and negative clamp");
}

fn t6() -> TestResult {
  let h = static_last_modified(784111777);
  var ok = streq(h.name, "Last-Modified");
  if !streq(h.value, "Sun, 06 Nov 1994 08:49:37 GMT") { ok = false; }
  let h0 = static_last_modified(-1);
  if !streq(h0.value, "Thu, 01 Jan 1970 00:00:00 GMT") { ok = false; }
  return assert(ok, "last_modified: header name and clamped RFC 1123 value");
}

fn t7() -> TestResult {
  let p1 = StaticPolicy{ max_age: 3600; immutable: false; must_revalidate: false; no_store: false };
  var ok = streq(static_cache_control(&p1), "public, max-age=3600");
  let p2 = StaticPolicy{ max_age: 31536000; immutable: true; must_revalidate: false; no_store: false };
  if !streq(static_cache_control(&p2), "public, max-age=31536000, immutable") { ok = false; }
  let p3 = StaticPolicy{ max_age: 60; immutable: true; must_revalidate: true; no_store: false };
  if !streq(static_cache_control(&p3), "public, max-age=60, immutable, must-revalidate") { ok = false; }
  return assert(ok, "cache_control: public visibility with max-age and immutable");
}

fn t8() -> TestResult {
  let p1 = StaticPolicy{ max_age: 0; immutable: false; must_revalidate: true; no_store: false };
  var ok = streq(static_cache_control(&p1), "public, max-age=0, must-revalidate");
  let p2 = StaticPolicy{ max_age: 0; immutable: false; must_revalidate: false; no_store: true };
  if !streq(static_cache_control(&p2), "private, max-age=0, no-store") { ok = false; }
  let p3 = StaticPolicy{ max_age: 5; immutable: true; must_revalidate: true; no_store: true };
  if !streq(static_cache_control(&p3), "private, max-age=5, immutable, must-revalidate, no-store") { ok = false; }
  let p4 = StaticPolicy{ max_age: -5; immutable: false; must_revalidate: false; no_store: false };
  if !streq(static_cache_control(&p4), "public, max-age=0") { ok = false; }
  return assert(ok, "cache_control: must-revalidate, private+no-store, flag order, negative clamp");
}

fn t9() -> TestResult {
  var ok = range_is(static_range_parse("bytes=0-0", 10), true, false, 0, 0);
  if !range_is(static_range_parse("bytes=2-5", 10), true, false, 2, 5) { ok = false; }
  if !range_is(static_range_parse("bytes=0-9", 10), true, false, 0, 9) { ok = false; }
  if !range_is(static_range_parse("bytes=2-", 10), true, false, 2, 9) { ok = false; }
  if !range_is(static_range_parse("bytes=9-100", 10), true, false, 9, 9) { ok = false; }
  return assert(ok, "range: closed ranges, open-ended range, end clamp");
}

fn t10() -> TestResult {
  var ok = range_is(static_range_parse("bytes=-3", 10), true, false, 7, 9);
  if !range_is(static_range_parse("bytes=-1", 10), true, false, 9, 9) { ok = false; }
  if !range_is(static_range_parse("bytes=-10", 10), true, false, 0, 9) { ok = false; }
  if !range_is(static_range_parse("bytes=-20", 10), true, false, 0, 9) { ok = false; }
  return assert(ok, "range: suffix forms, including a suffix at/above the size");
}

fn t11() -> TestResult {
  var ok = range_is(static_range_parse("bytes=10-", 10), true, true, 0, 0);
  if !range_is(static_range_parse("bytes=10-12", 10), true, true, 0, 0) { ok = false; }
  if !range_is(static_range_parse("bytes=-0", 10), true, true, 0, 0) { ok = false; }
  if !range_is(static_range_parse("bytes=0-", 0), true, true, 0, 0) { ok = false; }
  if !range_is(static_range_parse("bytes=-1", 0), true, true, 0, 0) { ok = false; }
  if !range_is(static_range_parse("bytes=0-0", -5), true, true, 0, 0) { ok = false; }
  return assert(ok, "range: unsatisfiable starts, zero-length suffix, empty resource");
}

fn t12() -> TestResult {
  var ok = range_invalid("", 10);
  if !range_invalid("bytes=", 10) { ok = false; }
  if !range_invalid("bytes=-", 10) { ok = false; }
  if !range_invalid("bytes=0", 10) { ok = false; }
  if !range_invalid("bytes=x-y", 10) { ok = false; }
  if !range_invalid("bytes=1-2-3", 10) { ok = false; }
  if !range_invalid("bytes=--1", 10) { ok = false; }
  if !range_invalid("bytes=1 -2", 10) { ok = false; }
  if !range_invalid("items=0-1", 10) { ok = false; }
  if !range_invalid("Bytes=0-1", 10) { ok = false; }
  if !range_invalid("bytes=0-1,3-4", 10) { ok = false; }
  if !range_invalid("bytes=+1-2", 10) { ok = false; }
  if !range_invalid("bytes=5-3", 10) { ok = false; }
  return assert(ok, "range: malformed matrix (no prefix, multi-range, signs, reversed, wrong case)");
}

fn t13() -> TestResult {
  var ok = range_is(static_range_parse("bytes=99999999999999999999-", 10), true, true, 0, 0);
  if !range_is(static_range_parse("bytes=0-99999999999999999999", 10), true, false, 0, 9) { ok = false; }
  if !range_is(static_range_parse("bytes=0007-0008", 10), true, false, 7, 8) { ok = false; }
  return assert(ok, "range: overflowing digit strings saturate (no wrap), leading zeros parse");
}

fn t14() -> TestResult {
  let cr = static_content_range(1, 3, 10);
  var ok = streq(cr.name, "Content-Range");
  if !streq(cr.value, "bytes 1-3/10") { ok = false; }
  let ar = static_accept_ranges();
  if !streq(ar.name, "Accept-Ranges") { ok = false; }
  if !streq(ar.value, "bytes") { ok = false; }
  return assert(ok, "content_range and accept_ranges header shapes");
}

fn t15() -> TestResult {
  var ok = str_ok_is(static_resolve_path("C:/root", "index.html"), "C:/root/index.html");
  if !str_ok_is(static_resolve_path("C:/root", "a/b.txt"), "C:/root/a/b.txt") { ok = false; }
  if !str_ok_is(static_resolve_path("C:/root/", "x"), "C:/root/x") { ok = false; }
  if !str_ok_is(static_resolve_path("C:\\root\\", "x"), "C:\\root\\x") { ok = false; }
  if !str_ok_is(static_resolve_path("C:/root", "a/./b"), "C:/root/a/./b") { ok = false; }
  if !str_ok_is(static_resolve_path("C:/root", "%61.txt"), "C:/root/a.txt") { ok = false; }
  if !str_ok_is(static_resolve_path("C:/root", "a%2Fb"), "C:/root/a/b") { ok = false; }
  if !str_ok_is(static_resolve_path("C:/root", "..."), "C:/root/...") { ok = false; }
  if !str_ok_is(static_resolve_path("C:/root", "a..b"), "C:/root/a..b") { ok = false; }
  return assert(ok, "resolve: manual join, decoded escapes, '.' and non-parent dots allowed");
}

fn t16() -> TestResult {
  var ok = str_err_is(static_resolve_path("C:/root", ".."), "static: parent segment in path");
  if !str_err_is(static_resolve_path("C:/root", "a/../b"), "static: parent segment in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "a/.."), "static: parent segment in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "..%2fb"), "static: parent segment in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "%2e%2e/x"), "static: parent segment in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "a/%2E%2E"), "static: parent segment in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "a\\..\\b"), "static: parent segment in path") { ok = false; }
  return assert(ok, "resolve: '..' segments under / and \\, raw and percent-encoded");
}

fn t17() -> TestResult {
  var ok = str_err_is(static_resolve_path("C:/root", "%00"), "static: NUL byte in path");
  if !str_err_is(static_resolve_path("C:/root", "a%00b"), "static: NUL byte in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "a%00/../b"), "static: NUL byte in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "%zz"), "static: invalid percent-encoding") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "%2"), "static: invalid percent-encoding") { ok = false; }
  return assert(ok, "resolve: NUL escapes rejected before decode; malformed escapes error");
}

fn t18() -> TestResult {
  var ok = str_err_is(static_resolve_path("C:/root", ""), "static: empty path");
  if !str_err_is(static_resolve_path("C:/root", "/etc"), "static: absolute path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "%2Fetc"), "static: absolute path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "a\\b"), "static: backslash in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "C:/x"), "static: drive colon in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "C:x"), "static: drive colon in path") { ok = false; }
  if !str_err_is(static_resolve_path("C:/root", "a:b"), "static: drive colon in path") { ok = false; }
  return assert(ok, "resolve: empty, absolute, backslash and drive-colon rejections");
}

fn t19() -> TestResult {
  let v = bytes_of("\u{00E9}");
  let ints = static_body_ints(&v);
  var want = Vec[Int].new();
  want.push(195);
  want.push(169);
  var ok = int_list_equal(&ints, &want);
  let empty = Vec[UInt8].new();
  let noints = static_body_ints(&empty);
  if noints.len() != 0 { ok = false; }
  let fixture = fixture_bytes();
  let fints = static_body_ints(&fixture);
  var fwant = fixture_ints();
  if !int_list_equal(&fints, &fwant) { ok = false; }
  return assert(ok, "body_ints: 0..255 bridge preserves NUL and high bytes");
}

// --------------------------------------------------
//  File-backed checks
// --------------------------------------------------

fn t20() -> TestResult {
  let td = fs.fs_temp_dir();
  let path = td + "/xiom_static_bin.bin";
  let want = fixture_bytes();
  var ok = write_bytes(path, &want);
  let pol = policy_default();
  let served = static_serve(td, "xiom_static_bin.bin", "", "", false, &pol);
  if served.status != 200 { ok = false; }
  let headers: Vec[StaticHeader] = served.headers;
  let body: Vec[UInt8] = served.body;
  if !bytes_equal(&body, &want) { ok = false; }
  if !streq(header_value(&headers, "Content-Type"), "application/octet-stream") { ok = false; }
  if !streq(header_value(&headers, "Content-Length"), "10") { ok = false; }
  if !streq(header_value(&headers, "Accept-Ranges"), "bytes") { ok = false; }
  if !streq(header_value(&headers, "Cache-Control"), "public, max-age=3600") { ok = false; }
  let sr = fs.fs_size(path);
  let mr = fs.fs_mtime(path);
  if sr.is_ok && mr.is_ok {
    let size: Int = sr.value;
    let mtime: Int = mr.value;
    if !streq(header_value(&headers, "ETag"), static_etag_stat(size, mtime)) { ok = false; }
    if !streq(header_value(&headers, "Last-Modified"), static_http_date(mtime)) { ok = false; }
  } else {
    ok = false;
  }
  let ints = static_body_ints(&body);
  let want_ints = fixture_ints();
  if !int_list_equal(&ints, &want_ints) { ok = false; }
  let _ = io.remove_file(path);
  return assert(ok, "file 200: binary body byte-exact, stat ETag, Last-Modified, Content-Type");
}

fn t21() -> TestResult {
  let td = fs.fs_temp_dir();
  let path = td + "/xiom_static_head.bin";
  let want = fixture_bytes();
  var ok = write_bytes(path, &want);
  let pol = policy_default();
  let served = static_serve(td, "xiom_static_head.bin", "", "", true, &pol);
  if served.status != 200 { ok = false; }
  let headers: Vec[StaticHeader] = served.headers;
  let body: Vec[UInt8] = served.body;
  if body.len() != 0 { ok = false; }
  if !streq(header_value(&headers, "Content-Length"), "10") { ok = false; }
  let r = static_serve(td, "xiom_static_head.bin", "", "bytes=1-2", true, &pol);
  if r.status != 206 { ok = false; }
  let rbody: Vec[UInt8] = r.body;
  if rbody.len() != 0 { ok = false; }
  let rh: Vec[StaticHeader] = r.headers;
  if !streq(header_value(&rh, "Content-Range"), "bytes 1-2/10") { ok = false; }
  if !streq(header_value(&rh, "Content-Length"), "2") { ok = false; }
  let _ = io.remove_file(path);
  return assert(ok, "file HEAD: empty body, full Content-Length; ranged HEAD keeps range headers");
}

fn t22() -> TestResult {
  let td = fs.fs_temp_dir();
  let path = td + "/xiom_static_range.bin";
  let want = fixture_bytes();
  var ok = write_bytes(path, &want);
  let pol = policy_default();
  let s1 = static_serve(td, "xiom_static_range.bin", "", "bytes=2-4", false, &pol);
  if s1.status != 206 { ok = false; }
  let b1: Vec[UInt8] = s1.body;
  let e1 = sub_bytes(&want, 2, 4);
  if !bytes_equal(&b1, &e1) { ok = false; }
  let h1: Vec[StaticHeader] = s1.headers;
  if !streq(header_value(&h1, "Content-Range"), "bytes 2-4/10") { ok = false; }
  if !streq(header_value(&h1, "Content-Length"), "3") { ok = false; }
  if !streq(header_value(&h1, "Content-Type"), "application/octet-stream") { ok = false; }
  let s2 = static_serve(td, "xiom_static_range.bin", "", "bytes=-3", false, &pol);
  if s2.status != 206 { ok = false; }
  let b2: Vec[UInt8] = s2.body;
  let e2 = sub_bytes(&want, 7, 9);
  if !bytes_equal(&b2, &e2) { ok = false; }
  let h2: Vec[StaticHeader] = s2.headers;
  if !streq(header_value(&h2, "Content-Range"), "bytes 7-9/10") { ok = false; }
  let s3 = static_serve(td, "xiom_static_range.bin", "", "bytes=5-", false, &pol);
  if s3.status != 206 { ok = false; }
  let b3: Vec[UInt8] = s3.body;
  let e3 = sub_bytes(&want, 5, 9);
  if !bytes_equal(&b3, &e3) { ok = false; }
  let s4 = static_serve(td, "xiom_static_range.bin", "", "bytes=8-99", false, &pol);
  if s4.status != 206 { ok = false; }
  let b4: Vec[UInt8] = s4.body;
  let e4 = sub_bytes(&want, 8, 9);
  if !bytes_equal(&b4, &e4) { ok = false; }
  let h4: Vec[StaticHeader] = s4.headers;
  if !streq(header_value(&h4, "Content-Range"), "bytes 8-9/10") { ok = false; }
  let s5 = static_serve(td, "xiom_static_range.bin", "", "bytes=abc", false, &pol);
  if s5.status != 200 { ok = false; }
  let b5: Vec[UInt8] = s5.body;
  if !bytes_equal(&b5, &want) { ok = false; }
  let h5: Vec[StaticHeader] = s5.headers;
  if !streq(header_value(&h5, "Content-Range"), "") { ok = false; }
  let _ = io.remove_file(path);
  return assert(ok, "file 206: byte-exact ranges (closed/suffix/open/clamped); malformed -> 200 full");
}

fn t23() -> TestResult {
  let td = fs.fs_temp_dir();
  let path = td + "/xiom_static_304.bin";
  let want = fixture_bytes();
  var ok = write_bytes(path, &want);
  let pol = policy_default();
  let s1 = static_serve(td, "xiom_static_304.bin", "", "", false, &pol);
  let h1: Vec[StaticHeader] = s1.headers;
  let et = header_value(&h1, "ETag");
  if et.len() == 0 { ok = false; }
  let s2 = static_serve(td, "xiom_static_304.bin", et, "", false, &pol);
  if s2.status != 304 { ok = false; }
  let b2: Vec[UInt8] = s2.body;
  if b2.len() != 0 { ok = false; }
  let h2: Vec[StaticHeader] = s2.headers;
  if !streq(header_value(&h2, "ETag"), et) { ok = false; }
  if streq(header_value(&h2, "Last-Modified"), "") { ok = false; }
  let s3 = static_serve(td, "xiom_static_304.bin", "*", "", false, &pol);
  if s3.status != 304 { ok = false; }
  let s4 = static_serve(td, "xiom_static_304.bin", "W/" + et, "", false, &pol);
  if s4.status != 304 { ok = false; }
  let s5 = static_serve(td, "xiom_static_304.bin", "\"nope\"", "", false, &pol);
  if s5.status != 200 { ok = false; }
  let s6 = static_serve(td, "xiom_static_304.bin", et, "bytes=1-2", false, &pol);
  if s6.status != 304 { ok = false; }
  let _ = io.remove_file(path);
  return assert(ok, "file 304: exact/star/W/ matches win over Range; miss -> 200");
}

fn t24() -> TestResult {
  let td = fs.fs_temp_dir();
  let path = td + "/xiom_static_416.bin";
  let want = fixture_bytes();
  var ok = write_bytes(path, &want);
  let pol = policy_default();
  let s416 = static_serve(td, "xiom_static_416.bin", "", "bytes=9999-", false, &pol);
  if s416.status != 416 { ok = false; }
  let h416: Vec[StaticHeader] = s416.headers;
  if !streq(header_value(&h416, "Content-Range"), "bytes */10") { ok = false; }
  if !streq(header_value(&h416, "Accept-Ranges"), "bytes") { ok = false; }
  let b416: Vec[UInt8] = s416.body;
  if b416.len() != 0 { ok = false; }
  let s0 = static_serve(td, "xiom_static_416.bin", "", "bytes=-0", false, &pol);
  if s0.status != 416 { ok = false; }
  let miss = static_serve(td, "xiom_static_missing.bin", "", "", false, &pol);
  if miss.status != 404 { ok = false; }
  let mh: Vec[StaticHeader] = miss.headers;
  if mh.len() != 0 { ok = false; }
  let dir = static_serve(td, ".", "", "", false, &pol);
  if dir.status != 404 { ok = false; }
  let trav = static_serve(td, "../xiom_static_nope.bin", "", "", false, &pol);
  if trav.status != 404 { ok = false; }
  let abs = static_serve(td, "/etc/hosts", "", "", false, &pol);
  if abs.status != 404 { ok = false; }
  let _ = io.remove_file(path);
  return assert(ok, "file 416/404: unsatisfied range, zero suffix, missing, directory, traversal");
}

fn t25() -> TestResult {
  let td = fs.fs_temp_dir();
  let path = td + "/xiom_static_text.txt";
  var ok = write_text(path, "hello static\n");
  let pol = policy_default();
  let s = static_serve(td, "xiom_static_text.txt", "", "", false, &pol);
  if s.status != 200 { ok = false; }
  let h: Vec[StaticHeader] = s.headers;
  if !streq(header_value(&h, "Content-Type"), "text/plain") { ok = false; }
  let b: Vec[UInt8] = s.body;
  let file_r = fs.fs_read(path);
  if file_r.is_ok {
    let file_bytes: Vec[UInt8] = file_r.value;
    if !bytes_equal(&b, &file_bytes) { ok = false; }
  } else {
    ok = false;
  }
  let _ = io.remove_file(path);
  return assert(ok, "file text: text/plain content type and byte-exact served body");
}

fn main() -> Int {
  io.println("=== xiom.static conformance tests ===");
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
    io.println("xiom.static: all tests passed");
  } else {
    io.println("xiom.static: tests failed");
  }
  return failed;
}
