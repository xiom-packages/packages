// XIOM -- xiom.midi package manifest
// Port task: replace the xiom.midi placeholder with a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module itself imports nothing; the
// tests use xiom.test, xiom.io, xiom.string and xiom.string.compare from it.

package xiom_midi {
  name: "xiom.midi";
  version: "0.1.0";
  description: "Standard MIDI File structure: header, track chunks, variable-length quantities, event counts";
  categories: ["data","media"];
  keywords: ["midi","music","binary","events"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.midi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
