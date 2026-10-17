// XIOM -- Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_tensorflow {
  name: "xiom.tensorflow";
  version: "0.1.0";
  description: "TensorFlow C API (libtensorflow) bindings -- graph, session, tensor, ops essentials behind a multi-soname loader";
  categories: ["ai-ml"];
  keywords: ["tensorflow", "ml", "inference", "tensors"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
  modules: [
    "xiom.tensorflow.types",
    "xiom.tensorflow.loader",
    "xiom.tensorflow.tensor",
    "xiom.tensorflow.graph",
    "xiom.tensorflow.session",
    "xiom.tensorflow.ops",
  ];
}
