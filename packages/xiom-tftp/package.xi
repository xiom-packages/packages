// XIOM -- xiom.tftp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_tftp {
  name: "xiom.tftp";
  version: "0.1.0";
  description: "Pure-XIOM TFTP packet codec (RFC 1350) with RFC 2347 option TLVs: RRQ, WRQ, DATA, ACK, ERROR, OACK";
  categories: ["network"];
  keywords: ["tftp", "protocol", "wire", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tftp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
