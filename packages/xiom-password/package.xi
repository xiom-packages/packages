// XIOM -- xiom.password package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_password {
  name: "xiom.password";
  version: "0.1.0";
  description: "Password strength scoring and structural checks (no crypto, no dictionaries)";
  categories: ["safety", "text"];
  keywords: ["password", "strength", "security", "score"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.password"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
