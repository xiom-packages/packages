// XIOM -- xiom.refactor package manifest
// Port task: replace the xiom.refactor placeholder with a real, tested,
// pure-XIOM (no FFI) package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_refactor {
  name: "xiom.refactor";
  version: "0.1.0";
  description: "Text-level identifier renaming with word boundaries and dry-run counts";
  categories: ["tooling","text"];
  keywords: ["refactor","rename","identifier","source"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.refactor"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
