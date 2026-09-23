// XIOM -- xiom.markdown package manifest
// Port task: promote the xiom.markdown placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_markdown {
  name: "xiom.markdown";
  version: "0.1.0";
  description: "Markdown subset to HTML renderer";
  categories: ["text"];
  keywords: ["markdown", "html", "render", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.markdown"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
