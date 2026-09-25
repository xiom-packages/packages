// XIOM -- xiom.iban package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module itself uses
// xiom.string / xiom.string.compare / xiom.convert from it.

package xiom_iban {
  name: "xiom.iban";
  version: "0.1.0";
  description: "IBAN parsing, validation, formatting and MOD-97 check-digit computation";
  categories: ["data"];
  keywords: ["iban", "finance", "validation", "banking"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.iban"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
