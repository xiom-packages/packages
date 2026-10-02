// XIOM -- xiom.saml conformance tests (28 checks)
// Port task: prove the SAML 2.0 structure toolkit against the rules
// documented in SPEC.md. Every check is one fn returning TestResult via
// assert(cond, "name"); main returns the failure count (0 = green). All
// fixtures are inline; there are no external files.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// BUG 17 discipline: all Str equality goes through
// xiom.string.compare.str_compare (never `==` on Str values read from a Vec),
// every Vec element read is widened with `(x as Int) & 0xFF`, and every Str
// read out of a Struct or Result field is bound to a typed local first.

module saml_tests

use xiom.io;
use xiom.test;
use xiom.saml;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn has_prefix(s: Str, p: Str) -> Bool {
  if p.len() > s.len() {
    return false;
  }
  let head = string.str_slice(s, 0, p.len());
  return streq(head, p);
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

// Byte i of v widened to Int space.
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

// True when r is Err with a message starting with `prefix`.
fn str_err_prefix(r: Result[Str, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
}

// True when r is Ok(v) with v == want.
fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// True when r is Err with a message starting with `prefix`.
fn int_err_prefix(r: Result[Int, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
}

// True when r is Err with a message starting with `prefix`.
fn doc_err_prefix(r: Result[XmlDoc, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
}

// True when r is Err with a message starting with `prefix`.
fn assertion_err_prefix(r: Result[SamlAssertion, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
}

// True when r is Err with a message starting with `prefix`.
fn response_err_prefix(r: Result[SamlResponse, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
}

// True when r is Err with a message starting with `prefix`.
fn meta_err_prefix(r: Result[SamlIdpMetadata, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
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

// True when the Str Vec has exactly n entries and entry i equals want.
fn vec_str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() {
    return false;
  }
  let x: Str = v[i];
  return streq(x, want);
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

const ASSERTION_XML: Str = "<saml:Assertion xmlns:saml=\"urn:oasis:names:tc:SAML:2.0:assertion\" ID=\"_a1\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\"><saml:Issuer>https://idp.example.org</saml:Issuer><saml:Subject><saml:NameID Format=\"urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress\">alice@example.com</saml:NameID><saml:SubjectConfirmation Method=\"urn:oasis:names:tc:SAML:2.0:cm:bearer\"><saml:SubjectConfirmationData Recipient=\"https://sp.example.org/acs\" InResponseTo=\"_req1\" NotOnOrAfter=\"2026-10-02T12:05:00Z\"/></saml:SubjectConfirmation></saml:Subject><saml:Conditions NotBefore=\"2026-10-02T11:59:00Z\" NotOnOrAfter=\"2026-10-02T12:05:00Z\"><saml:AudienceRestriction><saml:Audience>https://sp.example.org</saml:Audience></saml:AudienceRestriction></saml:Conditions><saml:AuthnStatement AuthnInstant=\"2026-10-02T12:00:00Z\" SessionIndex=\"_s1\"/><saml:AttributeStatement><saml:Attribute Name=\"role\" NameFormat=\"urn:oasis:names:tc:SAML:2.0:attrname-format:basic\" FriendlyName=\"Role\"><saml:AttributeValue>admin</saml:AttributeValue><saml:AttributeValue>editor</saml:AttributeValue></saml:Attribute><saml:Attribute Name=\"email\"><saml:AttributeValue>alice@example.com</saml:AttributeValue></saml:Attribute></saml:AttributeStatement></saml:Assertion>";

const RESPONSE_XML: Str = "<samlp:Response xmlns:samlp=\"urn:oasis:names:tc:SAML:2.0:protocol\" xmlns:saml=\"urn:oasis:names:tc:SAML:2.0:assertion\" ID=\"_r1\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\" Destination=\"https://sp.example.org/acs\" InResponseTo=\"_req1\"><saml:Issuer>https://idp.example.org</saml:Issuer><samlp:Status><samlp:StatusCode Value=\"urn:oasis:names:tc:SAML:2.0:status:Success\"/></samlp:Status><saml:Assertion ID=\"_a1\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\"><saml:Issuer>https://idp.example.org</saml:Issuer><saml:Subject><saml:NameID>alice@example.com</saml:NameID></saml:Subject></saml:Assertion></samlp:Response>";

const METADATA_XML: Str = "<md:EntityDescriptor xmlns:md=\"urn:oasis:names:tc:SAML:2.0:metadata\" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\" entityID=\"https://idp.example.org/metadata\"><md:IDPSSODescriptor protocolSupportEnumeration=\"urn:oasis:names:tc:SAML:2.0:protocol\" WantAuthnRequestsSigned=\"true\"><md:KeyDescriptor use=\"signing\"><ds:KeyInfo><ds:X509Data><ds:X509Certificate>TUlJQ0F3\nPT0K</ds:X509Certificate></ds:X509Data></ds:KeyInfo></md:KeyDescriptor><md:SingleSignOnService Binding=\"urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect\" Location=\"https://idp.example.org/sso\"/><md:SingleSignOnService Binding=\"urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST\" Location=\"https://idp.example.org/sso/post\"/></md:IDPSSODescriptor></md:EntityDescriptor>";

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let dr = saml_xml_parse("<a><b x=\"1\">t</b><c/></a>");
  var ok = dr.is_ok;
  if dr.is_ok {
    let d: XmlDoc = dr.value;
    let root = saml_xml_root(&d);
    ok = ok && saml_xml_node_kind(&d, root) == 0;
    ok = ok && streq(saml_xml_node_name(&d, root), "a");
    ok = ok && saml_xml_node_depth(&d, root) == 1;
    ok = ok && saml_xml_child_count(&d, root) == 2;
    let b = saml_xml_child_by_name(&d, root, "b");
    ok = ok && b > 0;
    ok = ok && streq(saml_xml_text(&d, b), "t");
    let ar = saml_xml_attr(&d, b, "x");
    ok = ok && ar.is_ok;
    if ar.is_ok {
      let av: Str = ar.value;
      ok = ok && streq(av, "1");
    }
    let c = saml_xml_child_by_name(&d, root, "c");
    ok = ok && c > 0;
    ok = ok && saml_xml_child_count(&d, c) == 0;
    ok = ok && saml_xml_node_depth(&d, b) == 2;
  }
  return assert(ok, "xml: elements, attributes, text, self-closing, depth");
}

fn t2() -> TestResult {
  let dr = saml_xml_parse("<r a=\"&lt;&amp;&quot;&apos;\">&lt;&amp;&gt;&quot;&apos;&#65;&#x42;</r>");
  var ok = dr.is_ok;
  if dr.is_ok {
    let d: XmlDoc = dr.value;
    let root = saml_xml_root(&d);
    ok = ok && streq(saml_xml_text(&d, root), "<&>\"'AB");
    let ar = saml_xml_attr(&d, root, "a");
    ok = ok && ar.is_ok;
    if ar.is_ok {
      let av: Str = ar.value;
      ok = ok && streq(av, "<&\"'");
    }
  }
  return assert(ok, "xml: predefined and numeric character references");
}

fn t3() -> TestResult {
  let dr = saml_xml_parse("<?xml version=\"1.0\"?><!-- before --><r><!-- in --><?pi x?>t</r><!-- after -->");
  var ok = dr.is_ok;
  if dr.is_ok {
    let d: XmlDoc = dr.value;
    let root = saml_xml_root(&d);
    ok = ok && root > 0;
    ok = ok && streq(saml_xml_text(&d, root), "t");
    ok = ok && saml_xml_child_count(&d, root) == 0;
  }
  return assert(ok, "xml: processing instructions and comments are skipped");
}

fn t4() -> TestResult {
  let dr = saml_xml_parse("<r><![CDATA[a<b&c]]></r>");
  var ok = dr.is_ok;
  if dr.is_ok {
    let d: XmlDoc = dr.value;
    let root = saml_xml_root(&d);
    ok = ok && streq(saml_xml_text(&d, root), "a<b&c");
  }
  return assert(ok, "xml: CDATA sections are copied verbatim");
}

fn t5() -> TestResult {
  let dr = saml_xml_parse("<saml:Assertion xmlns:saml=\"urn:oasis:names:tc:SAML:2.0:assertion\"><saml:Issuer>https://idp.example.org</saml:Issuer></saml:Assertion>");
  var ok = dr.is_ok;
  if dr.is_ok {
    let d: XmlDoc = dr.value;
    let root = saml_xml_root(&d);
    ok = ok && streq(saml_xml_node_name(&d, root), "saml:Assertion");
    ok = ok && streq(saml_xml_node_local(&d, root), "Assertion");
    ok = ok && saml_xml_attr_count(&d, root) == 1;
    ok = ok && streq(saml_xml_attr_name_at(&d, root, 0), "xmlns:saml");
    let issuer = saml_xml_child_by_name(&d, root, "Issuer");
    ok = ok && issuer > 0;
    ok = ok && streq(saml_xml_text(&d, issuer), "https://idp.example.org");
  }
  return assert(ok, "xml: namespace prefixes and local-name queries");
}

fn t6() -> TestResult {
  let e1 = saml_xml_parse("<a></b>");
  var ok = doc_err_prefix(e1, "saml: mismatched closing tag at offset");
  let e2 = saml_xml_parse("text<a/>");
  ok = ok && doc_err_prefix(e2, "saml: text outside root element");
  let e3 = saml_xml_parse("<a><b></a>");
  ok = ok && doc_err_prefix(e3, "saml: mismatched closing tag");
  let e4 = saml_xml_parse("<a>");
  ok = ok && doc_err_prefix(e4, "saml: unclosed element");
  let e5 = saml_xml_parse("<a/><b/>");
  ok = ok && doc_err_prefix(e5, "saml: multiple root elements");
  let e6 = saml_xml_parse("<a x=\"1\" x=\"2\"/>");
  ok = ok && doc_err_prefix(e6, "saml: duplicate attribute");
  let e7 = saml_xml_parse("<!DOCTYPE a><a/>");
  ok = ok && doc_err_prefix(e7, "saml: unsupported markup declaration");
  let e8 = saml_xml_parse("<!-- never closed <a/>");
  ok = ok && doc_err_prefix(e8, "saml: unclosed comment");
  let e9 = saml_xml_parse("   ");
  ok = ok && doc_err_prefix(e9, "saml: no root element");
  return assert(ok, "xml: malformed documents carry offset-bearing errors");
}

fn t7() -> TestResult {
  let e1 = saml_xml_parse("<r>&bogus;</r>");
  var ok = doc_err_prefix(e1, "saml: invalid character reference");
  let e2 = saml_xml_parse("<r>&#0;</r>");
  ok = ok && doc_err_prefix(e2, "saml: invalid character reference");
  let e3 = saml_xml_parse("<r>&#x110000;</r>");
  ok = ok && doc_err_prefix(e3, "saml: invalid character reference");
  let e4 = saml_xml_parse("<r>&amp</r>");
  ok = ok && doc_err_prefix(e4, "saml: unterminated entity");
  let e5 = saml_xml_parse("<r a=\"&bogus;\"/>");
  ok = ok && doc_err_prefix(e5, "saml: invalid character reference");
  let e6 = saml_xml_parse("<r>&#xD800;</r>");
  ok = ok && doc_err_prefix(e6, "saml: invalid character reference");
  return assert(ok, "xml: bad entities and NUL/surrogate references are rejected");
}

fn t8() -> TestResult {
  let deep = repeat_str("<d>", 70) + repeat_str("</d>", 70);
  let dr = saml_xml_parse(deep);
  var ok = doc_err_prefix(dr, "saml: nesting too deep");
  let shallow = repeat_str("<d>", 60) + repeat_str("</d>", 60);
  let dr2 = saml_xml_parse(shallow);
  ok = ok && dr2.is_ok;
  return assert(ok, "xml: nesting is depth-bounded (reject 70, accept 60)");
}

fn t9() -> TestResult {
  let text = "<r a=\"1\"><c /></r>";
  let dr = saml_xml_parse(text);
  var ok = dr.is_ok;
  if dr.is_ok {
    let d: XmlDoc = dr.value;
    let root = saml_xml_root(&d);
    ok = ok && saml_xml_node_open(&d, root) == 0;
    ok = ok && saml_xml_node_close(&d, root) == text.len();
    let raw = saml_xml_node_raw_bytes(&d, root);
    ok = ok && bytes_equal(raw, sb(text));
    let c = saml_xml_child_by_name(&d, root, "c");
    let craw = saml_xml_node_raw_bytes(&d, c);
    ok = ok && bytes_equal(craw, sb("<c />"));
    ok = ok && streq(saml_xml_attr_or(&d, root, "missing", "dflt"), "dflt");
    ok = ok && streq(saml_xml_escape("<a&b>\"'"), "&lt;a&amp;b&gt;&quot;&apos;");
  }
  return assert(ok, "xml: raw spans, defaults and escaping");
}

fn t10() -> TestResult {
  var ok = streq(saml_base64_encode(&sb("")), "");
  ok = ok && streq(saml_base64_encode(&sb("f")), "Zg==");
  ok = ok && streq(saml_base64_encode(&sb("fo")), "Zm8=");
  ok = ok && streq(saml_base64_encode(&sb("foo")), "Zm9v");
  ok = ok && streq(saml_base64_encode(&sb("foob")), "Zm9vYg==");
  ok = ok && streq(saml_base64_encode(&sb("fooba")), "Zm9vYmE=");
  ok = ok && streq(saml_base64_encode(&sb("foobar")), "Zm9vYmFy");
  return assert(ok, "base64 encode: RFC 4648 vectors");
}

fn t11() -> TestResult {
  var ok = streq("", "");
  let d1 = saml_base64_decode("Zg==");
  ok = ok && d1.is_ok;
  if d1.is_ok {
    let b: Vec[UInt8] = d1.value;
    ok = ok && bytes_equal(b, sb("f"));
  }
  let d2 = saml_base64_decode("Zm9vYmFy");
  ok = ok && d2.is_ok;
  if d2.is_ok {
    let b2: Vec[UInt8] = d2.value;
    ok = ok && bytes_equal(b2, sb("foobar"));
  }
  let d3 = saml_base64_decode("Zm9v\nYg==");
  ok = ok && d3.is_ok;
  if d3.is_ok {
    let b3: Vec[UInt8] = d3.value;
    ok = ok && bytes_equal(b3, sb("foob"));
  }
  let d4 = saml_base64_decode("Zm9vYg");
  ok = ok && d4.is_ok;
  if d4.is_ok {
    let b4: Vec[UInt8] = d4.value;
    ok = ok && bytes_equal(b4, sb("foob"));
  }
  let d5 = saml_base64_decode("  Zm8=  ");
  ok = ok && d5.is_ok;
  if d5.is_ok {
    let b5: Vec[UInt8] = d5.value;
    ok = ok && bytes_equal(b5, sb("fo"));
  }
  let d6 = saml_base64_decode("");
  ok = ok && d6.is_ok;
  if d6.is_ok {
    let b6: Vec[UInt8] = d6.value;
    ok = ok && b6.len() == 0;
  }
  return assert(ok, "base64 decode: padding, whitespace, unpadded, empty");
}

fn t12() -> TestResult {
  let e1 = saml_base64_decode("A");
  var ok = false;
  if !e1.is_ok {
    let m1: Str = e1.error;
    ok = has_prefix(m1, "saml: base64 invalid length at offset 0");
  }
  let e2 = saml_base64_decode("!!!!");
  ok = ok && has_prefix(_err_of(e2), "saml: base64 invalid character at offset 0");
  let e3 = saml_base64_decode("Zg=");
  ok = ok && has_prefix(_err_of(e3), "saml: base64 misplaced padding");
  let e4 = saml_base64_decode("Zh==");
  ok = ok && has_prefix(_err_of(e4), "saml: base64 non-canonical trailing bits at offset 1");
  let e5 = saml_base64_decode("Zm=v");
  ok = ok && has_prefix(_err_of(e5), "saml: base64 misplaced padding");
  let r1 = saml_base64_decode("Zm9vYmFy");
  ok = ok && r1.is_ok;
  if r1.is_ok {
    let b1: Vec[UInt8] = r1.value;
    let back = saml_base64_encode(&b1);
    ok = ok && streq(back, "Zm9vYmFy");
  }
  return assert(ok, "base64 decode: length, charset, padding and trailing-bit errors");
}

// Err message of a Result[Vec[UInt8], Str] ("" when Ok).
fn _err_of(r: Result[Vec[UInt8], Str]) -> Str {
  if r.is_ok {
    return "";
  }
  let m: Str = r.error;
  return m;
}

fn t13() -> TestResult {
  var ok = streq(saml_sha256_hex(&sb("")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  ok = ok && streq(saml_sha256_hex(&sb("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  ok = ok && streq(saml_sha256_hex(&sb("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  ok = ok && streq(saml_sha256_hex(&sb("The quick brown fox jumps over the lazy dog")), "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592");
  return assert(ok, "sha256: FIPS 180-4 test vectors");
}

fn t14() -> TestResult {
  let a = saml_sha256_str("abc");
  let b = saml_sha256(&sb("abc"));
  var ok = bytes_equal(a, b);
  ok = ok && a.len() == 32;
  let hex = saml_sha256_hex(&a);
  ok = ok && hex.len() == 64;
  let d2 = saml_sha256_str("abc");
  ok = ok && bytes_equal(a, d2);
  return assert(ok, "sha256: Str and byte views agree; 32-byte digest, 64-char hex");
}

fn t15() -> TestResult {
  var ok = int_ok_is(saml_parse_datetime("1970-01-01T00:00:00Z"), 0);
  ok = ok && int_ok_is(saml_parse_datetime("1970-01-02T00:00:01Z"), 86401);
  ok = ok && int_ok_is(saml_parse_datetime("1970-01-01T01:00:00+01:00"), 0);
  ok = ok && int_ok_is(saml_parse_datetime("1970-01-01T00:00:00.500Z"), 0);
  ok = ok && int_ok_is(saml_parse_datetime("1969-12-31T23:59:59Z"), -1);
  ok = ok && int_err_prefix(saml_parse_datetime("not-a-date"), "saml: invalid datetime");
  ok = ok && int_err_prefix(saml_parse_datetime("2026-02-30T00:00:00Z"), "saml: invalid datetime");
  ok = ok && int_err_prefix(saml_parse_datetime("2026-13-01T00:00:00Z"), "saml: invalid datetime");
  ok = ok && int_err_prefix(saml_parse_datetime("2026-10-02T12:00:00"), "saml: invalid datetime");
  ok = ok && int_err_prefix(saml_parse_datetime("2026-10-02T12:00:60Z"), "saml: invalid datetime");
  return assert(ok, "datetime: epoch math, offsets, fractions and malformed fields");
}

fn t16() -> TestResult {
  var cases = Vec[Int].new();
  cases.push(0);
  cases.push(1);
  cases.push(86401);
  cases.push(1234567890);
  cases.push(1780000000);
  cases.push(-1);
  cases.push(-86400);
  var ok = true;
  var i = 0;
  while i < cases.len() {
    let e: Int = cases[i];
    let text = saml_format_datetime(e);
    let back = saml_parse_datetime(text);
    if !back.is_ok {
      ok = false;
    }
    if back.is_ok {
      if back.value != e {
        ok = false;
      }
    }
    i = i + 1;
  }
  ok = ok && streq(saml_format_datetime(0), "1970-01-01T00:00:00Z");
  ok = ok && streq(saml_format_datetime(-1), "1969-12-31T23:59:59Z");
  return assert(ok, "datetime: format/parse round-trip including negative epochs");
}

fn t17() -> TestResult {
  var ok = true;
  let r1 = saml_parse_datetime("2024-02-29T00:00:00Z");
  ok = r1.is_ok;
  let r2 = saml_parse_datetime("2023-02-29T00:00:00Z");
  ok = ok && !r2.is_ok;
  let r3 = saml_parse_datetime("2000-02-29T00:00:00Z");
  ok = ok && r3.is_ok;
  let r4 = saml_parse_datetime("1900-02-29T00:00:00Z");
  ok = ok && !r4.is_ok;
  return assert(ok, "datetime: leap-year rules (2000 and 2024 leap, 1900 and 2023 not)");
}

fn t18() -> TestResult {
  let issuer = "https://sp.example.org & Co <x>";
  let br = saml_authn_request_build("_req1", issuer, "https://idp.example.org/sso",
                                   "https://sp.example.org/acs", "2026-10-02T12:00:00Z");
  var ok = br.is_ok;
  if br.is_ok {
    let xml: Str = br.value;
    let pr = saml_authn_request_parse(xml);
    ok = ok && pr.is_ok;
    if pr.is_ok {
      let q = pr.value;
      ok = ok && streq(q.id, "_req1");
      ok = ok && streq(q.version, "2.0");
      ok = ok && streq(q.issue_instant, "2026-10-02T12:00:00Z");
      ok = ok && streq(q.destination, "https://idp.example.org/sso");
      ok = ok && streq(q.acs_url, "https://sp.example.org/acs");
      ok = ok && q.has_issuer;
      ok = ok && streq(q.issuer, issuer);
    }
    let payload = saml_post_binding_encode(xml);
    let back = saml_post_binding_decode(payload);
    ok = ok && back.is_ok;
    if back.is_ok {
      let xml2: Str = back.value;
      ok = ok && streq(xml2, xml);
    }
  }
  return assert(ok, "AuthnRequest: build/parse round-trip with escaping and POST binding");
}

fn t19() -> TestResult {
  var ok = streq(_err1(saml_authn_request_build("", "iss", "", "", "2026-10-02T12:00:00Z")), "saml: empty AuthnRequest ID");
  ok = ok && streq(_err1(saml_authn_request_build("id", "", "", "", "2026-10-02T12:00:00Z")), "saml: empty issuer");
  ok = ok && streq(_err1(saml_authn_request_build("id", "iss", "", "", "nope")), "saml: invalid IssueInstant");
  return assert(ok, "AuthnRequest: builder rejects empty ID/issuer and bad IssueInstant");
}

// Err message of a Result[Str, Str] ("" when Ok).
fn _err1(r: Result[Str, Str]) -> Str {
  if r.is_ok {
    return "";
  }
  let m: Str = r.error;
  return m;
}

fn t20() -> TestResult {
  let xml = "<r>Grüße ✓</r>";
  let payload = saml_post_binding_encode(xml);
  let back = saml_post_binding_decode(payload);
  var ok = back.is_ok;
  if back.is_ok {
    let v: Str = back.value;
    ok = ok && streq(v, xml);
  }
  let bad = saml_post_binding_decode("!!!");
  ok = ok && str_err_prefix2(bad, "saml: base64 invalid character");
  var z = Vec[UInt8].new();
  z.push(0);
  let z64 = saml_base64_encode(&z);
  let nul = saml_post_binding_decode(z64);
  ok = ok && str_err_prefix2(nul, "saml: post binding payload contains NUL");
  return assert(ok, "POST binding: unicode round-trip, bad base64, NUL rejection");
}

// True when a Result[Str, Str] is Err with a message starting with `prefix`.
fn str_err_prefix2(r: Result[Str, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
}

fn t21() -> TestResult {
  let ar = saml_assertion_parse(ASSERTION_XML);
  var ok = ar.is_ok;
  if ar.is_ok {
    let a = ar.value;
    ok = ok && streq(a.id, "_a1");
    ok = ok && streq(a.version, "2.0");
    ok = ok && streq(a.issue_instant, "2026-10-02T12:00:00Z");
    ok = ok && a.has_issuer;
    ok = ok && streq(a.issuer, "https://idp.example.org");
    ok = ok && a.subject.has_subject;
    ok = ok && a.subject.has_name_id;
    ok = ok && streq(a.subject.name_id, "alice@example.com");
    ok = ok && streq(a.subject.name_id_format, "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress");
    ok = ok && a.subject.confirmation_count == 1;
    ok = ok && streq(a.subject.recipient, "https://sp.example.org/acs");
    ok = ok && streq(a.subject.in_response_to, "_req1");
    ok = ok && a.conditions.has_not_before;
    ok = ok && a.conditions.has_not_on_or_after;
    ok = ok && a.conditions.has_audience_restriction;
    ok = ok && a.conditions.audiences.len() == 1;
    if a.conditions.audiences.len() == 1 {
      ok = ok && vec_str_at(&a.conditions.audiences, 0, "https://sp.example.org");
    }
    ok = ok && a.has_authn_statement;
    ok = ok && streq(a.authn_instant, "2026-10-02T12:00:00Z");
    ok = ok && streq(a.session_index, "_s1");
    ok = ok && a.attributes.names.len() == 2;
    ok = ok && a.attributes.value_counts.len() == 2;
    if a.attributes.value_counts.len() == 2 {
      let c0: Int = a.attributes.value_counts[0];
      let c1: Int = a.attributes.value_counts[1];
      ok = ok && c0 == 2;
      ok = ok && c1 == 1;
    }
    ok = ok && a.attributes.values.len() == 3;
    ok = ok && saml_assertion_attribute_value_count(&a, "role") == 2;
    let roles = saml_assertion_attribute_values(&a, "role");
    ok = ok && roles.len() == 2;
    ok = ok && vec_str_at(&roles, 0, "admin");
    ok = ok && vec_str_at(&roles, 1, "editor");
    ok = ok && saml_assertion_attribute_value_count(&a, "email") == 1;
    ok = ok && saml_assertion_attribute_value_count(&a, "missing") == 0;
    ok = ok && !a.has_signature;
  }
  return assert(ok, "assertion: issuer, subject, conditions, authn and attributes");
}

// Epoch seconds of a fixture datetime (0 on a parse failure).
fn epoch_of(s: Str) -> Int {
  let r = saml_parse_datetime(s);
  if !r.is_ok {
    return 0;
  }
  return r.value;
}

fn t22() -> TestResult {
  let ar = saml_assertion_parse(ASSERTION_XML);
  var ok = ar.is_ok;
  if ar.is_ok {
    let a = ar.value;
    let noon = epoch_of("2026-10-02T12:00:00Z");
    let early = epoch_of("2026-10-02T11:58:00Z");
    let late = epoch_of("2026-10-02T12:05:00Z");
    let near = epoch_of("2026-10-02T11:58:30Z");
    let past = epoch_of("2026-10-02T12:06:30Z");
    ok = ok && str_ok_is(saml_assertion_valid_at(&a, noon), "");
    ok = ok && streq(_err1(saml_assertion_valid_at(&a, early)), "saml: assertion not yet valid");
    ok = ok && streq(_err1(saml_assertion_valid_at(&a, late)), "saml: assertion expired");
    ok = ok && str_ok_is(saml_assertion_valid_skew(&a, near, 60), "");
    ok = ok && str_ok_is(saml_assertion_valid_skew(&a, late, 60), "");
    ok = ok && streq(_err1(saml_assertion_valid_skew(&a, past, 60)), "saml: assertion expired");
    ok = ok && streq(_err1(saml_assertion_valid_skew(&a, noon, 0 - 1)), "saml: negative clock skew");
    ok = ok && saml_assertion_audience_matches(&a, "https://sp.example.org");
    ok = ok && !saml_assertion_audience_matches(&a, "https://other.example.org");
  }
  return assert(ok, "assertion: validity windows, clock skew and audience matching");
}

fn t23() -> TestResult {
  let rr = saml_response_parse(RESPONSE_XML);
  var ok = rr.is_ok;
  if rr.is_ok {
    let r = rr.value;
    ok = ok && streq(r.id, "_r1");
    ok = ok && streq(r.version, "2.0");
    ok = ok && streq(r.issuer, "https://idp.example.org");
    ok = ok && streq(r.destination, "https://sp.example.org/acs");
    ok = ok && streq(r.in_response_to, "_req1");
    ok = ok && r.has_status;
    ok = ok && streq(r.status_code, "urn:oasis:names:tc:SAML:2.0:status:Success");
    ok = ok && saml_response_is_success(&r);
    ok = ok && saml_response_assertion_count(&r) == 1;
    ok = ok && r.encrypted_assertion_count == 0;
    let a = saml_response_assertion(&r, 0);
    ok = ok && a.is_ok;
    if a.is_ok {
      let av = a.value;
      ok = ok && streq(av.id, "_a1");
      ok = ok && streq(av.issuer, "https://idp.example.org");
    }
    let miss = saml_response_assertion(&r, 5);
    ok = ok && assertion_err_prefix(miss, "saml: assertion index out of range");
  }
  return assert(ok, "response: envelope, success status and assertion extraction");
}

fn t24() -> TestResult {
  let xml = "<samlp:Response xmlns:samlp=\"urn:oasis:names:tc:SAML:2.0:protocol\" ID=\"_r2\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\"><samlp:Status><samlp:StatusCode Value=\"urn:oasis:names:tc:SAML:2.0:status:Requester\"/><samlp:StatusMessage>Denied</samlp:StatusMessage></samlp:Status></samlp:Response>";
  let rr = saml_response_parse(xml);
  var ok = rr.is_ok;
  if rr.is_ok {
    let r = rr.value;
    ok = ok && !saml_response_is_success(&r);
    ok = ok && streq(r.status_message, "Denied");
    ok = ok && saml_status_is_valid(r.status_code);
  }
  ok = ok && saml_status_is_success("urn:oasis:names:tc:SAML:2.0:status:Success");
  ok = ok && !saml_status_is_success("urn:oasis:names:tc:SAML:2.0:status:Requester");
  ok = ok && saml_status_is_valid("urn:oasis:names:tc:SAML:2.0:status:Responder");
  ok = ok && !saml_status_is_valid("bogus");
  let broken = saml_response_parse("<samlp:Response xmlns:samlp=\"urn:oasis:names:tc:SAML:2.0:protocol\" ID=\"_r3\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\"><samlp:Status/></samlp:Response>");
  ok = ok && response_err_prefix(broken, "saml: Status without StatusCode");
  return assert(ok, "response: error status, validity predicate and malformed Status");
}

fn t25() -> TestResult {
  let digest = saml_base64_encode(&saml_sha256(&sb("x")));
  let xml = "<ds:Signature xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\"><ds:SignedInfo><ds:CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"/><ds:SignatureMethod Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#rsa-sha256\"/><ds:Reference URI=\"#a1\"><ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"/><ds:DigestValue>" + digest + "</ds:DigestValue></ds:Reference></ds:SignedInfo><ds:SignatureValue>AQIDBA==</ds:SignatureValue></ds:Signature>";
  let dr = saml_xml_parse(xml);
  var ok = dr.is_ok;
  if dr.is_ok {
    let d: XmlDoc = dr.value;
    let root = saml_xml_root(&d);
    let found = saml_dsig_find(&d, root);
    ok = ok && found == root;
    let sp = saml_dsig_parse(&d, found);
    ok = ok && sp.is_ok;
    if sp.is_ok {
      let s = sp.value;
      ok = ok && s.has_signed_info;
      ok = ok && streq(s.canonicalization_algorithm, "http://www.w3.org/2001/10/xml-exc-c14n#");
      ok = ok && streq(s.signature_algorithm, "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256");
      ok = ok && saml_dsig_reference_count(&s) == 1;
      ok = ok && streq(saml_dsig_reference_uri(&s, 0), "#a1");
      ok = ok && streq(saml_dsig_reference_digest_algorithm(&s, 0), "http://www.w3.org/2001/04/xmlenc#sha256");
      ok = ok && saml_dsig_digest_algorithm_supported(saml_dsig_reference_digest_algorithm(&s, 0));
      ok = ok && !saml_dsig_digest_algorithm_supported("urn:example:md5");
      let db = saml_dsig_digest_bytes(&s, 0);
      ok = ok && db.is_ok;
      if db.is_ok {
        let bytes: Vec[UInt8] = db.value;
        ok = ok && bytes.len() == 32;
      }
      let svb = saml_dsig_signature_value_bytes(&s);
      ok = ok && svb.is_ok;
      if svb.is_ok {
        let bytes2: Vec[UInt8] = svb.value;
        ok = ok && bytes2.len() == 4;
      }
    }
  }
  let tiny = _doc_ok("<r/>");
  let missing = saml_dsig_parse(&tiny, 1);
  ok = ok && signature_err_prefix(missing, "saml: not a Signature element");
  let no_sig = saml_dsig_find(&tiny, saml_xml_root(&tiny));
  ok = ok && no_sig < 0;
  return assert(ok, "dsig: structural parse of SignedInfo, Reference and values");
}

// A parsed tiny document; callers guarantee `text` is well formed.
fn _doc_ok(text: Str) -> XmlDoc {
  let r = saml_xml_parse(text);
  if r.is_ok {
    let d: XmlDoc = r.value;
    return d;
  }
  return _empty_doc();
}

// An empty flat document value for failure paths in tests.
fn _empty_doc() -> XmlDoc {
  return XmlDoc{
    kinds: Vec[Int].new();
    names: Vec[Str].new();
    texts: Vec[Str].new();
    parents: Vec[Int].new();
    opens: Vec[Int].new();
    closes: Vec[Int].new();
    attr_names: Vec[Str].new();
    attr_values: Vec[Str].new();
    attr_owners: Vec[Int].new();
    src: Vec[UInt8].new();
  };
}

// True when a Result[SamlSignature, Str] is Err with the prefix.
fn signature_err_prefix(r: Result[SamlSignature, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return has_prefix(m, prefix);
}

fn t26() -> TestResult {
  let assertion = "<Assertion xmlns=\"urn:oasis:names:tc:SAML:2.0:assertion\" ID=\"a1\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\"><Issuer>https://idp.example.org</Issuer></Assertion>";
  let ab = sb(assertion);
  let digest_b64 = saml_base64_encode(&saml_sha256(&ab));
  let xml = "<Response xmlns=\"urn:oasis:names:tc:SAML:2.0:protocol\" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\" ID=\"r1\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\">" + assertion + "<ds:Signature><ds:SignedInfo><ds:CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"/><ds:SignatureMethod Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#rsa-sha256\"/><ds:Reference URI=\"#a1\"><ds:DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha256\"/><ds:DigestValue>" + digest_b64 + "</ds:DigestValue></ds:Reference></ds:SignedInfo><ds:SignatureValue>AQIDBA==</ds:SignatureValue></ds:Signature></Response>";
  let rr = saml_response_parse(xml);
  var ok = rr.is_ok;
  if rr.is_ok {
    let r = rr.value;
    let doc: XmlDoc = r.doc;
    let sig_node = saml_dsig_find(&doc, r.node);
    ok = ok && sig_node > 0;
    let sp = saml_dsig_parse(&doc, sig_node);
    ok = ok && sp.is_ok;
    if sp.is_ok {
      let s = sp.value;
      let target = saml_dsig_reference_target(&doc, &s, 0);
      ok = ok && target > 0;
      ok = ok && streq(saml_xml_node_local(&doc, target), "Assertion");
      ok = ok && saml_dsig_reference_resolves(&doc, &s, 0);
      ok = ok && saml_dsig_verify_reference_raw_sha256(&doc, &s, 0);
      let raw = saml_xml_node_raw_bytes(&doc, target);
      ok = ok && bytes_equal(raw, ab);
      ok = ok && saml_dsig_verify_reference_sha256(&s, 0, &raw);
      ok = ok && saml_dsig_verify_digest_sha256(digest_b64, &ab);
      let evil = sb("<Assertion xmlns=\"urn:oasis:names:tc:SAML:2.0:assertion\" ID=\"a1\" Version=\"2.0\" IssueInstant=\"2026-10-02T12:00:00Z\"><Issuer>https://evil.example.org</Issuer></Assertion>");
      ok = ok && !saml_dsig_verify_reference_sha256(&s, 0, &evil);
      ok = ok && !saml_dsig_verify_digest_sha256(digest_b64, &evil);
      ok = ok && !saml_dsig_verify_reference_raw_sha256(&doc, &s, 9);
    }
  }
  return assert(ok, "dsig: reference resolution and SHA-256 digest verification/tamper detection");
}

fn t27() -> TestResult {
  let mr = saml_idp_metadata_parse(METADATA_XML);
  var ok = mr.is_ok;
  if mr.is_ok {
    let m = mr.value;
    ok = ok && m.has_entity_id;
    ok = ok && streq(m.entity_id, "https://idp.example.org/metadata");
    ok = ok && m.want_authn_requests_signed;
    ok = ok && saml_metadata_sso_count(&m) == 2;
    ok = ok && streq(saml_metadata_sso_binding_at(&m, 0), "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect");
    ok = ok && streq(saml_metadata_sso_location_at(&m, 0), "https://idp.example.org/sso");
    ok = ok && streq(saml_metadata_sso_location_for_binding(&m, "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"), "https://idp.example.org/sso/post");
    ok = ok && streq(saml_metadata_sso_location_for_binding(&m, "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Artifact"), "");
    ok = ok && m.cert_count == 1;
    ok = ok && streq(saml_metadata_certificate_at(&m, 0), "TUlJQ0F3PT0K");
    ok = ok && streq(m.protocol_support, "urn:oasis:names:tc:SAML:2.0:protocol");
  }
  return assert(ok, "metadata: entityID, IDP descriptor, SSO bindings and certificates");
}

fn t28() -> TestResult {
  let e1 = saml_idp_metadata_parse("<md:EntityDescriptor xmlns:md=\"urn:oasis:names:tc:SAML:2.0:metadata\"><md:IDPSSODescriptor protocolSupportEnumeration=\"x\"/></md:EntityDescriptor>");
  var ok = meta_err_prefix(e1, "saml: missing entityID");
  let e2 = saml_idp_metadata_parse("<md:EntityDescriptor xmlns:md=\"urn:oasis:names:tc:SAML:2.0:metadata\" entityID=\"https://idp\"/>");
  ok = ok && meta_err_prefix(e2, "saml: missing IDPSSODescriptor");
  let e3 = saml_idp_metadata_parse("<md:EntityDescriptor xmlns:md=\"urn:oasis:names:tc:SAML:2.0:metadata\" entityID=\"https://idp\"><md:IDPSSODescriptor protocolSupportEnumeration=\"x\"/></md:EntityDescriptor>");
  ok = ok && meta_err_prefix(e3, "saml: IDPSSODescriptor without SingleSignOnService");
  let e4 = saml_idp_metadata_parse("<md:EntityDescriptor xmlns:md=\"urn:oasis:names:tc:SAML:2.0:metadata\" entityID=\"https://idp\"><md:IDPSSODescriptor protocolSupportEnumeration=\"x\"><md:SingleSignOnService Binding=\"urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST\"/></md:IDPSSODescriptor></md:EntityDescriptor>");
  ok = ok && meta_err_prefix(e4, "saml: SingleSignOnService without Location");
  let e5 = saml_idp_metadata_parse("<md:EntityDescriptor");
  ok = ok && meta_err_prefix(e5, "saml:");
  return assert(ok, "metadata: missing entityID/IDP descriptor/SSO location errors");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.saml conformance tests ===");
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
    io.println("xiom.saml: all tests passed");
  } else {
    io.println("xiom.saml: tests failed");
  }
  return failed;
}

