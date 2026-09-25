// XIOM -- xiom.bencode package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_bencode {
  name: "xiom.bencode";
  version: "0.1.0";
  description: "Strict pure-XIOM bencode codec with flat token storage and canonical encoding";
  categories: ["data"];
  keywords: ["bencode", "bittorrent", "encoding", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.bencode"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
