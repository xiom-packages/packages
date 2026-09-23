// XIOM -- xiom.wav package manifest
// Port task: replace the xiom.wav placeholder with a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string.builder from it;
// the tests additionally use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex.

package xiom_wav {
  name: "xiom.wav";
  version: "0.1.0";
  description: "Canonical PCM WAV (RIFF) header parsing, building, and metadata";
  categories: ["data","media"];
  keywords: ["wav","riff","audio","pcm"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.wav"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
