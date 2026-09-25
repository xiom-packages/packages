// XIOM -- xiom.nii package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield pure-XIOM NIfTI-1 header codec (no FFI).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.convert and xiom.encoding.hex from it; the tests
// additionally use xiom.io and xiom.test. No FFI blocks are declared.

package xiom_nii {
  name: "xiom.nii";
  version: "0.1.0";
  description: "Pure-XIOM NIfTI-1 header codec: 348-byte parse, validation and builder";
  categories: ["science"];
  keywords: ["nifti", "neuroimaging", "header", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.nii"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
