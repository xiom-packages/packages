// XIOM -- xiom.bech32 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_bech32 {
  name: "xiom.bech32";
  version: "0.1.0";
  description: "Bech32 and Bech32m checksummed base32 encoding and decoding (BIP-173, BIP-350)";
  categories: ["data"];
  keywords: ["bech32", "bech32m", "encoding", "bitcoin"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.bech32"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
