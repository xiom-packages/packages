// XIOM -- xiom.plural package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare, xiom.string.lowercase, xiom.string.uppercase and
// xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_plural {
  name: "xiom.plural";
  version: "0.1.0";
  description: "English pluralization and singularization with irregular and suffix rules";
  categories: ["text"];
  keywords: ["plural", "singular", "inflection", "strings"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.plural"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
