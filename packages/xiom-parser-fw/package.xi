// XIOM -- xiom.parser-fw package manifest
// Port task: promote the xiom.parser-fw placeholder to a real, tested,
// pure-XIOM package (a framework for recursive-descent and
// precedence-climbing parsers: token model and classification, grammar rule
// declarations and production helpers, a backtracking core engine,
// Pratt/precedence binding powers, panic-mode error recovery and a parse-tree
// node model).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_parser_fw {
  name: "xiom.parser-fw";
  version: "0.1.1";
  description: "Parser framework: recursive-descent engine, precedence climbing, panic-mode recovery, parse trees";
  categories: ["tooling"];
  keywords: ["parser", "recursive-descent", "pratt", "precedence", "framework"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.parser_fw"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
