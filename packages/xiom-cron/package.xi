// XIOM -- xiom.cron package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_cron {
  name: "xiom.cron";
  version: "0.1.0";
  description: "Classic 5-field cron expression parser, validator and canonical emitter";
  categories: ["tooling"];
  keywords: ["cron", "schedule", "parser", "expression"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cron"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
