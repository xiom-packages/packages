// XIOM -- xiom.zstd package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing outside the
// stdlib builtins (its Str/int helpers are local); the tests use xiom.io,
// xiom.convert, xiom.test, xiom.string and xiom.string.compare.

package xiom_zstd {
  name: "xiom.zstd";
  version: "0.3.0";
  description: "Zstandard bindings for XIOM (vendored 1.5.7 single-file amalgamation, no system library) + ZSTC container framing with a random-access frame index (writer, reader, seek, append+finalize builder)";
  categories: ["data"];
  keywords: ["zstd", "compression", "streaming", "container", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.zstd"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
