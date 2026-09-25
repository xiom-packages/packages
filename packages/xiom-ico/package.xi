// XIOM -- xiom.ico package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test/xiom.io from it.

package xiom_ico {
  name: "xiom.ico";
  version: "0.1.0";
  description: "ICO/CUR icon container codec: directory parse, payload slices, canonical builder";
  categories: ["graphics"];
  keywords: ["ico", "cursor", "icon", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ico"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
