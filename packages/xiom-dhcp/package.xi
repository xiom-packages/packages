// XIOM -- xiom.dhcp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free; the tests
// use xiom.io, xiom.test, xiom.string, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_dhcp {
  name: "xiom.dhcp";
  version: "0.1.0";
  description: "DHCPv4 packet codec: BOOTP fixed header, magic cookie and options TLV";
  categories: ["network"];
  keywords: ["dhcp", "bootp", "wire", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.dhcp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
