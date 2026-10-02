// XIOM -- xiom.terraform package manifest
// Port task: promote the xiom.terraform placeholder to a real, tested,
// pure-XIOM package (infrastructure-as-code workflow model: HCL subset
// parser, execution plan graph with diffs, apply/destroy state machine,
// state model and provider registry; no network, no real providers).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test and xiom.io.

package xiom_terraform {
  name: "xiom.terraform";
  version: "0.1.0";
  description: "Pure infrastructure-as-code workflow model: HCL subset parser, execution plan graph with diffs, apply/destroy state machine with revisions, state and provider registry";
  categories: ["systems"];
  keywords: ["terraform", "hcl", "iac", "plan", "apply", "state", "provider", "graph"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.terraform"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
