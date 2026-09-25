// XIOM -- xiom.luhn package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module itself uses
// xiom.string and xiom.convert from it; the tests additionally use
// xiom.string.compare, xiom.test and xiom.io.

package xiom_luhn {
  name: "xiom.luhn";
  version: "0.1.0";
  description: "Luhn (mod-10) check-digit validation and computation for ASCII digit strings";
  categories: ["data"];
  keywords: ["luhn", "check-digit", "validation", "mod10"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.luhn"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
