// XIOM -- xiom.autoscale package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing from it; the
// tests use xiom.test, xiom.io and xiom.string.compare.

package xiom_autoscale {
  name: "xiom.autoscale";
  version: "0.1.0";
  description: "Deterministic autoscaling policy model: metric ring buffer, rolling-window thresholds with hysteresis, per-direction cooldowns, replica bounds and fixed/proportional steps";
  categories: ["data", "tooling"];
  keywords: ["autoscale", "autoscaling", "scaling-policy", "hysteresis", "cooldown", "replicas", "metrics"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.autoscale"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
