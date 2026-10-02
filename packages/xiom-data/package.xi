// XIOM -- xiom.data package manifest
// Port task: promote the xiom.data placeholder to a real, tested, pure-XIOM
// package: dataset container and iterators, deterministic LCG shuffling,
// samplers, a batched loader, batch assembly/collation and train/validation/
// test splitting over parallel integer vectors (no floats, no FFI, no
// Vec[Float64], no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it (decimal
// rendering for the canonical batch/split dumps); the tests additionally use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_data {
  name: "xiom.data";
  version: "0.1.0";
  description: "Pure deterministic integer dataset utilities: dataset container with iterators, deterministic LCG Fisher-Yates shuffling, sequential/shuffled/weighted samplers, a batched data loader, batch assembly/collation and train/validation/test splitting";
  categories: ["data", "ai-ml"];
  keywords: ["dataset", "loader", "batched", "sampler", "shuffle", "batch", "collate", "split", "train-test-split", "lcg", "deterministic", "integer"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.data", "xiom.data.batch", "xiom.data.order"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
