module xiom.crypto.tests

use xiom.crypto.sha;
use xiom.crypto.md5;
use xiom.crypto.hash;
use xiom.crypto.hex;
use xiom.crypto.b64;
use xiom.crypto.aes;
use xiom.crypto.pbkdf;
use xiom.crypto.ed25519;
use xiom.crypto.random;
use xiom.crypto;

type TestResult = { name: Str; passed: Bool; }
type Counter = { passed: Int; failed: Int; }

fn assert_eq_int(name: Str, actual: Int, expected: Int) -> TestResult {
  return TestResult{ name: name; passed: actual == expected; };
}

fn assert_eq_str(name: Str, actual: Str, expected: Str) -> TestResult {
  return TestResult{ name: name; passed: actual == expected; };
}

fn assert_eq_vec(name: Str, actual: &Vec[Int], expected: &Vec[Int]) -> TestResult {
  if actual.len() != expected.len() {
    return TestResult{ name: name; passed: false; };
  };
  var i = 0;
  while i < actual.len() {
    if actual[i] != expected[i] {
      return TestResult{ name: name; passed: false; };
    };
    i = i + 1;
  };
  return TestResult{ name: name; passed: true; };
}

fn assert_true(name: Str, condition: Bool) -> TestResult {
  return TestResult{ name: name; passed: condition; };
}

fn ascii(s: Str) -> Vec[Int] {
  var i = 0;
  var result = Vec[Int].new();
  while i < s.len() {
    var c = xiom.encoding.str_char_code(s, i);
    result.push(c);
    i = i + 1;
  };
  return result;
}

fn test_sha256_hello_world() -> TestResult {
  var data = ascii("Hello World");
  var hash = sha256(&data);
  var expected = Vec[Int].new();
  expected.push(0xa5); expected.push(0x91); expected.push(0xa6); expected.push(0xd4);
  expected.push(0x0b); expected.push(0xf4); expected.push(0x20); expected.push(0x40);
  expected.push(0x4a); expected.push(0x01); expected.push(0x17); expected.push(0x33);
  expected.push(0xcf); expected.push(0xb7); expected.push(0xb1); expected.push(0x90);
  expected.push(0xd6); expected.push(0x2c); expected.push(0x65); expected.push(0xbf);
  expected.push(0x0b); expected.push(0xcd); expected.push(0xa3); expected.push(0x2b);
  expected.push(0x57); expected.push(0xb2); expected.push(0x77); expected.push(0xd9);
  expected.push(0xad); expected.push(0x9f); expected.push(0x14); expected.push(0x6e);
  return assert_eq_vec("sha256_hello_world", &hash, &expected);
}

fn test_sha256_hello() -> TestResult {
  var data = ascii("Hello");
  var hash = sha256(&data);
  var expected = Vec[Int].new();
  expected.push(0x18); expected.push(0x5f); expected.push(0x8d); expected.push(0xb3);
  expected.push(0x22); expected.push(0x71); expected.push(0xfe); expected.push(0x25);
  expected.push(0xf5); expected.push(0x61); expected.push(0xa6); expected.push(0xfc);
  expected.push(0x93); expected.push(0x8b); expected.push(0x2e); expected.push(0x26);
  expected.push(0x43); expected.push(0x06); expected.push(0xec); expected.push(0x30);
  expected.push(0x4e); expected.push(0xda); expected.push(0x51); expected.push(0x80);
  expected.push(0x07); expected.push(0xd1); expected.push(0x76); expected.push(0x48);
  expected.push(0x26); expected.push(0x38); expected.push(0x19); expected.push(0x69);
  return assert_eq_vec("sha256_hello", &hash, &expected);
}

fn test_sha256_output_size() -> TestResult {
  var data = ascii("A");
  var hash = sha256(&data);
  return assert_eq_int("sha256_output_size", hash.len(), 32);
}

fn test_sha256_hex_hello_world() -> TestResult {
  var data = ascii("Hello World");
  var hex = sha256_hex(&data);
  return assert_eq_str("sha256_hex_hello_world", hex, "a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e");
}

fn test_sha256_hex_output_size() -> TestResult {
  var data = ascii("test");
  var hex = sha256_hex(&data);
  return assert_eq_int("sha256_hex_output_size", hex.len(), 64);
}

fn test_sha512_hello() -> TestResult {
  var data = ascii("Hello");
  var hash = sha512(&data);
  var expected = Vec[Int].new();
  expected.push(0x36); expected.push(0x15); expected.push(0xf8); expected.push(0x0c);
  expected.push(0x9d); expected.push(0x29); expected.push(0x3e); expected.push(0xd7);
  expected.push(0x40); expected.push(0x26); expected.push(0x87); expected.push(0xf9);
  expected.push(0x4b); expected.push(0x22); expected.push(0xd5); expected.push(0x8a);
  expected.push(0xfb); expected.push(0x15); expected.push(0x5b); expected.push(0x56);
  expected.push(0xb7); expected.push(0xe6); expected.push(0xcc); expected.push(0xa8);
  expected.push(0xf9); expected.push(0x2e); expected.push(0x65); expected.push(0xb1);
  expected.push(0x24); expected.push(0xe2); expected.push(0x2c); expected.push(0x74);
  expected.push(0xf4); expected.push(0xa7); expected.push(0xcd); expected.push(0xe6);
  expected.push(0x2f); expected.push(0xff); expected.push(0xe9); expected.push(0xc6);
  expected.push(0xe9); expected.push(0xcf); expected.push(0x56); expected.push(0x83);
  expected.push(0x72); expected.push(0x87); expected.push(0xe7); expected.push(0x81);
  expected.push(0x78); expected.push(0x9b); expected.push(0x27); expected.push(0x07);
  expected.push(0x9e); expected.push(0x34); expected.push(0xca); expected.push(0xc8);
  expected.push(0xbb); expected.push(0x08); expected.push(0xd9); expected.push(0x0a);
  expected.push(0x5e); expected.push(0x5e); expected.push(0x7c); expected.push(0xfa);
  return assert_eq_vec("sha512_hello", &hash, &expected);
}

fn test_sha512_output_size() -> TestResult {
  var data = ascii("A");
  var hash = sha512(&data);
  return assert_eq_int("sha512_output_size", hash.len(), 64);
}

fn test_sha512_hex_hello() -> TestResult {
  var data = ascii("Hello");
  var hex = sha512_hex(&data);
  return assert_eq_str("sha512_hex_hello", hex, "3615f80c9d293ed7402687f94b22d58afb155b56b7e6cca8f92e65b124e22c74f4a7cde62fffe9c6e9cf56837287e781789b27079e34cac8bb08d90a5e5e7cfa");
}

fn test_sha512_hex_output_size() -> TestResult {
  var data = ascii("test");
  var hex = sha512_hex(&data);
  return assert_eq_int("sha512_hex_output_size", hex.len(), 128);
}

fn test_md5_hello() -> TestResult {
  var data = ascii("Hello");
  var hash = md5(&data);
  var expected = Vec[Int].new();
  expected.push(0x8b); expected.push(0x1a); expected.push(0x99); expected.push(0x53);
  expected.push(0xc4); expected.push(0x61); expected.push(0x12); expected.push(0x96);
  expected.push(0xa8); expected.push(0x27); expected.push(0xab); expected.push(0xf8);
  expected.push(0xc4); expected.push(0x78); expected.push(0x04); expected.push(0xd7);
  return assert_eq_vec("md5_hello", &hash, &expected);
}

fn test_md5_output_size() -> TestResult {
  var data = ascii("A");
  var hash = md5(&data);
  return assert_eq_int("md5_output_size", hash.len(), 16);
}

fn test_md5_hex_hello() -> TestResult {
  var data = ascii("Hello");
  var hex = md5_hex(&data);
  return assert_eq_str("md5_hex_hello", hex, "8b1a9953c4611296a827abf8c47804d7");
}

fn test_md5_hex_output_size() -> TestResult {
  var data = ascii("test");
  var hex = md5_hex(&data);
  return assert_eq_int("md5_hex_output_size", hex.len(), 32);
}

fn test_hmac_sha256_known() -> TestResult {
  var data = ascii("Hello World");
  var key = ascii("secret");
  var mac = sha256_hmac(&data, &key);
  return assert_eq_int("hmac_sha256_output_size", mac.len(), 32);
}

fn test_sha256_deterministic() -> TestResult {
  var data = ascii("Hello World");
  var h1 = sha256(&data);
  var h2 = sha256(&data);
  return assert_eq_vec("sha256_deterministic", &h1, &h2);
}

fn test_sha512_deterministic() -> TestResult {
  var data = ascii("Hello World");
  var h1 = sha512(&data);
  var h2 = sha512(&data);
  return assert_eq_vec("sha512_deterministic", &h1, &h2);
}

fn test_md5_deterministic() -> TestResult {
  var data = ascii("Hello World");
  var h1 = md5(&data);
  var h2 = md5(&data);
  return assert_eq_vec("md5_deterministic", &h1, &h2);
}

fn test_hex_encode() -> TestResult {
  var data = Vec[Int].new();
  data.push(0xde); data.push(0xad); data.push(0xbe); data.push(0xef);
  var hex = hex_encode(&data);
  return assert_eq_str("hex_encode_deadbeef", hex, "deadbeef");
}

fn test_hex_encode_upper() -> TestResult {
  var data = Vec[Int].new();
  data.push(0xca); data.push(0xfe);
  var hex = hex_encode_upper(&data);
  return assert_eq_str("hex_encode_upper_cafe", hex, "CAFE");
}

fn test_hex_encode_output_size() -> TestResult {
  var data = Vec[Int].new();
  data.push(0x00); data.push(0x01); data.push(0x02);
  var hex = hex_encode(&data);
  return assert_eq_int("hex_encode_output_size", hex.len(), 6);
}

fn test_hex_decode_valid() -> TestResult {
  var result = hex_decode("deadbeef");
  if result is Err {
    return TestResult{ name: "hex_decode_valid"; passed: false; };
  };
  var bytes = result as Ok;
  return assert_eq_int("hex_decode_valid", bytes.len(), 4);
}

fn test_hex_decode_roundtrip() -> TestResult {
  var data = Vec[Int].new();
  data.push(0xab); data.push(0xcd); data.push(0xef);
  var encoded = hex_encode(&data);
  var result = hex_decode(encoded);
  if result is Err {
    return TestResult{ name: "hex_roundtrip"; passed: false; };
  };
  var decoded = result as Ok;
  return assert_eq_vec("hex_roundtrip", &data, &decoded);
}

fn test_base64_encode_hello() -> TestResult {
  var data = ascii("Hello");
  var b64 = base64_encode(&data);
  return assert_eq_str("base64_encode_hello", b64, "SGVsbG8=");
}

fn test_base64_encode_output_nonempty() -> TestResult {
  var data = ascii("A");
  var b64 = base64_encode(&data);
  return assert_true("base64_encode_nonempty", b64.len() > 0);
}

fn test_base64_decode_valid() -> TestResult {
  var result = base64_decode("SGVsbG8=");
  if result is Err {
    return TestResult{ name: "base64_decode_valid"; passed: false; };
  };
  var bytes = result as Ok;
  return assert_eq_int("base64_decode_valid", bytes.len(), 5);
}

fn test_base64_roundtrip() -> TestResult {
  var data = ascii("Hello World");
  var encoded = base64_encode(&data);
  var result = base64_decode(encoded);
  if result is Err {
    return TestResult{ name: "base64_roundtrip"; passed: false; };
  };
  var decoded = result as Ok;
  return assert_eq_vec("base64_roundtrip", &data, &decoded);
}

fn test_base64url_encode() -> TestResult {
  var data = ascii("Hello");
  var b64 = base64url_encode(&data);
  return assert_true("base64url_encode_nonempty", b64.len() > 0);
}

fn test_base64url_roundtrip() -> TestResult {
  var data = ascii("Hello World");
  var encoded = base64url_encode(&data);
  var result = base64url_decode(encoded);
  if result is Err {
    return TestResult{ name: "base64url_roundtrip"; passed: false; };
  };
  var decoded = result as Ok;
  return assert_eq_vec("base64url_roundtrip", &data, &decoded);
}

fn test_random_bytes_ok() -> TestResult {
  var result = random_bytes(16);
  if result is Err {
    return TestResult{ name: "random_bytes_ok"; passed: false; };
  };
  var bytes = result as Ok;
  return assert_eq_int("random_bytes_ok_size", bytes.len(), 16);
}

fn test_hash_djb2() -> TestResult {
  var data = ascii("hello");
  var hash = hash_djb2(&data);
  return assert_true("hash_djb2_nonzero", hash != 0);
}

fn test_hash_fnv1a() -> TestResult {
  var data = ascii("hello");
  var hash = hash_fnv1a(&data);
  return assert_true("hash_fnv1a_nonzero", hash != 0);
}

fn test_hash_murmur3_32() -> TestResult {
  var data = ascii("hello");
  var hash = hash_murmur3_32(&data, 42);
  return assert_true("murmur3_32_nonzero", hash != 0);
}

fn test_hash_murmur3_deterministic() -> TestResult {
  var data = ascii("hello");
  var h1 = hash_murmur3_32(&data, 42);
  var h2 = hash_murmur3_32(&data, 42);
  return assert_eq_int("murmur3_deterministic", h1, h2);
}

fn test_hash_murmur3_seed_affects_output() -> TestResult {
  var data = ascii("hello");
  var h1 = hash_murmur3_32(&data, 1);
  var h2 = hash_murmur3_32(&data, 999);
  return assert_true("murmur3_seed_differs", h1 != h2);
}

fn test_aes128_encrypt_decrypt_roundtrip() -> TestResult {
  var key = Vec[Int].new();
  var i = 0;
  while i < 16 {
    key.push(i);
    i = i + 1;
  };
  var plaintext = Vec[Int].new();
  i = 0;
  while i < 16 {
    plaintext.push(i + 0x30);
    i = i + 1;
  };
  var enc_result = aes128_encrypt(&plaintext, &key);
  if enc_result is Err {
    return TestResult{ name: "aes128_encrypt_roundtrip"; passed: false; };
  };
  var ciphertext = enc_result as Ok;
  var dec_result = aes128_decrypt(&ciphertext, &key);
  if dec_result is Err {
    return TestResult{ name: "aes128_decrypt_roundtrip"; passed: false; };
  };
  var decrypted = dec_result as Ok;
  return assert_eq_vec("aes128_roundtrip", &plaintext, &decrypted);
}

fn test_aes256_encrypt_decrypt_roundtrip() -> TestResult {
  var key = Vec[Int].new();
  var i = 0;
  while i < 32 {
    key.push(i);
    i = i + 1;
  };
  var plaintext = Vec[Int].new();
  i = 0;
  while i < 16 {
    plaintext.push(i + 0x30);
    i = i + 1;
  };
  var enc_result = aes256_encrypt(&plaintext, &key);
  if enc_result is Err {
    return TestResult{ name: "aes256_encrypt_roundtrip"; passed: false; };
  };
  var ciphertext = enc_result as Ok;
  var dec_result = aes256_decrypt(&ciphertext, &key);
  if dec_result is Err {
    return TestResult{ name: "aes256_decrypt_roundtrip"; passed: false; };
  };
  var decrypted = dec_result as Ok;
  return assert_eq_vec("aes256_roundtrip", &plaintext, &decrypted);
}

fn test_aes128_encrypt_output_size() -> TestResult {
  var key = Vec[Int].new();
  var i = 0;
  while i < 16 {
    key.push(i);
    i = i + 1;
  };
  var plaintext = Vec[Int].new();
  i = 0;
  while i < 16 {
    plaintext.push(i + 0x30);
    i = i + 1;
  };
  var result = aes128_encrypt(&plaintext, &key);
  if result is Err {
    return TestResult{ name: "aes128_output_size"; passed: false; };
  };
  var ct = result as Ok;
  return assert_eq_int("aes128_output_size", ct.len(), 16);
}

fn test_aes128_bad_key_size() -> TestResult {
  var key = Vec[Int].new();
  key.push(0);
  var plaintext = Vec[Int].new();
  var i = 0;
  while i < 16 {
    plaintext.push(i + 0x30);
    i = i + 1;
  };
  var result = aes128_encrypt(&plaintext, &key);
  return TestResult{ name: "aes128_bad_key_size"; passed: result is Err; };
}

fn test_aes128_bad_plaintext_size() -> TestResult {
  var key = Vec[Int].new();
  var i = 0;
  while i < 16 {
    key.push(i);
    i = i + 1;
  };
  var plaintext = Vec[Int].new();
  plaintext.push(0x41);
  var result = aes128_encrypt(&plaintext, &key);
  return TestResult{ name: "aes128_bad_plaintext_size"; passed: result is Err; };
}

fn test_aes256_bad_key_size() -> TestResult {
  var key = Vec[Int].new();
  key.push(0);
  var plaintext = Vec[Int].new();
  var i = 0;
  while i < 16 {
    plaintext.push(i + 0x30);
    i = i + 1;
  };
  var result = aes256_encrypt(&plaintext, &key);
  return TestResult{ name: "aes256_bad_key_size"; passed: result is Err; };
}

fn test_aes256_bad_plaintext_size() -> TestResult {
  var key = Vec[Int].new();
  var i = 0;
  while i < 32 {
    key.push(i);
    i = i + 1;
  };
  var plaintext = Vec[Int].new();
  plaintext.push(0x41);
  var result = aes256_encrypt(&plaintext, &key);
  return TestResult{ name: "aes256_bad_plaintext_size"; passed: result is Err; };
}

fn test_aes128_decrypt_bad_key() -> TestResult {
  var key = Vec[Int].new();
  key.push(0);
  var ciphertext = Vec[Int].new();
  var i = 0;
  while i < 16 {
    ciphertext.push(i + 0x30);
    i = i + 1;
  };
  var result = aes128_decrypt(&ciphertext, &key);
  return TestResult{ name: "aes128_decrypt_bad_key"; passed: result is Err; };
}

fn test_aes256_decrypt_bad_key() -> TestResult {
  var key = Vec[Int].new();
  key.push(0);
  var ciphertext = Vec[Int].new();
  var i = 0;
  while i < 16 {
    ciphertext.push(i + 0x30);
    i = i + 1;
  };
  var result = aes256_decrypt(&ciphertext, &key);
  return TestResult{ name: "aes256_decrypt_bad_key"; passed: result is Err; };
}

fn test_aes_sbox_valid_range() -> TestResult {
  var i = 0;
  while i < 256 {
    var val = aes_sbox(i);
    if val < 0 || val > 255 {
      return TestResult{ name: "aes_sbox_valid_range"; passed: false; };
    };
    i = i + 1;
  };
  return TestResult{ name: "aes_sbox_valid_range"; passed: true; };
}

fn test_aes_inv_sbox_valid_range() -> TestResult {
  var i = 0;
  while i < 256 {
    var val = aes_inv_sbox(i);
    if val < 0 || val > 255 {
      return TestResult{ name: "aes_inv_sbox_valid_range"; passed: false; };
    };
    i = i + 1;
  };
  return TestResult{ name: "aes_inv_sbox_valid_range"; passed: true; };
}

fn test_aes_rcon_known_values() -> TestResult {
  var r1 = aes_rcon(1);
  var r2 = aes_rcon(2);
  var r10 = aes_rcon(10);
  var ok = (r1 == 0x01) && (r2 == 0x02) && (r10 == 0x36);
  return TestResult{ name: "aes_rcon_known_values"; passed: ok; };
}

fn test_aes_sbox_inv_sbox_roundtrip() -> TestResult {
  var i = 0;
  while i < 256 {
    var forward = aes_sbox(i);
    var back = aes_inv_sbox(forward);
    if back != i {
      return TestResult{ name: "aes_sbox_inv_roundtrip"; passed: false; };
    };
    i = i + 1;
  };
  return TestResult{ name: "aes_sbox_inv_roundtrip"; passed: true; };
}

fn test_pbkdf2_sha256_output_size() -> TestResult {
  var password = ascii("password");
  var salt = ascii("salt");
  var derived = pbkdf2_sha256(&password, &salt, 1, 32);
  return assert_eq_int("pbkdf2_output_size", derived.len(), 32);
}

fn test_pbkdf2_sha256_deterministic() -> TestResult {
  var password = ascii("password");
  var salt = ascii("salt");
  var d1 = pbkdf2_sha256(&password, &salt, 10, 32);
  var d2 = pbkdf2_sha256(&password, &salt, 10, 32);
  return assert_eq_vec("pbkdf2_deterministic", &d1, &d2);
}

fn test_pbkdf2_sha256_iterations_differ() -> TestResult {
  var password = ascii("password");
  var salt = ascii("salt");
  var d1 = pbkdf2_sha256(&password, &salt, 1, 16);
  var d2 = pbkdf2_sha256(&password, &salt, 100, 16);
  return assert_true("pbkdf2_iterations_differ", d1[0] != d2[0] || d1[1] != d2[1]);
}

fn test_hkdf_sha256_output_size() -> TestResult {
  var ikm = ascii("input key material");
  var salt = ascii("salt");
  var info = ascii("info");
  var derived = hkdf_sha256(&ikm, &salt, &info, 32);
  return assert_eq_int("hkdf_output_size", derived.len(), 32);
}

fn test_hkdf_sha256_deterministic() -> TestResult {
  var ikm = ascii("input key material");
  var salt = ascii("salt");
  var info = ascii("info");
  var d1 = hkdf_sha256(&ikm, &salt, &info, 16);
  var d2 = hkdf_sha256(&ikm, &salt, &info, 16);
  return assert_eq_vec("hkdf_deterministic", &d1, &d2);
}

fn test_ed25519_keygen_stub() -> TestResult {
  var kp = ed25519_keygen();
  var ok = (kp.public_key.len() == 0) && (kp.private_key.len() == 0);
  return TestResult{ name: "ed25519_keygen_stub_empty"; passed: ok; };
}

fn test_ed25519_sign_stub() -> TestResult {
  var kp = ed25519_keygen();
  var msg = ascii("test");
  var sig = ed25519_sign(&msg, &kp);
  var ok = (sig.r.len() == 0) && (sig.s.len() == 0);
  return TestResult{ name: "ed25519_sign_stub_empty"; passed: ok; };
}

fn test_ed25519_verify_stub() -> TestResult {
  var kp = ed25519_keygen();
  var msg = ascii("test");
  var sig = ed25519_sign(&msg, &kp);
  var result = ed25519_verify(&msg, &sig, &kp.public_key);
  return TestResult{ name: "ed25519_verify_stub_false"; passed: result == false; };
}

fn test_sha256_ffi_hello() -> TestResult {
  var data = ascii("Hello");
  var hash = xiom.crypto.sha256(&data);
  var expected = Vec[Int].new();
  expected.push(0x18); expected.push(0x5f); expected.push(0x8d); expected.push(0xb3);
  expected.push(0x22); expected.push(0x71); expected.push(0xfe); expected.push(0x25);
  expected.push(0xf5); expected.push(0x61); expected.push(0xa6); expected.push(0xfc);
  expected.push(0x93); expected.push(0x8b); expected.push(0x2e); expected.push(0x26);
  expected.push(0x43); expected.push(0x06); expected.push(0xec); expected.push(0x30);
  expected.push(0x4e); expected.push(0xda); expected.push(0x51); expected.push(0x80);
  expected.push(0x07); expected.push(0xd1); expected.push(0x76); expected.push(0x48);
  expected.push(0x26); expected.push(0x38); expected.push(0x19); expected.push(0x69);
  return assert_eq_vec("sha256_ffi_hello", &hash, &expected);
}

fn test_sha512_ffi_hello() -> TestResult {
  var data = ascii("Hello");
  var hash = xiom.crypto.sha512(&data);
  var expected = Vec[Int].new();
  expected.push(0x36); expected.push(0x15); expected.push(0xf8); expected.push(0x0c);
  expected.push(0x9d); expected.push(0x29); expected.push(0x3e); expected.push(0xd7);
  expected.push(0x40); expected.push(0x26); expected.push(0x87); expected.push(0xf9);
  expected.push(0x4b); expected.push(0x22); expected.push(0xd5); expected.push(0x8a);
  expected.push(0xfb); expected.push(0x15); expected.push(0x5b); expected.push(0x56);
  expected.push(0xb7); expected.push(0xe6); expected.push(0xcc); expected.push(0xa8);
  expected.push(0xf9); expected.push(0x2e); expected.push(0x65); expected.push(0xb1);
  expected.push(0x24); expected.push(0xe2); expected.push(0x2c); expected.push(0x74);
  expected.push(0xf4); expected.push(0xa7); expected.push(0xcd); expected.push(0xe6);
  expected.push(0x2f); expected.push(0xff); expected.push(0xe9); expected.push(0xc6);
  expected.push(0xe9); expected.push(0xcf); expected.push(0x56); expected.push(0x83);
  expected.push(0x72); expected.push(0x87); expected.push(0xe7); expected.push(0x81);
  expected.push(0x78); expected.push(0x9b); expected.push(0x27); expected.push(0x07);
  expected.push(0x9e); expected.push(0x34); expected.push(0xca); expected.push(0xc8);
  expected.push(0xbb); expected.push(0x08); expected.push(0xd9); expected.push(0x0a);
  expected.push(0x5e); expected.push(0x5e); expected.push(0x7c); expected.push(0xfa);
  return assert_eq_vec("sha512_ffi_hello", &hash, &expected);
}

fn test_md5_ffi_hello() -> TestResult {
  var data = ascii("Hello");
  var hash = xiom.crypto.md5(&data);
  var expected = Vec[Int].new();
  expected.push(0x8b); expected.push(0x1a); expected.push(0x99); expected.push(0x53);
  expected.push(0xc4); expected.push(0x61); expected.push(0x12); expected.push(0x96);
  expected.push(0xa8); expected.push(0x27); expected.push(0xab); expected.push(0xf8);
  expected.push(0xc4); expected.push(0x78); expected.push(0x04); expected.push(0xd7);
  return assert_eq_vec("md5_ffi_hello", &hash, &expected);
}

fn test_ffi_sha256_hex_hello() -> TestResult {
  var data = ascii("Hello");
  var hex = xiom.crypto.sha256_hex(&data);
  return assert_eq_str("ffi_sha256_hex_hello", hex, "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969");
}

fn test_ffi_sha512_hex_hello() -> TestResult {
  var data = ascii("Hello");
  var hex = xiom.crypto.sha512_hex(&data);
  return assert_eq_str("ffi_sha512_hex_hello", hex, "3615f80c9d293ed7402687f94b22d58afb155b56b7e6cca8f92e65b124e22c74f4a7cde62fffe9c6e9cf56837287e781789b27079e34cac8bb08d90a5e5e7cfa");
}

fn test_ffi_md5_hex_hello() -> TestResult {
  var data = ascii("Hello");
  var hex = xiom.crypto.md5_hex(&data);
  return assert_eq_str("ffi_md5_hex_hello", hex, "8b1a9953c4611296a827abf8c47804d7");
}

fn test_ffi_hmac_sha256_output_size() -> TestResult {
  var data = ascii("Hello World");
  var key = ascii("secret");
  var mac = xiom.crypto.hmac_sha256(&data, &key);
  return assert_eq_int("ffi_hmac_sha256_output_size", mac.len(), 32);
}

fn test_ffi_hex_encode() -> TestResult {
  var data = Vec[Int].new();
  data.push(0xde); data.push(0xad); data.push(0xbe); data.push(0xef);
  var hex = xiom.crypto.hex_encode(&data);
  return assert_eq_str("ffi_hex_encode_deadbeef", hex, "deadbeef");
}

fn test_ffi_hex_decode_roundtrip() -> TestResult {
  var data = Vec[Int].new();
  data.push(0xab); data.push(0xcd); data.push(0xef);
  var encoded = xiom.crypto.hex_encode(&data);
  var result = xiom.crypto.hex_decode(encoded);
  if result is Err {
    return TestResult{ name: "ffi_hex_roundtrip"; passed: false; };
  };
  var decoded = result as Ok;
  return assert_eq_vec("ffi_hex_roundtrip", &data, &decoded);
}

fn test_ffi_base64_roundtrip() -> TestResult {
  var data = ascii("Hello World");
  var encoded = xiom.crypto.base64_encode(&data);
  var result = xiom.crypto.base64_decode(encoded);
  if result is Err {
    return TestResult{ name: "ffi_base64_roundtrip"; passed: false; };
  };
  var decoded = result as Ok;
  return assert_eq_vec("ffi_base64_roundtrip", &data, &decoded);
}

fn test_ffi_random_bytes_ok() -> TestResult {
  var result = xiom.crypto.random_bytes(8);
  if result is Err {
    return TestResult{ name: "ffi_random_bytes_ok"; passed: false; };
  };
  var bytes = result as Ok;
  return assert_eq_int("ffi_random_bytes_ok_size", bytes.len(), 8);
}

fn test_random_bytes_pure_xiom() -> TestResult {
  var bytes = random_bytes(12);
  return assert_eq_int("random_bytes_pure_size", bytes.len(), 12);
}

pub fn run_all() -> Int {
  var counter = Counter{ passed: 0; failed: 0; };

  var tests = Vec[TestResult].new();

  tests.push(test_sha256_hello());
  tests.push(test_sha256_hello_world());
  tests.push(test_sha256_output_size());
  tests.push(test_sha256_hex_hello_world());
  tests.push(test_sha256_hex_output_size());
  tests.push(test_sha256_deterministic());

  tests.push(test_sha512_hello());
  tests.push(test_sha512_output_size());
  tests.push(test_sha512_hex_hello());
  tests.push(test_sha512_hex_output_size());
  tests.push(test_sha512_deterministic());

  tests.push(test_md5_hello());
  tests.push(test_md5_output_size());
  tests.push(test_md5_hex_hello());
  tests.push(test_md5_hex_output_size());
  tests.push(test_md5_deterministic());

  tests.push(test_hmac_sha256_known());

  tests.push(test_hex_encode());
  tests.push(test_hex_encode_upper());
  tests.push(test_hex_encode_output_size());
  tests.push(test_hex_decode_valid());
  tests.push(test_hex_decode_roundtrip());

  tests.push(test_base64_encode_hello());
  tests.push(test_base64_encode_output_nonempty());
  tests.push(test_base64_decode_valid());
  tests.push(test_base64_roundtrip());

  tests.push(test_base64url_encode());
  tests.push(test_base64url_roundtrip());

  tests.push(test_random_bytes_ok());
  tests.push(test_random_bytes_pure_xiom());

  tests.push(test_hash_djb2());
  tests.push(test_hash_fnv1a());
  tests.push(test_hash_murmur3_32());
  tests.push(test_hash_murmur3_deterministic());
  tests.push(test_hash_murmur3_seed_affects_output());

  tests.push(test_aes128_encrypt_decrypt_roundtrip());
  tests.push(test_aes256_encrypt_decrypt_roundtrip());
  tests.push(test_aes128_encrypt_output_size());
  tests.push(test_aes128_bad_key_size());
  tests.push(test_aes128_bad_plaintext_size());
  tests.push(test_aes256_bad_key_size());
  tests.push(test_aes256_bad_plaintext_size());
  tests.push(test_aes128_decrypt_bad_key());
  tests.push(test_aes256_decrypt_bad_key());
  tests.push(test_aes_sbox_valid_range());
  tests.push(test_aes_inv_sbox_valid_range());
  tests.push(test_aes_rcon_known_values());
  tests.push(test_aes_sbox_inv_sbox_roundtrip());

  tests.push(test_pbkdf2_sha256_output_size());
  tests.push(test_pbkdf2_sha256_deterministic());
  tests.push(test_pbkdf2_sha256_iterations_differ());

  tests.push(test_hkdf_sha256_output_size());
  tests.push(test_hkdf_sha256_deterministic());

  tests.push(test_ed25519_keygen_stub());
  tests.push(test_ed25519_sign_stub());
  tests.push(test_ed25519_verify_stub());

  tests.push(test_sha256_ffi_hello());
  tests.push(test_sha512_ffi_hello());
  tests.push(test_md5_ffi_hello());
  tests.push(test_ffi_sha256_hex_hello());
  tests.push(test_ffi_sha512_hex_hello());
  tests.push(test_ffi_md5_hex_hello());
  tests.push(test_ffi_hmac_sha256_output_size());
  tests.push(test_ffi_hex_encode());
  tests.push(test_ffi_hex_decode_roundtrip());
  tests.push(test_ffi_base64_roundtrip());
  tests.push(test_ffi_random_bytes_ok());

  var i = 0;
  while i < tests.len() {
    var t = tests[i];
    if t.passed {
      counter = Counter{ passed: counter.passed + 1; failed: counter.failed; };
    } else {
      counter = Counter{ passed: counter.passed; failed: counter.failed + 1; };
    };
    i = i + 1;
  };

  return counter.failed;
}
