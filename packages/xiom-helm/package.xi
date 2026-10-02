// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.helm package manifest
// Port task: promote the xiom.helm placeholder to a real, tested, pure-XIOM
// package: chart manifests (Chart.yaml subset), release install/upgrade/
// rollback state machine, repository index subset, values deep-merge and a
// bounded Go-template-ish renderer. Pure model only: no Kubernetes API, no
// networking, no file I/O.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The modules import xiom.string, xiom.string.compare,
// xiom.convert and xiom.misc.semver from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_helm {
  name: "xiom.helm";
  version: "0.1.0";
  description: "Pure-XIOM Helm model: chart manifests, release state machine, repository index, values deep-merge and a bounded Go-template subset";
  categories: ["systems"];
  keywords: ["helm", "chart", "kubernetes", "release", "values", "template"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.helm", "xiom.helm.base", "xiom.helm.release", "xiom.helm.repo", "xiom.helm.tmpl"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
