// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.training package manifest
// Port task: promote the xiom.training placeholder to a real, tested,
// pure-XIOM package: a fixed-point training toolkit (epoch/step loop driver
// with concrete callbacks, checkpoint capture/restore with a text codec,
// learning-rate schedules with warmup, early-stopping state and metric logs).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.split,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_training {
  name: "xiom.training";
  version: "0.1.0";
  description: "Fixed-point training toolkit: epoch/step loop driver with concrete callbacks, checkpoint save/restore, learning-rate schedules with warmup, early stopping and metric logs";
  categories: ["ai-ml", "science"];
  keywords: ["training", "trainer", "checkpoint", "scheduler", "warmup", "early-stopping", "metrics", "fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.training", "xiom.training.schedules", "xiom.training.earlystop", "xiom.training.logger", "xiom.training.checkpoint"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
