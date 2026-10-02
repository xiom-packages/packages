// XIOM -- xiom.i2c package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free (no `use`
// at all); the tests use xiom.test, xiom.io, xiom.string,
// xiom.string.compare and xiom.encoding.hex from it.

package xiom_i2c {
  name: "xiom.i2c";
  version: "0.1.3";
  description: "I2C/SMBus codec: 7-bit and 10-bit addressing, typed bus events and SMBus PEC";
  categories: ["systems"];
  keywords: ["i2c", "smbus", "bus", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.i2c"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
