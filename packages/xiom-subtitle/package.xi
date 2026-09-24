// XIOM -- xiom.subtitle package manifest
// Port task: replace the xiom.subtitle placeholder with a pure-XIOM,
// tested SRT + WebVTT module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_subtitle {
  name: "xiom.subtitle";
  version: "0.1.0";
  description: "SRT and WebVTT subtitle parsing, formatting, and shifting";
  categories: ["text", "media"];
  keywords: ["subtitle", "srt", "vtt", "captions"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.subtitle"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
