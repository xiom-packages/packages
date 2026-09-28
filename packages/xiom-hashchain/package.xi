// XIOM -- xiom.hashchain package manifest
// Port task: promote the xiom.hashchain placeholder to a real, tested,
// pure-XIOM package (hash-linked record chains, SHA-256 block digests and
// integrity verification over caller byte buffers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.convert and
// xiom.crypto (SHA-256) from it; the tests additionally use xiom.test,
// xiom.io and xiom.string.compare.

package xiom_hashchain {
  name: "xiom.hashchain";
  version: "0.1.0";
  description: "Hash-linked record chains with deterministic SHA-256 block digests and first-error integrity verification";
  categories: ["data", "crypto-security"];
  keywords: ["hash", "chain", "hashchain", "sha256", "integrity"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.hashchain"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
