// XIOM -- xiom.properties package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Java .properties parsing and emitting with escapes and line continuations.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_properties {
  name: "xiom.properties";
  version: "0.1.0";
  description: "Java .properties parsing and emitting with escapes and line continuations";
  categories: ["data", "tooling"];
  keywords: ["properties", "java", "config", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.properties"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
