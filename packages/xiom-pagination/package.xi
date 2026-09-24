// XIOM -- xiom.pagination package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports xiom.string, xiom.string.builder and
// xiom.convert from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_pagination {
  name: "xiom.pagination";
  version: "0.1.0";
  description: "Page and offset math plus opaque cursor tokens for list endpoints";
  categories: ["data","tooling"];
  keywords: ["pagination","page","offset","cursor"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pagination"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
