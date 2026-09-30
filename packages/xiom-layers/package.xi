// XIOM -- xiom.layers package manifest
// Port task: promote the xiom.layers placeholder to a real, tested, pure-XIOM
// package (ordered layered configuration over dotted keys: precedence,
// replace/append/delete sentinels, provenance, shadow queries, flatten, diff).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_layers {
  name: "xiom.layers";
  version: "0.1.0";
  description: "Ordered layered configuration over dotted keys: later-wins precedence, replace/append/delete sentinels, provenance, shadowed-value queries, flattening and layer diff";
  categories: ["data", "tooling"];
  keywords: ["config", "layers", "overrides", "precedence", "merge", "provenance"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.layers"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
