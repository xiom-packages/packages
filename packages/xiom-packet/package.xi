// XIOM -- xiom.packet package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test, xiom.io, xiom.string, xiom.string.compare and xiom.encoding.hex.

package xiom_packet {
  name: "xiom.packet";
  version: "0.1.0";
  description: "Length-prefixed packet framing with CRC-32 validation";
  categories: ["data", "networking"];
  keywords: ["packet", "framing", "crc32", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.packet"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
