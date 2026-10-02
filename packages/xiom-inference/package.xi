// XIOM -- xiom.inference package manifest
// Port task: promote the xiom.inference placeholder to a real, tested,
// pure-XIOM package: deterministic fixed-point forward execution over a
// parallel-vector model descriptor (1e-4 scale), a high-level predict API,
// batched and streaming inference, per-tensor shift quantization with a
// documented error bound, and lossless text/binary dump codecs.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (byte scanning)
// and xiom.convert (decimal rendering for the text dump); the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_inference {
  name: "xiom.inference";
  version: "0.1.0";
  description: "Deterministic fixed-point inference over a parallel-vector model descriptor: dense and activation layers with precomputed weight offsets, forward pass, softmax and argmax predict, batched and streaming inference, per-tensor shift quantization with a documented error bound, and lossless text/binary dump codecs";
  categories: ["ai-ml", "data"];
  keywords: ["inference", "forward", "predict", "batch", "streaming", "quantization", "fixed-point", "export", "deterministic"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.inference"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
