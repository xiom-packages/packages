// XIOM -- xiom.finance package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module itself imports nothing; the tests use
// xiom.test and xiom.io from it.

package xiom_finance {
  name: "xiom.finance";
  version: "0.1.0";
  description: "Integer time-value-of-money: interest, annuities, NPV, doubling time";
  categories: ["data", "finance"];
  keywords: ["finance", "interest", "annuity", "npv"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.finance"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
