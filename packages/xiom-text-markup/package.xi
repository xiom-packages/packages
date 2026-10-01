// XIOM -- xiom.text-markup package manifest
// Port task: promote the xiom.text-markup placeholder to a real, tested,
// pure-XIOM package (a deterministic BBCode-style markup codec: parse with
// proper nesting validation, span records over the source, plain-text
// rendering and canonical re-serialization).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_text_markup {
  name: "xiom.text-markup";
  version: "0.1.0";
  description: "BBCode-style inline markup codec: parse with nesting validation, span records, plain-text render, canonical re-serialization";
  categories: ["text"];
  keywords: ["markup", "bbcode", "parse", "render", "span", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.text_markup"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
