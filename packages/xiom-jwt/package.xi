// XIOM -- xiom.jwt package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Decode-only JWT package: splits a compact token into its three base64url
// segments, decodes the header/payload text and reads exp/nbf claims with a
// minimal scanner. NO signature verification and NO JSON parsing.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module imports only
// xiom.string from it; the tests add xiom.io and xiom.test.

package xiom_jwt {
  name: "xiom.jwt";
  version: "0.1.0";
  description: "JWT structural decoding: headers, claims, timestamps (no signature verification)";
  categories: ["data", "safety"];
  keywords: ["jwt", "token", "claims", "decode"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.jwt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
