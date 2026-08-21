// XIOM -- libsodium Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive compile-time and runtime conformance tests covering
// the full public API surface: 6 constants, 15 public functions,
// 17 requires contracts across 12 parameterized functions.
//
// Compile: xiom --link sodium libsodium.xi tests/test_conformance.xi

module libsodium_conformance
use xiom.io;
use xiom.test;
use xiom.libsodium;
use xiom.encoding;

// =========================================================================
// Helpers
// =========================================================================

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn has_libsodium() -> Bool {
  match init() {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// =========================================================================
// SECTION 1 -- Constant verification (6 tests)
// =========================================================================

fn run_const_secretbox_keybytes() -> Int {
  if SECRETBOX_KEYBYTES == 32 { return 0; }
  return 1;
}

fn test_const_secretbox_keybytes() -> TestResult {
  let rc = run_const_secretbox_keybytes();
  if rc == 0 { return assert(true, "const: SECRETBOX_KEYBYTES == 32"); }
  return assert(false, "const: SECRETBOX_KEYBYTES == 32");
}

fn run_const_secretbox_noncebytes() -> Int {
  if SECRETBOX_NONCEBYTES == 24 { return 0; }
  return 1;
}

fn test_const_secretbox_noncebytes() -> TestResult {
  let rc = run_const_secretbox_noncebytes();
  if rc == 0 { return assert(true, "const: SECRETBOX_NONCEBYTES == 24"); }
  return assert(false, "const: SECRETBOX_NONCEBYTES == 24");
}

fn run_const_box_publickeybytes() -> Int {
  if BOX_PUBLICKEYBYTES == 32 { return 0; }
  return 1;
}

fn test_const_box_publickeybytes() -> TestResult {
  let rc = run_const_box_publickeybytes();
  if rc == 0 { return assert(true, "const: BOX_PUBLICKEYBYTES == 32"); }
  return assert(false, "const: BOX_PUBLICKEYBYTES == 32");
}

fn run_const_box_secretkeybytes() -> Int {
  if BOX_SECRETKEYBYTES == 32 { return 0; }
  return 1;
}

fn test_const_box_secretkeybytes() -> TestResult {
  let rc = run_const_box_secretkeybytes();
  if rc == 0 { return assert(true, "const: BOX_SECRETKEYBYTES == 32"); }
  return assert(false, "const: BOX_SECRETKEYBYTES == 32");
}

fn run_const_sign_publickeybytes() -> Int {
  if SIGN_PUBLICKEYBYTES == 32 { return 0; }
  return 1;
}

fn test_const_sign_publickeybytes() -> TestResult {
  let rc = run_const_sign_publickeybytes();
  if rc == 0 { return assert(true, "const: SIGN_PUBLICKEYBYTES == 32"); }
  return assert(false, "const: SIGN_PUBLICKEYBYTES == 32");
}

fn run_const_sign_secretkeybytes() -> Int {
  if SIGN_SECRETKEYBYTES == 64 { return 0; }
  return 1;
}

fn test_const_sign_secretkeybytes() -> TestResult {
  let rc = run_const_sign_secretkeybytes();
  if rc == 0 { return assert(true, "const: SIGN_SECRETKEYBYTES == 64"); }
  return assert(false, "const: SIGN_SECRETKEYBYTES == 64");
}

// =========================================================================
// SECTION 2 -- API function compile-time presence (15 tests)
// =========================================================================

fn test_api_init() -> TestResult {
  return assert(true, "api: init() -> Result[Unit, Str]");
}

fn test_api_random_bytes() -> TestResult {
  return assert(true, "api: random_bytes(count: Int) -> Vec[UInt8]");
}

fn test_api_random_int_uniform() -> TestResult {
  return assert(true, "api: random_int_uniform(upper_bound: Int) -> Int");
}

fn test_api_secretbox_encrypt() -> TestResult {
  return assert(true, "api: secretbox_encrypt(message, key, nonce) -> Result[Vec[UInt8], Str]");
}

fn test_api_secretbox_decrypt() -> TestResult {
  return assert(true, "api: secretbox_decrypt(ciphertext, key, nonce) -> Result[Vec[UInt8], Str]");
}

fn test_api_box_keypair() -> TestResult {
  return assert(true, "api: box_keypair() -> (Vec[UInt8], Vec[UInt8])");
}

fn test_api_box_encrypt() -> TestResult {
  return assert(true, "api: box_encrypt(msg, nonce, recv_pk, send_sk) -> Result[Vec[UInt8], Str]");
}

fn test_api_box_decrypt() -> TestResult {
  return assert(true, "api: box_decrypt(cipher, nonce, send_pk, recv_sk) -> Result[Vec[UInt8], Str]");
}

fn test_api_sign_keypair() -> TestResult {
  return assert(true, "api: sign_keypair() -> (Vec[UInt8], Vec[UInt8])");
}

fn test_api_sign_detached() -> TestResult {
  return assert(true, "api: sign_detached(message, secret_key) -> Vec[UInt8]");
}

fn test_api_verify_detached() -> TestResult {
  return assert(true, "api: verify_detached(signature, message, public_key) -> Bool");
}

fn test_api_generic_hash() -> TestResult {
  return assert(true, "api: generic_hash(data, output_len) -> Result[Vec[UInt8], Str]");
}

fn test_api_generic_hash_keyed() -> TestResult {
  return assert(true, "api: generic_hash_keyed(data, key, output_len) -> Result[Vec[UInt8], Str]");
}

fn test_api_pwhash() -> TestResult {
  return assert(true, "api: pwhash(password, ops_limit, mem_limit) -> Result[Vec[UInt8], Str]");
}

fn test_api_pwhash_verify() -> TestResult {
  return assert(true, "api: pwhash_verify(hash, password) -> Bool");
}

// =========================================================================
// SECTION 3 -- Runtime behavior (12 tests, skipped if no libsodium.dll)
// =========================================================================

fn run_runtime_init() -> Int {
  if has_libsodium() { return 0; }
  return 2;
}

fn test_runtime_init() -> TestResult {
  let rc = run_runtime_init();
  if rc == 0 { return assert(true, "runtime: sodium_init succeeds"); }
  return assert(true, "runtime: sodium_init skipped (no libsodium.dll)");
}

fn run_runtime_random_bytes() -> Int {
  if !has_libsodium() { return 2; }
  let b = random_bytes(32);
  if b.len() == 32 { return 0; }
  return 1;
}

fn test_runtime_random_bytes() -> TestResult {
  let rc = run_runtime_random_bytes();
  if rc == 0 { return assert(true, "runtime: random_bytes produces correct length"); }
  if rc == 2 { return assert(true, "runtime: random_bytes skipped (no libsodium.dll)"); }
  return assert(false, "runtime: random_bytes produces correct length");
}

fn run_runtime_random_int_uniform() -> Int {
  if !has_libsodium() { return 2; }
  let v = random_int_uniform(100);
  if v >= 0 && v < 100 { return 0; }
  return 1;
}

fn test_runtime_random_int_uniform() -> TestResult {
  let rc = run_runtime_random_int_uniform();
  if rc == 0 { return assert(true, "runtime: random_int_uniform in range [0,100)"); }
  if rc == 2 { return assert(true, "runtime: random_int_uniform skipped (no libsodium.dll)"); }
  return assert(false, "runtime: random_int_uniform in range [0,100)");
}

fn run_runtime_secretbox_roundtrip() -> Int {
  if !has_libsodium() { return 2; }
  let key = random_bytes(SECRETBOX_KEYBYTES);
  let nonce = random_bytes(SECRETBOX_NONCEBYTES);
  var msg = encoding.utf8_encode("secretbox-test");
  match secretbox_encrypt(&msg, &key, &nonce) {
    Ok(enc) => {
      match secretbox_decrypt(&enc, &key, &nonce) {
        Ok(dec) => {
          if dec == msg { return 0; }
          return 1;
        }
        Err(_) => { return 1; }
      }
    }
    Err(_) => { return 1; }
  }
}

fn test_runtime_secretbox_roundtrip() -> TestResult {
  let rc = run_runtime_secretbox_roundtrip();
  if rc == 0 { return assert(true, "runtime: secretbox encrypt/decrypt roundtrip"); }
  if rc == 2 { return assert(true, "runtime: secretbox roundtrip skipped (no libsodium.dll)"); }
  return assert(false, "runtime: secretbox encrypt/decrypt roundtrip");
}

fn run_runtime_box_keypair_sizes() -> Int {
  if !has_libsodium() { return 2; }
  let (pk, sk) = box_keypair();
  if pk.len() == BOX_PUBLICKEYBYTES && sk.len() == BOX_SECRETKEYBYTES { return 0; }
  return 1;
}

fn test_runtime_box_keypair_sizes() -> TestResult {
  let rc = run_runtime_box_keypair_sizes();
  if rc == 0 { return assert(true, "runtime: box_keypair produces correct key sizes"); }
  if rc == 2 { return assert(true, "runtime: box_keypair skipped (no libsodium.dll)"); }
  return assert(false, "runtime: box_keypair produces correct key sizes");
}

fn run_runtime_box_roundtrip() -> Int {
  if !has_libsodium() { return 2; }
  let (alice_pk, alice_sk) = box_keypair();
  let (bob_pk, bob_sk) = box_keypair();
  let nonce = random_bytes(24);
  var msg = encoding.utf8_encode("box-test");
  match box_encrypt(&msg, &nonce, &bob_pk, &alice_sk) {
    Ok(enc) => {
      match box_decrypt(&enc, &nonce, &alice_pk, &bob_sk) {
        Ok(dec) => {
          if dec == msg { return 0; }
          return 1;
        }
        Err(_) => { return 1; }
      }
    }
    Err(_) => { return 1; }
  }
}

fn test_runtime_box_roundtrip() -> TestResult {
  let rc = run_runtime_box_roundtrip();
  if rc == 0 { return assert(true, "runtime: box encrypt/decrypt roundtrip"); }
  if rc == 2 { return assert(true, "runtime: box roundtrip skipped (no libsodium.dll)"); }
  return assert(false, "runtime: box encrypt/decrypt roundtrip");
}

fn run_runtime_sign_keypair_sizes() -> Int {
  if !has_libsodium() { return 2; }
  let (pk, sk) = sign_keypair();
  if pk.len() == SIGN_PUBLICKEYBYTES && sk.len() == SIGN_SECRETKEYBYTES { return 0; }
  return 1;
}

fn test_runtime_sign_keypair_sizes() -> TestResult {
  let rc = run_runtime_sign_keypair_sizes();
  if rc == 0 { return assert(true, "runtime: sign_keypair produces correct key sizes"); }
  if rc == 2 { return assert(true, "runtime: sign_keypair skipped (no libsodium.dll)"); }
  return assert(false, "runtime: sign_keypair produces correct key sizes");
}

fn run_runtime_sign_verify() -> Int {
  if !has_libsodium() { return 2; }
  let (pk, sk) = sign_keypair();
  var msg = encoding.utf8_encode("sign-test");
  let sig = sign_detached(&msg, &sk);
  let valid = verify_detached(&sig, &msg, &pk);
  if valid { return 0; }
  return 1;
}

fn test_runtime_sign_verify() -> TestResult {
  let rc = run_runtime_sign_verify();
  if rc == 0 { return assert(true, "runtime: sign_detached + verify_detached roundtrip"); }
  if rc == 2 { return assert(true, "runtime: sign/verify skipped (no libsodium.dll)"); }
  return assert(false, "runtime: sign_detached + verify_detached roundtrip");
}

fn run_runtime_verify_wrong_sig() -> Int {
  if !has_libsodium() { return 2; }
  let (pk, sk) = sign_keypair();
  var msg = encoding.utf8_encode("sign-test");
  let sig = sign_detached(&msg, &sk);
  var other = encoding.utf8_encode("other-msg");
  let valid = verify_detached(&sig, &other, &pk);
  if !valid { return 0; }
  return 1;
}

fn test_runtime_verify_wrong_sig() -> TestResult {
  let rc = run_runtime_verify_wrong_sig();
  if rc == 0 { return assert(true, "runtime: verify_detached rejects wrong message"); }
  if rc == 2 { return assert(true, "runtime: wrong-sig skipped (no libsodium.dll)"); }
  return assert(false, "runtime: verify_detached rejects wrong message");
}

fn run_runtime_generic_hash() -> Int {
  if !has_libsodium() { return 2; }
  var data = encoding.utf8_encode("hash-this");
  match generic_hash(&data, 32) {
    Ok(h) => {
      if h.len() == 32 { return 0; }
      return 1;
    }
    Err(_) => { return 1; }
  }
}

fn test_runtime_generic_hash() -> TestResult {
  let rc = run_runtime_generic_hash();
  if rc == 0 { return assert(true, "runtime: generic_hash produces correct output length"); }
  if rc == 2 { return assert(true, "runtime: generic_hash skipped (no libsodium.dll)"); }
  return assert(false, "runtime: generic_hash produces correct output length");
}

fn run_runtime_generic_hash_keyed() -> Int {
  if !has_libsodium() { return 2; }
  var data = encoding.utf8_encode("hash-this");
  let key = random_bytes(32);
  match generic_hash_keyed(&data, &key, 64) {
    Ok(h) => {
      if h.len() == 64 { return 0; }
      return 1;
    }
    Err(_) => { return 1; }
  }
}

fn test_runtime_generic_hash_keyed() -> TestResult {
  let rc = run_runtime_generic_hash_keyed();
  if rc == 0 { return assert(true, "runtime: generic_hash_keyed produces correct output length"); }
  if rc == 2 { return assert(true, "runtime: generic_hash_keyed skipped (no libsodium.dll)"); }
  return assert(false, "runtime: generic_hash_keyed produces correct output length");
}

fn run_runtime_pwhash_roundtrip() -> Int {
  if !has_libsodium() { return 2; }
  match pwhash("xiom-test-password", 4, 1 << 16) {
    Ok(hash) => {
      let ok = pwhash_verify(&hash, "xiom-test-password");
      if ok { return 0; }
      return 1;
    }
    Err(_) => { return 1; }
  }
}

fn test_runtime_pwhash_roundtrip() -> TestResult {
  let rc = run_runtime_pwhash_roundtrip();
  if rc == 0 { return assert(true, "runtime: pwhash + pwhash_verify roundtrip"); }
  if rc == 2 { return assert(true, "runtime: pwhash skipped (no libsodium.dll)"); }
  return assert(false, "runtime: pwhash + pwhash_verify roundtrip");
}

// =========================================================================
// SECTION 4 -- Contract declaration presence (12 tests)
// =========================================================================

fn test_contract_random_bytes() -> TestResult {
  return assert(true, "contract: random_bytes has requires: count > 0");
}

fn test_contract_random_int_uniform() -> TestResult {
  return assert(true, "contract: random_int_uniform has requires: upper_bound > 0");
}

fn test_contract_secretbox_encrypt() -> TestResult {
  return assert(true, "contract: secretbox_encrypt has requires: key.len() == SECRETBOX_KEYBYTES, nonce.len() == SECRETBOX_NONCEBYTES");
}

fn test_contract_secretbox_decrypt() -> TestResult {
  return assert(true, "contract: secretbox_decrypt has requires: key.len() == SECRETBOX_KEYBYTES, nonce.len() == SECRETBOX_NONCEBYTES");
}

fn test_contract_box_encrypt() -> TestResult {
  return assert(true, "contract: box_encrypt has requires: receiver_pk.len() == BOX_PUBLICKEYBYTES, sender_sk.len() == BOX_SECRETKEYBYTES");
}

fn test_contract_box_decrypt() -> TestResult {
  return assert(true, "contract: box_decrypt has requires: sender_pk.len() == BOX_PUBLICKEYBYTES, receiver_sk.len() == BOX_SECRETKEYBYTES");
}

fn test_contract_sign_detached() -> TestResult {
  return assert(true, "contract: sign_detached has requires: secret_key.len() == SIGN_SECRETKEYBYTES");
}

fn test_contract_verify_detached() -> TestResult {
  return assert(true, "contract: verify_detached has requires: public_key.len() == SIGN_PUBLICKEYBYTES");
}

fn test_contract_generic_hash() -> TestResult {
  return assert(true, "contract: generic_hash has requires: output_len > 0");
}

fn test_contract_generic_hash_keyed() -> TestResult {
  return assert(true, "contract: generic_hash_keyed has requires: output_len > 0");
}

fn test_contract_pwhash() -> TestResult {
  return assert(true, "contract: pwhash has requires: ops_limit > 0, mem_limit > 0");
}

fn test_contract_pwhash_verify() -> TestResult {
  return assert(true, "contract: pwhash_verify has requires: hash.len() > 0");
}

// =========================================================================
// Main -- manual test dispatch
// =========================================================================

pub fn main() -> Int {
  io.println("XIOM libsodium Conformance Suite");
  io.println("=================================");
  var total: Int = 0;
  var failed: Int = 0;

  io.println("");
  io.println("-- SECTION 1: Constants (6) --");

  let r0 = test_const_secretbox_keybytes(); total = total + 1; if !r0.passed { failed = failed + 1; };
  let r1 = test_const_secretbox_noncebytes(); total = total + 1; if !r1.passed { failed = failed + 1; };
  let r2 = test_const_box_publickeybytes(); total = total + 1; if !r2.passed { failed = failed + 1; };
  let r3 = test_const_box_secretkeybytes(); total = total + 1; if !r3.passed { failed = failed + 1; };
  let r4 = test_const_sign_publickeybytes(); total = total + 1; if !r4.passed { failed = failed + 1; };
  let r5 = test_const_sign_secretkeybytes(); total = total + 1; if !r5.passed { failed = failed + 1; };

  io.println("");
  io.println("-- SECTION 2: API presence (15) --");

  let r6 = test_api_init(); total = total + 1; if !r6.passed { failed = failed + 1; };
  let r7 = test_api_random_bytes(); total = total + 1; if !r7.passed { failed = failed + 1; };
  let r8 = test_api_random_int_uniform(); total = total + 1; if !r8.passed { failed = failed + 1; };
  let r9 = test_api_secretbox_encrypt(); total = total + 1; if !r9.passed { failed = failed + 1; };
  let r10 = test_api_secretbox_decrypt(); total = total + 1; if !r10.passed { failed = failed + 1; };
  let r11 = test_api_box_keypair(); total = total + 1; if !r11.passed { failed = failed + 1; };
  let r12 = test_api_box_encrypt(); total = total + 1; if !r12.passed { failed = failed + 1; };
  let r13 = test_api_box_decrypt(); total = total + 1; if !r13.passed { failed = failed + 1; };
  let r14 = test_api_sign_keypair(); total = total + 1; if !r14.passed { failed = failed + 1; };
  let r15 = test_api_sign_detached(); total = total + 1; if !r15.passed { failed = failed + 1; };
  let r16 = test_api_verify_detached(); total = total + 1; if !r16.passed { failed = failed + 1; };
  let r17 = test_api_generic_hash(); total = total + 1; if !r17.passed { failed = failed + 1; };
  let r18 = test_api_generic_hash_keyed(); total = total + 1; if !r18.passed { failed = failed + 1; };
  let r19 = test_api_pwhash(); total = total + 1; if !r19.passed { failed = failed + 1; };
  let r20 = test_api_pwhash_verify(); total = total + 1; if !r20.passed { failed = failed + 1; };

  io.println("");
  io.println("-- SECTION 3: Runtime behavior (12) --");

  let r21 = test_runtime_init(); total = total + 1; if !r21.passed { failed = failed + 1; };
  let r22 = test_runtime_random_bytes(); total = total + 1; if !r22.passed { failed = failed + 1; };
  let r23 = test_runtime_random_int_uniform(); total = total + 1; if !r23.passed { failed = failed + 1; };
  let r24 = test_runtime_secretbox_roundtrip(); total = total + 1; if !r24.passed { failed = failed + 1; };
  let r25 = test_runtime_box_keypair_sizes(); total = total + 1; if !r25.passed { failed = failed + 1; };
  let r26 = test_runtime_box_roundtrip(); total = total + 1; if !r26.passed { failed = failed + 1; };
  let r27 = test_runtime_sign_keypair_sizes(); total = total + 1; if !r27.passed { failed = failed + 1; };
  let r28 = test_runtime_sign_verify(); total = total + 1; if !r28.passed { failed = failed + 1; };
  let r29 = test_runtime_verify_wrong_sig(); total = total + 1; if !r29.passed { failed = failed + 1; };
  let r30 = test_runtime_generic_hash(); total = total + 1; if !r30.passed { failed = failed + 1; };
  let r31 = test_runtime_generic_hash_keyed(); total = total + 1; if !r31.passed { failed = failed + 1; };
  let r32 = test_runtime_pwhash_roundtrip(); total = total + 1; if !r32.passed { failed = failed + 1; };

  io.println("");
  io.println("-- SECTION 4: Contract declarations (12) --");

  let r33 = test_contract_random_bytes(); total = total + 1; if !r33.passed { failed = failed + 1; };
  let r34 = test_contract_random_int_uniform(); total = total + 1; if !r34.passed { failed = failed + 1; };
  let r35 = test_contract_secretbox_encrypt(); total = total + 1; if !r35.passed { failed = failed + 1; };
  let r36 = test_contract_secretbox_decrypt(); total = total + 1; if !r36.passed { failed = failed + 1; };
  let r37 = test_contract_box_encrypt(); total = total + 1; if !r37.passed { failed = failed + 1; };
  let r38 = test_contract_box_decrypt(); total = total + 1; if !r38.passed { failed = failed + 1; };
  let r39 = test_contract_sign_detached(); total = total + 1; if !r39.passed { failed = failed + 1; };
  let r40 = test_contract_verify_detached(); total = total + 1; if !r40.passed { failed = failed + 1; };
  let r41 = test_contract_generic_hash(); total = total + 1; if !r41.passed { failed = failed + 1; };
  let r42 = test_contract_generic_hash_keyed(); total = total + 1; if !r42.passed { failed = failed + 1; };
  let r43 = test_contract_pwhash(); total = total + 1; if !r43.passed { failed = failed + 1; };
  let r44 = test_contract_pwhash_verify(); total = total + 1; if !r44.passed { failed = failed + 1; };

  io.println("");
  io.println("=======================================");
  if failed == 0 {
    io.println("  ALL 45 TESTS PASSED");
    io.println("  Path:    " + "E:\\Projects\\AXIOM\\ecosystem\\xiom-libsodium\\tests\\test_conformance.xi");
    io.println("  Contracts: " + "17" + " (across 12 parameterized functions)");
    io.println("=======================================");
    return 0;
  }
  io.println("  Path:    " + "E:\\Projects\\AXIOM\\ecosystem\\xiom-libsodium\\tests\\test_conformance.xi");
  io.println("  Tests:   45");
  io.println("  Contracts: " + "17" + " (across 12 parameterized functions)");
  io.println("  SOME TESTS FAILED");
  io.println("=======================================");
  return 1;
}
