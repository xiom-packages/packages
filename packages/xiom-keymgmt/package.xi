// XIOM -- xiom.keymgmt package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_keymgmt {
  name: "xiom.keymgmt";
  version: "0.1.2";
  description: "Key structure management: JWK/JWKS (RFC 7517/7518), base64url, PKCS#8/SPKI DER structures and PEM armor (no crypto)";
  categories: ["crypto-security"];
  keywords: ["jwk", "jwks", "pkcs8", "spki", "der", "pem", "base64url", "key"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.keymgmt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
