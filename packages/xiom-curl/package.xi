// XIOM -- xiom.curl package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare, xiom.convert and
// xiom.encoding.base64 from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_curl {
  name: "xiom.curl";
  version: "0.1.0";
  description: "Pure-XIOM HTTP client model: URL parsing/normalization, request and response envelopes, redirect semantics, cookies, auth header shapes, retry policy and keep-alive pool accounting (no sockets, no TLS)";
  categories: ["network"];
  keywords: ["http", "curl", "url", "client", "redirect", "cookie", "keep-alive"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.curl"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
