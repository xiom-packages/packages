// XIOM -- cuDNN Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_cudnn {
  name: "xiom.cudnn";
  version: "0.1.0";
  modules: ["xiom.cudnn"];
  description: "NVIDIA cuDNN bindings (user-supplied runtime, nothing vendored): version, handles, 4D tensor/filter/convolution/activation/pooling descriptors, convolution forward, ReLU, max pooling, softmax, and a known-shape conv+ReLU live probe; SKIP-safe multi-soname loader (cudnn64_9.dll / cudnn64_8.dll)"
  categories: ["ai-ml", "science"];
  keywords: ["cudnn", "cuda", "nvidia", "deep-learning", "convolution", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
