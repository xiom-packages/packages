// XIOM -- xiom.avro package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_avro {
  name: "xiom.avro";
  version: "0.1.0";
  description: "Strict pure-XIOM Avro 1.11 binary primitive codecs and Object Container File header parser";
  categories: ["data"];
  keywords: ["avro", "binary", "encoding", "format", "ocf"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.avro"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
