// XIOM -- xiom.interrupt package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.interrupt placeholder.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.convert.int; the tests add xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_interrupt {
  name: "xiom.interrupt";
  version: "0.1.0";
  description: "Interrupt controller structure codecs: x86 IDT gate descriptors and ARM GICv2 distributor registers";
  categories: ["systems"];
  keywords: ["interrupt", "idt", "gic", "x86", "arm", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.interrupt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
