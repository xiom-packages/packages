// XIOM -- xiom.vectors package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.math and xiom.num.float
// from it; the tests additionally use xiom.io and xiom.test.

package xiom_vectors {
  name: "xiom.vectors";
  version: "0.1.0";
  description: "Dense vectors, cosine/dot/L2 distance, normalization, bounded top-K, and the WAL value codec";
  categories: ["database", "systems"];
  keywords: ["vector", "embedding", "distance", "ann", "database"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.vectors"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
