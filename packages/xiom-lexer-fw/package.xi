// XIOM -- xiom.lexer-fw package manifest
// Port task: promote the xiom.lexer-fw placeholder to a real, tested,
// pure-XIOM package (a framework for building lexical analyzers: scan state
// with line/column tracking, regex-free byte matchers, a keyword/punctuation
// table and a parallel-Vec token stream).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io and xiom.convert.

package xiom_lexer_fw {
  name: "xiom.lexer-fw";
  version: "0.1.1";
  description: "Lexical-analyzer framework: scan state with line/column tracking, byte matchers, keyword table, token streams";
  categories: ["tooling", "text-nlp"];
  keywords: ["lexer", "lexing", "scanner", "tokens", "framework"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.lexer"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
