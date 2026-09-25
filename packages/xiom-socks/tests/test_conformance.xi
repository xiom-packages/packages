// XIOM -- xiom.socks conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM SOCKS5 codec against its documented wire
// layouts and error catalog.
//
// Covers the documented API: exact greeting/method-selection/request/reply
// bytes pinned with hand-built hex fixtures; parse/build round-trips for all
// three address types (IPv4, domain, IPv6) in both directions; the REP code
// range 0x00..0x08; the RFC 1929 username/password request and status reply;
// boundaries (255 methods, 255-byte domain, 255-byte credentials, ports 0
// and 65535, high-bit address bytes); and the full error catalog (bad
// version, bad RSV, unknown command/reply/address type, empty domain, bad
// address lengths, out-of-range port/method/status, and every truncated
// shape) with atomic-failure checks on the builders.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); error messages go through
// compare.str_compare. Vec elements are bound to typed locals before use.

module socks_tests
use xiom.io; use xiom.test;
use xiom.socks;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Helpers (independent of src/socks.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_greeting_is(r: Result[Socks5Greeting, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_choice_is(r: Result[Socks5Choice, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_request_is(r: Result[Socks5Request, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_reply_is(r: Result[Socks5Reply, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_userpass_is(r: Result[Socks5UserPass, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_auth_reply_is(r: Result[Socks5AuthReply, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Build a CONNECT request with `atyp`/`addr`/`port`, parse it back and
// require every field to survive.
fn request_roundtrip(atyp: Int, addr: Vec[UInt8], port: Int) -> Bool {
  var out = Vec[UInt8].new();
  let r = socks5_request_build(&mut out, 1, atyp, &addr, port);
  if !r.is_ok {
    return false;
  }
  let pr = socks5_request_parse(&out);
  if !pr.is_ok {
    return false;
  }
  let q: Socks5Request = pr.value;
  if q.cmd != 1 { return false; }
  if q.atyp != atyp { return false; }
  if q.port != port { return false; }
  let back: Vec[UInt8] = q.addr;
  return bytes_equal(back, addr);
}

// Build a reply with `rep`/`atyp`/`addr`/`port`, parse it back and require
// every field to survive.
fn reply_roundtrip(rep: Int, atyp: Int, addr: Vec[UInt8], port: Int) -> Bool {
  var out = Vec[UInt8].new();
  let r = socks5_reply_build(&mut out, rep, atyp, &addr, port);
  if !r.is_ok {
    return false;
  }
  let pr = socks5_reply_parse(&out);
  if !pr.is_ok {
    return false;
  }
  let q: Socks5Reply = pr.value;
  if q.rep != rep { return false; }
  if q.atyp != atyp { return false; }
  if q.port != port { return false; }
  let back: Vec[UInt8] = q.addr;
  return bytes_equal(back, addr);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var methods = Vec[Int].new();
  methods.push(0);
  methods.push(1);
  methods.push(2);
  var out = Vec[UInt8].new();
  let r = socks5_greeting_build(&mut out, &methods);
  var ok = r.is_ok;
  if !bytes_equal(out, hb("0503000102")) { ok = false; }

  var only = Vec[Int].new();
  only.push(255);
  var out2 = Vec[UInt8].new();
  let r2 = socks5_greeting_build(&mut out2, &only);
  if !r2.is_ok { ok = false; }
  if !bytes_equal(out2, hb("0501ff")) { ok = false; }

  var none = Vec[Int].new();
  var out3 = Vec[UInt8].new();
  let r3 = socks5_greeting_build(&mut out3, &none);
  if !r3.is_ok { ok = false; }
  if !bytes_equal(out3, hb("0500")) { ok = false; }
  return assert(ok, "greeting build writes VER, NMETHODS and METHODS");
}

fn t2() -> TestResult {
  let data = hb("0503000102");
  let r = socks5_greeting_parse(&data);
  if !r.is_ok { return assert(false, "greeting must parse"); }
  let g: Socks5Greeting = r.value;
  var ok = g.methods.len() == 3;
  let m0: Int = g.methods[0];
  let m1: Int = g.methods[1];
  let m2: Int = g.methods[2];
  if m0 != 0 { ok = false; }
  if m1 != 1 { ok = false; }
  if m2 != 2 { ok = false; }

  let one = hb("0501ff");
  let r1 = socks5_greeting_parse(&one);
  if !r1.is_ok { ok = false; } else {
    let g1: Socks5Greeting = r1.value;
    let m: Int = g1.methods[0];
    if m != 255 { ok = false; }
  }

  let empty = hb("0500");
  let re = socks5_greeting_parse(&empty);
  if !re.is_ok { ok = false; } else {
    let ge: Socks5Greeting = re.value;
    if ge.methods.len() != 0 { ok = false; }
  }

  let extra = hb("050102ff");
  let rx = socks5_greeting_parse(&extra);
  if !rx.is_ok { ok = false; } else {
    let gx: Socks5Greeting = rx.value;
    let mx: Int = gx.methods[0];
    if gx.methods.len() != 1 { ok = false; }
    if mx != 2 { ok = false; }
  }
  return assert(ok, "greeting parse reads methods and ignores trailing bytes");
}

fn t3() -> TestResult {
  var many = Vec[Int].new();
  var i = 0;
  while i < 255 {
    many.push(i);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  let r = socks5_greeting_build(&mut out, &many);
  var ok = r.is_ok;
  if out.len() != 257 { ok = false; }
  let b0: UInt8 = out[0];
  let b1: UInt8 = out[1];
  if (b0 as Int) != 5 { ok = false; }
  if (b1 as Int) != 255 { ok = false; }
  let pr = socks5_greeting_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let g: Socks5Greeting = pr.value;
    if g.methods.len() != 255 { ok = false; }
    let first: Int = g.methods[0];
    let last: Int = g.methods[254];
    if first != 0 { ok = false; }
    if last != 254 { ok = false; }
  }

  var too = Vec[Int].new();
  var j = 0;
  while j < 256 {
    too.push(0);
    j = j + 1;
  }
  var out2 = Vec[UInt8].new();
  if !err_unit_is(socks5_greeting_build(&mut out2, &too), "socks: too many methods") { ok = false; }

  var high = Vec[Int].new();
  high.push(256);
  var out3 = Vec[UInt8].new();
  if !err_unit_is(socks5_greeting_build(&mut out3, &high), "socks: method out of range") { ok = false; }

  var neg = Vec[Int].new();
  neg.push(-1);
  if !err_unit_is(socks5_greeting_build(&mut out3, &neg), "socks: method out of range") { ok = false; }
  if out2.len() != 0 { ok = false; }
  if out3.len() != 0 { ok = false; }
  return assert(ok, "255 methods round-trip; 256 methods and 256/-1 are Err");
}

fn t4() -> TestResult {
  var ok = err_greeting_is(socks5_greeting_parse(&hb("05")), "socks: truncated greeting");
  if !err_greeting_is(socks5_greeting_parse(&hb("")), "socks: truncated greeting") { ok = false; }
  if !err_greeting_is(socks5_greeting_parse(&hb("040100")), "socks: bad version") { ok = false; }
  if !err_greeting_is(socks5_greeting_parse(&hb("0502")), "socks: truncated methods") { ok = false; }
  if !err_greeting_is(socks5_greeting_parse(&hb("050200")), "socks: truncated methods") { ok = false; }
  if !err_greeting_is(socks5_greeting_parse(&hb("0502ff")), "socks: truncated methods") { ok = false; }
  let exact2 = socks5_greeting_parse(&hb("05020001"));
  if !exact2.is_ok { ok = false; } else {
    let g2: Socks5Greeting = exact2.value;
    if g2.methods.len() != 2 { ok = false; }
  }
  return assert(ok, "greeting errors: truncation and bad version are Err");
}

fn t5() -> TestResult {
  var ok = true;
  let r0 = socks5_choice_parse(&hb("0500"));
  if !r0.is_ok { ok = false; } else {
    let c0: Socks5Choice = r0.value;
    if c0.method != 0 { ok = false; }
  }
  let r2 = socks5_choice_parse(&hb("0502"));
  if !r2.is_ok { ok = false; } else {
    let c2: Socks5Choice = r2.value;
    if c2.method != 2 { ok = false; }
  }
  let rf = socks5_choice_parse(&hb("05ff"));
  if !rf.is_ok { ok = false; } else {
    let cf: Socks5Choice = rf.value;
    if cf.method != 255 { ok = false; }
  }

  var out = Vec[UInt8].new();
  let rb = socks5_choice_build(&mut out, 255);
  if !rb.is_ok { ok = false; }
  if !bytes_equal(out, hb("05ff")) { ok = false; }

  if !err_choice_is(socks5_choice_parse(&hb("05")), "socks: truncated choice") { ok = false; }
  if !err_choice_is(socks5_choice_parse(&hb("")), "socks: truncated choice") { ok = false; }
  if !err_choice_is(socks5_choice_parse(&hb("0400")), "socks: bad version") { ok = false; }
  let extra = socks5_choice_parse(&hb("0500ff00"));
  if !extra.is_ok { ok = false; } else {
    let ce: Socks5Choice = extra.value;
    if ce.method != 0 { ok = false; }
  }

  var out2 = Vec[UInt8].new();
  if !err_unit_is(socks5_choice_build(&mut out2, 256), "socks: method out of range") { ok = false; }
  if !err_unit_is(socks5_choice_build(&mut out2, -1), "socks: method out of range") { ok = false; }
  if out2.len() != 0 { ok = false; }
  return assert(ok, "method selection: 0x00/0x02/0xFF parse; bad version and range are Err");
}

fn t6() -> TestResult {
  let a = hb("c0a80001");
  var out = Vec[UInt8].new();
  let r = socks5_request_build(&mut out, CMD_CONNECT, ATYP_IPV4, &a, 80);
  var ok = r.is_ok;
  if !bytes_equal(out, hb("05010001c0a800010050")) { ok = false; }
  if out.len() != 10 { ok = false; }

  var out2 = Vec[UInt8].new();
  let r2 = socks5_request_build(&mut out2, 1, 1, &a, 0);
  if !r2.is_ok { ok = false; }
  if !bytes_equal(out2, hb("05010001c0a800010000")) { ok = false; }

  var out3 = Vec[UInt8].new();
  let r3 = socks5_request_build(&mut out3, 3, 1, &a, 65535);
  if !r3.is_ok { ok = false; }
  if !bytes_equal(out3, hb("05030001c0a80001ffff")) { ok = false; }
  return assert(ok, "CONNECT request build writes exact IPv4 bytes (ports 0 and 65535)");
}

fn t7() -> TestResult {
  let data = hb("05010001c0a800010050");
  let r = socks5_request_parse(&data);
  if !r.is_ok { return assert(false, "IPv4 request must parse"); }
  let q: Socks5Request = r.value;
  var ok = q.cmd == 1;
  if q.atyp != 1 { ok = false; }
  if q.port != 80 { ok = false; }
  let a: Vec[UInt8] = q.addr;
  if a.len() != 4 { ok = false; }
  if !bytes_equal(a, hb("c0a80001")) { ok = false; }
  return assert(ok, "CONNECT request parse pins cmd/atyp/addr/port");
}

fn t8() -> TestResult {
  let dom = socks5_domain_bytes("example.com");
  var out = Vec[UInt8].new();
  let r = socks5_request_build(&mut out, 1, 3, &dom, 443);
  var ok = r.is_ok;
  let want = cat(cat(hb("050100030b"), dom), hb("01bb"));
  if !bytes_equal(out, want) { ok = false; }
  if out.len() != 18 { ok = false; }
  let pr = socks5_request_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let q: Socks5Request = pr.value;
    if q.atyp != 3 { ok = false; }
    if q.port != 443 { ok = false; }
    let back: Vec[UInt8] = q.addr;
    if back.len() != 11 { ok = false; }
    if !bytes_equal(back, dom) { ok = false; }
  }

  let longdom = repeat_byte(97, 255);
  var out2 = Vec[UInt8].new();
  let r2 = socks5_request_build(&mut out2, 1, 3, &longdom, 0);
  if !r2.is_ok { ok = false; }
  if out2.len() != 262 { ok = false; }
  let dlen: UInt8 = out2[4];
  if (dlen as Int) != 255 { ok = false; }
  let pr2 = socks5_request_parse(&out2);
  if !pr2.is_ok { ok = false; } else {
    let q2: Socks5Request = pr2.value;
    let back2: Vec[UInt8] = q2.addr;
    if back2.len() != 255 { ok = false; }
    if !bytes_equal(back2, longdom) { ok = false; }
  }
  return assert(ok, "domain request round-trips at 11 and 255 bytes");
}

fn t9() -> TestResult {
  let a = hb("fe800000000000000000000000000001");
  var out = Vec[UInt8].new();
  let r = socks5_request_build(&mut out, 1, 4, &a, 65535);
  var ok = r.is_ok;
  if !bytes_equal(out, hb("05010004fe800000000000000000000000000001ffff")) { ok = false; }
  if out.len() != 22 { ok = false; }
  let pr = socks5_request_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let q: Socks5Request = pr.value;
    if q.atyp != 4 { ok = false; }
    if q.port != 65535 { ok = false; }
    let back: Vec[UInt8] = q.addr;
    if back.len() != 16 { ok = false; }
    if !bytes_equal(back, a) { ok = false; }
  }
  return assert(ok, "IPv6 request round-trips 16 high-bit address bytes");
}

fn t10() -> TestResult {
  var ok = err_request_is(socks5_request_parse(&hb("050100")), "socks: truncated request");
  if !err_request_is(socks5_request_parse(&hb("04010001c0a800010050")), "socks: bad version") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05000001c0a800010050")), "socks: unknown command") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05040001c0a800010050")), "socks: unknown command") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05010101c0a800010050")), "socks: bad reserved byte") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05010000c0a800010050")), "socks: unknown address type") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05010002c0a800010050")), "socks: unknown address type") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05010005c0a800010050")), "socks: unknown address type") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05010001c0a8")), "socks: truncated address") { ok = false; }
  let cut6 = cat(hb("05010004"), repeat_byte(254, 15));
  if !err_request_is(socks5_request_parse(&cut6), "socks: truncated address") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05010001c0a8000100")), "socks: truncated port") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("05010003")), "socks: truncated address") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("0501000300")), "socks: empty domain") { ok = false; }
  if !err_request_is(socks5_request_parse(&hb("050100030a6162")), "socks: truncated address") { ok = false; }

  let trailing = hb("05010001c0a800010050ffff");
  let tr = socks5_request_parse(&trailing);
  if !tr.is_ok { ok = false; } else {
    let q: Socks5Request = tr.value;
    if q.port != 80 { ok = false; }
  }
  return assert(ok, "request parse errors: version, cmd, RSV, atyp, truncation, empty domain");
}

fn t11() -> TestResult {
  let ip4 = hb("c0a80001");
  var out = Vec[UInt8].new();
  var ok = err_unit_is(socks5_request_build(&mut out, 0, 1, &ip4, 80), "socks: unknown command");
  if !err_unit_is(socks5_request_build(&mut out, 4, 1, &ip4, 80), "socks: unknown command") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 0, &ip4, 80), "socks: unknown address type") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 2, &ip4, 80), "socks: unknown address type") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 5, &ip4, 80), "socks: unknown address type") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 1, &hb("c0a800"), 80), "socks: bad IPv4 length") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 1, &hb("c0a8000102"), 80), "socks: bad IPv4 length") { ok = false; }
  var empty = Vec[UInt8].new();
  if !err_unit_is(socks5_request_build(&mut out, 1, 3, &empty, 80), "socks: empty domain") { ok = false; }
  let longdom = repeat_byte(97, 256);
  if !err_unit_is(socks5_request_build(&mut out, 1, 3, &longdom, 80), "socks: domain too long") { ok = false; }
  let ip6short = repeat_byte(0, 15);
  if !err_unit_is(socks5_request_build(&mut out, 1, 4, &ip6short, 80), "socks: bad IPv6 length") { ok = false; }
  let ip6long = repeat_byte(0, 17);
  if !err_unit_is(socks5_request_build(&mut out, 1, 4, &ip6long, 80), "socks: bad IPv6 length") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 1, &ip4, -1), "socks: port out of range") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 1, &ip4, 65536), "socks: port out of range") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 1, 0, &ip4, -1), "socks: unknown address type") { ok = false; }
  if !err_unit_is(socks5_request_build(&mut out, 0, 1, &ip4, 70000), "socks: unknown command") { ok = false; }
  if out.len() != 0 { ok = false; }
  return assert(ok, "request build errors are atomic and reported in check order");
}

fn t12() -> TestResult {
  let a = hb("0a000001");
  var out = Vec[UInt8].new();
  let r = socks5_reply_build(&mut out, REP_SUCCEEDED, ATYP_IPV4, &a, 1080);
  var ok = r.is_ok;
  if !bytes_equal(out, hb("050000010a0000010438")) { ok = false; }
  if out.len() != 10 { ok = false; }
  let pr = socks5_reply_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let q: Socks5Reply = pr.value;
    if q.rep != 0 { ok = false; }
    if q.atyp != 1 { ok = false; }
    if q.port != 1080 { ok = false; }
    let back: Vec[UInt8] = q.addr;
    if !bytes_equal(back, hb("0a000001")) { ok = false; }
  }
  return assert(ok, "reply build/parse pins REP, ATYP, BND.ADDR and BND.PORT");
}

fn t13() -> TestResult {
  var ok = true;
  let a = hb("00000000");
  var rep = 0;
  while rep <= 8 {
    var out = Vec[UInt8].new();
    let r = socks5_reply_build(&mut out, rep, 1, &a, 0);
    if !r.is_ok { ok = false; }
    if out.len() != 10 { ok = false; }
    let b1: UInt8 = out[1];
    if (b1 as Int) != rep { ok = false; }
    let pr = socks5_reply_parse(&out);
    if !pr.is_ok { ok = false; } else {
      let q: Socks5Reply = pr.value;
      if q.rep != rep { ok = false; }
    }
    rep = rep + 1;
  }

  var out2 = Vec[UInt8].new();
  if !err_unit_is(socks5_reply_build(&mut out2, 9, 1, &a, 0), "socks: unknown reply code") { ok = false; }
  if !err_unit_is(socks5_reply_build(&mut out2, -1, 1, &a, 0), "socks: unknown reply code") { ok = false; }
  if !err_reply_is(socks5_reply_parse(&hb("05090001000000000000")), "socks: unknown reply code") { ok = false; }
  if !err_reply_is(socks5_reply_parse(&hb("05ff0001000000000000")), "socks: unknown reply code") { ok = false; }
  if out2.len() != 0 { ok = false; }
  return assert(ok, "all REP codes 0x00..0x08 round-trip; 0x09/0xFF and -1 are Err");
}

fn t14() -> TestResult {
  var ok = err_reply_is(socks5_reply_parse(&hb("0500")), "socks: truncated reply");
  if !err_reply_is(socks5_reply_parse(&hb("0400000100000000")), "socks: bad version") { ok = false; }
  if !err_reply_is(socks5_reply_parse(&hb("05000101000000000000")), "socks: bad reserved byte") { ok = false; }
  if !err_reply_is(socks5_reply_parse(&hb("0500000000000000")), "socks: unknown address type") { ok = false; }
  if !err_reply_is(socks5_reply_parse(&hb("05000001c0a8")), "socks: truncated address") { ok = false; }
  if !err_reply_is(socks5_reply_parse(&hb("05000001c0a8000100")), "socks: truncated port") { ok = false; }
  if !err_reply_is(socks5_reply_parse(&hb("0500000300")), "socks: empty domain") { ok = false; }

  let dom = bytes_of("abc");
  var out = Vec[UInt8].new();
  let r = socks5_reply_build(&mut out, 0, 3, &dom, 80);
  if !r.is_ok { ok = false; }
  if !bytes_equal(out, hb("05000003036162630050")) { ok = false; }
  let pr = socks5_reply_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let q: Socks5Reply = pr.value;
    if q.rep != 0 { ok = false; }
    if q.atyp != 3 { ok = false; }
    if q.port != 80 { ok = false; }
    let back: Vec[UInt8] = q.addr;
    if !bytes_equal(back, dom) { ok = false; }
  }
  return assert(ok, "reply errors are Err; a domain reply round-trips");
}

fn t15() -> TestResult {
  let u = bytes_of("user");
  let p = bytes_of("pass");
  var out = Vec[UInt8].new();
  let r = socks5_auth_build(&mut out, &u, &p);
  var ok = r.is_ok;
  if !bytes_equal(out, hb("0104757365720470617373")) { ok = false; }
  let pr = socks5_auth_parse(&out);
  if !pr.is_ok { ok = false; } else {
    let q: Socks5UserPass = pr.value;
    let ub: Vec[UInt8] = q.uname;
    let pb: Vec[UInt8] = q.passwd;
    if !bytes_equal(ub, u) { ok = false; }
    if !bytes_equal(pb, p) { ok = false; }
  }

  let e = hb("01017500");
  let pe = socks5_auth_parse(&e);
  if !pe.is_ok { ok = false; } else {
    let qe: Socks5UserPass = pe.value;
    let ub2: Vec[UInt8] = qe.uname;
    let pb2: Vec[UInt8] = qe.passwd;
    if ub2.len() != 1 { ok = false; }
    if pb2.len() != 0 { ok = false; }
    let ub0: UInt8 = ub2[0];
    if (ub0 as Int) != 117 { ok = false; }
  }

  let u255 = repeat_byte(65, 255);
  let p255 = repeat_byte(66, 255);
  var big = Vec[UInt8].new();
  let rb = socks5_auth_build(&mut big, &u255, &p255);
  if !rb.is_ok { ok = false; }
  if big.len() != 513 { ok = false; }
  let pbig = socks5_auth_parse(&big);
  if !pbig.is_ok { ok = false; } else {
    let qb: Socks5UserPass = pbig.value;
    let ub3: Vec[UInt8] = qb.uname;
    let pb3: Vec[UInt8] = qb.passwd;
    if ub3.len() != 255 { ok = false; }
    if pb3.len() != 255 { ok = false; }
    let firstu: UInt8 = ub3[0];
    let lastp: UInt8 = pb3[254];
    if (firstu as Int) != 65 { ok = false; }
    if (lastp as Int) != 66 { ok = false; }
  }
  return assert(ok, "auth request round-trips, including empty password and 255-byte fields");
}

fn t16() -> TestResult {
  var ok = err_userpass_is(socks5_auth_parse(&hb("01")), "socks: truncated auth request");
  if !err_userpass_is(socks5_auth_parse(&hb("02017500")), "socks: bad auth version") { ok = false; }
  if !err_userpass_is(socks5_auth_parse(&hb("0000")), "socks: bad auth version") { ok = false; }
  if !err_userpass_is(socks5_auth_parse(&hb("0100")), "socks: empty username") { ok = false; }
  if !err_userpass_is(socks5_auth_parse(&hb("010575")), "socks: truncated username") { ok = false; }
  if !err_userpass_is(socks5_auth_parse(&hb("010175")), "socks: truncated password") { ok = false; }
  if !err_userpass_is(socks5_auth_parse(&hb("010175056162")), "socks: truncated password") { ok = false; }

  var out = Vec[UInt8].new();
  var empty = Vec[UInt8].new();
  let u = bytes_of("u");
  if !err_unit_is(socks5_auth_build(&mut out, &empty, &u), "socks: empty username") { ok = false; }
  let u256 = repeat_byte(65, 256);
  if !err_unit_is(socks5_auth_build(&mut out, &u256, &empty), "socks: username too long") { ok = false; }
  let p256 = repeat_byte(66, 256);
  if !err_unit_is(socks5_auth_build(&mut out, &u, &p256), "socks: password too long") { ok = false; }
  if out.len() != 0 { ok = false; }
  return assert(ok, "auth request errors: version, empty/truncated fields, oversized credentials");
}

fn t17() -> TestResult {
  var out = Vec[UInt8].new();
  let r0 = socks5_auth_reply_build(&mut out, 0);
  var ok = r0.is_ok;
  if !bytes_equal(out, hb("0100")) { ok = false; }
  var out1 = Vec[UInt8].new();
  let r1 = socks5_auth_reply_build(&mut out1, 1);
  if !r1.is_ok { ok = false; }
  if !bytes_equal(out1, hb("0101")) { ok = false; }
  var out2 = Vec[UInt8].new();
  let r2 = socks5_auth_reply_build(&mut out2, 255);
  if !r2.is_ok { ok = false; }
  if !bytes_equal(out2, hb("01ff")) { ok = false; }

  let p0 = socks5_auth_reply_parse(&hb("0100"));
  if !p0.is_ok { ok = false; } else {
    let q0: Socks5AuthReply = p0.value;
    if q0.status != 0 { ok = false; }
  }
  let pf = socks5_auth_reply_parse(&hb("01ff"));
  if !pf.is_ok { ok = false; } else {
    let qf: Socks5AuthReply = pf.value;
    if qf.status != 255 { ok = false; }
  }

  if !err_auth_reply_is(socks5_auth_reply_parse(&hb("01")), "socks: truncated auth reply") { ok = false; }
  if !err_auth_reply_is(socks5_auth_reply_parse(&hb("0000")), "socks: bad auth version") { ok = false; }
  if !err_auth_reply_is(socks5_auth_reply_parse(&hb("0200")), "socks: bad auth version") { ok = false; }

  var out3 = Vec[UInt8].new();
  if !err_unit_is(socks5_auth_reply_build(&mut out3, -1), "socks: status out of range") { ok = false; }
  if !err_unit_is(socks5_auth_reply_build(&mut out3, 256), "socks: status out of range") { ok = false; }
  if out3.len() != 0 { ok = false; }
  return assert(ok, "auth status reply: 0/1/255 round-trip; bad version and status are Err");
}

fn t18() -> TestResult {
  var ok = request_roundtrip(1, hb("ffffffff"), 65535);
  if !request_roundtrip(4, repeat_byte(255, 16), 0) { ok = false; }
  if !request_roundtrip(3, socks5_domain_bytes("localhost"), 8080) { ok = false; }
  if !reply_roundtrip(0, 1, hb("ffffffff"), 65535) { ok = false; }
  if !reply_roundtrip(8, 4, repeat_byte(255, 16), 1) { ok = false; }
  if !reply_roundtrip(5, 3, socks5_domain_bytes("a.b"), 0) { ok = false; }

  let a6 = repeat_byte(255, 16);
  var out = Vec[UInt8].new();
  let r6 = socks5_request_build(&mut out, 1, 4, &a6, 65535);
  if !r6.is_ok { ok = false; }
  if out.len() != 22 { ok = false; }
  let o4: UInt8 = out[4];
  let o19: UInt8 = out[19];
  let o20: UInt8 = out[20];
  let o21: UInt8 = out[21];
  if (o4 as Int) != 255 { ok = false; }
  if (o19 as Int) != 255 { ok = false; }
  if (o20 as Int) != 255 { ok = false; }
  if (o21 as Int) != 255 { ok = false; }
  return assert(ok, "round-trip matrix: IPv4, IPv6 and domain survive request and reply");
}

fn main() -> Int {
  io.println("=== xiom.socks conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.socks: all tests passed");
  } else {
    io.println("xiom.socks: tests failed");
  }
  return failed;
}
