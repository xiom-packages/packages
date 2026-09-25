// XIOM -- xiom.zonefile package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_zonefile {
  name: "xiom.zonefile";
  version: "0.1.0";
  description: "DNS zone-file (master file) codec subset: $ORIGIN/$TTL, relative names, flat records and a canonical emitter";
  categories: ["network"];
  keywords: ["dns", "zone", "master-file", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.zonefile"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
