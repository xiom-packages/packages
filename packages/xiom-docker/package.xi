// XIOM -- xiom.docker package manifest
// Port task: promote the xiom.docker placeholder to a real, tested,
// pure-XIOM package (Docker container lifecycle as a deterministic
// management model; no FFI, no HTTP, no sockets, no daemon).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The modules import xiom.string from it; the
// tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_docker {
  name: "xiom.docker";
  version: "0.1.0";
  description: "Deterministic Docker lifecycle management model: image reference parsing, layer chains, container state machine, registry push/pull plans, compose dependency graphs, volumes and networks";
  categories: ["systems"];
  keywords: ["docker", "container", "image", "registry", "compose", "volume", "network", "state-machine"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.docker", "xiom.docker.image", "xiom.docker.registry", "xiom.docker.compose", "xiom.docker.resources"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
