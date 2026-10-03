// XIOM -- xiom.ast package manifest
// Port task: promote the xiom.ast placeholder to a real, tested, pure-XIOM
// package (a deterministic AST toolkit: parallel-array node model, builder
// with cycle refusal, pre/post-order traversal, spans, diagnostics and a
// canonical pretty-printer, demonstrated on a fixed fixture grammar).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io and xiom.string.join.

package xiom_ast {
  name: "xiom.ast";
  version: "0.1.0";
  description: "Deterministic AST toolkit: parallel-array node model, cycle-safe builder, pre/post-order traversal, spans, pretty-printer";
  categories: ["tooling", "text-nlp"];
  keywords: ["ast", "syntax-tree", "traversal", "spans", "pretty-printer"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ast"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
