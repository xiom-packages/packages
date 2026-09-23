// XIOM -- xiom.summary package manifest
// Port task: promote the xiom.summary placeholder to a real, tested,
// pure-XIOM (no FFI) package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_summary {
  name: "xiom.summary";
  version: "0.1.0";
  description: "Extractive text summarization with frequency scoring";
  categories: ["text"];
  keywords: ["summary", "extractive", "nlp", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.summary"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
