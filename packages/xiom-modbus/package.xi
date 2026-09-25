// XIOM -- xiom.modbus package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test, xiom.io, xiom.string, xiom.string.compare and xiom.encoding.hex.

package xiom_modbus {
  name: "xiom.modbus";
  version: "0.1.0";
  description: "Modbus RTU/TCP frame codec with CRC-16/Modbus and MBAP validation";
  categories: ["protocol"];
  keywords: ["modbus", "rtu", "tcp", "industrial"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.modbus"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
