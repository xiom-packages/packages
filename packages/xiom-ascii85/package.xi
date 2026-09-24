// XIOM -- xiom.ascii85 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Adobe ASCII85 (Base85): the PostScript/PDF text encoding that maps every
// 4-byte group to 5 characters of the '!'..'u' alphabet (with 'z' for an
// all-zero group). xiom.std is the standard library: a platform dependency,
// excluded from the registry install closure. The module imports xiom.string
// and xiom.string.builder from it; the tests additionally use xiom.test,
// xiom.io, xiom.string, xiom.string.compare and xiom.encoding.hex.

package xiom_ascii85 {
  name: "xiom.ascii85";
  version: "0.1.0";
  description: "Adobe ASCII85 (Base85) encoding and decoding";
  categories: ["data"];
  keywords: ["ascii85","base85","adobe","encoding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ascii85"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
