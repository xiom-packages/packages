// XIOM -- xiom.ann package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The modules import xiom.vectors (the published
// 0.1.0 package) for the dense-vector primitive, distance metrics, neighbor
// edge and value codec; the tests additionally use xiom.io and xiom.test.

package xiom_ann {
  name: "xiom.ann";
  version: "0.1.0";
  description: "ANN index surface: AnnIndexKind/AnnParams with stable on-disk codes, the exact flat-scan oracle, and a multi-layer HNSW graph over flat parallel arrays";
  categories: ["database", "systems"];
  keywords: ["ann", "hnsw", "vector", "index", "database"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ann", "xiom.ann.hnsw"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0", "xiom.vectors": "0.1.0" };
}
