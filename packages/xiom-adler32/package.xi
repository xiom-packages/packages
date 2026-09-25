// XIOM -- xiom.adler32 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string (for the
// hex display helper); the tests use xiom.test, xiom.io, xiom.string and
// xiom.string.compare.

package xiom_adler32 {
  name: "xiom.adler32";
  version: "0.1.0";
  description: "Adler-32 checksum with one-shot, incremental and hex-display APIs";
  categories: ["data"];
  keywords: ["adler32", "checksum", "zlib", "integrity"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.adler32"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
