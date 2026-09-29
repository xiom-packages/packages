// XIOM -- xiom.auth package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.encoding.base64 from it;
// the tests additionally use xiom.test and xiom.io.

package xiom_auth {
  name: "xiom.auth";
  version: "0.1.2";
  description: "Pure-XIOM HTTP authentication header codecs (RFC 7235 / 7617 / 7616 / 6750): Authorization and WWW-Authenticate grammar, Basic, Digest and Bearer structure helpers, no crypto and no network";
  categories: ["protocol"];
  keywords: ["http", "auth", "authorization", "www-authenticate", "basic", "digest", "bearer", "rfc7235"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.auth"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
