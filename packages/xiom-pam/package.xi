// XIOM -- xiom.pam package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.builder only; the conformance suite additionally uses
// xiom.test/xiom.io/xiom.string.compare.

package xiom_pam {
  name: "xiom.pam";
  version: "0.1.0";
  description: "Netpbm PAM (P7) header parsing, raster spans and building for flat tuple images";
  categories: ["graphics"];
  keywords: ["pam", "netpbm", "image", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pam"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
