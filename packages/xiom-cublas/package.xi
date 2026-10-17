// XIOM -- xiom.cublas package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Loader-only binding: the NVIDIA cuBLAS runtime is USER-SUPPLIED at run
// time and nothing from NVIDIA is vendored or linked.  xiom.std is the
// standard library (a platform dependency, outside the install closure).

package xiom_cublas {
  name: "xiom.cublas";
  version: "0.1.0";
  description: "NVIDIA cuBLAS bindings for XIOM (runtime-loaded cublas64_13/12/11/10.dll; user-supplied CUDA math runtime, nothing vendored): handle lifecycle, setStream, version, sgemm/dgemm, axpy/dot/scal/nrm2, gemv, typed SKIP/error classification, driver-side device-memory helpers"
  categories: ["ai-ml", "science"];
  keywords: ["cublas", "cuda", "nvidia", "blas", "linear-algebra", "gpu", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.cublas"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
