// XIOM -- xiom.metrics package manifest
// Port task: replace the xiom.metrics placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// tests use xiom.test and xiom.io.

package xiom_metrics {
  name: "xiom.metrics";
  version: "0.1.0";
  description: "Counters, gauges, and histograms for in-process metrics";
  categories: ["core","tooling"];
  keywords: ["metrics","histogram","counter","gauge"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.metrics"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
