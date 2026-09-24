// XIOM -- xiom.signal package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports only xiom.convert and
// xiom.math from it (scalar Float64 math, no FFI); the tests use xiom.test
// and xiom.io from the same dependency.

package xiom_signal {
  name: "xiom.signal";
  version: "0.1.0";
  description: "Integer-friendly window functions, convolution, and moving extrema for signals";
  categories: ["science","data"];
  keywords: ["signal","window","convolution","smoothing"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.signal"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
