// XIOM -- xiom.smartcontract package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare, xiom.convert and xiom.serialize.endian from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_smartcontract {
  name: "xiom.smartcontract";
  version: "0.1.0";
  description: "Deterministic pure-XIOM stack VM for a documented contract bytecode subset, with assembler, disassembler, gas metering and traces";
  categories: ["systems", "network"];
  keywords: ["vm", "bytecode", "smart-contract", "interpreter", "assembler", "gas"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.smartcontract"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
