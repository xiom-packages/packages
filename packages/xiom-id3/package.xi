// XIOM -- xiom.id3 package manifest
// Port task: replace the xiom.id3 placeholder with a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string.builder and
// xiom.string.compare from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.

package xiom_id3 {
  name: "xiom.id3";
  version: "0.1.0";
  description: "ID3v2 tag inspection: version, size, and text frames (TIT2/TPE1/TALB/...)";
  categories: ["data","media"];
  keywords: ["id3","metadata","mp3","tags"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.id3"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
