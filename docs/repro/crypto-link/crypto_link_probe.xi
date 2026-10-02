// XIOM -- crypto linkability probe (facade shape)
// Expected on v0.62.2: lld-link: undefined symbol: xiom_sha256_hash
// Compile WITH linking (a package/test run, or a direct compile); --emit-ir
// alone will not reproduce the failure.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module crypto_link_probe

use xiom.io;
use xiom.crypto;

fn main() -> Int {
  var data = Vec[UInt8].new();
  data.push(97);   // 'a'
  data.push(98);   // 'b'
  data.push(99);   // 'c'
  let hexed: Str = crypto.sha256_hex(&data);
  io.println(hexed);
  return 0;
}
