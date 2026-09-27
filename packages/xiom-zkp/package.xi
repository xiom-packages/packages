// XIOM -- xiom.zkp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.convert from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_zkp {
  name: "xiom.zkp";
  version: "0.1.0";
  description: "Zero-knowledge proof serialization structures (BLS12-381 Groth16/PLONK): field/point encodings, blob decode, structural validation";
  categories: ["crypto-security", "data"];
  keywords: ["zkp", "zero-knowledge", "groth16", "plonk", "bls12-381", "serialization"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.zkp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
