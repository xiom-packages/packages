// XIOM -- xiom.vault package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The modules import xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.encoding.hex from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_vault {
  name: "xiom.vault";
  version: "0.1.0";
  description: "Pure-XIOM secret vault backend MODEL (no HTTP, no crypto): Vault API request/response model with a JSON-ish body builder and raw key lookup, KV v1/v2 path and version state model, Shamir secret sharing over GF(256) with unseal progress, token/AppRole login models and policy path/capability matching";
  categories: ["crypto-security"];
  keywords: ["vault", "secrets", "kv", "shamir", "unseal", "policy", "approle", "token", "capabilities"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.vault", "xiom.vault.kv", "xiom.vault.unseal", "xiom.vault.auth", "xiom.vault.policy"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
