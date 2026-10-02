// XIOM -- xiom.aws conformance tests (27 checks)
// Port task: prove the AWS SigV4 request/signing model documented in SPEC.md.
// Every check is a named assert(cond, "name") call, one fn per check, and main
// returns the failure count (0 = green).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Known-answer values:
//   * SHA-256: NIST FIPS 180-4 examples (abc / empty / 448-bit) and the
//     canonical "hello world" digest.
//   * HMAC-SHA-256: RFC 4231 test cases 1, 2, 3 and 6 (case 6 has a 131-byte
//     key, so the key is hashed before padding).
//   * SigV4: the AWS documentation IAM ListUsers example and the AWS
//     aws-sig-v4-test-suite get-vanilla request, plus the documented
//     IAM example's intermediate canonical-request hash and signing key.
//   * Backoff: the deterministic LCG schedule is pinned by exact values.
//
// BUG-17 discipline: Str equality goes through compare.str_compare, every
// Vec element read is bound to a typed local, and bytes are widened with
// `(x as Int) & 0xFF` before comparison.

module aws_tests
use xiom.io; use xiom.test; use xiom.aws; use xiom.aws.base;
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

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
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

fn str_ok_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return streq(v, want);
}

fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn cred_err_is(r: Result[AwsCredential, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn svc_err_is(r: Result[AwsService, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let m: Str = r.error;
  return streq(m, want);
}

fn cred_ok_is(r: Result[AwsCredential, Str], ak: Str, sk: Str, tok: Str) -> Bool {  if !r.is_ok {
    return false;
  }
  let c: AwsCredential = r.value;
  let gak: Str = c.access_key;
  let gsk: Str = c.secret_key;
  let gtok: Str = c.session_token;
  if !streq(gak, ak) {
    return false;
  }
  if !streq(gsk, sk) {
    return false;
  }
  return streq(gtok, tok);
}

fn svc_ok_is(r: Result[AwsService, Str], host: Str, signing: Str, global: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let s: AwsService = r.value;
  let gh: Str = s.host;
  let gs: Str = s.signing_name;
  if !streq(gh, host) {
    return false;
  }
  if !streq(gs, signing) {
    return false;
  }
  return s.is_global == global;
}

// Parallel header vectors for the SigV4 known-answer requests.
fn headers_iam(names: &mut Vec[Str], values: &mut Vec[Str]) {
  names.push("Content-Type");
  names.push("Host");
  names.push("X-Amz-Date");
  values.push("application/x-www-form-urlencoded; charset=utf-8");
  values.push("iam.amazonaws.com");
  values.push("20150830T123600Z");
}

fn headers_get_vanilla(names: &mut Vec[Str], values: &mut Vec[Str]) {
  names.push("Host");
  names.push("X-Amz-Date");
  values.push("example.amazonaws.com");
  values.push("20150830T123600Z");
}

// --------------------------------------------------
//  SHA-256 known answers
// --------------------------------------------------

fn t1() -> TestResult {
  let abc = sb("abc");
  let empty = sb("");
  let h1: Str = base.aws_sha256_hex(&abc);
  var ok = streq(h1, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  let h2: Str = base.aws_sha256_hex(&empty);
  ok = ok && streq(h2, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  ok = ok && streq(h2, base.aws_empty_payload_sha256());
  return assert(ok, "sha256: NIST abc and empty-string KATs");
}

fn t2() -> TestResult {
  let hw = sb("hello world");
  let h1: Str = base.aws_sha256_hex(&hw);
  var ok = streq(h1, "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9");
  let m56 = sb("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
  let h2: Str = base.aws_sha256_hex(&m56);
  ok = ok && streq(h2, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  let d: Vec[UInt8] = base.aws_sha256(&m56);
  ok = ok && d.len() == 32;
  return assert(ok, "sha256: hello-world and NIST 448-bit (56-byte) KATs");
}

// --------------------------------------------------
//  HMAC-SHA-256 known answers (RFC 4231)
// --------------------------------------------------

fn t3() -> TestResult {
  let k1 = base.aws_bytes_repeat(0x0B, 20);
  let d1 = sb("Hi There");
  let m1: Str = base.aws_hmac_sha256_hex(&k1, &d1);
  var ok = streq(m1, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
  let k2 = sb("Jefe");
  let d2 = sb("what do ya want for nothing?");
  let m2: Str = base.aws_hmac_sha256_hex(&k2, &d2);
  ok = ok && streq(m2, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
  return assert(ok, "hmac-sha256: RFC 4231 TC1 and TC2 KATs");
}

fn t4() -> TestResult {
  let k3 = base.aws_bytes_repeat(0xAA, 20);
  let d3 = base.aws_bytes_repeat(0xDD, 50);
  let m3: Str = base.aws_hmac_sha256_hex(&k3, &d3);
  var ok = streq(m3, "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe");
  let k6 = base.aws_bytes_repeat(0xAA, 131);
  let d6 = sb("Test Using Larger Than Block-Size Key - Hash Key First");
  let m6: Str = base.aws_hmac_sha256_hex(&k6, &d6);
  ok = ok && streq(m6, "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");
  return assert(ok, "hmac-sha256: RFC 4231 TC3 and TC6 (key > 64 bytes) KATs");
}

// --------------------------------------------------
//  Bytes and hex
// --------------------------------------------------

fn t5() -> TestResult {
  let b = sb("Hello, AWS!");
  let hx: Str = base.aws_hex_encode_lower(&b);
  var ok = streq(hx, "48656c6c6f2c2041575321");
  let a = sb("abc");
  let c = sb("def");
  let joined = base.aws_bytes_concat(&a, &c);
  let want = sb("abcdef");
  ok = ok && base.aws_bytes_eq(&joined, &want);
  ok = ok && !base.aws_bytes_eq(&a, &c);
  let r = base.aws_bytes_repeat(65, 3);
  ok = ok && r.len() == 3;
  ok = ok && ((r[0] as Int) & 0xFF) == 65 && ((r[2] as Int) & 0xFF) == 65;
  let rt = base.aws_bytes_of_str("round trip");
  let back = base.aws_bytes_of_str("round trip");
  ok = ok && base.aws_bytes_eq(&rt, &back);
  return assert(ok, "bytes: hex KAT, concat, repeat, round-trip equality");
}

// --------------------------------------------------
//  URI and canonicalization
// --------------------------------------------------

fn t6() -> TestResult {
  let e1: Str = aws_uri_encode("a b/c~d");
  var ok = streq(e1, "a%20b%2Fc~d");
  let e2: Str = aws_uri_encode("Az09-._~");
  ok = ok && streq(e2, "Az09-._~");
  let e3: Str = aws_uri_encode("=");
  ok = ok && streq(e3, "%3D");
  let e4: Str = aws_canonical_uri("/a b/stack~1/x");
  ok = ok && streq(e4, "/a%20b/stack~1/x");
  return assert(ok, "uri: SigV4 percent-encoding and canonical URI");
}

fn t7() -> TestResult {
  let q1: Str = aws_canonical_query("Version=2010-05-08&Action=ListUsers");
  var ok = streq(q1, "Action=ListUsers&Version=2010-05-08");
  let q2: Str = aws_canonical_query("b=2&a=1&a=0");
  ok = ok && streq(q2, "a=0&a=1&b=2");
  let q3: Str = aws_canonical_query("");
  ok = ok && streq(q3, "");
  let q4: Str = aws_canonical_query("flag");
  ok = ok && streq(q4, "flag=");
  let q5: Str = aws_canonical_query("k=a b");
  ok = ok && streq(q5, "k=a%20b");
  return assert(ok, "query: sort by name then value, encode, flag= and empty cases");
}

fn t8() -> TestResult {
  var hn = Vec[Str].new();
  var hv = Vec[Str].new();
  headers_iam(&mut hn, &mut hv);
  let ch: Str = aws_canonical_headers(&hn, &hv);
  var ok = streq(ch, "content-type:application/x-www-form-urlencoded; charset=utf-8\nhost:iam.amazonaws.com\nx-amz-date:20150830T123600Z\n");
  let sh: Str = aws_signed_headers(&hn);
  ok = ok && streq(sh, "content-type;host;x-amz-date");
  var hn2 = Vec[Str].new();
  var hv2 = Vec[Str].new();
  hn2.push("A");
  hv2.push("  x   y  ");
  let ch2: Str = aws_canonical_headers(&hn2, &hv2);
  ok = ok && streq(ch2, "a:x y\n");
  return assert(ok, "headers: lowercase, trim/collapse, sort, signed-header list");
}

// --------------------------------------------------
//  SigV4 known-answer vectors
// --------------------------------------------------

fn t9() -> TestResult {
  let ph: Str = base.aws_empty_payload_sha256();
  let req = AwsRequest{
    service: "service";
    region: "us-east-1";
    method: "GET";
    path: "/";
    query: "";
    action: "";
    payload_hash: ph;
  };
  var hn = Vec[Str].new();
  var hv = Vec[Str].new();
  headers_get_vanilla(&mut hn, &mut hv);
  let crr = aws_canonical_request(&req, &hn, &hv);
  var ok = crr.is_ok;
  if crr.is_ok {
    let cr: Str = crr.value;
    let want = "GET\n/\n\nhost:example.amazonaws.com\nx-amz-date:20150830T123600Z\n\nhost;x-amz-date\n" + ph;
    ok = ok && streq(cr, want);
    let h: Str = base.aws_sha256_hex_str(cr);
    ok = ok && streq(h, "bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63");
  }
  return assert(ok, "sigv4: get-vanilla canonical request text and hash");
}

fn t10() -> TestResult {
  let d1 = aws_amz_date_from_unix(1440938160);
  var ok = str_ok_is(d1, "20150830T123600Z");
  let d2 = aws_amz_date_from_unix(0);
  ok = ok && str_ok_is(d2, "19700101T000000Z");
  let d3 = aws_amz_date_from_unix(-1);
  ok = ok && str_err_is(d3, "aws: negative unix time");
  return assert(ok, "date: Unix seconds to amz date (documented epoch 1440938160)");
}

fn t11() -> TestResult {
  let d8: Str = aws_date8("20150830T123600Z");
  var ok = streq(d8, "20150830");
  let s1 = aws_credential_scope("20150830T123600Z", "us-east-1", "iam");
  ok = ok && str_ok_is(s1, "20150830/us-east-1/iam/aws4_request");
  let s2 = aws_credential_scope("20150830T123600Z", "us-east-1", "cloudwatch");
  ok = ok && str_ok_is(s2, "20150830/us-east-1/monitoring/aws4_request");
  let s3 = aws_credential_scope("2015083", "us-east-1", "iam");
  ok = ok && str_err_is(s3, "aws: bad amz date");
  let s4 = aws_credential_scope("20150830T123600Z", "", "iam");
  ok = ok && str_err_is(s4, "aws: missing region");
  return assert(ok, "scope: date8, signing-name mapping, bad-date and region errors");
}

fn t12() -> TestResult {
  let k = aws_signing_key("wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "20150830", "us-east-1", "iam");
  let hx: Str = base.aws_hex_encode_lower(&k);
  return assert(streq(hx, "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9"), "sigv4: derived signing key KAT (AWS IAM example)");
}

fn t13() -> TestResult {
  let ph: Str = base.aws_empty_payload_sha256();
  let req = AwsRequest{
    service: "iam";
    region: "us-east-1";
    method: "GET";
    path: "/";
    query: "Action=ListUsers&Version=2010-05-08";
    action: "ListUsers";
    payload_hash: ph;
  };
  let cred = AwsCredential{
    access_key: "AKIDEXAMPLE";
    secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  var hn = Vec[Str].new();
  var hv = Vec[Str].new();
  headers_iam(&mut hn, &mut hv);
  let r = aws_sign_v4(&req, &cred, "20150830T123600Z", &hn, &hv);
  let want = "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/iam/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7";
  return assert(str_ok_is(r, want), "sigv4: AWS documentation IAM ListUsers full-request KAT");
}

fn t14() -> TestResult {
  let ph: Str = base.aws_empty_payload_sha256();
  let req = AwsRequest{
    service: "service";
    region: "us-east-1";
    method: "GET";
    path: "/";
    query: "";
    action: "";
    payload_hash: ph;
  };
  let cred = AwsCredential{
    access_key: "AKIDEXAMPLE";
    secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  var hn = Vec[Str].new();
  var hv = Vec[Str].new();
  headers_get_vanilla(&mut hn, &mut hv);
  let r = aws_sign_v4(&req, &cred, "20150830T123600Z", &hn, &hv);
  let want = "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31";
  return assert(str_ok_is(r, want), "sigv4: aws-sig-v4-test-suite get-vanilla full-request KAT");
}

fn t15() -> TestResult {
  let ph: Str = base.aws_empty_payload_sha256();
  let req = AwsRequest{
    service: "sts";
    region: "us-east-1";
    method: "GET";
    path: "/";
    query: "";
    action: "";
    payload_hash: ph;
  };
  let cred = AwsCredential{
    access_key: "AKIDEXAMPLE";
    secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY";
    session_token: "SESSIONTOKENEXAMPLE";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  var hn = Vec[Str].new();
  var hv = Vec[Str].new();
  hn.push("Host");
  hn.push("X-Amz-Date");
  hn.push("X-Amz-Security-Token");
  hv.push("sts.amazonaws.com");
  hv.push("20150830T123600Z");
  hv.push("SESSIONTOKENEXAMPLE");
  let r = aws_sign_v4(&req, &cred, "20150830T123600Z", &hn, &hv);
  let want = "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/sts/aws4_request, SignedHeaders=host;x-amz-date;x-amz-security-token, Signature=10d12af4f59ebc6f28e7962f0a3f38f5649ad8811f1a82d770f13dbf94d9831c";
  return assert(str_ok_is(r, want), "sigv4: session-token header participates in the signature");
}

// --------------------------------------------------
//  Signing error cases
// --------------------------------------------------

fn t16() -> TestResult {
  let ph: Str = base.aws_empty_payload_sha256();
  let req = AwsRequest{
    service: "iam";
    region: "us-east-1";
    method: "GET";
    path: "/";
    query: "";
    action: "";
    payload_hash: ph;
  };
  let noak = AwsCredential{
    access_key: "";
    secret_key: "s";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  let nosk = AwsCredential{
    access_key: "ak";
    secret_key: "";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  var hn = Vec[Str].new();
  var hv = Vec[Str].new();
  headers_get_vanilla(&mut hn, &hv);
  let e1 = aws_sign_v4(&req, &noak, "20150830T123600Z", &hn, &hv);
  var ok = str_err_is(e1, "aws: missing access key");
  let e2 = aws_sign_v4(&req, &nosk, "20150830T123600Z", &hn, &hv);
  ok = ok && str_err_is(e2, "aws: missing secret key");
  var short_hv = Vec[Str].new();
  short_hv.push("example.amazonaws.com");
  let good = AwsCredential{
    access_key: "ak";
    secret_key: "sk";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  let e3 = aws_sign_v4(&req, &good, "20150830T123600Z", &hn, &short_hv);
  ok = ok && str_err_is(e3, "aws: header name/value count mismatch");
  var nhn = Vec[Str].new();
  var nhv = Vec[Str].new();
  nhn.push("X-Amz-Date");
  nhv.push("20150830T123600Z");
  let e4 = aws_canonical_request(&req, &nhn, &nhv);
  ok = ok && str_err_is(e4, "aws: missing host header");
  let e5 = aws_canonical_request(&req, &hn, &short_hv);
  ok = ok && str_err_is(e5, "aws: header name/value count mismatch");
  return assert(ok, "errors: missing keys, header arity mismatch, missing host");
}

// --------------------------------------------------
//  Credential model
// --------------------------------------------------

fn t17() -> TestResult {
  let now = 1000000;
  let never = AwsCredential{
    access_key: "AKIA_LONG";
    secret_key: "longsecret";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_EXPLICIT;
  };
  let expired = AwsCredential{
    access_key: "AKIA_TEMP";
    secret_key: "temsecret";
    session_token: "tok";
    expiry_unix: 999999;
    source: AWS_CRED_SOURCE_ENVIRONMENT;
  };
  let future = AwsCredential{
    access_key: "AKIA_TEMP2";
    secret_key: "temsecret2";
    session_token: "tok2";
    expiry_unix: 1000001;
    source: AWS_CRED_SOURCE_PROFILE;
  };
  let empty = AwsCredential{
    access_key: "";
    secret_key: "";
    session_token: "";
    expiry_unix: 0;
    source: AWS_CRED_SOURCE_INSTANCE;
  };
  var ok = aws_credential_valid(&never, now);
  ok = ok && !aws_credential_valid(&expired, now);
  ok = ok && aws_credential_valid(&future, now);
  ok = ok && !aws_credential_valid(&empty, now);
  return assert(ok, "credentials: validity, 0 = never expires, expiry boundaries");
}

fn t18() -> TestResult {
  var src = Vec[Int].new();
  var ak = Vec[Str].new();
  var sk = Vec[Str].new();
  var tok = Vec[Str].new();
  var exp = Vec[Int].new();
  src.push(AWS_CRED_SOURCE_EXPLICIT);
  ak.push("AKIA_EXPIRED");
  sk.push("s1");
  tok.push("");
  exp.push(900);
  src.push(AWS_CRED_SOURCE_ENVIRONMENT);
  ak.push("AKIA_ENV");
  sk.push("s2");
  tok.push("");
  exp.push(0);
  src.push(AWS_CRED_SOURCE_PROFILE);
  ak.push("AKIA_PROFILE");
  sk.push("s3");
  tok.push("tok3");
  exp.push(0);
  let r = aws_resolve_credential(&src, &ak, &sk, &tok, &exp, 1000);
  var ok = cred_ok_is(r, "AKIA_ENV", "s2", "");
  if r.is_ok {
    let c: AwsCredential = r.value;
    ok = ok && c.source == AWS_CRED_SOURCE_ENVIRONMENT;
  }
  var esrc = Vec[Int].new();
  var eak = Vec[Str].new();
  var esk = Vec[Str].new();
  var etok = Vec[Str].new();
  var eexp = Vec[Int].new();
  esrc.push(AWS_CRED_SOURCE_EXPLICIT);
  eak.push("AKIA_EXPIRED");
  esk.push("s1");
  etok.push("");
  eexp.push(900);
  let all_bad = aws_resolve_credential(&esrc, &eak, &esk, &etok, &eexp, 1000);
  if all_bad.is_ok {
    ok = false;
  } else {
    let m: Str = all_bad.error;
    ok = ok && streq(m, "aws: no usable credentials");
  }
  let mismatch = aws_resolve_credential(&src, &ak, &sk, &etok, &exp, 1000);
  ok = ok && cred_err_is(mismatch, "aws: credential chain arity mismatch");
  return assert(ok, "credentials: chain picks first usable, all-bad and arity errors");
}

fn t19() -> TestResult {
  var ok = streq(aws_credential_source_name(AWS_CRED_SOURCE_EXPLICIT), "explicit");
  ok = ok && streq(aws_credential_source_name(AWS_CRED_SOURCE_ENVIRONMENT), "environment");
  ok = ok && streq(aws_credential_source_name(AWS_CRED_SOURCE_PROFILE), "profile");
  ok = ok && streq(aws_credential_source_name(AWS_CRED_SOURCE_INSTANCE), "instance");
  ok = ok && streq(aws_credential_source_name(AWS_CRED_SOURCE_NONE), "none");
  ok = ok && streq(aws_credential_source_name(99), "unknown");
  return assert(ok, "credentials: source-name dispatch");
}

// --------------------------------------------------
//  Service registry
// --------------------------------------------------

fn t20() -> TestResult {
  let iam = aws_service_lookup("iam", "");
  var ok = svc_ok_is(iam, "iam.amazonaws.com", "iam", true);
  let sts = aws_service_lookup("sts", "us-east-1");
  ok = ok && svc_ok_is(sts, "sts.amazonaws.com", "sts", true);
  let s3 = aws_service_lookup("s3", "eu-west-1");
  ok = ok && svc_ok_is(s3, "s3.eu-west-1.amazonaws.com", "s3", false);
  let cw = aws_service_lookup("cloudwatch", "us-east-1");
  ok = ok && svc_ok_is(cw, "monitoring.us-east-1.amazonaws.com", "monitoring", false);
  let q = aws_service_lookup("sqs", "us-east-1");
  ok = ok && svc_ok_is(q, "sqs.us-east-1.amazonaws.com", "sqs", false);
  let bad1 = aws_service_lookup("", "us-east-1");
  ok = ok && svc_err_is(bad1, "aws: empty service name");
  let bad2 = aws_service_lookup("dynamodb", "");
  ok = ok && svc_err_is(bad2, "aws: empty region for regional service");
  let h = aws_service_host("s3", "us-west-2");
  ok = ok && str_ok_is(h, "s3.us-west-2.amazonaws.com");
  return assert(ok, "registry: global vs regional dispatch, cloudwatch->monitoring");
}

// --------------------------------------------------
//  Retry / backoff
// --------------------------------------------------

fn t21() -> TestResult {
  var ok = aws_retryable_status(408);
  ok = ok && aws_retryable_status(429);
  ok = ok && aws_retryable_status(500);
  ok = ok && aws_retryable_status(502);
  ok = ok && aws_retryable_status(503);
  ok = ok && aws_retryable_status(504);
  ok = ok && !aws_retryable_status(200);
  ok = ok && !aws_retryable_status(400);
  ok = ok && !aws_retryable_status(404);
  return assert(ok, "retry: transient status set");
}

fn t22() -> TestResult {
  var ok = aws_retryable_error_code("Throttling");
  ok = ok && aws_retryable_error_code("ThrottlingException");
  ok = ok && aws_retryable_error_code("ProvisionedThroughputExceededException");
  ok = ok && aws_retryable_error_code("RequestTimeout");
  ok = ok && aws_retryable_error_code("SlowDown");
  ok = ok && aws_retryable_error_code("InternalError");
  ok = ok && !aws_retryable_error_code("AccessDenied");
  ok = ok && !aws_retryable_error_code("NoSuchBucket");
  ok = ok && !aws_retryable_error_code("");
  return assert(ok, "retry: transient error-code dispatch");
}

fn t23() -> TestResult {
  let d1 = aws_backoff_delay_ms(1, 100, 20000, 42);
  let d1b = aws_backoff_delay_ms(1, 100, 20000, 42);
  var ok = d1 == d1b;
  ok = ok && d1 == 35;
  let d3 = aws_backoff_delay_ms(3, 100, 20000, 42);
  ok = ok && d3 == 83 && d3 <= 400;
  let d4 = aws_backoff_delay_ms(4, 100, 20000, 42);
  ok = ok && d4 == 705 && d4 <= 800;
  let dbig = aws_backoff_delay_ms(1000, 100, 250, 42);
  ok = ok && dbig >= 0 && dbig <= 250;
  let s1 = aws_backoff_delay_ms(4, 100, 20000, 7);
  let s2 = aws_backoff_delay_ms(4, 100, 20000, 8);
  ok = ok && s1 != s2;
  let z = aws_backoff_delay_ms(0, 100, 20000, 42);
  ok = ok && z == 0;
  let zm = aws_backoff_delay_ms(3, 100, 0, 42);
  ok = ok && zm == 0;
  return assert(ok, "retry: deterministic full-jitter backoff, capped and bounded");
}

// --------------------------------------------------
//  Response envelope
// --------------------------------------------------

fn t24() -> TestResult {
  var ok = aws_response_class(100) == AWS_STATUS_INFORMATIONAL;
  ok = ok && aws_response_class(200) == AWS_STATUS_SUCCESS;
  ok = ok && aws_response_class(204) == AWS_STATUS_SUCCESS;
  ok = ok && aws_response_class(301) == AWS_STATUS_REDIRECT;
  ok = ok && aws_response_class(404) == AWS_STATUS_CLIENT_ERROR;
  ok = ok && aws_response_class(503) == AWS_STATUS_SERVER_ERROR;
  ok = ok && aws_response_class(0) == AWS_STATUS_UNKNOWN;
  ok = ok && aws_response_class(700) == AWS_STATUS_UNKNOWN;
  ok = ok && aws_response_is_success(200);
  ok = ok && !aws_response_is_success(302);
  return assert(ok, "response: status class dispatch and 2xx success predicate");
}

fn t25() -> TestResult {
  let empty = sb("");
  let ws = sb(" \t\r\n");
  let json = sb("  {\"a\":1}");
  let arr = sb("[1,2]");
  let xml = sb("<?xml version=\"1.0\"?><Error/>");
  let text = sb("hello");
  var bin = Vec[UInt8].new();
  bin.push(1 as UInt8);
  bin.push(65 as UInt8);
  var ok = aws_body_shape(&empty) == AWS_SHAPE_EMPTY;
  ok = ok && aws_body_shape(&ws) == AWS_SHAPE_EMPTY;
  ok = ok && aws_body_shape(&json) == AWS_SHAPE_JSON;
  ok = ok && aws_body_shape(&arr) == AWS_SHAPE_JSON;
  ok = ok && aws_body_shape(&xml) == AWS_SHAPE_XML;
  ok = ok && aws_body_shape(&text) == AWS_SHAPE_TEXT;
  ok = ok && aws_body_shape(&bin) == AWS_SHAPE_BINARY;
  return assert(ok, "response: body-shape classification across five shapes");
}

fn t26() -> TestResult {
  var hn = Vec[Str].new();
  var hv = Vec[Str].new();
  headers_get_vanilla(&mut hn, &mut hv);
  let r1 = aws_header_find(&hn, &hv, "host");
  var ok = str_ok_is(r1, "example.amazonaws.com");
  let r2 = aws_header_find(&hn, &hv, "HOST");
  ok = ok && str_ok_is(r2, "example.amazonaws.com");
  let r3 = aws_header_find(&hn, &hv, "X-Missing");
  ok = ok && str_err_is(r3, "aws: header not found: X-Missing");
  var short_v = Vec[Str].new();
  short_v.push("only-one");
  let r4 = aws_header_find(&hn, &short_v, "host");
  ok = ok && str_err_is(r4, "aws: header name/value count mismatch");
  return assert(ok, "response: case-insensitive header lookup and arity error");
}

fn t27() -> TestResult {
  let empty = sb("");
  let json = sb("{\"message\":\"boom\"}");
  let r1 = aws_response_envelope(503, &json);
  var ok = r1.status == 503;
  ok = ok && r1.shape == AWS_SHAPE_JSON;
  ok = ok && r1.retryable;
  let r2 = aws_response_envelope(200, &empty);
  ok = ok && r2.shape == AWS_SHAPE_EMPTY;
  ok = ok && !r2.retryable;
  let r3 = aws_response_envelope(429, &empty);
  ok = ok && r3.retryable;
  return assert(ok, "response: envelope composes status, shape and retryability");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.aws conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.aws: all tests passed");
  } else {
    io.println("xiom.aws: tests failed");
  }
  return failed;
}
