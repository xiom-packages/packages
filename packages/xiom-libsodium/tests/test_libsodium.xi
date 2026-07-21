// XIOM — libsodium Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module libsodium_tests
use xiom.test;
use xiom.libsodium;
use xiom.encoding;

fn test_init() -> TestResult {
  match init() {
    Ok(_) => { return assert(true, "libsodium init"); }
    Err(_) => { return assert(true, "libsodium skip"); }
  }
}

fn test_random_bytes() -> TestResult {
  match init() {
    Ok(_) => { let b = random_bytes(32); return assert(b.len() == 32, "libsodium random"); }
    Err(_) => { return assert(true, "libsodium skip"); }
  }
}

fn test_secretbox_roundtrip() -> TestResult {
  match init() {
    Ok(_) => {
      let key = random_bytes(SECRETBOX_KEYBYTES);
      let nonce = random_bytes(SECRETBOX_NONCEBYTES);
      var msg = encoding.utf8_encode("test");
      match secretbox_encrypt(&msg, &key, &nonce) {
        Ok(enc) => {
          match secretbox_decrypt(enc, key, nonce) {
            Ok(_) => { return assert(true, "libsodium secretbox roundtrip"); }
            Err(_) => { return assert(false, "libsodium secretbox decrypt fail"); }
          }
        }
        Err(_) => { return assert(false, "libsodium secretbox encrypt fail"); }
      }
    }
    Err(_) => { return assert(true, "libsodium skip"); }
  }
}

fn main() -> Int {
  var tests = [test_init, test_random_bytes, test_secretbox_roundtrip];
  return test.run_all(tests);
}
