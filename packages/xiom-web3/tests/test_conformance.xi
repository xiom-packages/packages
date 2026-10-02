// XIOM -- xiom.web3 conformance tests (28 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic, self-contained: every input is built in-test (no files, no
// network, no randomness). Covers Keccak-256 known vectors (including the
// 135/136-byte padding boundary), EIP-55 checksum vectors and verification
// policy, address normalization/round-trips, ENS normalization errors and
// namehash vectors, selectors, the 32-byte ABI word set, and the provider
// request/response model (including id matching and malformed envelopes).
//
// Harness style mirrors xiom.hello / xiom.ethereum: one fn tN() -> TestResult
// per check, called directly from main; Str payloads compare with str_compare
// (never `==`), every Vec element read is bound to a typed local first, and
// every UInt8 is widened with `(x as Int) & 0xFF`. Calls into the package go
// through the `web3.` facade so the public entry point is exercised too.

module web3_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.web3;
use xiom.web3.provider;

// Expected bytes for a hex string ("" on malformed input; the check then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// Bytes of a Str, byte-for-byte.
fn ab(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if ((x as Int) & 0xFF) != ((y as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Byte `i` of a byte vector widened to an Int (0..255).
fn bv(v: &Vec[UInt8], i: Int) -> Int {
  let b: UInt8 = v[i];
  return (b as Int) & 0xFF;
}

fn str_is(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

fn hex_of(v: &Vec[UInt8]) -> Str {
  return hex.hex_encode(v);
}

// `n` zero bytes.
fn zn(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

// `n` copies of `c`.
fn rep_str(c: Str, n: Int) -> Str {
  var out = "";
  var i = 0;
  while i < n {
    out = out + c;
    i = i + 1;
  }
  return out;
}

// Result[Vec[UInt8], Str] is Ok and equals the expected hex bytes.
fn bexp(r: Result[Vec[UInt8], Str], hexstr: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  let e = hb(hexstr);
  return bytes_equal(&v, &e);
}

// Result[Str, Str] error starts with `prefix`.
fn sprefix(r: Result[Str, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return string.str_starts_with(r.error, prefix);
}

// Result[Vec[UInt8], Str] error starts with `prefix`.
fn bprefix(r: Result[Vec[UInt8], Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return string.str_starts_with(r.error, prefix);
}

// Result[Int, Str] error starts with `prefix`.
fn iprefix(r: Result[Int, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return string.str_starts_with(r.error, prefix);
}

// Result[Bool, Str] error starts with `prefix`.
fn boolprefix(r: Result[Bool, Str], prefix: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return string.str_starts_with(r.error, prefix);
}

// Lowercase hex of keccak256 over the UTF-8 bytes of `s`.
fn kh(s: Str) -> Str {
  let b = ab(s);
  let h = web3.keccak256(&b);
  return hex_of(&h);
}

// Lowercase hex of keccak256 over `n` zero bytes.
fn kz(n: Int) -> Str {
  let z = zn(n);
  let h = web3.keccak256(&z);
  return hex_of(&h);
}

fn t1() -> TestResult {
  let ok = str_is(kh(""), "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
  return assert(ok, "keccak256 of empty input matches the known vector");
}

fn t2() -> TestResult {
  let ok = str_is(kh("abc"), "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45");
  return assert(ok, "keccak256 of \"abc\" matches the known vector");
}

fn t3() -> TestResult {
  let ok = str_is(kh("The quick brown fox jumps over the lazy dog"),
                  "4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15");
  return assert(ok, "keccak256 of the fox sentence matches the known vector");
}

fn t4() -> TestResult {
  let ok = str_is(kh("Hello, world!"),
                  "b6e16d27ac5ab427a7f68900ac5559ce272dc6c37c82b3e052246c82244c50e4");
  return assert(ok, "keccak256 of \"Hello, world!\" matches the known vector");
}

fn t5() -> TestResult {
  let ok = str_is(kz(135), "29e3704feeca7fb9ba229f0fa04d9b36449cf3ad6e1d85d9cfff3a10df9abc3e");
  return assert(ok, "keccak256 of 135 zero bytes (pad byte collides with 0x80)");
}

fn t6() -> TestResult {
  let ok = str_is(kz(136), "3a5912a7c5faa06ee4fe906253e339467a9ce87d533c65be3c15cb231cdb25f9");
  return assert(ok, "keccak256 of 136 zero bytes (two absorbed blocks)");
}

fn t7() -> TestResult {
  let b = ab("transfer(address,uint256)");
  let h = web3.keccak256(&b);
  var ok = h.len() == 32;
  if !str_is(hex_of(&h), "a9059cbb2ab09eb219583f4a59a5d0623ade346d962bcd4e46b11da047c9049b") {
    ok = false;
  }
  if bv(&h, 0) != 0xA9 { ok = false; }
  if bv(&h, 1) != 0x05 { ok = false; }
  if bv(&h, 2) != 0x9C { ok = false; }
  if bv(&h, 3) != 0xBB { ok = false; }
  return assert(ok, "keccak256 of a function signature and its selector prefix");
}

fn t8() -> TestResult {
  var ok = true;
  let n1 = web3.account_address_normalize("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
  if !n1.is_ok {
    ok = false;
  } else if !str_is(n1.value, "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") {
    ok = false;
  }
  let n2 = web3.account_address_normalize("5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED");
  if !n2.is_ok {
    ok = false;
  } else if !str_is(n2.value, "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") {
    ok = false;
  }
  let n3 = web3.account_address_normalize("0X5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
  if !n3.is_ok {
    ok = false;
  } else if !str_is(n3.value, "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") {
    ok = false;
  }
  if !sprefix(web3.account_address_normalize("0x123"), "web3: address must be 40 hex digits") { ok = false; }
  if !sprefix(web3.account_address_normalize("0xgg908400098527886e0f7030069857d2e4169ee7"), "web3: address contains a non-hex character") { ok = false; }
  return assert(ok, "address normalization: case folding, prefixes, error catalog");
}

fn t9() -> TestResult {
  let r = web3.account_address_checksum("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed");
  var ok = r.is_ok;
  if ok {
    if !str_is(r.value, "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed") { ok = false; }
  }
  return assert(ok, "EIP-55 checksum vector 1");
}

fn t10() -> TestResult {
  let r = web3.account_address_checksum("0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359");
  var ok = r.is_ok;
  if ok {
    if !str_is(r.value, "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359") { ok = false; }
  }
  return assert(ok, "EIP-55 checksum vector 2");
}

fn t11() -> TestResult {
  let r = web3.account_address_checksum("0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb");
  var ok = r.is_ok;
  if ok {
    if !str_is(r.value, "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB") { ok = false; }
  }
  return assert(ok, "EIP-55 checksum vector 3");
}

fn t12() -> TestResult {
  let r = web3.account_address_checksum("0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb");
  var ok = r.is_ok;
  if ok {
    if !str_is(r.value, "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb") { ok = false; }
  }
  return assert(ok, "EIP-55 checksum vector 4");
}

fn t13() -> TestResult {
  var ok = true;
  let v1 = web3.account_checksum_valid("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
  if !v1.is_ok {
    ok = false;
  } else if !v1.value {
    ok = false;
  }
  let v2 = web3.account_checksum_valid("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed");
  if !v2.is_ok {
    ok = false;
  } else if v2.value {
    ok = false;
  }
  let v3 = web3.account_checksum_valid("0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED");
  if !v3.is_ok {
    ok = false;
  } else if v3.value {
    ok = false;
  }
  let v4 = web3.account_checksum_valid("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD");
  if !v4.is_ok {
    ok = false;
  } else if v4.value {
    ok = false;
  }
  if !boolprefix(web3.account_checksum_valid("0xzz"), "web3: address must be 40 hex digits") { ok = false; }
  return assert(ok, "EIP-55 verification policy: mixed case valid, single case not checksummed");
}

fn t14() -> TestResult {
  var ok = true;
  let addr = hb("52908400098527886e0f7030069857d2e4169ee7");
  let fr = web3.account_address_from_bytes(&addr);
  if !fr.is_ok {
    ok = false;
  } else if !str_is(fr.value, "0x52908400098527886e0f7030069857d2e4169ee7") {
    ok = false;
  }
  let br = web3.account_address_bytes("0x52908400098527886E0F7030069857D2E4169EE7");
  if !br.is_ok {
    ok = false;
  } else {
    let b: Vec[UInt8] = br.value;
    if b.len() != 20 { ok = false; }
    if bv(&b, 0) != 0x52 { ok = false; }
    if bv(&b, 19) != 0xE7 { ok = false; }
  }
  if !sprefix(web3.account_address_from_bytes(&zn(19)), "web3: address bytes must be 20 bytes") { ok = false; }
  return assert(ok, "address byte decode/encode round trip and length error");
}

fn t15() -> TestResult {
  var ok = true;
  let n1 = web3.ens_normalize("FOO.eth");
  if !n1.is_ok {
    ok = false;
  } else if !str_is(n1.value, "foo.eth") {
    ok = false;
  }
  let n2 = web3.ens_normalize("Sub.Example.eth");
  if !n2.is_ok {
    ok = false;
  } else if !str_is(n2.value, "sub.example.eth") {
    ok = false;
  }
  let n3 = web3.ens_normalize("a-b.c0.eth");
  if !n3.is_ok {
    ok = false;
  } else if !str_is(n3.value, "a-b.c0.eth") {
    ok = false;
  }
  let n4 = web3.ens_normalize("");
  if !n4.is_ok {
    ok = false;
  } else if !str_is(n4.value, "") {
    ok = false;
  }
  return assert(ok, "ENS normalization: lowercase fold, hyphens, root name");
}

fn t16() -> TestResult {
  var ok = true;
  if !sprefix(web3.ens_normalize("foo..eth"), "web3: ENS name has an empty label") { ok = false; }
  if !sprefix(web3.ens_normalize(".foo.eth"), "web3: ENS name has an empty label") { ok = false; }
  if !sprefix(web3.ens_normalize("foo.eth."), "web3: ENS name has an empty label") { ok = false; }
  if !sprefix(web3.ens_normalize("-foo.eth"), "web3: ENS label starts or ends with a hyphen") { ok = false; }
  if !sprefix(web3.ens_normalize("foo-.eth"), "web3: ENS label starts or ends with a hyphen") { ok = false; }
  if !sprefix(web3.ens_normalize("foo bar.eth"), "web3: ENS name contains a character outside the ASCII subset") { ok = false; }
  if !sprefix(web3.ens_normalize("xn--abc.eth"), "web3: ENS punycode labels") { ok = false; }
  if !sprefix(web3.ens_normalize("caf\u{00E9}.eth"), "web3: ENS name contains a character outside the ASCII subset") { ok = false; }
  let long = rep_str("a", 64) + ".eth";
  if !sprefix(web3.ens_normalize(long), "web3: ENS label exceeds 63 bytes") { ok = false; }
  return assert(ok, "ENS normalization rejects empty labels, hyphen edges, Unicode, punycode, long labels");
}

fn t17() -> TestResult {
  var ok = bexp(web3.ens_labelhash("eth"), "4f5b812789fc606be1b3b16908db13fc7a9adf7ca72641f84d75b47069d3d7f0");
  if !bexp(web3.ens_labelhash("ETH"), "4f5b812789fc606be1b3b16908db13fc7a9adf7ca72641f84d75b47069d3d7f0") { ok = false; }
  if !sprefix(web3.ens_labelhash("foo.eth"), "web3: ENS label must not contain a dot") { ok = false; }
  if !sprefix(web3.ens_labelhash(""), "web3: ENS label must not be empty") { ok = false; }
  return assert(ok, "ENS labelhash vector and single-label validation");
}

fn t18() -> TestResult {
  var ok = bexp(web3.ens_namehash("eth"), "93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae");
  if !bexp(web3.ens_namehash("ETH"), "93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae") { ok = false; }
  return assert(ok, "ENS namehash(\"eth\") matches EIP-137");
}

fn t19() -> TestResult {
  var ok = bexp(web3.ens_namehash("foo.eth"), "de9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f");
  if !bexp(web3.ens_namehash("FOO.eth"), "de9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f") { ok = false; }
  return assert(ok, "ENS namehash(\"foo.eth\") matches EIP-137 after normalization");
}

fn t20() -> TestResult {
  var ok = bexp(web3.ens_namehash(""), rep_str("0", 64));
  let hr = web3.ens_namehash_hex("foo.eth");
  if !hr.is_ok {
    ok = false;
  } else if !str_is(hr.value, "0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f") {
    ok = false;
  }
  let a = web3.ens_namehash("foo.eth");
  let b = web3.ens_namehash("eth");
  if a.is_ok && b.is_ok {
    let av: Vec[UInt8] = a.value;
    let bvv: Vec[UInt8] = b.value;
    if bytes_equal(&av, &bvv) { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "ENS root hash, hex rendering, and distinct names");
}

fn t21() -> TestResult {
  var ok = true;
  let sr = web3.contract_selector("transfer(address,uint256)");
  if !sr.is_ok {
    ok = false;
  } else {
    let sel: Vec[UInt8] = sr.value;
    if sel.len() != 4 { ok = false; }
    if bv(&sel, 0) != 0xA9 { ok = false; }
    if bv(&sel, 3) != 0xBB { ok = false; }
  }
  let hx = web3.contract_selector_hex("transfer(address,uint256)");
  if !hx.is_ok {
    ok = false;
  } else if !str_is(hx.value, "0xa9059cbb") {
    ok = false;
  }
  if !bprefix(web3.contract_selector(""), "web3: signature must be a non-empty function signature") { ok = false; }
  if !bprefix(web3.contract_selector("transfer"), "web3: signature has no argument list") { ok = false; }
  if !bprefix(web3.contract_selector("transfer("), "web3: signature has unbalanced parentheses") { ok = false; }
  if !bprefix(web3.contract_selector("transfer address)"), "web3: signature must be printable ASCII without spaces") { ok = false; }
  if !bprefix(web3.contract_selector("(address)"), "web3: signature must start with a function name") { ok = false; }
  if !bprefix(web3.contract_selector("transfer(address"), "web3: signature has unbalanced parentheses") { ok = false; }
  return assert(ok, "function selector vector and signature validation catalog");
}

fn t22() -> TestResult {
  var ok = true;
  let w5r = web3.abi_encode_uint(5);
  if !w5r.is_ok {
    ok = false;
  } else {
    let w: Vec[UInt8] = w5r.value;
    if w.len() != 32 { ok = false; }
    if bv(&w, 30) != 0 { ok = false; }
    if bv(&w, 31) != 5 { ok = false; }
    let dr = web3.abi_decode_uint_word(&w);
    if !dr.is_ok {
      ok = false;
    } else if dr.value != 5 {
      ok = false;
    }
  }
  let wmr = web3.abi_encode_uint(9223372036854775807);
  if !wmr.is_ok {
    ok = false;
  } else {
    let w: Vec[UInt8] = wmr.value;
    if bv(&w, 24) != 0x7F { ok = false; }
    if bv(&w, 31) != 0xFF { ok = false; }
    let dr = web3.abi_decode_uint_word(&w);
    if !dr.is_ok {
      ok = false;
    } else if dr.value != 9223372036854775807 {
      ok = false;
    }
  }
  let z5 = hb("0000000000000000000000000000000000000000000000000000000000000005");
  let dz = web3.abi_decode_uint_word(&z5);
  if !dz.is_ok {
    ok = false;
  } else if dz.value != 5 {
    ok = false;
  }
  let ff = hb("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
  if !iprefix(web3.abi_decode_uint_word(&ff), "web3: ABI uint word does not fit Int") { ok = false; }
  if !iprefix(web3.abi_decode_uint_word(&zn(31)), "web3: ABI word must be 32 bytes") { ok = false; }
  if !iprefix(web3.abi_encode_uint(-1), "web3: ABI uint value is negative") { ok = false; }
  return assert(ok, "ABI uint256 encode/decode round trips, range and word-size errors");
}

fn t23() -> TestResult {
  var ok = true;
  let neg = web3.abi_encode_int(0 - 100);
  if neg.len() != 32 { ok = false; }
  if bv(&neg, 0) != 0xFF { ok = false; }
  if bv(&neg, 23) != 0xFF { ok = false; }
  if bv(&neg, 24) != 0xFF { ok = false; }
  if bv(&neg, 30) != 0xFF { ok = false; }
  if bv(&neg, 31) != 0x9C { ok = false; }
  let m1 = web3.abi_encode_int(-1);
  if bv(&m1, 0) != 0xFF { ok = false; }
  if bv(&m1, 31) != 0xFF { ok = false; }
  let zero = web3.abi_encode_int(0);
  if bv(&zero, 0) != 0 { ok = false; }
  if bv(&zero, 31) != 0 { ok = false; }
  let bt = web3.abi_encode_bool(true);
  if bt.len() != 32 { ok = false; }
  if bv(&bt, 30) != 0 { ok = false; }
  if bv(&bt, 31) != 1 { ok = false; }
  let bf = web3.abi_encode_bool(false);
  if bv(&bf, 31) != 0 { ok = false; }
  return assert(ok, "ABI int256 two's complement and bool words");
}

fn t24() -> TestResult {
  var ok = true;
  let addr = hb("52908400098527886e0f7030069857d2e4169ee7");
  let wr = web3.abi_encode_address(&addr);
  if !wr.is_ok {
    ok = false;
  } else {
    var w: Vec[UInt8] = wr.value;
    if w.len() != 32 { ok = false; }
    if bv(&w, 11) != 0 { ok = false; }
    if bv(&w, 12) != 0x52 { ok = false; }
    if bv(&w, 31) != 0xE7 { ok = false; }
    let dr = web3.abi_decode_address_word(&w);
    if !dr.is_ok {
      ok = false;
    } else {
      let back: Vec[UInt8] = dr.value;
      if !bytes_equal(&back, &addr) { ok = false; }
    }
    w[11] = 1 as UInt8;
    if !bprefix(web3.abi_decode_address_word(&w), "web3: ABI address word is not right-aligned") { ok = false; }
  }
  if !bprefix(web3.abi_encode_address(&zn(19)), "web3: ABI address value must be 20 bytes") { ok = false; }
  return assert(ok, "ABI address word alignment, round trip and errors");
}

fn t25() -> TestResult {
  var ok = true;
  let addr = hb("52908400098527886e0f7030069857d2e4169ee7");
  let wu = web3.abi_encode_uint(5);
  let wa = web3.abi_encode_address(&addr);
  if !wu.is_ok || !wa.is_ok {
    ok = false;
  } else {
    let wuv: Vec[UInt8] = wu.value;
    let wav: Vec[UInt8] = wa.value;
    var words = Vec[Vec[UInt8]].new();
    words.push(wuv);
    words.push(wav);
    let sel = hb("a9059cbb");
    let cr = web3.abi_encode_call(&sel, &words);
    if !cr.is_ok {
      ok = false;
    } else {
      let call: Vec[UInt8] = cr.value;
      if call.len() != 68 { ok = false; }
      if bv(&call, 0) != 0xA9 { ok = false; }
      if bv(&call, 3) != 0xBB { ok = false; }
      if bv(&call, 35) != 5 { ok = false; }
      if bv(&call, 48) != 0x52 { ok = false; }
      if bv(&call, 67) != 0xE7 { ok = false; }
      let rd = web3.abi_read_word(&call, 4);
      if !rd.is_ok {
        ok = false;
      } else {
        let word0: Vec[UInt8] = rd.value;
        if bv(&word0, 31) != 5 { ok = false; }
      }
      if !bprefix(web3.abi_read_word(&call, 37), "web3: ABI word out of bounds") { ok = false; }
    }
    var words2 = Vec[Vec[UInt8]].new();
    words2.push(zn(31));
    if !bprefix(web3.abi_encode_words(&words2), "web3: ABI word must be 32 bytes") { ok = false; }
    var sel_bad = Vec[UInt8].new();
    sel_bad.push(0xA9 as UInt8);
    sel_bad.push(0x05 as UInt8);
    sel_bad.push(0x9C as UInt8);
    if !bprefix(web3.abi_encode_call(&sel_bad, &words), "web3: ABI selector must be 4 bytes") { ok = false; }
  }
  return assert(ok, "ABI call data layout, word reads and selector/size errors");
}

fn t26() -> TestResult {
  var ok = true;
  let pc = web3.provider_config(web3.PROVIDER_HTTP, "https://rpc.example.org", 1, 5000);
  if !pc.is_ok {
    ok = false;
  } else {
    let cfg: ProviderConfig = pc.value;
    if cfg.kind != web3.PROVIDER_HTTP { ok = false; }
    if cfg.chain_id != 1 { ok = false; }
    if cfg.timeout_ms != 5000 { ok = false; }
  }
  let pw = web3.provider_config(web3.PROVIDER_WS, "wss://rpc.example.org", 10, 1000);
  if !pw.is_ok { ok = false; }
  let pi = web3.provider_config(web3.PROVIDER_IPC, "/tmp/geth.ipc", 1, 1000);
  if !pi.is_ok { ok = false; }
  let e1 = web3.provider_config(3, "http://x", 0, 10);
  if e1.is_ok { ok = false; } else if !string.str_starts_with(e1.error, "web3: provider kind") { ok = false; }
  let e2 = web3.provider_config(web3.PROVIDER_HTTP, "ws://x", 0, 10);
  if e2.is_ok { ok = false; } else if !string.str_starts_with(e2.error, "web3: provider url scheme") { ok = false; }
  let e3 = web3.provider_config(web3.PROVIDER_WS, "ws://x", -1, 10);
  if e3.is_ok { ok = false; } else if !string.str_starts_with(e3.error, "web3: provider chain id") { ok = false; }
  let e4 = web3.provider_config(web3.PROVIDER_HTTP, "http://x", 0, 0);
  if e4.is_ok { ok = false; } else if !string.str_starts_with(e4.error, "web3: provider timeout") { ok = false; }
  let e5 = web3.provider_config(web3.PROVIDER_HTTP, "", 0, 10);
  if e5.is_ok { ok = false; } else if !string.str_starts_with(e5.error, "web3: provider url must not be empty") { ok = false; }
  let e6 = web3.provider_config(web3.PROVIDER_IPC, "http://x", 0, 10);
  if e6.is_ok { ok = false; } else if !string.str_starts_with(e6.error, "web3: provider url scheme") { ok = false; }
  let rq = web3.provider_request(7, "eth_chainId", "[]");
  if !rq.is_ok {
    ok = false;
  } else {
    let req: RpcRequest = rq.value;
    if req.id != 7 { ok = false; }
    if !str_is(web3.provider_encode_request(&req),
               "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"eth_chainId\",\"params\":[]}") {
      ok = false;
    }
  }
  let rq1 = web3.provider_request(-1, "eth_chainId", "[]");
  if rq1.is_ok { ok = false; } else if !string.str_starts_with(rq1.error, "web3: rpc request id is negative") { ok = false; }
  let rq2 = web3.provider_request(1, "", "[]");
  if rq2.is_ok { ok = false; } else if !string.str_starts_with(rq2.error, "web3: rpc method must not be empty") { ok = false; }
  let rq3 = web3.provider_request(1, "eth chainId", "[]");
  if rq3.is_ok { ok = false; } else if !string.str_starts_with(rq3.error, "web3: rpc method contains an invalid character") { ok = false; }
  let rq4 = web3.provider_request(1, "eth_chainId", "{}");
  if rq4.is_ok { ok = false; } else if !string.str_starts_with(rq4.error, "web3: rpc params must be a JSON array text") { ok = false; }
  return assert(ok, "provider configuration, request encoding and validation catalog");
}

fn t27() -> TestResult {
  var ok = true;
  let b1 = "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":\"0x1\"}";
  let d1 = web3.provider_decode_response(b1, 7);
  if !d1.is_ok {
    ok = false;
  } else {
    let resp: RpcResponse = d1.value;
    if !resp.ok { ok = false; }
    if resp.id != 7 { ok = false; }
    if !str_is(resp.result_json, "\"0x1\"") { ok = false; }
  }
  let b2 = "{\"jsonrpc\": \"2.0\", \"id\": 7, \"result\": 42}";
  let d2 = web3.provider_decode_response(b2, 7);
  if !d2.is_ok {
    ok = false;
  } else {
    let resp: RpcResponse = d2.value;
    if !resp.ok { ok = false; }
    if !str_is(resp.result_json, "42") { ok = false; }
  }
  let b3 = "{\"jsonrpc\":\"2.0\",\"id\":7,\"error\":{\"code\":-32601,\"message\":\"method not found\"}}";
  let d3 = web3.provider_decode_response(b3, 7);
  if !d3.is_ok {
    ok = false;
  } else {
    let resp: RpcResponse = d3.value;
    if resp.ok { ok = false; }
    if resp.error_code != -32601 { ok = false; }
    if !str_is(resp.error_message, "method not found") { ok = false; }
  }
  let d4 = web3.provider_decode_response(b1, 8);
  if d4.is_ok { ok = false; } else if !string.str_starts_with(d4.error, "web3: response id does not match the request id") { ok = false; }
  let d5 = web3.provider_decode_response("{\"jsonrpc\":\"2.0\",\"id\":7}", -1);
  if d5.is_ok { ok = false; } else if !string.str_starts_with(d5.error, "web3: response has neither result nor error member") { ok = false; }
  let d6 = web3.provider_decode_response("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"a\":1}}", -1);
  if d6.is_ok { ok = false; } else if !string.str_starts_with(d6.error, "web3: response result must be a scalar JSON value") { ok = false; }
  let d7 = web3.provider_decode_response("{\"id\":7,\"error\":{\"code\":1}}", -1);
  if d7.is_ok { ok = false; } else if !string.str_starts_with(d7.error, "web3: response error object needs code and message") { ok = false; }
  return assert(ok, "provider response scanner: success, error, id match, malformed envelopes");
}

fn t28() -> TestResult {
  var ok = true;
  let q1 = web3.provider_parse_quantity("0x2a");
  if !q1.is_ok {
    ok = false;
  } else if q1.value != 42 {
    ok = false;
  }
  let q0 = web3.provider_parse_quantity("0x0");
  if !q0.is_ok {
    ok = false;
  } else if q0.value != 0 {
    ok = false;
  }
  let qm = web3.provider_parse_quantity("0x7fffffffffffffff");
  if !qm.is_ok {
    ok = false;
  } else if qm.value != 9223372036854775807 {
    ok = false;
  }
  if !iprefix(web3.provider_parse_quantity("42"), "web3: quantity must start with 0x") { ok = false; }
  if !iprefix(web3.provider_parse_quantity("0x"), "web3: quantity has no hex digits") { ok = false; }
  if !iprefix(web3.provider_parse_quantity("0x01"), "web3: quantity is not canonical (leading zero)") { ok = false; }
  if !iprefix(web3.provider_parse_quantity("0xzz"), "web3: quantity has a non-hex character") { ok = false; }
  let f0 = web3.provider_format_quantity(0);
  if !f0.is_ok {
    ok = false;
  } else if !str_is(f0.value, "0x0") {
    ok = false;
  }
  let f42 = web3.provider_format_quantity(42);
  if !f42.is_ok {
    ok = false;
  } else if !str_is(f42.value, "0x2a") {
    ok = false;
  }
  let f255 = web3.provider_format_quantity(255);
  if !f255.is_ok {
    ok = false;
  } else if !str_is(f255.value, "0xff") {
    ok = false;
  }
  let fr = web3.provider_format_quantity(123456789);
  if !fr.is_ok {
    ok = false;
  } else {
    let pr = web3.provider_parse_quantity(fr.value);
    if !pr.is_ok {
      ok = false;
    } else if pr.value != 123456789 {
      ok = false;
    }
  }
  if !sprefix(web3.provider_format_quantity(-1), "web3: quantity must be non-negative") { ok = false; }
  return assert(ok, "quantity parsing/formatting round trip and canonical errors");
}

fn main() -> Int {
  io.println("=== xiom.web3 conformance tests ===");
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
    io.println("xiom.web3: all tests passed");
  } else {
    io.println("xiom.web3: tests failed");
  }
  return failed;
}
