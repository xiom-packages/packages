// XIOM -- xiom.eeprom package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert and
// xiom.string.compare from it; the tests use xiom.test, xiom.io,
// xiom.string.compare, xiom.convert and xiom.encoding.hex.

package xiom_eeprom {
  name: "xiom.eeprom";
  version: "0.1.0";
  description: "Serial EEPROM device protocol codecs: 24Cxx I2C and 93Cxx Microwire framing";
  categories: ["protocol"];
  keywords: ["eeprom", "i2c", "microwire", "24cxx", "93cxx", "serial", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.eeprom"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
