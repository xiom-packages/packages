// XIOM — Package Manifest
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_crypto {
  name: "xiom-crypto";
  version: "0.1.0";
  description: "XIOM Cryptography Library — Layer 3.4: Pure-XIOM Hashing, Encryption, Encoding, and Key Derivation";
  authors: ["XIOM Team"];
  modules: [
    "xiom.crypto",
    "xiom.crypto.demo",
    "xiom.crypto.hash",
    "xiom.crypto.sha",
    "xiom.crypto.md5",
    "xiom.crypto.aes",
    "xiom.crypto.b64",
    "xiom.crypto.hex",
    "xiom.crypto.random",
    "xiom.crypto.pbkdf",
    "xiom.crypto.ed25519",
  ];
}
