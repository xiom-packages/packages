// XIOM -- xiom.crc package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test, xiom.io and xiom.string.

package xiom_crc {
  name: "xiom.crc";
  version: "0.1.0";
  description: "Parameterized CRC-8/16/32 with named presets and known-answer vectors";
  categories: ["data", "tooling"];
  keywords: ["crc", "checksum", "error-detection", "hash"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.crc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
