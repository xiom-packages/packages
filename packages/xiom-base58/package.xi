// XIOM -- xiom.base58 package manifest
// Port task: new greenfield pure-XIOM Base58 (Bitcoin alphabet) codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_base58 {
  name: "xiom.base58";
  version: "0.1.0";
  description: "Base58 (Bitcoin alphabet) encoding and decoding with leading-zero handling";
  categories: ["data"];
  keywords: ["base58","bitcoin","encoding","codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.base58"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
