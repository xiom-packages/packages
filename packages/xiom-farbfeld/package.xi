// XIOM -- xiom.farbfeld package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// conformance suite uses xiom.test/xiom.io/xiom.string/xiom.string.compare
// from it.

package xiom_farbfeld {
  name: "xiom.farbfeld";
  version: "0.1.0";
  description: "Farbfeld 16-bit RGBA image parsing, pixel access and canonical building";
  categories: ["graphics"];
  keywords: ["farbfeld", "image", "rgba", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.farbfeld"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
