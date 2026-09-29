// XIOM -- xiom.executor package manifest
// Port task: promote the xiom.executor placeholder to a real, tested,
// pure-XIOM package (task execution engine as a deterministic state machine).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_executor {
  name: "xiom.executor";
  version: "0.1.1";
  description: "Task execution engine as a deterministic state machine (ready queue, futures, continuations)";
  categories: ["concurrency", "systems"];
  keywords: ["executor", "scheduler", "futures", "continuations", "ready-queue"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.executor"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
