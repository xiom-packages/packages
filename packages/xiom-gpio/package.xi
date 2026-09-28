// XIOM -- xiom.gpio package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert,
// xiom.string and xiom.string.builder from it (error text and C string
// materialization); the tests also use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_gpio {
  name: "xiom.gpio";
  version: "0.1.1";
  description: "Linux GPIO character-device uAPI (v2) structure codec: chip info, line info, requests and events";
  categories: ["protocol"];
  keywords: ["gpio", "linux", "chardev", "uapi", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.gpio"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
