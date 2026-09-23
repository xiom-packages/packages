// XIOM -- xiom.diff package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert.int from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_diff {
  name: "xiom.diff";
  version: "0.1.0";
  description: "Line diff with longest-common-subsequence edit scripts and unified diff output";
  categories: ["text", "tooling"];
  keywords: ["diff", "lcs", "unified", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.diff"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
