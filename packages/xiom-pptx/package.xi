// XIOM -- xiom.pptx package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare, xiom.string.builder, xiom.convert,
// xiom.compress.deflate and xiom.compress.gzip from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.

package xiom_pptx {
  name: "xiom.pptx";
  version: "0.1.0";
  description: "PowerPoint PresentationML reader/writer: minimal ZIP container, slide/shape model and text-box shape tree";
  categories: ["data"];
  keywords: ["pptx", "powerpoint", "presentationml", "ooxml", "zip", "slides", "deflate"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pptx"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
