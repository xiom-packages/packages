// XIOM -- xiom.edl package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module imports xiom.string, xiom.string.builder,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_edl {
  name: "xiom.edl";
  version: "0.1.0";
  description: "CMX EDL parsing and canonical emitting for a documented subset";
  categories: ["media"];
  keywords: ["edl", "cmx", "video", "editing"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.edl"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
