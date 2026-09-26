// XIOM -- xiom.thrift package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_thrift {
  name: "xiom.thrift";
  version: "0.1.0";
  description: "Apache Thrift binary protocol codec (message headers, fields, primitives, containers, skip)";
  categories: ["data"];
  keywords: ["thrift", "binary", "serialization", "codec", "rpc"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.thrift"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
