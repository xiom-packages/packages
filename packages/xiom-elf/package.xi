// XIOM -- xiom.elf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string from it;
// the tests add xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_elf {
  name: "xiom.elf";
  version: "0.1.0";
  description: "Pure-XIOM ELF header and program/section table codec (32/64-bit, LE/BE)";
  categories: ["systems"];
  keywords: ["elf", "binary", "executable", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.elf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
