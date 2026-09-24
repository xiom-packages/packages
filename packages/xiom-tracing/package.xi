// XIOM -- xiom.tracing package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports nothing from it; the
// tests use xiom.test, xiom.io and xiom.string.compare.

package xiom_tracing {
  name: "xiom.tracing";
  version: "0.1.0";
  description: "In-memory span trees: explicit-clock spans, durations, children, and self time";
  categories: ["tooling","core"];
  keywords: ["tracing","spans","timing","observability"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tracing"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
