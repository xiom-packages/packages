// XIOM -- xiom.zonefile conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: $ORIGIN/$TTL directives, relative-name
// completion and "@", omitted name/TTL inheritance, class defaulting, type
// case, parenthesized multi-line records, comments, quoted TXT strings with
// \" and \\ escapes, joined TXT text, the per-type token counts, the full
// error catalog, the canonical emitter, round-trip stability and the
// out-of-range accessor behavior.
//
// Str values are compared with compare.str_compare (BUG 17 discipline:
// `==` on Str values read from Vec[Str] elements lowers to a pointer
// comparison); Vec elements are read into typed locals first. No test does
// table-driven Vec[fn] dispatch: every test is called directly from main.
// Expected text is assembled with `+` from short literals so the source
// keeps no ambiguous multi-line string literals.

module zonefile_tests
use xiom.io; use xiom.test;
use xiom.zonefile;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers (independent of src/zonefile.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when zone_parse(text) is Err with exactly `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = zone_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// zone_emit of zone_parse(text), or "" on error (callers compare text, so a
// safe empty result fails the check).
fn emit_of(text: Str) -> Str {
  let r = zone_parse(text);
  match r {
    Ok(z) => { let zz: Zone = z; return zone_emit(&zz); },
    Err(_) => {},
  }
  return "";
}

// True when every accessor of the two documents agrees record by record.
fn zones_equal(a: &Zone, b: &Zone) -> Bool {
  let n = zone_record_count(a);
  if n != zone_record_count(b) { return false; }
  var i = 0;
  while i < n {
    if !streq(zone_name(a, i), zone_name(b, i)) { return false; }
    if zone_ttl(a, i) != zone_ttl(b, i) { return false; }
    if !streq(zone_class(a, i), zone_class(b, i)) { return false; }
    if !streq(zone_type(a, i), zone_type(b, i)) { return false; }
    if zone_rdata_token_count(a, i) != zone_rdata_token_count(b, i) { return false; }
    if !streq(zone_txt_text(a, i), zone_txt_text(b, i)) { return false; }
    var j = 0;
    while j < zone_rdata_token_count(a, i) {
      if !streq(zone_rdata_token(a, i, j), zone_rdata_token(b, i, j)) { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "$TTL 3600\n";
  text = text + "@ IN SOA ns1.example.com. admin.example.com. 2024010101 3600 600 604800 86400\n";
  text = text + "www A 192.0.2.1\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "SOA zone must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 2;
  if !streq(zone_name(&z, 0), "example.com.") { ok = false; }
  if zone_ttl(&z, 0) != 3600 { ok = false; }
  if !streq(zone_class(&z, 0), "IN") { ok = false; }
  if !streq(zone_type(&z, 0), "SOA") { ok = false; }
  if zone_rdata_token_count(&z, 0) != 7 { ok = false; }
  if !streq(zone_rdata_token(&z, 0, 0), "ns1.example.com.") { ok = false; }
  if !streq(zone_rdata_token(&z, 0, 6), "86400") { ok = false; }
  if !streq(zone_name(&z, 1), "www.example.com.") { ok = false; }
  if zone_ttl(&z, 1) != 3600 { ok = false; }
  if !streq(zone_type(&z, 1), "A") { ok = false; }
  if zone_rdata_token_count(&z, 1) != 1 { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), "192.0.2.1") { ok = false; }
  return assert(ok, "SOA zone: origin, @, relative owner, TTL and tokens");
}

fn t2() -> TestResult {
  var text = "$ORIGIN example.com\n";
  text = text + "$ORIGIN sub\n";
  text = text + "@ A 192.0.2.1\n";
  text = text + "abs. CNAME real.example.net.\n";
  text = text + "rel MX 10 mail\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "$ORIGIN chain must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 3;
  if !streq(zone_name(&z, 0), "sub.example.com.") { ok = false; }
  if !streq(zone_name(&z, 1), "abs.") { ok = false; }
  if !streq(zone_name(&z, 2), "rel.sub.example.com.") { ok = false; }
  if !streq(zone_type(&z, 1), "CNAME") { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), "real.example.net.") { ok = false; }
  if zone_rdata_token_count(&z, 2) != 2 { ok = false; }
  if !streq(zone_rdata_token(&z, 2, 0), "10") { ok = false; }
  if !streq(zone_rdata_token(&z, 2, 1), "mail") { ok = false; }
  return assert(ok, "$ORIGIN chaining resolves relative names; absolute names preserved");
}

fn t3() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "$TTL 300\n";
  text = text + "www A 192.0.2.1\n";
  text = text + "    A 192.0.2.2\n";
  text = text + "mail 600 MX 10 mail\n";
  text = text + "     MX 20 backup\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "inheritance zone must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 4;
  if !streq(zone_name(&z, 1), "www.example.com.") { ok = false; }
  if zone_ttl(&z, 1) != 300 { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), "192.0.2.2") { ok = false; }
  if !streq(zone_name(&z, 3), "mail.example.com.") { ok = false; }
  if zone_ttl(&z, 3) != 600 { ok = false; }
  if zone_rdata_token_count(&z, 3) != 2 { ok = false; }
  if !streq(zone_rdata_token(&z, 3, 1), "backup") { ok = false; }
  return assert(ok, "omitted owner and TTL inherit the previous record");
}

fn t4() -> TestResult {
  var text = "WWW.Example.COM. In a 192.0.2.1\n";
  text = text + "mail 300 in MX 5 Mail.Example.Com.\n";
  text = text + "   IN A 192.0.2.9\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "class and case zone must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 3;
  if !streq(zone_name(&z, 0), "WWW.Example.COM.") { ok = false; }
  if !streq(zone_class(&z, 0), "IN") { ok = false; }
  if !streq(zone_type(&z, 0), "A") { ok = false; }
  if !streq(zone_type(&z, 1), "MX") { ok = false; }
  if zone_ttl(&z, 1) != 300 { ok = false; }
  if !streq(zone_name(&z, 2), "mail.") { ok = false; }
  if zone_ttl(&z, 2) != 300 { ok = false; }
  if !streq(zone_type(&z, 2), "A") { ok = false; }
  return assert(ok, "class defaults to IN; type tokens are case-insensitive");
}

fn t5() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "@ IN SOA ns1 admin ( ; open\n";
  text = text + "  2024010101 ; serial\n";
  text = text + "  3600 600 604800 ; timers\n";
  text = text + "  86400 )\n";
  text = text + "  NS ns2\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "parenthesized record must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 2;
  if zone_rdata_token_count(&z, 0) != 7 { ok = false; }
  if !streq(zone_rdata_token(&z, 0, 0), "ns1") { ok = false; }
  if !streq(zone_rdata_token(&z, 0, 1), "admin") { ok = false; }
  if !streq(zone_rdata_token(&z, 0, 2), "2024010101") { ok = false; }
  if !streq(zone_rdata_token(&z, 0, 6), "86400") { ok = false; }
  if !streq(zone_name(&z, 1), "example.com.") { ok = false; }
  if !streq(zone_type(&z, 1), "NS") { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), "ns2") { ok = false; }
  return assert(ok, "parenthesized record spans lines with comments inside");
}

fn t6() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "t1 TXT \"hello world\"\n";
  text = text + "t2 TXT \"a\\\"b\"\n";
  text = text + "t3 TXT \"c\\\\d\"\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "quoted TXT must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 3;
  if !streq(zone_rdata_token(&z, 0, 0), "hello world") { ok = false; }
  if zone_rdata_token_count(&z, 0) != 1 { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), "a\"b") { ok = false; }
  if !streq(zone_txt_text(&z, 1), "a\"b") { ok = false; }
  if !streq(zone_rdata_token(&z, 2, 0), "c\\d") { ok = false; }
  if !streq(zone_txt_text(&z, 2), "c\\d") { ok = false; }
  return assert(ok, "quoted TXT strings decode the documented escapes");
}

fn t7() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "t1 TXT one two three\n";
  text = text + "t2 TXT \"\" \"a;b\"\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "multi-token TXT must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 2;
  if zone_rdata_token_count(&z, 0) != 3 { ok = false; }
  if !streq(zone_txt_text(&z, 0), "one two three") { ok = false; }
  if zone_rdata_token_count(&z, 1) != 2 { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), "") { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 1), "a;b") { ok = false; }
  if !streq(zone_txt_text(&z, 1), " a;b") { ok = false; }
  return assert(ok, "TXT joined text vs token list; empty token");
}

fn t8() -> TestResult {
  var text = "; top comment\n";
  text = text + "www A 192.0.2.1 ; trailing\n";
  text = text + "; another\n";
  text = text + "mail TXT \"x;y\"\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "comment zone must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 2;
  if !streq(zone_name(&z, 0), "www.") { ok = false; }
  if !streq(zone_name(&z, 1), "mail.") { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), "x;y") { ok = false; }
  if !streq(zone_txt_text(&z, 1), "x;y") { ok = false; }
  return assert(ok, "comments run to end of line and not inside quotes");
}

fn t9() -> TestResult {
  var ok = parse_err_is("www A\n", "zonefile: missing rdata");
  if !parse_err_is("www TXT\n", "zonefile: missing rdata") { ok = false; }
  if !parse_err_is("www CNAME ; nothing here\n", "zonefile: missing rdata") { ok = false; }
  if !parse_err_is("$ORIGIN example.com.\nwww SOA a b c d e\n", "zonefile: bad token count") { ok = false; }
  return assert(ok, "missing rdata is rejected");
}

fn t10() -> TestResult {
  var ok = parse_err_is("$ORIGIN example.com.\nwww BOGUS x\n", "zonefile: bad type");
  if !parse_err_is("www\n", "zonefile: bad type") { ok = false; }
  if !parse_err_is("www IN\n", "zonefile: bad type") { ok = false; }
  if !parse_err_is("www SRV 0 5 80 target\n", "zonefile: bad type") { ok = false; }
  if !parse_err_is("www CH A 192.0.2.1\n", "zonefile: bad type") { ok = false; }
  return assert(ok, "unknown or missing type is rejected");
}

fn t11() -> TestResult {
  var ok = parse_err_is("www TXT ( \"ok\"\n", "zonefile: unbalanced parentheses");
  if !parse_err_is("www A ) 1.2.3.4\n", "zonefile: unbalanced parentheses") { ok = false; }
  if !parse_err_is("www A 1.2.3.4 )\n", "zonefile: unbalanced parentheses") { ok = false; }
  if !parse_err_is("www A ( 1.2.3.4\nmail A 192.0.2.1\n", "zonefile: unbalanced parentheses") { ok = false; }
  let r = zone_parse("www A ( 1.2.3.4 )\n");
  if !r.is_ok { return assert(false, "balanced parentheses must parse"); }
  let z: Zone = r.value;
  if zone_record_count(&z) != 1 { ok = false; }
  if !streq(zone_rdata_token(&z, 0, 0), "1.2.3.4") { ok = false; }
  return assert(ok, "unbalanced parentheses are rejected");
}

fn t12() -> TestResult {
  var ok = parse_err_is("$ORIGIN example.com.\nmail MX 10\n", "zonefile: bad token count");
  if !parse_err_is("www A 1.2.3.4 5.6.7.8\n", "zonefile: bad token count") { ok = false; }
  if !parse_err_is("www NS a b\n", "zonefile: bad token count") { ok = false; }
  if !parse_err_is("@ SOA a b c d e f\n", "zonefile: bad token count") { ok = false; }
  if !parse_err_is("@ SOA a b c d e f g h\n", "zonefile: bad token count") { ok = false; }
  let r = zone_parse("txt TXT a b c d\n");
  if !r.is_ok { return assert(false, "TXT accepts one or more tokens"); }
  let z: Zone = r.value;
  if zone_rdata_token_count(&z, 0) != 4 { ok = false; }
  return assert(ok, "per-type RDATA token counts are enforced");
}

fn t13() -> TestResult {
  var ok = parse_err_is("www TXT \"abc\n", "zonefile: unterminated quote");
  if !parse_err_is("www TXT \"abc", "zonefile: unterminated quote") { ok = false; }
  if !parse_err_is("www TXT \"a\nb\"\n", "zonefile: unterminated quote") { ok = false; }
  if !parse_err_is("www TXT \"a\\\"\n", "zonefile: unterminated quote") { ok = false; }
  return assert(ok, "unterminated quotes are rejected");
}

fn t14() -> TestResult {
  var ok = parse_err_is("$ORIGIN\n", "zonefile: $ORIGIN without value");
  if !parse_err_is("$ORIGIN a b\n", "zonefile: bad $ORIGIN") { ok = false; }
  if !parse_err_is("$TTL\n", "zonefile: $TTL without value") { ok = false; }
  if !parse_err_is("$TTL abc\n", "zonefile: bad $TTL") { ok = false; }
  if !parse_err_is("$TTL 4294967296\n", "zonefile: bad $TTL") { ok = false; }
  if !parse_err_is("$INCLUDE other.zone\n", "zonefile: unknown directive") { ok = false; }
  let r = zone_parse("$ORIGIN example.com. ; ok\nwww A 192.0.2.1\n");
  if !r.is_ok { return assert(false, "directive with trailing comment must parse"); }
  let z: Zone = r.value;
  if zone_record_count(&z) != 1 { ok = false; }
  if !streq(zone_name(&z, 0), "www.example.com.") { ok = false; }
  return assert(ok, "directive errors: $ORIGIN, $TTL, unknown");
}

fn t15() -> TestResult {
  var ok = parse_err_is("www 4294967296 A 1.2.3.4\n", "zonefile: bad TTL");
  if !parse_err_is("   A 1.2.3.4\n", "zonefile: missing name") { ok = false; }
  if !parse_err_is("$TTL 3600\n   A 1.2.3.4\n", "zonefile: missing name") { ok = false; }
  let r = zone_parse("www 0 A 1.2.3.4\n");
  if !r.is_ok { return assert(false, "TTL 0 must parse"); }
  let z: Zone = r.value;
  if zone_ttl(&z, 0) != 0 { ok = false; }
  let r2 = zone_parse("www 4294967295 A 1.2.3.4\n");
  if !r2.is_ok {
    ok = false;
  } else {
    let z2: Zone = r2.value;
    if zone_ttl(&z2, 0) != 4294967295 { ok = false; }
  }
  return assert(ok, "bad TTL and missing owner name are rejected");
}

fn t16() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "$TTL 300\n";
  text = text + "@ IN SOA ns1.example.com. admin.example.com. ( 1 2 3 4 5 )\n";
  text = text + "www A 192.0.2.1\n";
  text = text + "    A 192.0.2.2\n";
  text = text + "txt TXT \"hello world\" \"a\\\"b\"\n";
  text = text + "empty TXT \"\"\n";
  let got = emit_of(text);
  var want = "example.com. 300 IN SOA ns1.example.com. admin.example.com. 1 2 3 4 5\n";
  want = want + "www.example.com. 300 IN A 192.0.2.1\n";
  want = want + "www.example.com. 300 IN A 192.0.2.2\n";
  want = want + "txt.example.com. 300 IN TXT \"hello world\" \"a\\\"b\"\n";
  want = want + "empty.example.com. 300 IN TXT \"\"\n";
  var ok = streq(got, want);
  if !streq(emit_of(""), "") { ok = false; }
  return assert(ok, "canonical emitter: one record per line, deterministic");
}

fn t17() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "$TTL 300\n";
  text = text + "@ IN SOA ns1 admin ( 1 2 3 4 5 )\n";
  text = text + "www A 192.0.2.1\n";
  text = text + "    AAAA 2001:db8::1\n";
  text = text + "mail 600 MX 10 mail.example.com.\n";
  text = text + "txt TXT \"a b\" c\n";
  let r1 = zone_parse(text);
  if !r1.is_ok { return assert(false, "round-trip source must parse"); }
  let z1: Zone = r1.value;
  let e1 = emit_of(text);
  let e2 = emit_of(e1);
  var ok = streq(e1, e2);
  if e1.len() == 0 { ok = false; }
  let r2 = zone_parse(e1);
  if !r2.is_ok {
    ok = false;
  } else {
    let z2: Zone = r2.value;
    if !zones_equal(&z1, &z2) { ok = false; }
  }
  return assert(ok, "round-trip: emit is stable and preserves every accessor");
}

fn t18() -> TestResult {
  let r0 = zone_parse("");
  if !r0.is_ok { return assert(false, "empty zone must parse"); }
  let z0: Zone = r0.value;
  var ok = zone_record_count(&z0) == 0;
  if !streq(zone_name(&z0, 0), "") { ok = false; }
  if zone_ttl(&z0, 0) != -1 { ok = false; }
  if !streq(zone_class(&z0, 0), "") { ok = false; }
  if !streq(zone_type(&z0, 0), "") { ok = false; }
  if zone_rdata_token_count(&z0, 0) != 0 { ok = false; }
  if !streq(zone_rdata_token(&z0, 0, 0), "") { ok = false; }
  if !streq(zone_txt_text(&z0, 0), "") { ok = false; }
  if !streq(zone_emit(&z0), "") { ok = false; }
  let r1 = zone_parse("www A 1.2.3.4\n");
  if !r1.is_ok { return assert(false, "one-record zone must parse"); }
  let z1: Zone = r1.value;
  if !streq(zone_name(&z1, -1), "") { ok = false; }
  if !streq(zone_name(&z1, 1), "") { ok = false; }
  if zone_ttl(&z1, 1) != -1 { ok = false; }
  if !streq(zone_type(&z1, -3), "") { ok = false; }
  if zone_rdata_token_count(&z1, 1) != 0 { ok = false; }
  if !streq(zone_rdata_token(&z1, 0, -1), "") { ok = false; }
  if !streq(zone_rdata_token(&z1, 0, 1), "") { ok = false; }
  if !streq(zone_txt_text(&z1, 0), "") { ok = false; }
  if !streq(zone_txt_text(&z1, 5), "") { ok = false; }
  return assert(ok, "accessors clamp out-of-range indexes; empty zone");
}

fn t19() -> TestResult {
  var text = "$ORIGIN example.com.\n";
  text = text + "@ NS ns1\n";
  text = text + "@ A 192.0.2.1\n";
  text = text + "@ AAAA 2001:db8::1\n";
  text = text + "@ CNAME target\n";
  text = text + "@ MX 10 mail\n";
  text = text + "@ TXT \"hi\"\n";
  text = text + "@ PTR ptr.example.net.\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "all-types zone must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 7;
  if !streq(zone_type(&z, 0), "NS") { ok = false; }
  if !streq(zone_type(&z, 1), "A") { ok = false; }
  if !streq(zone_type(&z, 2), "AAAA") { ok = false; }
  if !streq(zone_type(&z, 3), "CNAME") { ok = false; }
  if !streq(zone_type(&z, 4), "MX") { ok = false; }
  if !streq(zone_type(&z, 5), "TXT") { ok = false; }
  if !streq(zone_type(&z, 6), "PTR") { ok = false; }
  if zone_rdata_token_count(&z, 0) != 1 { ok = false; }
  if zone_rdata_token_count(&z, 2) != 1 { ok = false; }
  if zone_rdata_token_count(&z, 4) != 2 { ok = false; }
  if zone_rdata_token_count(&z, 5) != 1 { ok = false; }
  if !streq(zone_name(&z, 6), "example.com.") { ok = false; }
  if !streq(zone_rdata_token(&z, 2, 0), "2001:db8::1") { ok = false; }
  if !streq(zone_rdata_token(&z, 3, 0), "target") { ok = false; }
  if !streq(zone_rdata_token(&z, 4, 0), "10") { ok = false; }
  if !streq(zone_rdata_token(&z, 4, 1), "mail") { ok = false; }
  if !streq(zone_txt_text(&z, 5), "hi") { ok = false; }
  if !streq(zone_rdata_token(&z, 6, 0), "ptr.example.net.") { ok = false; }
  return assert(ok, "all eight documented types parse with their token counts");
}

fn t20() -> TestResult {
  var text = "123 A 192.0.2.1\r\n";
  text = text + "\r\n";
  text = text + "; c\r\n";
  text = text + "@ NS .\r\n";
  let r = zone_parse(text);
  if !r.is_ok { return assert(false, "CRLF root zone must parse"); }
  let z: Zone = r.value;
  var ok = zone_record_count(&z) == 2;
  if !streq(zone_name(&z, 0), "123.") { ok = false; }
  if zone_ttl(&z, 0) != 0 { ok = false; }
  if !streq(zone_type(&z, 0), "A") { ok = false; }
  if !streq(zone_name(&z, 1), ".") { ok = false; }
  if !streq(zone_type(&z, 1), "NS") { ok = false; }
  if !streq(zone_rdata_token(&z, 1, 0), ".") { ok = false; }
  return assert(ok, "root origin, numeric owner, CRLF and blank lines");
}

fn main() -> Int {
  io.println("=== xiom.zonefile conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.zonefile: all tests passed");
  } else {
    io.println("xiom.zonefile: tests failed");
  }
  return failed;
}
