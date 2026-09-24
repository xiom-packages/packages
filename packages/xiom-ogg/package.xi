// XIOM -- xiom.ogg package manifest
// Port task: replace the xiom.ogg placeholder with a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing from it; the
// tests use xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_ogg {
  name: "xiom.ogg";
  version: "0.1.0";
  description: "Ogg page structure: page walk, fields, and the Ogg CRC-32 checksum";
  categories: ["data","media"];
  keywords: ["ogg","page","crc32","container"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ogg"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
