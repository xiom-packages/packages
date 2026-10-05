// XIOM -- xiom.rate package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (part of xiom.std)
// for byte-wise key comparison; the tests use xiom.test and xiom.io.

package xiom_rate {
  name: "xiom.rate";
  version: "0.2.0";
  description: "Deterministic rate limiters with explicit clocks: token bucket, fixed window, and keyed multi-client layers";
  categories: ["core", "network"];
  keywords: ["rate-limit", "token-bucket", "throttle", "quota", "keyed"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.rate"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
