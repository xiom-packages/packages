// XIOM -- xiom.sgf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// SGF (Smart Game Format) codec for a documented subset: game-tree
// collections, nodes, properties with multi-values and escapes, nested
// variations, accessors and canonical emit. xiom.std is the standard library:
// a platform dependency, excluded from the registry install closure. The
// module itself imports xiom.string, xiom.string.builder, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_sgf {
  name: "xiom.sgf";
  version: "0.1.0";
  description: "Smart Game Format codec: game tree collections, nodes, properties and canonical emit";
  categories: ["graphics"];
  keywords: ["sgf", "go", "game", "notation"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.sgf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
