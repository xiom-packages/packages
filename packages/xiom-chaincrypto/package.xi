// XIOM -- xiom.chaincrypto package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert from it;
// the tests additionally use xiom.test, xiom.io and xiom.string.compare.
// Pure XIOM, no FFI, no cryptography: hashes are opaque caller-supplied ints.

package xiom_chaincrypto {
  name: "xiom.chaincrypto";
  version: "0.1.0";
  description: "Commitment and proof structures over opaque integer hashes: accumulator, membership proofs, m-of-n gates, commit-reveal";
  categories: ["data", "crypto-security"];
  keywords: ["blockchain", "commitment", "proof", "multisig", "commit-reveal", "accumulator"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.chaincrypto"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
