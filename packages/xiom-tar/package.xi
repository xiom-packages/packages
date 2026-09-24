// XIOM -- xiom.tar package manifest
// Port task: replace the xiom.tar placeholder with a real, tested, pure-XIOM
// POSIX ustar archive codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (byte_at and
// str_concat) from it; the tests additionally use xiom.test, xiom.io,
// xiom.string.compare and xiom.encoding.hex.

package xiom_tar {
  name: "xiom.tar";
  version: "0.1.0";
  description: "POSIX ustar archive codec: parse and build uncompressed tar files";
  categories: ["data","tooling"];
  keywords: ["tar","ustar","archive","codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tar"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
