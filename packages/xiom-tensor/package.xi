// XIOM -- xiom.tensor package manifest
// Port task: promote the xiom.tensor placeholder to a real, tested, pure-XIOM
// package: a deterministic n-dimensional integer tensor core over a flat
// Vec[Int] plus a shape (no floats, no FFI, no Vec[Float64], no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it (decimal
// rendering for the canonical tensor dump); the tests additionally use
// xiom.test, xiom.io, xiom.string and xiom.string.compare.

package xiom_tensor {
  name: "xiom.tensor";
  version: "0.1.0";
  description: "Pure deterministic n-dimensional integer tensor core: validated shape construction, row-major strides, coordinate and flat get/set, reshape, rank-2 transpose, axis-0 slicing with an offset map, broadcasting add, elementwise add/multiply, axis sum/max reductions and a canonical text dump";
  categories: ["ai-ml", "science"];
  keywords: ["tensor", "ndarray", "n-dimensional", "shape", "stride", "reshape", "transpose", "slice", "broadcast", "reduction", "integer"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.tensor"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
