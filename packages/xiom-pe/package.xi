// XIOM -- xiom.pe package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free below
// xiom.std; the tests use xiom.test, xiom.io, xiom.string and
// xiom.string.compare from it.

package xiom_pe {
  name: "xiom.pe";
  version: "0.1.0";
  description: "PE/COFF header codec (documented subset): DOS header and stub, COFF file header, PE32/PE32+ optional header, data directories and section table";
  categories: ["systems"];
  keywords: ["pe", "coff", "windows", "binary"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pe"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
