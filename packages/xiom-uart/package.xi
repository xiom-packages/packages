// XIOM -- xiom.uart package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing (no `use` at
// all); the tests use xiom.test, xiom.io and xiom.string.compare from it.

package xiom_uart {
  name: "xiom.uart";
  version: "0.1.3";
  description: "UART line codec: framing bits, parity, framing errors and baud divisors";
  categories: ["systems"];
  keywords: ["uart", "serial", "baud", "framing"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.uart"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
