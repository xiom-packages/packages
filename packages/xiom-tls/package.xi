// XIOM -- xiom.tls package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert.int (error
// offset formatting) from it; the tests use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_tls {
  name: "xiom.tls";
  version: "0.1.0";
  description: "Pure-XIOM TLS record and handshake structure parser (no crypto)";
  categories: ["protocol"];
  keywords: ["tls", "handshake", "record", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tls"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
