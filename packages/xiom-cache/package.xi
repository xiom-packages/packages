// XIOM -- xiom.cache package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_cache {
  name: "xiom.cache";
  version: "0.1.2";
  description: "Deterministic in-memory cache eviction structures over Int keys and values: LRU, LFU, CLOCK and TTL";
  categories: ["data"];
  keywords: ["cache", "lru", "lfu", "clock", "ttl", "eviction", "deterministic"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cache"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
