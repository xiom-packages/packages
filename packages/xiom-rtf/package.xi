// XIOM -- xiom.rtf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: add a pure-XIOM (no FFI) RTF subset codec: tokenizer, canonical
// emitter and plain-text extraction for a documented RTF subset.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_rtf {
  name: "xiom.rtf";
  version: "0.1.0";
  description: "Pure-XIOM RTF subset codec: token stream parser, canonical emitter, plain-text extraction";
  categories: ["text"];
  keywords: ["rtf", "richtext", "parser", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.rtf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
