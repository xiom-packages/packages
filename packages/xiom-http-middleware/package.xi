// XIOM -- xiom.http.middleware package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.crypto and
// xiom.string from it; the tests additionally use xiom.test and xiom.io.

package xiom_http_middleware {
  name: "xiom.http.middleware";
  version: "0.1.0";
  description: "Envelope-agnostic HTTP middleware helpers: request ids, access-log lines, CORS headers, constant-time CSRF checks, escaped JSON error bodies";
  categories: ["web", "network"];
  keywords: ["middleware", "cors", "csrf", "request-id", "access-log"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.http.middleware"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
