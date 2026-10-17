// XIOM -- NVIDIA NVAPI bindings manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_nvapi {
  name: "xiom.nvapi";
  version: "0.1.0";
  description: "NVIDIA NVAPI presence/identity/telemetry bindings for XIOM (runtime-loaded nvapi64.dll via nvapi_QueryInterface; interface + driver versions, physical GPU enumeration, GPU 0 identity, temperature, utilization; nothing vendored)"
  categories: ["systems", "graphics"];
  keywords: ["nvidia", "nvapi", "gpu", "telemetry", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.nvapi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
