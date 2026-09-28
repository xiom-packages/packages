// XIOM -- xiom.config package manifest
// Port task: promote the xiom.config placeholder to a real, tested,
// pure-XIOM package (in-memory configuration model: sections, merge,
// typed getters, schema validation, canonical rendering).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.convert and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_config {
  name: "xiom.config";
  version: "0.1.0";
  description: "In-memory configuration model: sectioned parsing, overlay merge, typed getters, schema validation and canonical rendering";
  categories: ["data", "tooling"];
  keywords: ["config", "ini", "settings", "merge", "schema"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.config"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
