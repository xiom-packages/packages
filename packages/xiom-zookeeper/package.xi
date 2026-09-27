// XIOM -- xiom.zookeeper package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test, xiom.io and xiom.encoding.hex.

package xiom_zookeeper {
  name: "xiom.zookeeper";
  version: "0.1.0";
  description: "Apache ZooKeeper jute wire-format structure codec (primitives, connect handshake, headers, opcodes, Stat/ACL/watch events, request and response records)";
  categories: ["data"];
  keywords: ["zookeeper", "jute", "serialization", "codec", "coordination"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.zookeeper"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
