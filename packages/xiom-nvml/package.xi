// XIOM -- NVIDIA NVML (Management Library) bindings manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_nvml {
  name: "xiom.nvml";
  version: "0.1.0";
  description: "NVIDIA NVML telemetry bindings for XIOM (runtime-loaded nvml.dll; driver version, device identity, memory, utilization, temperature, power, clocks, fan, PCIe, energy; nothing vendored)"
  categories: ["systems", "observability"];
  keywords: ["nvidia", "nvml", "gpu", "telemetry", "monitoring", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.nvml"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}


