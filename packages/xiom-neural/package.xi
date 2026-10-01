// XIOM -- xiom.neural package manifest
// Port task: promote the xiom.neural placeholder to a real, tested, pure-XIOM
// package (deterministic fixed-point MLP inference on scaled integers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (byte scanning and
// comparison) and xiom.convert (decimal rendering for the dump); the tests
// additionally use xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_neural {
  name: "xiom.neural";
  version: "0.1.0";
  description: "Deterministic fixed-point MLP inference over scaled integers (1e-4): dense layers, relu/leaky/sigmoid/tanh/linear activations, guarded dot products, requantization, softmax, argmax prediction, parameter counts and a canonical text dump";
  categories: ["ai-ml", "data"];
  keywords: ["neural-network", "mlp", "inference", "fixed-point", "softmax", "activation", "deterministic"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.neural"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
