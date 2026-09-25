// XIOM -- xiom.ass package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_ass {
  name: "xiom.ass";
  version: "0.1.0";
  description: "ASS/SSA subtitle parsing, canonical formatting, and accessors";
  categories: ["media"];
  keywords: ["ass", "ssa", "subtitles", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ass"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
