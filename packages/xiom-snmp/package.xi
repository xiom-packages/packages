// XIOM -- xiom.snmp package manifest
// Port task: greenfield pure-XIOM port (no FFI) of an ASN.1 BER + SNMP codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string.builder
// from it; the tests use xiom.test, xiom.io, xiom.string,
// xiom.string.compare and xiom.encoding.hex.

package xiom_snmp {
  name: "xiom.snmp";
  version: "0.1.0";
  description: "ASN.1 BER decoder plus SNMPv1/v2c message parser and minimal GetRequest/Response encoder (RFC 1157 / 3416 subset)";
  categories: ["network"];
  keywords: ["snmp", "ber", "asn1", "wire", "codec", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.snmp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
