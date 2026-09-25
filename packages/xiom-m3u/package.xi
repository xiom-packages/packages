// XIOM -- xiom.m3u package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module imports xiom.string, xiom.string.builder and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_m3u {
  name: "xiom.m3u";
  version: "0.1.0";
  description: "M3U/M3U8 playlist parsing and canonical emitting";
  categories: ["media"];
  keywords: ["m3u", "m3u8", "playlist", "hls"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.m3u"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
