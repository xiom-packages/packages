// XIOM -- xiom.analyzer package manifest
// Port task: promote the xiom.analyzer placeholder to a real, tested,
// pure-XIOM package -- a deterministic static-analysis framework over a
// caller-supplied instruction list (basic blocks, CFG, forward reachability,
// dominators with immediate dominators, register liveness with interference,
// and a text report). The IR is generic; there is no parser.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_analyzer {
  name: "xiom.analyzer";
  version: "0.1.0";
  description: "Deterministic static-analysis framework over a caller-supplied instruction list: basic blocks, CFG, reachability, dominators, register liveness, text report";
  categories: ["tooling", "testing"];
  keywords: ["static-analysis", "cfg", "basic-blocks", "dominators", "liveness", "dataflow", "conformance"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.analyzer"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
