// XIOM -- xiom.keymgmt conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: base64url boundaries and rejections, JWK parse
// per kty (RSA/EC/OKP/oct) with required-field validation, JWKS parse and kid
// lookup, JWK canonical rendering, the DER TLV walker with offsets, PKCS#8
// PrivateKeyInfo / EncryptedPrivateKeyInfo and SPKI walks, the OID table,
// PEM unwrap/rewrap and the malformed-input catalogs.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison, so every comparison
// below is routed through streq or str_starts_with). Every Vec[UInt8] element
// read is widened with `(x as Int) & 0xFF` before comparison.
//
// All instruments are synthetic and built in-test: JWK/JWKS JSON by string
// concatenation (parameter values via kme_base64url_encode), DER buffers by
// the local TLV builder below. Pinned base64url vectors (Bw, -_8, SGVsbG8,
// TQ==/TWE= semantics) were cross-checked against RFC 4648 test vectors.

module keymgmt_tests
use xiom.io; use xiom.test; use xiom.keymgmt;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if (((a[i] as Int) & 0xFF) != ((b[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_slice_is(v: Vec[UInt8], off: Int, want: Vec[UInt8]) -> Bool {
  if off < 0 || off + want.len() > v.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if (((v[off + i] as Int) & 0xFF) != ((want[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Deterministic byte sequence of length n; covers 0x00 and bytes >= 0x80.
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn ff_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(255 as UInt8);
    i = i + 1;
  }
  return v;
}

fn cat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

fn cat3(a: Vec[UInt8], b: Vec[UInt8], c: Vec[UInt8]) -> Vec[UInt8] {
  return cat2(cat2(a, b), c);
}

// Error predicates (exact match and prefix match) for each Result type used
// by the library; Str errors are bound to typed locals before comparison.
fn err_b64_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn err_b64_pref(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_str_pref(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_jwk_pref(r: Result[Jwk, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_info_pref(r: Result[KmeJwkInfo, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_jwks_pref(r: Result[Jwks, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_pem_pref(r: Result[KmePem, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_tlv_pref(r: Result[KmeTlv, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_len_pref(r: Result[KmeLength, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_oid_pref(r: Result[KmeOid, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_pki_pref(r: Result[KmePrivateKeyInfo, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_epki_pref(r: Result[KmeEncryptedPrivateKeyInfo, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

fn err_spki_pref(r: Result[KmeSpki, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return string.str_starts_with(m, want);
}

// --------------------------------------------------
//  Synthetic DER helpers
// --------------------------------------------------

// Minimal DER length field for 0..65535 content bytes.
fn der_put_len(n: Int, out: &mut Vec[UInt8]) {
  if n < 128 {
    out.push(n as UInt8);
  } elif n < 256 {
    out.push(129 as UInt8);
    out.push(n as UInt8);
  } else {
    out.push(130 as UInt8);
    out.push((n / 256) as UInt8);
    out.push((n % 256) as UInt8);
  }
}

// One DER TLV: `tag` octet (primitive/constructed assumed), content bytes.
fn der(tag: Int, content: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(tag as UInt8);
  der_put_len(content.len(), &mut out);
  var i = 0;
  while i < content.len() {
    out.push(content[i]);
    i = i + 1;
  }
  return out;
}

fn seq_of(content: Vec[UInt8]) -> Vec[UInt8] {
  return der(48, content);
}

fn empty_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

fn int_u8(x: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(x as UInt8);
  return der(2, b);
}

fn octet(content: Vec[UInt8]) -> Vec[UInt8] {
  return der(4, content);
}

fn null_tlv() -> Vec[UInt8] {
  return der(5, empty_bytes());
}

// BIT STRING with `unused` unused bits and raw `bits` bytes.
fn bit_str(unused: Int, bits: Vec[UInt8]) -> Vec[UInt8] {
  var c = Vec[UInt8].new();
  c.push(unused as UInt8);
  var i = 0;
  while i < bits.len() {
    c.push(bits[i]);
    i = i + 1;
  }
  return der(3, c);
}

// OID body encoders (content octets, no TLV header).
fn oid_body_rsa() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(42 as UInt8);
  b.push(134 as UInt8);
  b.push(72 as UInt8);
  b.push(134 as UInt8);
  b.push(247 as UInt8);
  b.push(13 as UInt8);
  b.push(1 as UInt8);
  b.push(1 as UInt8);
  b.push(1 as UInt8);
  return b;
}

fn oid_body_ec() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(42 as UInt8);
  b.push(134 as UInt8);
  b.push(72 as UInt8);
  b.push(206 as UInt8);
  b.push(61 as UInt8);
  b.push(2 as UInt8);
  b.push(1 as UInt8);
  return b;
}

fn oid_body_p256() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(42 as UInt8);
  b.push(134 as UInt8);
  b.push(72 as UInt8);
  b.push(206 as UInt8);
  b.push(61 as UInt8);
  b.push(3 as UInt8);
  b.push(1 as UInt8);
  b.push(7 as UInt8);
  return b;
}

fn oid_body_p384() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(43 as UInt8);
  b.push(129 as UInt8);
  b.push(4 as UInt8);
  b.push(0 as UInt8);
  b.push(34 as UInt8);
  return b;
}

fn oid_body_p521() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(43 as UInt8);
  b.push(129 as UInt8);
  b.push(4 as UInt8);
  b.push(0 as UInt8);
  b.push(35 as UInt8);
  return b;
}

fn oid_body_secp256k1() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(43 as UInt8);
  b.push(129 as UInt8);
  b.push(4 as UInt8);
  b.push(0 as UInt8);
  b.push(10 as UInt8);
  return b;
}

fn oid_body_ed25519() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(43 as UInt8);
  b.push(101 as UInt8);
  b.push(112 as UInt8);
  return b;
}

fn oid_body_x25519() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(43 as UInt8);
  b.push(101 as UInt8);
  b.push(110 as UInt8);
  return b;
}

fn oid_body_ed448() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(43 as UInt8);
  b.push(101 as UInt8);
  b.push(113 as UInt8);
  return b;
}

fn oid_body_x448() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  b.push(43 as UInt8);
  b.push(101 as UInt8);
  b.push(111 as UInt8);
  return b;
}

fn oid_tlv(body: Vec[UInt8]) -> Vec[UInt8] {
  return der(6, body);
}

// AlgorithmIdentifier SEQUENCE { OID, NULL }.
fn alg_with_null(body: Vec[UInt8]) -> Vec[UInt8] {
  return seq_of(cat2(oid_tlv(body), null_tlv()));
}

// AlgorithmIdentifier SEQUENCE { OID, namedCurve OID }.
fn alg_with_curve(alg_body: Vec[UInt8], curve_body: Vec[UInt8]) -> Vec[UInt8] {
  return seq_of(cat2(oid_tlv(alg_body), oid_tlv(curve_body)));
}

// JWK JSON member with a base64url parameter value.
fn jwk_b64_member(name: Str, data: Vec[UInt8]) -> Str {
  return "\"" + name + "\":\"" + kme_base64url_encode(&data) + "\"";
}

// --------------------------------------------------
//  Base64url
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if !streq(kme_base64url_encode(&empty_bytes()), "") { ok = false; }
  let fb = Vec[UInt8].new();
  fb.push(251 as UInt8);
  fb.push(255 as UInt8);
  if !streq(kme_base64url_encode(&fb), "-_8") { ok = false; }
  let hello = Vec[UInt8].new();
  hello.push(72 as UInt8);
  hello.push(101 as UInt8);
  hello.push(108 as UInt8);
  hello.push(108 as UInt8);
  hello.push(111 as UInt8);
  if !streq(kme_base64url_encode(&hello), "SGVsbG8") { ok = false; }
  let b7 = Vec[UInt8].new();
  b7.push(7 as UInt8);
  if !streq(kme_base64url_encode(&b7), "Bw") { ok = false; }
  if !streq(kme_base64url_encode(&zeros(3)), "AAAA") { ok = false; }
  let ff1 = ff_bytes(1);
  if !streq(kme_base64url_encode(&ff1), "_w") { ok = false; }
  return assert(ok, "base64url encode: unpadded pinned vectors");
}

fn t2() -> TestResult {
  var ok = true;
  var hello = Vec[UInt8].new();
  hello.push(72 as UInt8);
  hello.push(101 as UInt8);
  hello.push(108 as UInt8);
  hello.push(108 as UInt8);
  hello.push(111 as UInt8);
  let d1 = kme_base64url_decode("SGVsbG8");
  if !d1.is_ok { ok = false; } else { let v: Vec[UInt8] = d1.value; if !bytes_equal(v, hello) { ok = false; } }
  let d2 = kme_base64url_decode("SGVsbG8=");
  if !d2.is_ok { ok = false; } else { let v: Vec[UInt8] = d2.value; if !bytes_equal(v, hello) { ok = false; } }
  let d3 = kme_base64url_decode("AA");
  if !d3.is_ok { ok = false; } else { let v: Vec[UInt8] = d3.value; if !bytes_equal(v, zeros(1)) { ok = false; } }
  let d4 = kme_base64url_decode("AAA=");
  if !d4.is_ok { ok = false; } else { let v: Vec[UInt8] = d4.value; if !bytes_equal(v, zeros(2)) { ok = false; } }
  let d5 = kme_base64url_decode("AAAA");
  if !d5.is_ok { ok = false; } else { let v: Vec[UInt8] = d5.value; if !bytes_equal(v, zeros(3)) { ok = false; } }
  let d6 = kme_base64url_decode("");
  if !d6.is_ok { ok = false; } else { let v: Vec[UInt8] = d6.value; if v.len() != 0 { ok = false; } }
  let d7 = kme_base64url_decode("_w");
  if !d7.is_ok { ok = false; } else { let v: Vec[UInt8] = d7.value; if !bytes_equal(v, ff_bytes(1)) { ok = false; } }
  var aqid = Vec[UInt8].new();
  aqid.push(1 as UInt8);
  aqid.push(2 as UInt8);
  aqid.push(3 as UInt8);
  let d8 = kme_base64url_decode("AQID");
  if !d8.is_ok { ok = false; } else { let v: Vec[UInt8] = d8.value; if !bytes_equal(v, aqid) { ok = false; } }
  var ma = Vec[UInt8].new();
  ma.push(77 as UInt8);
  ma.push(97 as UInt8);
  let d9 = kme_base64url_decode("TWE=");
  if !d9.is_ok { ok = false; } else { let v: Vec[UInt8] = d9.value; if !bytes_equal(v, ma) { ok = false; } }
  var n = 0;
  while n < 9 {
    let raw = seq_bytes(n);
    let enc = kme_base64url_encode(&raw);
    let dec = kme_base64url_decode(enc);
    if !dec.is_ok {
      ok = false;
    } else {
      let v: Vec[UInt8] = dec.value;
      if !bytes_equal(v, raw) {
        ok = false;
      }
    }
    n = n + 1;
  }
  return assert(ok, "base64url decode: unpadded/padded tolerance and round-trip");
}

fn t3() -> TestResult {
  var ok = true;
  if !err_b64_is(kme_base64url_decode("A"), "keymgmt: base64url bad length at offset 0") { ok = false; }
  if !err_b64_is(kme_base64url_decode("!"), "keymgmt: base64url invalid character at offset 0") { ok = false; }
  if !err_b64_is(kme_base64url_decode("+"), "keymgmt: base64url invalid character at offset 0") { ok = false; }
  if !err_b64_is(kme_base64url_decode("/"), "keymgmt: base64url invalid character at offset 0") { ok = false; }
  if !err_b64_is(kme_base64url_decode("AA==AA"), "keymgmt: base64url bad padding at offset 4") { ok = false; }
  if !err_b64_is(kme_base64url_decode("A==="), "keymgmt: base64url bad padding at offset 1") { ok = false; }
  if !err_b64_is(kme_base64url_decode("AAAA="), "keymgmt: base64url bad padding at offset 4") { ok = false; }
  if !err_b64_is(kme_base64url_decode("TR=="), "keymgmt: base64url non-canonical trailing bits at offset 2") { ok = false; }
  if !err_b64_is(kme_base64url_decode("TWF="), "keymgmt: base64url non-canonical trailing bits at offset 3") { ok = false; }
  return assert(ok, "base64url decode: bad length, character, padding and trailing bits");
}

// --------------------------------------------------
//  JWK
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = true;
  let text = "{\"kty\":\"RSA\",\"kid\":\"rsa-1\",\"use\":\"sig\",\"alg\":\"RS256\",\"key_ops\":[\"verify\",\"sign\"],\"n\":\"AQAB\",\"e\":\"AQAB\",\"x5c\":[\"TUlJ\"],\"x5t\":\"aGVsbG8\",\"x5u\":\"https://k.example/jwks\"}";
  let r = kme_jwk_parse(text);
  if !r.is_ok {
    ok = false;
  } else {
    let k: Jwk = r.value;
    if kme_jwk_type(&k) != 1 { ok = false; }
    if !streq(kme_jwk_kty(&k), "RSA") { ok = false; }
    if !streq(kme_jwk_kid(&k), "rsa-1") { ok = false; }
    if !streq(kme_jwk_use(&k), "sig") { ok = false; }
    if !streq(kme_jwk_alg(&k), "RS256") { ok = false; }
    if kme_jwk_key_ops_count(&k) != 2 { ok = false; }
    if !streq(kme_jwk_key_op(&k, 0), "verify") { ok = false; }
    if !streq(kme_jwk_key_op(&k, 1), "sign") { ok = false; }
    if kme_jwk_x5c_count(&k) != 1 { ok = false; }
    if !streq(kme_jwk_x5c(&k, 0), "TUlJ") { ok = false; }
    if !streq(kme_jwk_x5t(&k), "aGVsbG8") { ok = false; }
    if !streq(kme_jwk_x5u(&k), "https://k.example/jwks") { ok = false; }
    if kme_jwk_member_count(&k) != 10 { ok = false; }
    if !streq(kme_jwk_member(&k, 0), "kty") { ok = false; }
    if !kme_jwk_has_member(&k, "key_ops") { ok = false; }
    if kme_jwk_has_member(&k, "zz") { ok = false; }
    if kme_jwk_param_len(&k, "n") != 3 { ok = false; }
    if kme_jwk_param_len(&k, "e") != 3 { ok = false; }
    if !kme_jwk_has_param(&k, "n") { ok = false; }
    if kme_jwk_has_param(&k, "kid") { ok = false; }
    var onezeroone = Vec[UInt8].new();
    onezeroone.push(1 as UInt8);
    onezeroone.push(0 as UInt8);
    onezeroone.push(1 as UInt8);
    let nb = kme_jwk_param(&k, "n");
    if !bytes_equal(nb, onezeroone) { ok = false; }
    if kme_jwk_is_private(&k) { ok = false; }
    let chk = kme_jwk_check(&k);
    if !chk.is_ok {
      ok = false;
    } else {
      let info: KmeJwkInfo = chk.value;
      if kme_jwk_info_kind(&info) != 1 { ok = false; }
      if kme_jwk_info_is_private(&info) { ok = false; }
      if kme_jwk_info_param_count(&info) != 2 { ok = false; }
    }
  }
  return assert(ok, "JWK parse: RSA public members, accessors and validation");
}

fn t5() -> TestResult {
  var ok = true;
  let kk = seq_bytes(3);
  let priv_text = "{\"kty\":\"RSA\"," + jwk_b64_member("n", kk) + "," + jwk_b64_member("e", kk) + "," + jwk_b64_member("d", kk) + "," + jwk_b64_member("p", kk) + "," + jwk_b64_member("q", kk) + "," + jwk_b64_member("dp", kk) + "," + jwk_b64_member("dq", kk) + "," + jwk_b64_member("qi", kk) + "}";
  let r = kme_jwk_parse(priv_text);
  if !r.is_ok {
    ok = false;
  } else {
    let k: Jwk = r.value;
    if !kme_jwk_is_private(&k) { ok = false; }
    if kme_jwk_param_len(&k, "qi") != 3 { ok = false; }
    let chk = kme_jwk_check(&k);
    if !chk.is_ok {
      ok = false;
    } else {
      let info: KmeJwkInfo = chk.value;
      if kme_jwk_info_kind(&info) != 1 { ok = false; }
      if !kme_jwk_info_is_private(&info) { ok = false; }
      if kme_jwk_info_param_count(&info) != 8 { ok = false; }
    }
  }
  let no_d = "{\"kty\":\"RSA\"," + jwk_b64_member("n", kk) + "," + jwk_b64_member("e", kk) + "," + jwk_b64_member("p", kk) + "}";
  let r2 = kme_jwk_parse(no_d);
  if !r2.is_ok { ok = false; } else { let k2: Jwk = r2.value; if !err_info_pref(kme_jwk_check(&k2), "keymgmt: jwk missing d") { ok = false; } }
  let d_no_p = "{\"kty\":\"RSA\"," + jwk_b64_member("n", kk) + "," + jwk_b64_member("e", kk) + "," + jwk_b64_member("d", kk) + "," + jwk_b64_member("q", kk) + "}";
  let r3 = kme_jwk_parse(d_no_p);
  if !r3.is_ok { ok = false; } else { let k3: Jwk = r3.value; if !err_info_pref(kme_jwk_check(&k3), "keymgmt: jwk missing p") { ok = false; } }
  var lead = Vec[UInt8].new();
  lead.push(0 as UInt8);
  lead.push(7 as UInt8);
  lead.push(44 as UInt8);
  let nonmin = "{\"kty\":\"RSA\"," + jwk_b64_member("n", lead) + "," + jwk_b64_member("e", kk) + "}";
  let r4 = kme_jwk_parse(nonmin);
  if !r4.is_ok { ok = false; } else { let k4: Jwk = r4.value; if !err_info_pref(kme_jwk_check(&k4), "keymgmt: jwk non-minimal n") { ok = false; } }
  let no_e = "{\"kty\":\"RSA\",\"n\":\"AQAB\"}";
  let r5 = kme_jwk_parse(no_e);
  if !r5.is_ok { ok = false; } else { let k5: Jwk = r5.value; if !err_info_pref(kme_jwk_check(&k5), "keymgmt: jwk missing e") { ok = false; } }
  let empty_n = "{\"kty\":\"RSA\",\"n\":\"\",\"e\":\"AQAB\"}";
  let r6 = kme_jwk_parse(empty_n);
  if !r6.is_ok { ok = false; } else { let k6: Jwk = r6.value; if !err_info_pref(kme_jwk_check(&k6), "keymgmt: jwk empty n") { ok = false; } }
  return assert(ok, "JWK RSA private: CRT all-or-nothing, minimality, empty fields");
}

fn t6() -> TestResult {
  var ok = true;
  let x32 = seq_bytes(32);
  let y32 = seq_bytes(32);
  let d32 = seq_bytes(32);
  let priv = "{\"kty\":\"EC\",\"crv\":\"P-256\"," + jwk_b64_member("x", x32) + "," + jwk_b64_member("y", y32) + "," + jwk_b64_member("d", d32) + "}";
  let r = kme_jwk_parse(priv);
  if !r.is_ok {
    ok = false;
  } else {
    let k: Jwk = r.value;
    if kme_jwk_type(&k) != 2 { ok = false; }
    if !streq(kme_jwk_crv(&k), "P-256") { ok = false; }
    if kme_jwk_param_len(&k, "x") != 32 { ok = false; }
    if !kme_jwk_is_private(&k) { ok = false; }
    let chk = kme_jwk_check(&k);
    if !chk.is_ok {
      ok = false;
    } else {
      let info: KmeJwkInfo = chk.value;
      if kme_jwk_info_kind(&info) != 2 { ok = false; }
      if !kme_jwk_info_is_private(&info) { ok = false; }
      if kme_jwk_info_param_count(&info) != 3 { ok = false; }
    }
    if !streq(kme_jwk_oid(&k), "1.2.840.10045.2.1") { ok = false; }
    if !streq(kme_jwk_alg_name(&k), "id-ecPublicKey") { ok = false; }
    if !streq(kme_jwk_curve_oid(&k), "1.2.840.10045.3.1.7") { ok = false; }
  }
  let pub_text = "{\"kty\":\"EC\",\"crv\":\"P-256\"," + jwk_b64_member("x", x32) + "," + jwk_b64_member("y", y32) + "}";
  let r2 = kme_jwk_parse(pub_text);
  if !r2.is_ok { ok = false; } else { let k2: Jwk = r2.value; if kme_jwk_is_private(&k2) { ok = false; } }
  let bad_curve = "{\"kty\":\"EC\",\"crv\":\"P-999\"," + jwk_b64_member("x", x32) + "," + jwk_b64_member("y", y32) + "}";
  let r3 = kme_jwk_parse(bad_curve);
  if !r3.is_ok { ok = false; } else { let k3: Jwk = r3.value; if !err_info_pref(kme_jwk_check(&k3), "keymgmt: jwk unsupported curve P-999") { ok = false; } }
  let x31 = seq_bytes(31);
  let short_x = "{\"kty\":\"EC\",\"crv\":\"P-256\"," + jwk_b64_member("x", x31) + "," + jwk_b64_member("y", y32) + "}";
  let r4 = kme_jwk_parse(short_x);
  if !r4.is_ok { ok = false; } else { let k4: Jwk = r4.value; if !err_info_pref(kme_jwk_check(&k4), "keymgmt: jwk x length must be 32") { ok = false; } }
  let no_y = "{\"kty\":\"EC\",\"crv\":\"P-256\"," + jwk_b64_member("x", x32) + "}";
  let r5 = kme_jwk_parse(no_y);
  if !r5.is_ok { ok = false; } else { let k5: Jwk = r5.value; if !err_info_pref(kme_jwk_check(&k5), "keymgmt: jwk missing y") { ok = false; } }
  let mismatched = "{\"kty\":\"EC\",\"crv\":\"Ed25519\"," + jwk_b64_member("x", x32) + "," + jwk_b64_member("y", y32) + "}";
  let r6 = kme_jwk_parse(mismatched);
  if !r6.is_ok { ok = false; } else { let k6: Jwk = r6.value; if !err_info_pref(kme_jwk_check(&k6), "keymgmt: jwk curve mismatch") { ok = false; } }
  return assert(ok, "JWK EC: P-256 sizes, curve table, private detection and rejections");
}

fn t7() -> TestResult {
  var ok = true;
  let x32 = seq_bytes(32);
  let x57 = seq_bytes(57);
  let ed = "{\"kty\":\"OKP\",\"crv\":\"Ed25519\"," + jwk_b64_member("x", x32) + "}";
  let r = kme_jwk_parse(ed);
  if !r.is_ok {
    ok = false;
  } else {
    let k: Jwk = r.value;
    if kme_jwk_type(&k) != 3 { ok = false; }
    if !streq(kme_jwk_crv(&k), "Ed25519") { ok = false; }
    if !streq(kme_jwk_alg_name(&k), "Ed25519") { ok = false; }
    if !streq(kme_jwk_oid(&k), "1.3.101.112") { ok = false; }
    if kme_jwk_is_private(&k) { ok = false; }
    let chk = kme_jwk_check(&k);
    if !chk.is_ok { ok = false; } else { let info: KmeJwkInfo = chk.value; if kme_jwk_info_kind(&info) != 3 { ok = false; } }
  }
  let priv = "{\"kty\":\"OKP\",\"crv\":\"Ed25519\"," + jwk_b64_member("x", x32) + "," + jwk_b64_member("d", x32) + "}";
  let r2 = kme_jwk_parse(priv);
  if !r2.is_ok { ok = false; } else { let k2: Jwk = r2.value; if !kme_jwk_is_private(&k2) { ok = false; } }
  let x25519 = "{\"kty\":\"OKP\",\"crv\":\"X25519\"," + jwk_b64_member("x", x32) + "}";
  let r3 = kme_jwk_parse(x25519);
  if !r3.is_ok { ok = false; } else { let k3: Jwk = r3.value; if !streq(kme_jwk_oid(&k3), "1.3.101.110") { ok = false; } }
  let ed448 = "{\"kty\":\"OKP\",\"crv\":\"Ed448\"," + jwk_b64_member("x", x57) + "}";
  let r4 = kme_jwk_parse(ed448);
  if !r4.is_ok { ok = false; } else { let k4: Jwk = r4.value; if !kme_jwk_check(&k4).is_ok { ok = false; } }
  let ed448_bad = "{\"kty\":\"OKP\",\"crv\":\"Ed448\"," + jwk_b64_member("x", x32) + "}";
  let r5 = kme_jwk_parse(ed448_bad);
  if !r5.is_ok { ok = false; } else { let k5: Jwk = r5.value; if !err_info_pref(kme_jwk_check(&k5), "keymgmt: jwk x length must be 57") { ok = false; } }
  let oct = "{\"kty\":\"oct\",\"k\":\"AQAB\"}";
  let r6 = kme_jwk_parse(oct);
  if !r6.is_ok {
    ok = false;
  } else {
    let k6: Jwk = r6.value;
    if kme_jwk_type(&k6) != 4 { ok = false; }
    if kme_jwk_param_len(&k6, "k") != 3 { ok = false; }
    if !kme_jwk_is_private(&k6) { ok = false; }
    if !streq(kme_jwk_oid(&k6), "") { ok = false; }
    let chk6 = kme_jwk_check(&k6);
    if !chk6.is_ok { ok = false; } else { let info6: KmeJwkInfo = chk6.value; if kme_jwk_info_kind(&info6) != 4 { ok = false; } if !kme_jwk_info_is_private(&info6) { ok = false; } }
  }
  let oct_missing = "{\"kty\":\"oct\"}";
  let r7 = kme_jwk_parse(oct_missing);
  if !r7.is_ok { ok = false; } else { let k7: Jwk = r7.value; if !err_info_pref(kme_jwk_check(&k7), "keymgmt: jwk missing k") { ok = false; } }
  let oct_empty = "{\"kty\":\"oct\",\"k\":\"\"}";
  let r8 = kme_jwk_parse(oct_empty);
  if !r8.is_ok { ok = false; } else { let k8: Jwk = r8.value; if !err_info_pref(kme_jwk_check(&k8), "keymgmt: jwk empty k") { ok = false; } }
  return assert(ok, "JWK OKP/oct: curve sizes, private detection and required fields");
}

fn t8() -> TestResult {
  var ok = true;
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"FOO\"}"), "keymgmt: jwk unsupported kty") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kid\":\"x\"}"), "keymgmt: jwk missing kty") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"kty\":\"oct\",\"k\":\"AQAB\"}"), "keymgmt: jwk duplicate member") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\",\"key_ops\":[]}"), "keymgmt: jwk empty array") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":5}"), "keymgmt: json expected string") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\",\"kid\":\"\\q\"}"), "keymgmt: json invalid escape") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\",\"kid\":\"\\u0000\"}"), "keymgmt: json NUL character") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\",\"kid\":\"\\ud800\"}"), "keymgmt: json invalid surrogate") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\""), "keymgmt: jwk unterminated object") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\"} x"), "keymgmt: jwk trailing data") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("[]"), "keymgmt: jwk expected object") { ok = false; }
  if !err_jwk_pref(kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"!\"}"), "keymgmt: jwk k: invalid character") { ok = false; }
  let skipped = kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\",\"zz\":{\"a\":[1,2,{\"b\":null}]}}");
  if !skipped.is_ok {
    ok = false;
  } else {
    let k: Jwk = skipped.value;
    if kme_jwk_member_count(&k) != 3 { ok = false; }
  }
  var deep = "{\"kty\":\"oct\",\"k\":\"AQAB\",\"u\":";
  var i = 0;
  while i < 18 {
    deep = deep + "[";
    i = i + 1;
  }
  i = 0;
  while i < 18 {
    deep = deep + "]";
    i = i + 1;
  }
  deep = deep + "}";
  if !err_jwk_pref(kme_jwk_parse(deep), "keymgmt: json nesting too deep") { ok = false; }
  return assert(ok, "JWK malformed: kty, duplicates, JSON escapes, nesting and offsets");
}

fn t9() -> TestResult {
  var ok = true;
  let k1 = "{\"kty\":\"RSA\",\"kid\":\"k1\",\"n\":\"AQAB\",\"e\":\"AQAB\"}";
  let k2 = "{\"kty\":\"oct\",\"kid\":\"k2\",\"k\":\"AQAB\"}";
  let x32 = seq_bytes(32);
  let y32 = seq_bytes(32);
  let k3 = "{\"kty\":\"EC\",\"kid\":\"k3\",\"crv\":\"P-256\"," + jwk_b64_member("x", x32) + "," + jwk_b64_member("y", y32) + "}";
  let text = "{\"keys\":[" + k1 + "," + k2 + "," + k3 + "]}";
  let r = kme_jwks_parse(text);
  if !r.is_ok {
    ok = false;
  } else {
    let s: Jwks = r.value;
    if kme_jwks_count(&s) != 3 { ok = false; }
    if kme_jwks_lookup(&s, "k1") != 0 { ok = false; }
    if kme_jwks_lookup(&s, "k2") != 1 { ok = false; }
    if kme_jwks_lookup(&s, "k3") != 2 { ok = false; }
    if kme_jwks_lookup(&s, "zzz") != -1 { ok = false; }
    let kr = kme_jwks_key(&s, 1);
    if !kr.is_ok {
      ok = false;
    } else {
      let key: Jwk = kr.value;
      if !streq(kme_jwk_kty(&key), "oct") { ok = false; }
      if !streq(kme_jwk_kid(&key), "k2") { ok = false; }
    }
    if !err_jwk_pref(kme_jwks_key(&s, 5), "keymgmt: jwks index out of range") { ok = false; }
  }
  let e0 = kme_jwks_parse("{\"keys\":[]}");
  if !e0.is_ok { ok = false; } else { let s0: Jwks = e0.value; if kme_jwks_count(&s0) != 0 { ok = false; } }
  if !err_jwks_pref(kme_jwks_parse("{}"), "keymgmt: jwks missing keys") { ok = false; }
  if !err_jwks_pref(kme_jwks_parse("{\"keys\":{}}"), "keymgmt: jwks keys not array") { ok = false; }
  if !err_jwks_pref(kme_jwks_parse("{\"keys\":[5]}"), "keymgmt: jwks key not object") { ok = false; }
  if !err_jwks_pref(kme_jwks_parse("{\"keys\":[]}x"), "keymgmt: jwks trailing data") { ok = false; }
  let extra = kme_jwks_parse("{\"keys\":[],\"x\":{\"deep\":[1,{\"a\":2}]}}");
  if !extra.is_ok { ok = false; } else { let sx: Jwks = extra.value; if kme_jwks_count(&sx) != 0 { ok = false; } }
  return assert(ok, "JWKS: parse, count, kid lookup and malformed documents");
}

fn t10() -> TestResult {
  var ok = true;
  let small = "{\"kty\":\"oct\",\"k\":\"AQAB\"}";
  let r0 = kme_jwk_parse(small);
  if !r0.is_ok {
    ok = false;
  } else {
    let k0: Jwk = r0.value;
    let rendered = kme_jwk_render(&k0);
    if !rendered.is_ok {
      ok = false;
    } else {
      let t: Str = rendered.value;
      if !streq(t, small) { ok = false; }
    }
  }
  let x32 = seq_bytes(32);
  let y32 = seq_bytes(32);
  let d32 = seq_bytes(32);
  let full = "{\"kty\":\"EC\",\"kid\":\"e1\",\"use\":\"sig\",\"key_ops\":[\"sign\",\"verify\"],\"alg\":\"ES256\",\"crv\":\"P-256\"," + jwk_b64_member("x", x32) + "," + jwk_b64_member("y", y32) + "," + jwk_b64_member("d", d32) + "}";
  let r1 = kme_jwk_parse(full);
  if !r1.is_ok {
    ok = false;
  } else {
    let k1: Jwk = r1.value;
    let rend = kme_jwk_render(&k1);
    if !rend.is_ok {
      ok = false;
    } else {
      let t1: Str = rend.value;
      let r2 = kme_jwk_parse(t1);
      if !r2.is_ok {
        ok = false;
      } else {
        let k2: Jwk = r2.value;
        if !streq(kme_jwk_kid(&k2), "e1") { ok = false; }
        if !streq(kme_jwk_alg(&k2), "ES256") { ok = false; }
        if !streq(kme_jwk_use(&k2), "sig") { ok = false; }
        if kme_jwk_key_ops_count(&k2) != 2 { ok = false; }
        if !streq(kme_jwk_key_op(&k2, 0), "sign") { ok = false; }
        if kme_jwk_param_len(&k2, "x") != 32 { ok = false; }
        if kme_jwk_param_len(&k2, "d") != 32 { ok = false; }
        let rend2 = kme_jwk_render(&k2);
        if !rend2.is_ok { ok = false; } else { let t2: Str = rend2.value; if !streq(t1, t2) { ok = false; } }
        let xb = kme_jwk_param(&k2, "x");
        if !bytes_equal(xb, x32) { ok = false; }
      }
    }
  }
  let esc = kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\",\"kid\":\"a\\\"b\\\\c\"}");
  if !esc.is_ok {
    ok = false;
  } else {
    let ke: Jwk = esc.value;
    if !streq(kme_jwk_kid(&ke), "a\"b\\c") { ok = false; }
    let re = kme_jwk_render(&ke);
    if !re.is_ok {
      ok = false;
    } else {
      let te: Str = re.value;
      let re2 = kme_jwk_parse(te);
      if !re2.is_ok { ok = false; } else { let ke2: Jwk = re2.value; if !streq(kme_jwk_kid(&ke2), "a\"b\\c") { ok = false; } }
    }
  }
  return assert(ok, "JWK render: canonical order, escaping and round-trip");
}

// --------------------------------------------------
//  DER walker / PKCS#8 / SPKI
// --------------------------------------------------

fn t11() -> TestResult {
  var ok = true;
  var one = Vec[UInt8].new();
  one.push(1 as UInt8);
  let buf = der(2, one);
  let r = kme_der_tlv(&buf, 0);
  if !r.is_ok {
    ok = false;
  } else {
    let t: KmeTlv = r.value;
    if t.tag_class != 0 { ok = false; }
    if t.constructed { ok = false; }
    if t.tag_number != 2 { ok = false; }
    if t.header != 0 { ok = false; }
    if t.content != 2 { ok = false; }
    if t.len != 1 { ok = false; }
    if t.next != 3 { ok = false; }
  }
  let lr = kme_der_length(&buf, 1);
  if !lr.is_ok { ok = false; } else { let l: KmeLength = lr.value; if l.len != 1 || l.size != 1 { ok = false; } }
  let long_buf = der(4, seq_bytes(200));
  if long_buf.len() != 203 { ok = false; }
  let lr2 = kme_der_length(&long_buf, 1);
  if !lr2.is_ok { ok = false; } else { let l2: KmeLength = lr2.value; if l2.len != 200 || l2.size != 2 { ok = false; } }
  let r2 = kme_der_tlv(&long_buf, 0);
  if !r2.is_ok { ok = false; } else { let t2: KmeTlv = r2.value; if t2.content != 3 { ok = false; } if t2.next != 203 { ok = false; } }
  var high = Vec[UInt8].new();
  high.push(159 as UInt8);
  high.push(32 as UInt8);
  high.push(0 as UInt8);
  let r3 = kme_der_tlv(&high, 0);
  if !r3.is_ok { ok = false; } else { let t3: KmeTlv = r3.value; if t3.tag_class != 2 { ok = false; } if t3.constructed { ok = false; } if t3.tag_number != 32 { ok = false; } if t3.next != 3 { ok = false; } }
  let empty = Vec[UInt8].new();
  if !err_tlv_pref(kme_der_tlv(&empty, 0), "keymgmt: der truncated tag") { ok = false; }
  var tl = Vec[UInt8].new();
  tl.push(2 as UInt8);
  if !err_tlv_pref(kme_der_tlv(&tl, 0), "keymgmt: der truncated length") { ok = false; }
  var ind = Vec[UInt8].new();
  ind.push(2 as UInt8);
  ind.push(128 as UInt8);
  if !err_len_pref(kme_der_length(&ind, 1), "keymgmt: der indefinite length") { ok = false; }
  var nonmin = Vec[UInt8].new();
  nonmin.push(2 as UInt8);
  nonmin.push(129 as UInt8);
  nonmin.push(5 as UInt8);
  if !err_len_pref(kme_der_length(&nonmin, 1), "keymgmt: der non-minimal length") { ok = false; }
  var trunc = Vec[UInt8].new();
  trunc.push(4 as UInt8);
  trunc.push(3 as UInt8);
  trunc.push(1 as UInt8);
  trunc.push(2 as UInt8);
  if !err_tlv_pref(kme_der_tlv(&trunc, 0), "keymgmt: der truncated value") { ok = false; }
  var over = Vec[UInt8].new();
  over.push(4 as UInt8);
  over.push(3 as UInt8);
  over.push(1 as UInt8);
  over.push(2 as UInt8);
  over.push(3 as UInt8);
  if !err_tlv_pref(kme_der_tlv_in(&over, 0, 2), "keymgmt: der value overruns container") { ok = false; }
  let oid = oid_tlv(oid_body_rsa());
  let orr = kme_der_oid(&oid, 0);
  if !orr.is_ok {
    ok = false;
  } else {
    let o: KmeOid = orr.value;
    if !streq(o.value, "1.2.840.113549.1.1.1") { ok = false; }
    if o.header != 0 { ok = false; }
    if o.next != oid.len() { ok = false; }
  }
  if !err_oid_pref(kme_der_oid(&buf, 0), "keymgmt: der tag mismatch") { ok = false; }
  return assert(ok, "DER walker: offsets, long lengths, high tags, truncation and OID");
}

fn t12() -> TestResult {
  var ok = true;
  let key3 = seq_bytes(3);
  let rsa_alg = alg_with_null(oid_body_rsa());
  let buf = seq_of(cat3(int_u8(0), rsa_alg, octet(key3)));
  let r = kme_pkcs8_parse(&buf);
  if !r.is_ok {
    ok = false;
  } else {
    let p: KmePrivateKeyInfo = r.value;
    if kme_pkcs8_version(&p) != 0 { ok = false; }
    if !streq(kme_pkcs8_alg_oid(&p), "1.2.840.113549.1.1.1") { ok = false; }
    if !kme_pkcs8_alg_params_present(&p) { ok = false; }
    if !streq(kme_pkcs8_alg_param_oid(&buf, &p), "") { ok = false; }
    if kme_pkcs8_key_len(&p) != 3 { ok = false; }
    if kme_pkcs8_key_offset(&p) < 0 { ok = false; }
    let kb = kme_pkcs8_key_bytes(&buf, &p);
    if !bytes_equal(kb, key3) { ok = false; }
    if kme_pkcs8_has_attributes(&p) { ok = false; }
    if kme_pkcs8_next(&p) != buf.len() { ok = false; }
  }
  let ec_alg = alg_with_curve(oid_body_ec(), oid_body_p256());
  let buf2 = seq_of(cat3(int_u8(1), ec_alg, octet(seq_bytes(1))));
  let r2 = kme_pkcs8_parse(&buf2);
  if !r2.is_ok {
    ok = false;
  } else {
    let p2: KmePrivateKeyInfo = r2.value;
    if kme_pkcs8_version(&p2) != 1 { ok = false; }
    if !streq(kme_pkcs8_alg_oid(&p2), "1.2.840.10045.2.1") { ok = false; }
    if !streq(kme_pkcs8_alg_param_oid(&buf2, &p2), "1.2.840.10045.3.1.7") { ok = false; }
  }
  let attrs = der(160, null_tlv());
  let buf3 = seq_of(cat3(int_u8(0), rsa_alg, cat2(octet(key3), attrs)));
  let r3 = kme_pkcs8_parse(&buf3);
  if !r3.is_ok {
    ok = false;
  } else {
    let p3: KmePrivateKeyInfo = r3.value;
    if !kme_pkcs8_has_attributes(&p3) { ok = false; }
    if kme_pkcs8_attrs_len(&p3) != 2 { ok = false; }
    if kme_pkcs8_attrs_offset(&p3) < 0 { ok = false; }
  }
  let buf4 = seq_of(cat3(int_u8(2), rsa_alg, octet(key3)));
  if !err_pki_pref(kme_pkcs8_parse(&buf4), "keymgmt: der bad pkcs8 version") { ok = false; }
  var tail = Vec[UInt8].new();
  tail.push(0 as UInt8);
  let buf5 = cat2(buf, tail);
  if !err_pki_pref(kme_pkcs8_parse(&buf5), "keymgmt: der trailing data") { ok = false; }
  let buf6 = seq_of(cat3(int_u8(0), rsa_alg, int_u8(1)));
  if !err_pki_pref(kme_pkcs8_parse(&buf6), "keymgmt: der tag mismatch") { ok = false; }
  return assert(ok, "PKCS#8 PrivateKeyInfo: RSA/EC walks, attributes and errors");
}

fn t13() -> TestResult {
  var ok = true;
  var pb = Vec[UInt8].new();
  pb.push(42 as UInt8);
  pb.push(134 as UInt8);
  pb.push(72 as UInt8);
  pb.push(134 as UInt8);
  pb.push(247 as UInt8);
  pb.push(13 as UInt8);
  pb.push(1 as UInt8);
  pb.push(5 as UInt8);
  pb.push(13 as UInt8);
  let alg = seq_of(cat2(oid_tlv(pb), null_tlv()));
  let payload = ff_bytes(4);
  let buf = seq_of(cat2(alg, octet(payload)));
  let r = kme_pkcs8_encrypted_parse(&buf);
  if !r.is_ok {
    ok = false;
  } else {
    let e: KmeEncryptedPrivateKeyInfo = r.value;
    if !streq(kme_epkcs8_alg_oid(&e), "1.2.840.113549.1.5.13") { ok = false; }
    if kme_epkcs8_data_len(&e) != 4 { ok = false; }
    if kme_epkcs8_data_offset(&e) < 0 { ok = false; }
    let db = kme_epkcs8_data_bytes(&buf, &e);
    if !bytes_equal(db, payload) { ok = false; }
    if kme_epkcs8_next(&e) != buf.len() { ok = false; }
  }
  var trunc = Vec[UInt8].new();
  var i = 0;
  while i < buf.len() - 1 {
    trunc.push(buf[i]);
    i = i + 1;
  }
  if !err_epki_pref(kme_pkcs8_encrypted_parse(&trunc), "keymgmt: der truncated value") { ok = false; }
  return assert(ok, "PKCS#8 EncryptedPrivateKeyInfo: walk and truncation");
}

fn t14() -> TestResult {
  var ok = true;
  let key65 = seq_bytes(65);
  let buf = seq_of(cat2(alg_with_curve(oid_body_ec(), oid_body_p256()), bit_str(0, key65)));
  let r = kme_spki_parse(&buf);
  if !r.is_ok {
    ok = false;
  } else {
    let s: KmeSpki = r.value;
    if !streq(kme_spki_alg_oid(&s), "1.2.840.10045.2.1") { ok = false; }
    if !kme_spki_alg_params_present(&s) { ok = false; }
    if !streq(kme_spki_alg_param_oid(&buf, &s), "1.2.840.10045.3.1.7") { ok = false; }
    if kme_spki_unused(&s) != 0 { ok = false; }
    if kme_spki_key_len(&s) != 65 { ok = false; }
    let kb = kme_spki_key_bytes(&buf, &s);
    if !bytes_equal(kb, key65) { ok = false; }
    if kme_spki_next(&s) != buf.len() { ok = false; }
  }
  let buf2 = seq_of(cat2(alg_with_null(oid_body_rsa()), bit_str(0, seq_bytes(5))));
  let r2 = kme_spki_parse(&buf2);
  if !r2.is_ok {
    ok = false;
  } else {
    let s2: KmeSpki = r2.value;
    if !streq(kme_spki_alg_oid(&s2), "1.2.840.113549.1.1.1") { ok = false; }
    if !kme_spki_alg_params_present(&s2) { ok = false; }
    if kme_spki_key_len(&s2) != 5 { ok = false; }
  }
  let buf3 = seq_of(cat2(alg_with_null(oid_body_rsa()), bit_str(3, seq_bytes(5))));
  let r3 = kme_spki_parse(&buf3);
  if !r3.is_ok { ok = false; } else { let s3: KmeSpki = r3.value; if kme_spki_unused(&s3) != 3 { ok = false; } if kme_spki_key_len(&s3) != 5 { ok = false; } }
  let buf4 = seq_of(cat2(alg_with_null(oid_body_rsa()), der(3, empty_bytes())));
  if !err_spki_pref(kme_spki_parse(&buf4), "keymgmt: der bad bit string") { ok = false; }
  let buf5 = seq_of(cat2(alg_with_null(oid_body_rsa()), octet(seq_bytes(2))));
  if !err_spki_pref(kme_spki_parse(&buf5), "keymgmt: der tag mismatch") { ok = false; }
  return assert(ok, "SPKI: algorithm/curve walk, BIT STRING unused bits and errors");
}

fn t15() -> TestResult {
  var ok = true;
  if !streq(kme_oid_name("1.2.840.113549.1.1.1"), "rsaEncryption") { ok = false; }
  if !streq(kme_oid_name("1.2.840.10045.2.1"), "id-ecPublicKey") { ok = false; }
  if !streq(kme_oid_name("1.2.840.10045.3.1.7"), "P-256") { ok = false; }
  if !streq(kme_oid_name("1.3.132.0.34"), "P-384") { ok = false; }
  if !streq(kme_oid_name("1.3.132.0.35"), "P-521") { ok = false; }
  if !streq(kme_oid_name("1.3.132.0.10"), "secp256k1") { ok = false; }
  if !streq(kme_oid_name("1.3.101.112"), "Ed25519") { ok = false; }
  if !streq(kme_oid_name("1.3.101.110"), "X25519") { ok = false; }
  if !streq(kme_oid_name("1.3.101.113"), "Ed448") { ok = false; }
  if !streq(kme_oid_name("1.3.101.111"), "X448") { ok = false; }
  if !streq(kme_oid_name("1.2.3.4"), "") { ok = false; }
  if !streq(kme_curve_oid("P-256"), "1.2.840.10045.3.1.7") { ok = false; }
  if !streq(kme_curve_oid("secp256k1"), "1.3.132.0.10") { ok = false; }
  if !streq(kme_curve_oid("X448"), "1.3.101.111") { ok = false; }
  if !streq(kme_curve_oid("nope"), "") { ok = false; }
  return assert(ok, "OID table: algorithm and named-curve names");
}

fn t16() -> TestResult {
  var ok = true;
  var data3 = Vec[UInt8].new();
  data3.push(1 as UInt8);
  data3.push(2 as UInt8);
  data3.push(3 as UInt8);
  let w = kme_pem_wrap("PRIVATE KEY", data3);
  if !w.is_ok {
    ok = false;
  } else {
    let t: Str = w.value;
    if !streq(t, "-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----\n") { ok = false; }
    let u = kme_pem_unwrap(t);
    if !u.is_ok {
      ok = false;
    } else {
      let b: KmePem = u.value;
      if !streq(kme_pem_label(&b), "PRIVATE KEY") { ok = false; }
      if !bytes_equal(kme_pem_data(&b), data3) { ok = false; }
    }
    let crlf = string.replace(t, "\n", "\r\n");
    let u2 = kme_pem_unwrap(crlf);
    if !u2.is_ok { ok = false; } else { let b2: KmePem = u2.value; if !bytes_equal(kme_pem_data(&b2), data3) { ok = false; } }
    let no_lf = string.str_slice(t, 0, t.len() - 1);
    let u3 = kme_pem_unwrap(no_lf);
    if !u3.is_ok { ok = false; } else { let b3: KmePem = u3.value; if !bytes_equal(kme_pem_data(&b3), data3) { ok = false; } }
  }
  let w2 = kme_pem_wrap("PUBLIC KEY", data3);
  if !w2.is_ok { ok = false; } else { let t2: Str = w2.value; let u4 = kme_pem_unwrap(t2); if !u4.is_ok { ok = false; } else { let b4: KmePem = u4.value; if !streq(kme_pem_label(&b4), "PUBLIC KEY") { ok = false; } } }
  let w3 = kme_pem_wrap("ENCRYPTED PRIVATE KEY", data3);
  if !w3.is_ok { ok = false; } else { let t3: Str = w3.value; let u5 = kme_pem_unwrap(t3); if !u5.is_ok { ok = false; } else { let b5: KmePem = u5.value; if !streq(kme_pem_label(&b5), "ENCRYPTED PRIVATE KEY") { ok = false; } } }
  if !err_pem_pref(kme_pem_unwrap("-----BEGIN CERTIFICATE-----\nAQID\n-----END CERTIFICATE-----\n"), "keymgmt: pem unsupported label") { ok = false; }
  if !err_pem_pref(kme_pem_unwrap("-----BEGIN PRIVATE KEY-----\nAQID\n"), "keymgmt: pem unterminated block") { ok = false; }
  if !err_pem_pref(kme_pem_unwrap("-----BEGIN PRIVATE KEY-----\nAQ!D\n-----END PRIVATE KEY-----\n"), "keymgmt: pem invalid base64 character") { ok = false; }
  if !err_pem_pref(kme_pem_unwrap("-----BEGIN PRIVATE KEY-----\nAQI\n-----END PRIVATE KEY-----\n"), "keymgmt: pem bad length") { ok = false; }
  if !err_pem_pref(kme_pem_unwrap("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n"), "keymgmt: pem empty body") { ok = false; }
  if !err_pem_pref(kme_pem_unwrap("x\n-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----\n"), "keymgmt: pem text outside block") { ok = false; }
  if !err_pem_pref(kme_pem_unwrap("-----BEGIN PRIVATE KEY-----\n\nAQID\n-----END PRIVATE KEY-----\n"), "keymgmt: pem blank line in body") { ok = false; }
  if !err_pem_pref(kme_pem_unwrap("-----BEGIN PRIVATE KEY-----\nAQID\n-----END PUBLIC KEY-----\n"), "keymgmt: pem label mismatch") { ok = false; }
  if !err_str_pref(kme_pem_wrap("CERTIFICATE", data3), "keymgmt: pem unsupported label") { ok = false; }
  return assert(ok, "PEM unwrap/rewrap: labels, CRLF, no-LF and the malformed catalog");
}

fn t17() -> TestResult {
  var ok = true;
  let line64 = string.str_repeat("////////////////", 4);
  let w = kme_pem_wrap("PRIVATE KEY", ff_bytes(48));
  if !w.is_ok {
    ok = false;
  } else {
    let t: Str = w.value;
    let want = "-----BEGIN PRIVATE KEY-----\n" + line64 + "\n-----END PRIVATE KEY-----\n";
    if !streq(t, want) { ok = false; }
  }
  let w2 = kme_pem_wrap("PRIVATE KEY", ff_bytes(49));
  if !w2.is_ok {
    ok = false;
  } else {
    let t2: Str = w2.value;
    let want2 = "-----BEGIN PRIVATE KEY-----\n" + line64 + "\n/w==\n-----END PRIVATE KEY-----\n";
    if !streq(t2, want2) { ok = false; }
  }
  return assert(ok, "PEM wrap: exact 64-column body and padding of the final group");
}

fn t18() -> TestResult {
  var ok = true;
  let payload = seq_bytes(64);
  let w = kme_pem_wrap("ENCRYPTED PRIVATE KEY", payload);
  if !w.is_ok {
    ok = false;
  } else {
    let t: Str = w.value;
    let u = kme_pem_unwrap(t);
    if !u.is_ok {
      ok = false;
    } else {
      let b: KmePem = u.value;
      if !streq(kme_pem_label(&b), "ENCRYPTED PRIVATE KEY") { ok = false; }
      if !bytes_equal(kme_pem_data(&b), payload) { ok = false; }
    }
    let u2 = kme_pem_unwrap(string.replace(t, "\n", "\r\n"));
    if !u2.is_ok { ok = false; } else { let b2: KmePem = u2.value; if !bytes_equal(kme_pem_data(&b2), payload) { ok = false; } }
  }
  let pub_w = kme_pem_wrap("PUBLIC KEY", payload);
  if !pub_w.is_ok { ok = false; } else { let tp: Str = pub_w.value; let up = kme_pem_unwrap(tp); if !up.is_ok { ok = false; } else { let bp: KmePem = up.value; if !bytes_equal(kme_pem_data(&bp), payload) { ok = false; } } }
  return assert(ok, "PEM round-trip: 64-byte payload across labels and line endings");
}

fn t19() -> TestResult {
  var ok = true;
  let r = kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\"}");
  if !r.is_ok {
    ok = false;
  } else {
    let k: Jwk = r.value;
    if kme_jwk_param_len(&k, "zz") != -1 { ok = false; }
    if kme_jwk_param(&k, "zz").len() != 0 { ok = false; }
    if kme_jwk_key_ops_count(&k) != 0 { ok = false; }
    if !streq(kme_jwk_key_op(&k, 0), "") { ok = false; }
    if !streq(kme_jwk_x5c(&k, 0), "") { ok = false; }
    if !streq(kme_jwk_member(&k, 9), "") { ok = false; }
    if !streq(kme_jwk_alg(&k), "") { ok = false; }
    if !streq(kme_jwk_x5t_s256(&k), "") { ok = false; }
  }
  let s = kme_jwks_parse("{\"keys\":[]}");
  if !s.is_ok {
    ok = false;
  } else {
    let js: Jwks = s.value;
    if kme_jwks_count(&js) != 0 { ok = false; }
    if kme_jwks_lookup(&js, "x") != -1 { ok = false; }
    if !err_jwk_pref(kme_jwks_key(&js, -1), "keymgmt: jwks index out of range") { ok = false; }
  }
  if !streq(kme_label_private_key(), "PRIVATE KEY") { ok = false; }
  if !streq(kme_label_encrypted_private_key(), "ENCRYPTED PRIVATE KEY") { ok = false; }
  if !streq(kme_label_public_key(), "PUBLIC KEY") { ok = false; }
  if kme_version() != 1 { ok = false; }
  return assert(ok, "Accessors: out-of-range neutrals, labels and module version");
}

fn t20() -> TestResult {
  var ok = true;
  let rsa = kme_jwk_parse("{\"kty\":\"RSA\",\"n\":\"AQAB\",\"e\":\"AQAB\"}");
  if !rsa.is_ok {
    ok = false;
  } else {
    let k: Jwk = rsa.value;
    if !streq(kme_jwk_oid(&k), "1.2.840.113549.1.1.1") { ok = false; }
    if !streq(kme_jwk_alg_name(&k), "rsaEncryption") { ok = false; }
    if !streq(kme_jwk_curve_oid(&k), "") { ok = false; }
  }
  let x48 = seq_bytes(48);
  let ec = kme_jwk_parse("{\"kty\":\"EC\",\"crv\":\"P-384\"," + jwk_b64_member("x", x48) + "," + jwk_b64_member("y", x48) + "}");
  if !ec.is_ok {
    ok = false;
  } else {
    let k2: Jwk = ec.value;
    if !streq(kme_jwk_oid(&k2), "1.2.840.10045.2.1") { ok = false; }
    if !streq(kme_jwk_alg_name(&k2), "id-ecPublicKey") { ok = false; }
    if !streq(kme_jwk_curve_oid(&k2), "1.3.132.0.34") { ok = false; }
  }
  let x56 = seq_bytes(56);
  let okp = kme_jwk_parse("{\"kty\":\"OKP\",\"crv\":\"X448\"," + jwk_b64_member("x", x56) + "}");
  if !okp.is_ok {
    ok = false;
  } else {
    let k3: Jwk = okp.value;
    if !streq(kme_jwk_oid(&k3), "1.3.101.111") { ok = false; }
    if !streq(kme_jwk_alg_name(&k3), "X448") { ok = false; }
    if !streq(kme_jwk_curve_oid(&k3), "1.3.101.111") { ok = false; }
  }
  let oct = kme_jwk_parse("{\"kty\":\"oct\",\"k\":\"AQAB\"}");
  if !oct.is_ok {
    ok = false;
  } else {
    let k4: Jwk = oct.value;
    if !streq(kme_jwk_oid(&k4), "") { ok = false; }
    if !streq(kme_jwk_alg_name(&k4), "") { ok = false; }
    if !streq(kme_jwk_curve_oid(&k4), "") { ok = false; }
  }
  return assert(ok, "Cross-format JWK -> SPKI mappings for all four kty");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.keymgmt conformance tests ===");
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
    io.println("xiom.keymgmt: all tests passed");
  } else {
    io.println("xiom.keymgmt: tests failed");
  }
  return failed;
}
