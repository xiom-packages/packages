// XIOM -- xiom.memcached package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests use
// xiom.test, xiom.io and xiom.encoding.hex.

package xiom_memcached {
  name: "xiom.memcached";
  version: "0.1.3";
  description: "Pure-XIOM memcached text and binary protocol codec (no sockets)";
  categories: ["network"];
  keywords: ["memcached", "cache", "protocol", "codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.memcached"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
