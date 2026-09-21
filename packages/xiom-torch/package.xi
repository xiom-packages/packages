// XIOM -- Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_torch {
  name: "xiom.torch";
  version: "0.1.0";
  description: "LibTorch bindings for XIOM -- PyTorch C++ inference";
  categories: ["ai-ml"];
  keywords: ["torch", "pytorch", "inference", "tensors"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": "0.1.0" };
  modules: [
    "xiom.torch.types",
    "xiom.torch.ffi",
    "xiom.torch.nn",
  ];
}
