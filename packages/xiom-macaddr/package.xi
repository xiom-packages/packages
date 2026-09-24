// XIOM -- xiom.macaddr package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.string and
// xiom.string.builder; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_macaddr {
  name: "xiom.macaddr";
  version: "0.1.0";
  description: "MAC-48 address parsing, formatting, and flag helpers (48-bit values as Int)";
  categories: ["networking", "data"];
  keywords: ["mac", "ethernet", "address", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.macaddr"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
