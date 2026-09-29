// XIOM -- xiom.charts package manifest
// Port task: promote the xiom.charts placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_charts {
  name: "xiom.charts";
  version: "0.1.0";
  description: "Deterministic integer line and bar charts emitted as SVG";
  categories: ["graphics", "text"];
  keywords: ["charts", "svg", "plot", "bar-chart", "line-chart", "visualization"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.charts"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
