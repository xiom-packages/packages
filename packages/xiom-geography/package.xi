// XIOM -- xiom.geography package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module uses
// xiom.string, xiom.string.compare and xiom.convert from it; the tests
// additionally use xiom.io and xiom.test.

package xiom_geography {
  name: "xiom.geography";
  version: "0.1.1";
  description: "ISO 3166-1 country table, UN M49 regions, ISO 3166-2 subdivision syntax, and integer coordinate text codecs";
  categories: ["data", "science"];
  keywords: ["geography", "iso3166", "m49", "countries", "coordinates", "dms"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.geography"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
