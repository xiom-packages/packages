// XIOM -- xiom.actor package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.convert from it; the
// tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_actor {
  name: "xiom.actor";
  version: "0.1.0";
  description: "Deterministic actor-model scheduler: bounded mailboxes, priority scheduling, become, supervision, dead letters";
  categories: ["concurrency", "systems"];
  keywords: ["actor", "mailbox", "scheduler", "supervision", "dead-letter", "become"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.actor"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
