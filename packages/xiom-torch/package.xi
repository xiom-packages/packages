// XIOM -- Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_torch {
  name: "xiom.torch";
  version: "0.1.0";
  description: "LibTorch bindings for XIOM -- tensor types, neural-network building blocks with a real linear forward, and a multi-soname libtorch runtime tier (AOTI C ABI; typed SKIP when absent)";
  categories: ["ai-ml"];
  keywords: ["torch", "pytorch", "inference", "tensors", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
  modules: [
    "xiom.torch.types",
    "xiom.torch.nn",
    "xiom.torch.runtime",
  ];
}
