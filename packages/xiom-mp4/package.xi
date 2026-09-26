// XIOM -- xiom.mp4 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_mp4 {
  name: "xiom.mp4";
  version: "0.1.0";
  description: "ISO BMFF / MP4 box parser: recursive tree walk, ftyp/mvhd/tkhd/mdhd/hdlr/stsd/elst/stco/co64/stsz metadata and fragment detection";
  categories: ["media"];
  keywords: ["mp4", "isobmff", "video", "container", "metadata", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mp4"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
