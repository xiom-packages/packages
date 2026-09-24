// XIOM -- xiom.rbac package manifest
// Port task: replace the xiom.rbac placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.string.compare
// (byte-exact Str equality) and xiom.string.builder (rule text assembly); the
// tests additionally use xiom.test and xiom.io.

package xiom_rbac {
  name: "xiom.rbac";
  version: "0.1.0";
  description: "Role-based access rules with wildcard matching and deny-override";
  categories: ["safety","tooling"];
  keywords: ["rbac","permissions","roles","access"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.rbac"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
