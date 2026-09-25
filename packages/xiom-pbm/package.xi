// XIOM -- xiom.pbm package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string only; the
// conformance suite additionally uses xiom.test/xiom.io/xiom.string.compare.

package xiom_pbm {
  name: "xiom.pbm";
  version: "0.1.0";
  description: "Netpbm PBM (P1 ASCII / P4 binary) parsing and building for 1-bit rasters";
  categories: ["graphics"];
  keywords: ["pbm", "netpbm", "bitmap", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pbm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
