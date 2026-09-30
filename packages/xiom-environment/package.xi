// XIOM -- xiom.environment package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic environment-variable expansion: ${VAR} references with
// defaults, alternates and required messages, single/double-quoted spans, a
// nesting depth cap and a strict or lenient unknown-variable policy -- all
// against a caller-supplied variable table (no process-environment access).
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_environment {
  name: "xiom.environment";
  version: "0.1.0";
  description: "Deterministic environment-variable expansion: defaults, alternates, required messages, quoting, nesting and strict mode";
  categories: ["data", "tooling"];
  keywords: ["environment", "variables", "expansion", "config", "shell"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.environment"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
