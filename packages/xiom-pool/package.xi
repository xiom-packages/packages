// XIOM -- xiom.pool package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it; the
// tests additionally use xiom.string.compare, xiom.test and xiom.io.

package xiom_pool {
  name: "xiom.pool";
  version: "0.1.2";
  description: "Deterministic fixed-capacity slot pool with generation-checked leases";
  categories: ["concurrency", "systems"];
  keywords: ["pool", "slots", "lease", "reuse", "resource"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pool"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
