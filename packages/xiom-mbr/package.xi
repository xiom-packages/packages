// XIOM -- xiom.mbr package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing from it; the
// tests use xiom.test, xiom.io and xiom.string.compare.

package xiom_mbr {
  name: "xiom.mbr";
  version: "0.1.0";
  description: "Master Boot Record codec: parse and build a canonical 512-byte MBR sector";
  categories: ["systems"];
  keywords: ["mbr", "partition", "boot", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mbr"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
