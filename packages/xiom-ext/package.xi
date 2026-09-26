// XIOM -- xiom.ext package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.ext placeholder.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.string and
// xiom.encoding.hex from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.compare.

package xiom_ext {
  name: "xiom.ext";
  version: "0.1.0";
  description: "ext2/3/4 superblock codec: parse and build the 1024-byte superblock at offset 1024";
  categories: ["systems"];
  keywords: ["ext4", "filesystem", "superblock", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ext"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
