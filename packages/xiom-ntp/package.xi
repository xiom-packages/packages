// XIOM -- xiom.ntp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free; the tests
// use xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex from it.

package xiom_ntp {
  name: "xiom.ntp";
  version: "0.1.0";
  description: "Pure-XIOM NTPv4 packet codec (RFC 5905): 48-byte encode/decode, 32.32 timestamp math, offset/delay in microseconds";
  categories: ["network"];
  keywords: ["ntp", "time", "wire", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ntp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
