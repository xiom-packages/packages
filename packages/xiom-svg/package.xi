// XIOM -- xiom.svg package manifest
// Port task: promote the xiom.svg placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.compare.

package xiom_svg {
  name: "xiom.svg";
  version: "0.1.0";
  description: "SVG document builder with element helpers and escaping";
  categories: ["text", "graphics"];
  keywords: ["svg", "graphics", "markup", "builder"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.svg"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
