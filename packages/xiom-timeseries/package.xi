// XIOM -- xiom.timeseries package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports nothing; the tests use
// xiom.test and xiom.io from it.

package xiom_timeseries {
  name: "xiom.timeseries";
  version: "0.1.0";
  description: "Moving averages, deltas, and range statistics over integer series";
  categories: ["data"];
  keywords: ["timeseries", "moving-average", "statistics", "data"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.timeseries"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
