// XIOM -- xiom.pdf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare, xiom.convert,
// xiom.compress.zlib and xiom.compress.deflate from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_pdf {
  name: "xiom.pdf";
  version: "0.1.2";
  description: "PDF document structure parser: objects, xref tables/streams, trailers and page tree";
  categories: ["data"];
  keywords: ["pdf", "parser", "document", "xref", "structure"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pdf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
