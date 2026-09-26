// XIOM -- xiom.mp3 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string.builder,
// xiom.string.compare and xiom.convert from it; the tests add xiom.test,
// xiom.io and xiom.encoding.hex.

package xiom_mp3 {
  name: "xiom.mp3";
  version: "0.1.0";
  description: "MP3 structural parser: MPEG-1/2/2.5 frame headers, stream scan and ID3v1/v2 tags (no audio decoding)";
  categories: ["media"];
  keywords: ["mp3", "mpeg", "audio", "id3", "metadata", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mp3"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
