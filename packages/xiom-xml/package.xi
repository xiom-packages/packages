// XIOM -- xiom.xml package manifest
// Port task: promote the xiom.xml placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.compare.

package xiom_xml {
  name: "xiom.xml";
  version: "0.1.0";
  description: "XML subset parser with a flat node model, queries, and escaping helpers";
  categories: ["data"];
  keywords: ["xml", "parser", "markup", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.xml"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
