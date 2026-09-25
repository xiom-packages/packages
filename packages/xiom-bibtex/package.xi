// XIOM -- xiom.bibtex package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module imports xiom.string and xiom.string.compare from it;
// the tests additionally use xiom.test and xiom.io.

package xiom_bibtex {
  name: "xiom.bibtex";
  version: "0.1.0";
  description: "BibTeX bibliography parser and canonical emitter";
  categories: ["science"];
  keywords: ["bibtex", "bibliography", "academic", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.bibtex"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
