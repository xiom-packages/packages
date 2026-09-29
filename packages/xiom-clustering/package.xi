// XIOM -- xiom.clustering package manifest
// Port task: promote the xiom.clustering placeholder to a real, tested,
// pure-XIOM package (fixed-point k-means and DBSCAN on scaled integers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and xiom.string.

package xiom_clustering {
  name: "xiom.clustering";
  version: "0.1.1";
  description: "Fixed-point clustering primitives (scaled integers): k-means and DBSCAN";
  categories: ["ai-ml", "data"];
  keywords: ["kmeans", "dbscan", "clustering", "fixed-point", "unsupervised"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.clustering"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
