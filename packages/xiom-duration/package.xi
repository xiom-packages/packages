// XIOM -- xiom.duration package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module itself uses
// xiom.string / xiom.string.compare / xiom.convert from it; the tests use
// xiom.test / xiom.io.

package xiom_duration {
  name: "xiom.duration";
  version: "0.1.0";
  description: "Strict ISO 8601 duration parsing and canonical formatting";
  categories: ["data"];
  keywords: ["duration", "iso8601", "time", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.duration"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
