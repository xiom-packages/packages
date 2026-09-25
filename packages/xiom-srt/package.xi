// XIOM -- xiom.srt package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_srt {
  name: "xiom.srt";
  version: "0.1.0";
  description: "SubRip (SRT) subtitle parsing, canonical formatting, and accessors";
  categories: ["media"];
  keywords: ["srt", "subrip", "subtitles", "captions"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.srt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
