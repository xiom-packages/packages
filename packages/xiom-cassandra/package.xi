// XIOM -- xiom.cassandra package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test, xiom.io and xiom.encoding.hex.

package xiom_cassandra {
  name: "xiom.cassandra";
  version: "0.1.1";
  description: "Apache Cassandra CQL native protocol v4 frame structure codec (headers, primitives, STARTUP/QUERY/RESULT/ERROR bodies; no network, no compression)";
  categories: ["network"];
  keywords: ["cassandra", "cql", "wire", "binary", "codec", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cassandra"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
