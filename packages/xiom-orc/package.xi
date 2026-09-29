// XIOM -- xiom.orc package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string.builder
// and xiom.convert from it; the tests additionally use xiom.test, xiom.io,
// xiom.string, xiom.string.builder, xiom.string.compare and xiom.convert.

package xiom_orc {
  name: "xiom.orc";
  version: "0.1.1";
  description: "Apache ORC file metadata codec: postscript, protobuf footer, stripes and type tree";
  categories: ["data"];
  keywords: ["orc", "apache", "format", "metadata", "columnar"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.orc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
