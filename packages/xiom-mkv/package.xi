// XIOM -- xiom.mkv package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string.builder,
// xiom.string.compare and xiom.utf8 from it; the tests use xiom.test,
// xiom.io and xiom.string.compare.

package xiom_mkv {
  name: "xiom.mkv";
  version: "0.1.0";
  description: "Matroska/WebM (EBML) container reader: VINT decoding, EBML header, Info, Tracks and Cluster spans";
  categories: ["data", "media"];
  keywords: ["mkv", "matroska", "webm", "ebml", "container"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mkv"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
