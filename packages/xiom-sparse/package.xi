// XIOM -- xiom.sparse package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield pure-XIOM Android sparse-image codec (no FFI).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.convert; the tests
// use xiom.test, xiom.io, xiom.string, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_sparse {
  name: "xiom.sparse";
  version: "0.1.0";
  description: "Android sparse image codec with a flat chunk index and a canonical builder";
  categories: ["systems"];
  keywords: ["sparse", "android", "image", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.sparse"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
