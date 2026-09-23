// XIOM -- xiom.lru package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.collect.stringmap from it;
// the tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_lru {
  name: "xiom.lru";
  version: "0.1.0";
  description: "Bounded least-recently-used cache with O(1) get/put and eviction statistics";
  categories: ["core"];
  keywords: ["cache", "lru", "eviction", "collections"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.lru"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
