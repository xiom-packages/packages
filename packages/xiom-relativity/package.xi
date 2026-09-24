// XIOM -- xiom.relativity package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports only xiom.convert and
// xiom.math from it (scalar Float64 math and integer permille arithmetic, no
// FFI); the tests use xiom.test, xiom.io and xiom.math from the same
// dependency.

package xiom_relativity {
  name: "xiom.relativity";
  version: "0.1.0";
  description: "Special relativity scalar helpers: Lorentz factor, dilation, contraction, velocity addition";
  categories: ["science"];
  keywords: ["relativity","lorentz","physics","time-dilation"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.relativity"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
