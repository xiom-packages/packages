// XIOM -- xiom.query package manifest
// Port task: replace the xiom.query placeholder with a real, tested,
// pure-XIOM package (filter expressions over flat key/value records).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_query {
  name: "xiom.query";
  version: "0.1.0";
  description: "Simple filter expressions over flat key/value records with AND/OR connectors";
  categories: ["data", "tooling"];
  keywords: ["query", "filter", "expression", "records"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.query"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
