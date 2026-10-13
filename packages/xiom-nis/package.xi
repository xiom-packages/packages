// XIOM -- xiom.nis package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports nothing outside the
// stdlib builtins; the tests use xiom.io, xiom.test and xiom.string.

package xiom_nis {
  name: "xiom.nis";
  version: "0.1.0";
  description: "NVIDIA Image Scaling (NIS) SDK v1.0.3 bindings (vendored MIT core, byte-exact): 100% of the CPU-visible config surface -- NVScaler/NVSharpen config builders, NISOptimizer dispatch geometry, coefficient tables (f32/fp16) -- over XIOM-owned buffers; GPU pixel path is a typed SKIP (compute-shader-only in v1.0.3)";
  categories: ["graphics"];
  keywords: ["nis", "image-scaling", "upscale", "sharpen", "nvidia", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.nis"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
