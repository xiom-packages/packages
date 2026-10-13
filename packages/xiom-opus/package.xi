// XIOM -- xiom.opus package manifest
// Vendored libopus v1.6.1 bindings (streaming audio codec: encoder,
// decoder, repacketizer, multistream, Opus Custom, projection/ambisonics,
// DRED entry points, packet utilities).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the platform standard library (excluded from the registry
// install closure); the library modules import nothing from it, the tests
// use xiom.test, xiom.io, xiom.string.compare and xiom.math.

package xiom_opus {
  name: "xiom.opus";
  version: "0.1.0";
  description: "libopus v1.6.1 bindings for XIOM (vendored build: encoder/decoder, repacketizer, multistream, custom modes, projection, DRED entry points; 105/105 public functions bound)";
  categories: ["media"];
  keywords: ["opus", "audio", "codec", "streaming", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.opus", "xiom.opus.abi", "xiom.opus.ffi", "xiom.opus.types"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
