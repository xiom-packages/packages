// XIOM -- xiom.bloom package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_bloom {
  name: "xiom.bloom";
  version: "0.1.0";
  description: "Bloom filter over a flat byte buffer: double hashing, integer false-positive estimate, strict serialization";
  categories: ["data"];
  keywords: ["bloom", "filter", "probabilistic", "bitset"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.bloom"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
