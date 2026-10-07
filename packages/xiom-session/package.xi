// XIOM -- xiom.session package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.crypto (session
// id entropy), xiom.string (byte access, slicing, concatenation) and
// xiom.string.compare (every Str comparison); the tests additionally use
// xiom.test and xiom.io.

package xiom_session {
  name: "xiom.session";
  version: "0.1.0";
  description: "Deterministic in-memory session store: secure hex ids, absolute TTL with explicit clocks, exact cookie headers";
  categories: ["web", "network"];
  keywords: ["session", "cookie", "auth", "ttl"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.session"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
