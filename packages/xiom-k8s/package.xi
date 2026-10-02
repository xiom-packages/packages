// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.k8s package manifest
// Port task: promote the xiom.k8s placeholder to a real, tested, pure-XIOM
// package: Kubernetes orchestration as a deterministic in-memory model.
// No API server, no networking, no file I/O, no FFI.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The modules import xiom.string; the tests
// additionally use xiom.test and xiom.io.

package xiom_k8s {
  name: "xiom.k8s";
  version: "0.1.0";
  description: "Pure-XIOM Kubernetes orchestration model: Pod/Deployment/Service/ConfigMap/Namespace objects, pod phase machine, rolling-update replica math, service endpoints, ingress exposure, config/secret scoping and namespace quota accounting";
  categories: ["systems"];
  keywords: ["kubernetes", "k8s", "pod", "deployment", "service", "ingress", "configmap", "namespace", "scheduler", "state-machine"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.k8s", "xiom.k8s.selector", "xiom.k8s.rolling"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
