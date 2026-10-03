// XIOM -- xiom.mongo package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports nothing; the tests use
// xiom.test, xiom.io, xiom.string and xiom.encoding.hex from it.

package xiom_mongo {
  name: "xiom.mongo";
  version: "0.1.3";
  description: "Pure-XIOM MongoDB BSON document walker and wire-message framing codec (no queries, no driver)";
  categories: ["network"];
  keywords: ["mongodb", "bson", "wire", "protocol", "codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mongo"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
