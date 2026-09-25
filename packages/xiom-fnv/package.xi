// XIOM -- xiom.fnv package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string (for the
// hex display helpers); the tests use xiom.test, xiom.io and xiom.string.

package xiom_fnv {
  name: "xiom.fnv";
  version: "0.1.0";
  description: "FNV-1 and FNV-1a non-cryptographic hash functions in 32-bit and 64-bit widths";
  categories: ["data"];
  keywords: ["fnv", "hash", "checksum", "non-cryptographic"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.fnv"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
