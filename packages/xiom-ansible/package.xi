// XIOM -- xiom.ansible package manifest
// Port task: promote the xiom.ansible placeholder to a real, tested,
// pure-XIOM configuration-management model (inventory, playbook, module
// registry, facts, handlers and a deterministic executor -- no SSH/network).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.convert and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_ansible {
  name: "xiom.ansible";
  version: "0.1.0";
  description: "Configuration-management model: inventory, playbooks, module registry, typed facts, handlers and a deterministic executor";
  categories: ["systems"];
  keywords: ["ansible", "configuration-management", "playbook", "inventory", "orchestration"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ansible"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
