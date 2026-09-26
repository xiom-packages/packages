// XIOM -- xiom.uboot package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex.

package xiom_uboot {
  name: "xiom.uboot";
  version: "0.1.0";
  description: "U-Boot legacy image header codec: parse, inspect and build the 64-byte ih_ header";
  categories: ["systems"];
  keywords: ["uboot", "bootloader", "firmware", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.uboot"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
