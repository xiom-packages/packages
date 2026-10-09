// XIOM -- xiom.btree package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module `xiom.btree` imports nothing
// (core types only, verified by compiling with an empty import list); the
// tests additionally use xiom.test and xiom.io, and the churn probe uses
// xiom.io, xiom.os.env, xiom.convert and xiom.convert.parse.

package xiom_btree {
  name: "xiom.btree";
  version: "0.1.0";
  description: "Pure-XIOM in-memory B-tree index: insert/search/delete with predecessor/successor replacement, underflow borrow/merge, inclusive range scans and in-order traversal over a flat append-only node array";
  categories: ["database", "systems"];
  keywords: ["btree", "index", "database", "storage"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.btree"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
