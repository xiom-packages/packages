// XIOM -- xiom.avi package manifest
// Port task: replace the xiom.avi placeholder with a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_avi {
  name: "xiom.avi";
  version: "0.1.0";
  description: "RIFF/AVI structure: chunk walking and the main AVI header (avih)";
  categories: ["data","media"];
  keywords: ["avi","riff","video","container"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.avi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
