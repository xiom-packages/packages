// XIOM - Steam Audio (Phonon) Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.phonon"
  version: "0.3.0"
  description: "Steam Audio (Phonon) bindings for XIOM via dynamic loader: full audio-processing surface (context/HRTF/audio buffers + 10 effect groups + ambisonics) generated from the pinned public phonon.h, SKIP when phonon.dll is absent";
  categories: ["media"];
  keywords: ["steam-audio", "spatial-audio", "3d-audio", "phonon", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.phonon", "xiom.phonon.abi", "xiom.phonon.exports"];
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
