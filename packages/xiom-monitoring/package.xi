// XIOM -- xiom.monitoring package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare, xiom.convert.int and xiom.math.constants from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_monitoring {
  name: "xiom.monitoring";
  version: "0.1.0";
  description: "Prometheus/OpenMetrics text exposition format parser";
  categories: ["data", "tooling"];
  keywords: ["prometheus", "openmetrics", "metrics", "parser", "exposition"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.monitoring"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
