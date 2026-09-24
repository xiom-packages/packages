// XIOM -- xiom.varint package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports nothing; the tests use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex from it.

package xiom_varint {
  name: "xiom.varint";
  version: "0.1.0";
  description: "LEB128 unsigned varints and zigzag signed varints with size helpers";
  categories: ["data"];
  keywords: ["varint", "leb128", "zigzag", "encoding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.varint"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
