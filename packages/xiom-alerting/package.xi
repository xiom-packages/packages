// XIOM -- xiom.alerting package manifest
// Port task: replace the xiom.alerting placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// tests use xiom.test and xiom.io.

package xiom_alerting {
  name: "xiom.alerting";
  version: "0.1.0";
  description: "Threshold alert rules with breach streaks, firing state, and transition counts";
  categories: ["tooling","core"];
  keywords: ["alerting","threshold","monitoring","state"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.alerting"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
