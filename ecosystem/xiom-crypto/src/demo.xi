module xiom.crypto.demo

// ---------------------------------------------------------------------------
// PENDING: Cross-module function imports.
// This module depends on `xiom.crypto` (root crypto.xi):
//   sha256_hex(&Vec[Int]) -> Str
//   random_bytes(count: Int) -> Result[Vec[Int], Str]
//   hmac_sha256(&Vec[Int], &Vec[Int]) -> Vec[Int]
//   hex_encode(&Vec[Int]) -> Str
//   hex_decode(Str) -> Result[Vec[Int], Str]
// Once the XIOM module system supports `use` or auto-import for sibling
// modules within the same package, replace the local stubs below.
// ---------------------------------------------------------------------------

// ===========================================================================
// Internal stubs — delegate to xiom.crypto.* once module resolution is wired.
// ===========================================================================

fn sha256_hex(data: &Vec[Int]) -> Str {
  return "";
}

fn random_bytes(count: Int) -> Result[Vec[Int], Str] {
  var result = Vec[Int].new();
  var i = 0;
  while i < count {
    result.push(0);
    i = i + 1;
  }
  return Ok(result);
}

fn hmac_sha256(data: &Vec[Int], key: &Vec[Int]) -> Vec[Int] {
  var result = Vec[Int].new();
  var i = 0;
  while i < 32 {
    result.push(0);
    i = i + 1;
  }
  return result;
}

fn hex_encode(data: &Vec[Int]) -> Str {
  return "";
}

fn hex_decode(input: Str) -> Result[Vec[Int], Str] {
  return Ok(Vec[Int].new());
}

// ===========================================================================
// Byte literal helpers
// ===========================================================================

fn ascii_bytes(s: Str) -> Vec[Int] {
  // PENDING: @axiom_str_to_ptr / @axiom_str_len intrinsics needed for
  // iterating string characters by code point.
  // Workaround: pre-encode known strings as hex and decode at runtime.
  var result = Vec[Int].new();
  return result;
}

fn str_from_bytes(b: &Vec[Int]) -> Str {
  return "";
}

// ===========================================================================
// Demo functions
// ===========================================================================

pub fn demo_hash() -> Result[Unit, Str] {
  // "Hello World" — 11 ASCII bytes:
  //   48 65 6c 6c 6f 20 57 6f 72 6c 64
  // Expected SHA-256:
  //   a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e
  var hello_hex = hex_decode("48656c6c6f20576f726c64");
  var hello = hello_hex?;
  var hash_hex = sha256_hex(&hello);
  // PENDING: no `print` or `println` intrinsic yet.
  // Once available: print("SHA-256: " + hash_hex);
  return Ok(());
}

pub fn demo_random() -> Result[Unit, Str] {
  var result = random_bytes(16);
  var bytes = result?;
  var hex = hex_encode(&bytes);
  // PENDING: print("Random bytes (16): " + hex);
  return Ok(());
}

pub fn demo_hmac() -> Result[Unit, Str] {
  // Key: "secret"
  var key_hex = hex_decode("736563726574");
  var key = key_hex?;
  // Data: "Hello World"
  var data_hex = hex_decode("48656c6c6f20576f726c64");
  var data = data_hex?;
  var hmac_result = hmac_sha256(&data, &key);
  var hex = hex_encode(&hmac_result);
  // PENDING: print("HMAC-SHA256: " + hex);
  return Ok(());
}
