// XIOM -- xiom.dac package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert (decimal
// formatting for error messages); the tests use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_dac {
  name: "xiom.dac";
  version: "0.1.2";
  description: "DAC command and register codecs: MCP4725/MCP4728 I2C frames, MCP4921/MCP4922 SPI frames and integer code-to-microvolt scaling";
  categories: ["science", "systems"];
  keywords: ["dac", "analog", "mcp4725", "mcp4728", "mcp4921", "mcp4922", "i2c", "spi", "embedded"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.dac"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
