// XIOM -- xiom.git2 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert.int and
// xiom.string from it; the tests add xiom.test, xiom.io, xiom.string.compare
// and xiom.encoding.hex.

package xiom_git2 {
  name: "xiom.git2";
  version: "0.1.2";
  description: "Pure-XIOM Git object and pack-file codec: zlib/DEFLATE decoder, loose objects, tree/commit/tag headers, pack entries with OFS/REF deltas, pack index v2";
  categories: ["systems"];
  keywords: ["git", "binary", "format", "deflate", "zlib"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.git2"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
