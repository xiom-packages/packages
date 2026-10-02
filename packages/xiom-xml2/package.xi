// XIOM -- xiom.xml2 package manifest
// Port task: replace the xiom.xml2 placeholder with a complete, tested,
// pure-XIOM XML module (no FFI, no libxml2): parser subset, DOM tree over
// parallel vectors, serializer, namespace handling and an XPath-LITE
// evaluator.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests use
// xiom.test and xiom.io in addition.
//
// No FFI, no libxml2, no external files: everything is implemented in XIOM.

package xiom_xml2 {
  name: "xiom.xml2";
  version: "0.1.0";
  description: "Pure-XIOM XML module: parser subset, DOM tree (parallel vectors), serializer, namespaces and XPath-LITE (no FFI, no libxml2)";
  categories: ["text-nlp"];
  keywords: ["xml", "parser", "dom", "serializer", "namespaces", "xpath"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.xml2"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
