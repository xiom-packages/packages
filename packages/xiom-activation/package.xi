// XIOM -- xiom.activation package manifest
// Port task: promote the xiom.activation placeholder to a real, tested,
// pure-XIOM package (fixed-point activation functions and derivatives over
// integer data; no floats, no FFI, no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests use
// xiom.test, xiom.io, xiom.string and xiom.string.compare from it.

package xiom_activation {
  name: "xiom.activation";
  version: "0.1.0";
  description: "Fixed-point activation functions and derivatives (scale 1e-4): relu, leaky relu (slope bps), elu (alpha bps), sigmoid, tanh, softmax with an exact 10000 sum, documented integer approximations, saturation and overflow guards";
  categories: ["ai-ml", "data"];
  keywords: ["activation", "relu", "leaky-relu", "elu", "sigmoid", "tanh", "softmax", "fixed-point", "derivative"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.activation"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
