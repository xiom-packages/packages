// XIOM -- xiom.nlp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_nlp {
  name: "xiom.nlp";
  version: "0.1.1";
  description: "Deterministic byte-oriented NLP core: tokenizer, sentence splitter, Porter stemmer, statistics";
  categories: ["text"];
  keywords: ["nlp", "tokenizer", "stemming", "porter", "sentences", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.nlp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
