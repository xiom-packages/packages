// XIOM -- xiom.uf2 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.io.fs and
// xiom.time from it (host file copy and completion polling); the tests
// additionally use xiom.io, xiom.test and xiom.encoding.hex.

package xiom_uf2 {
  name: "xiom.uf2";
  version: "0.1.0";
  description: "USB Flashing Format (UF2) codec and host-side flashing: parse/build 512-byte blocks, validate full images, and copy to a mounted BOOTSEL volume with disconnect-based completion detection (typed SKIP when no volume)";
  categories: ["systems"];
  keywords: ["uf2", "flash", "bootloader", "rp2040", "rp2350", "samd21", "samd51", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.uf2"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
