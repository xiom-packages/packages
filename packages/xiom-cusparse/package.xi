// XIOM -- xiom.cusparse package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Loader-only binding: the NVIDIA cuSPARSE runtime is USER-SUPPLIED at run
// time and nothing from NVIDIA is vendored or linked.  xiom.std is the
// standard library (a platform dependency, outside the install closure).

package xiom_cusparse {
  name: "xiom.cusparse";
  version: "0.1.0";
  description: "NVIDIA cuSPARSE bindings for XIOM (runtime-loaded cusparse64_13/12/11/10.dll; user-supplied CUDA sparse runtime, nothing vendored): handle lifecycle, setStream, version, legacy mat descriptor, CSR/dense descriptors, SpMV (f32/f64) and SpMM (f64) with buffer-size query + external buffer, typed SKIP/error classification, driver-side device-memory helpers"
  categories: ["ai-ml", "science"];
  keywords: ["cusparse", "cuda", "nvidia", "sparse", "spmv", "spmm", "csr", "gpu", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.cusparse"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
