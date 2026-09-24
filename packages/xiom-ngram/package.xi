// XIOM -- xiom.ngram package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module uses xiom.string, xiom.string.compare and
// xiom.convert.int from it; the tests additionally use xiom.test and xiom.io.

package xiom_ngram {
  name: "xiom.ngram";
  version: "0.1.0";
  description: "Word and character n-grams with Jaccard/Dice similarity and MinHash signatures";
  categories: ["text", "data"];
  keywords: ["ngram", "shingles", "jaccard", "minhash", "similarity"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ngram"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
