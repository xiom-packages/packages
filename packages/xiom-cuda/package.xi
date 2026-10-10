// XIOM -- CUDA Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_cuda {
  name: "xiom.cuda";
  version: "0.2.0";
  description: "NVIDIA CUDA driver-API bindings for XIOM (runtime-loaded nvcuda.dll; nothing vendored)"
  categories: ["ai-ml", "science"];
  keywords: ["cuda", "gpu", "nvidia", "compute", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
