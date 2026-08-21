// XIOM -- Package Manifest
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_onnx {
  name: "xiom-onnx";
  version: "0.1.0";
  description: "ONNX Runtime bindings for XIOM -- cross-framework model inference";
  authors: ["XIOM Team"];
  deps: { "xiom-std": "0.1.0" };
  modules: [
    "xiom.onnx.types",
    "xiom.onnx.session",
    "xiom.onnx.io",
  ];
}
