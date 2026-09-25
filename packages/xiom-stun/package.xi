// XIOM -- xiom.stun package manifest
// Port task: greenfield pure-XIOM port (no FFI) of a STUN wire codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The tests use xiom.test, xiom.io, xiom.string,
// xiom.string.compare and xiom.encoding.hex from it.

package xiom_stun {
  name: "xiom.stun";
  version: "0.1.0";
  description: "RFC 5389 STUN message codec: header, attributes and address XOR";
  categories: ["network"];
  keywords: ["stun", "nat", "wire", "network"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.stun"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
