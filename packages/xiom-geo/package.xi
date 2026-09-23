// XIOM -- xiom.geo package manifest
// Port task: promote the xiom.geo placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_geo {
  name: "xiom.geo";
  version: "0.1.0";
  description: "Geohash encoding/decoding and latitude/longitude helpers";
  categories: ["science","data"];
  keywords: ["geohash","geo","coordinates","spatial"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.geo"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
