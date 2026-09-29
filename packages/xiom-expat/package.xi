// XIOM -- xiom.expat package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.builder,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_expat {
  name: "xiom.expat";
  version: "0.1.2";
  description: "Expat-style XML 1.0 parser: streaming events, entities, well-formedness checks";
  categories: ["data"];
  keywords: ["xml", "parser", "expat", "events", "markup"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.expat"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
