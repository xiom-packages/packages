// XIOM -- xiom.consul package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.string.builder from it; the tests use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_consul {
  name: "xiom.consul";
  version: "0.1.0";
  description: "Pure-XIOM Consul protocol model: KV store with CAS and monotonic indexes, service/check registry, TTL health transitions, session lifecycle with lock behavior, and the ACL rules subset (no HTTP, no agent, no network)";
  categories: ["systems"];
  keywords: ["consul", "kv", "service-registry", "health", "session", "acl", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.consul"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
