// XIOM -- xiom.nrd Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_nrd {
  name: "xiom.nrd";
  version: "0.1.0";
  description: "NVIDIA Real-time Denoisers (NRD) integration surface for XIOM -- reference-only dynamic-loader binding. Upstream (github.com/NVIDIA-RTX/NRD v4.17.3) is NOT MIT: it is the proprietary NVIDIA RTX SDKs License, so no NRD code, headers, shaders or binaries ship here (FFmpeg precedent, PROVENANCE.md); the suite exercises a locally built NRD.dll and classifies SKIP when absent.";
  categories: ["graphics"];
  keywords: ["nrd", "denoiser", "ray-tracing", "nvidia", "reference-only", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.nrd"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
