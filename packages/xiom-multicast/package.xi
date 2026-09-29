// XIOM -- xiom.multicast package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself is dependency-free
// beyond the stdlib; the tests use xiom.io, xiom.test, xiom.string,
// xiom.string.compare, xiom.encoding.hex and xiom.convert from it.

package xiom_multicast {
  name: "xiom.multicast";
  version: "0.1.1";
  description: "IGMPv2/v3 and MLD/MLDv2 multicast group management codecs";
  categories: ["network"];
  keywords: ["multicast", "igmp", "mld", "wire", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.multicast"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
