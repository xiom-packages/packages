// XIOM -- xiom.qoi package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// conformance suite uses xiom.test/xiom.io/xiom.string from it.

package xiom_qoi {
  name: "xiom.qoi";
  version: "0.1.0";
  description: "QOI image chunk-stream codec: header, flat op records, validation, canonical re-emit";
  categories: ["graphics"];
  keywords: ["qoi", "image", "codec", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.qoi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
