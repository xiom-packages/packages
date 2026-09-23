// XIOM -- xiom.tokenizer package manifest
// Port task: promote the xiom.tokenizer placeholder to a real, tested,
// pure-XIOM (no FFI) package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_tokenizer {
  name: "xiom.tokenizer";
  version: "0.1.0";
  description: "Text tokenization: words, sentences, lines, and n-grams";
  categories: ["text"];
  keywords: ["tokenizer", "nlp", "text", "ngram"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tokenizer"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
