// XIOM -- crypto linkability probe (xiom.crypto.hash module shape)
// Expected on v0.62.2: link failure on the underlying SHA-256 symbol.
// Compile WITH linking; --emit-ir alone will not reproduce it.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module crypto_hash_link_probe

use xiom.io;
use xiom.crypto.hash;

fn main() -> Int {
  var data = Vec[UInt8].new();
  data.push(97);   // 'a'
  data.push(98);   // 'b'
  data.push(99);   // 'c'
  let digest: Vec[UInt8] = hash.crypto_hash_sha256(&data);
  io.println("linked");
  return digest.len();
}
