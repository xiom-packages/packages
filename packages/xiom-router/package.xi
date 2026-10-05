// XIOM -- xiom.router package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_router {
  name: "xiom.router";
  version: "0.1.0";
  description: "Deterministic HTTP route table: exact and :parameter patterns, method matching, 404/405 aggregation";
  categories: ["web", "network"];
  keywords: ["router", "http", "routing", "path-parameters"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.router"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
