// XIOM -- xiom.optimizer-fw package manifest
// Port task: promote the xiom.optimizer-fw placeholder to a real, tested,
// pure-XIOM package (a deterministic optimization framework over integer
// objective records: sample tables and explicit value lists, grid search,
// first/best-improvement hill climbing, LCG simulated annealing with a
// fixed-point cooling schedule, random restarts, shared stopping rules and
// convergence traces).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports nothing; the tests use xiom.test,
// xiom.io and xiom.string.compare from it.

package xiom_optimizer_fw {
  name: "xiom.optimizer-fw";
  version: "0.1.0";
  description: "Deterministic optimization framework over integer objective records: grid search, first/best-improvement hill climbing, LCG simulated annealing, random restarts, stopping rules and convergence traces";
  categories: ["science", "tooling"];
  keywords: ["optimizer", "framework", "hill-climb", "annealing", "search", "trace"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.optimizer_fw"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
