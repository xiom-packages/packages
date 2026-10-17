// XIOM -- xiom.cufft package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Loader-only binding: the NVIDIA cuFFT runtime is USER-SUPPLIED at run
// time and nothing from NVIDIA is vendored or linked.  xiom.std is the
// standard library (a platform dependency, outside the install closure).

package xiom_cufft {
  name: "xiom.cufft";
  version: "0.1.0";
  description: "NVIDIA cuFFT bindings for XIOM (runtime-loaded cufft64_12/11/10.dll; user-supplied CUDA FFT runtime, nothing vendored): 1D/2D plans, destroy, setStream, version, plan-size estimates, R2C/C2R/C2C/D2Z/Z2D/Z2Z execution, typed SKIP/error classification, driver-side device-memory helpers"
  categories: ["ai-ml", "science"];
  keywords: ["cufft", "cuda", "nvidia", "fft", "fourier", "dsp", "gpu", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.cufft"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
