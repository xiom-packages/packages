// XIOM -- xiom.safetensors package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_safetensors {
  name: "xiom.safetensors";
  version: "0.1.0";
  description: "Pure-XIOM safetensors container codec: header parse, validation and builder";
  categories: ["ai-ml"];
  keywords: ["safetensors", "tensors", "model", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.safetensors"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
