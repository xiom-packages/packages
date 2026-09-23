// XIOM -- xiom.bson package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_bson {
  name: "xiom.bson";
  version: "0.1.0";
  description: "BSON document encoding and decoding (subset without doubles)";
  categories: ["data"];
  keywords: ["bson", "serialization", "binary", "codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.bson"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
