// XIOM -- xiom.docx package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from
// the registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.convert, xiom.compress.deflate and
// xiom.compress.gzip from it; the tests additionally use xiom.io,
// xiom.string.compare and xiom.convert.

package xiom_docx {
  name: "xiom.docx";
  version: "0.1.1";
  description: "Word OpenXML (.docx) reader/writer: a minimal ZIP container plus a WordprocessingML paragraph/run/style subset";
  categories: ["text-nlp"];
  keywords: ["docx", "word", "openxml", "office", "document", "zip"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.docx"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
