// XIOM -- xiom.webp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.convert and
// xiom.string.builder from it; the tests add xiom.test/xiom.io/
// xiom.string/xiom.string.compare.

package xiom_webp {
  name: "xiom.webp";
  version: "0.1.0";
  description: "WebP (RIFF) container parser: header, chunk stream, padding, VP8/VP8L/VP8X/ALPH/ANIM/ANMF/ICCP/EXIF/XMP validation";
  categories: ["graphics"];
  keywords: ["webp", "riff", "image", "container", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.webp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
