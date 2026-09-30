// XIOM -- xiom.discovery package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare and xiom.string.join from it; the tests use
// xiom.test, xiom.io, xiom.string.builder and xiom.string.compare.

package xiom_discovery {
  name: "xiom.discovery";
  version: "0.1.0";
  description: "Deterministic service-discovery registry: TTL heartbeats, health states, tag lookups, caller-seeded weighted selection and change watches";
  categories: ["network"];
  keywords: ["service-discovery", "registry", "ttl", "heartbeat", "weighted-selection", "watch"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.discovery"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
