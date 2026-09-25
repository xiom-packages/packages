// XIOM -- xiom.tzif package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free; the tests
// use xiom.test, xiom.io, xiom.string, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_tzif {
  name: "xiom.tzif";
  version: "0.1.0";
  description: "TZif time zone file codec for RFC 8536 versions 1/2/3 with a version 1 builder";
  categories: ["data"];
  keywords: ["tzif", "timezone", "binary", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tzif"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
