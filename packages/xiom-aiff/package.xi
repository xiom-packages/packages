// XIOM -- xiom.aiff package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string.builder
// (byte construction) and xiom.string (byte access) from it; the tests add
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_aiff {
  name: "xiom.aiff";
  version: "0.1.0";
  description: "AIFF/AIFF-C container header codec: FORM/COMM/SSND chunks, 80-bit sample rate, chunk index";
  categories: ["media"];
  keywords: ["aiff", "audio", "container", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.aiff"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
