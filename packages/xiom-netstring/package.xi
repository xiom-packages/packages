// XIOM -- xiom.netstring package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module is dependency-free; the tests use
// xiom.test, xiom.io, xiom.string, xiom.string.compare and xiom.encoding.hex
// from it.

package xiom_netstring {
  name: "xiom.netstring";
  version: "0.1.0";
  description: "DJB netstring framing: streaming parse, build and cursor iteration over <len>:<payload>, byte streams";
  categories: ["data"];
  keywords: ["netstring", "encoding", "wire", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.netstring"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
