// XIOM -- xiom.collation package manifest
// Port task: replace the xiom.collation placeholder with a real, tested,
// pure-XIOM (no FFI) package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_collation {
  name: "xiom.collation";
  version: "0.1.0";
  description: "Case-insensitive and natural (numeric-aware) string collation";
  categories: ["text"];
  keywords: ["collation", "sort", "natural", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.collation"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
