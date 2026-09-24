// XIOM -- xiom.tlv package manifest
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.tlv placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free; the tests
// use xiom.test, xiom.io, xiom.string, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_tlv {
  name: "xiom.tlv";
  version: "0.1.0";
  description: "Generic big-endian TLV parsing and building with configurable tag/length widths";
  categories: ["data"];
  keywords: ["tlv", "encoding", "binary", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tlv"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
