// XIOM -- xiom.zigbee package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free (no `use`
// at all); the tests use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_zigbee {
  name: "xiom.zigbee";
  version: "0.1.0";
  description: "ZigBee link-layer structure codec: IEEE 802.15.4 MAC, ZigBee NWK and APS header parsing";
  categories: ["protocol"];
  keywords: ["zigbee", "802.15.4", "mac", "nwk", "aps", "wireless"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.zigbee"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
