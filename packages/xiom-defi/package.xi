// XIOM -- xiom.defi package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports only xiom.core for INT_MAX; the
// tests use xiom.test and xiom.io from it.

package xiom_defi {
  name: "xiom.defi";
  version: "0.1.0";
  description: "Integer constant-product AMM and share-index lending pool models";
  categories: ["data"];
  keywords: ["defi", "amm", "lending", "liquidity", "fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.defi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
