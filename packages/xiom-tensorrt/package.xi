// XIOM -- NVIDIA TensorRT package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// CLOSED-SDK / loader-only pattern: nothing from NVIDIA is vendored.  The
// package declares the pinned TensorRT 10.16 interface facts independently
// and resolves the user-supplied nvinfer_10.dll at runtime.

package xiom_tensorrt {
  name: "xiom.tensorrt";
  version: "0.1.0";
  description: "NVIDIA TensorRT 10.x bindings (loader-only; runtime user-supplied; nothing vendored): builder/runtime factories, logger plumbing, network definition basics, builder config, build+serialize/deserialize, execution context, tensor addresses, enqueueV3, version query; SKIP-safe when the runtime is absent";
  categories: ["ai-ml", "science"];
  keywords: ["tensorrt", "nvidia", "inference", "gpu", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.tensorrt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
