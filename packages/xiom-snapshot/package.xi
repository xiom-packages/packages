// XIOM -- xiom.snapshot package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert.int from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_snapshot {
  name: "xiom.snapshot";
  version: "0.1.0";
  description: "Snapshot comparison helpers: normalization, line equality, and first-difference summaries";
  categories: ["tooling", "testing"];
  keywords: ["snapshot", "golden", "testing", "diff"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.snapshot"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
