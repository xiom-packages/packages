// XIOM -- xiom.murmur3 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string (for the
// hex display helper); the tests use xiom.test, xiom.io and xiom.string.

package xiom_murmur3 {
  name: "xiom.murmur3";
  version: "0.1.0";
  description: "MurmurHash3 x86_32 non-cryptographic hash with seed, streaming state and hex output";
  categories: ["data"];
  keywords: ["murmur3", "hash", "non-cryptographic", "smhasher"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.murmur3"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
