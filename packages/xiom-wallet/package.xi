// XIOM -- xiom.wallet package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io. Pure XIOM: no FFI, no external packages, no
// cryptography, no hashing and no networking (keys and addresses are opaque
// caller-supplied strings that are only validated structurally).

package xiom_wallet {
  name: "xiom.wallet";
  version: "0.1.0";
  description: "Deterministic wallet metadata model: BIP32-style derivation paths, account and address books, an integer balance ledger with transfer intents (no crypto, no network)";
  categories: ["data", "finance"];
  keywords: ["wallet", "bip32", "derivation-path", "accounts", "addresses", "ledger", "transfer", "metadata"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.wallet"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
