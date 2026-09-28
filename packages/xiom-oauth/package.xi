// XIOM -- xiom.oauth package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_oauth {
  name: "xiom.oauth";
  version: "0.1.1";
  description: "Pure-XIOM OAuth 2.0 / PKCE request-and-response structure codec: form-urlencoded and JSON message parsing/building, no network and no crypto";
  categories: ["protocol"];
  keywords: ["oauth", "oauth2", "pkce", "authorization", "token"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.oauth"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
