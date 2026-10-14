// XIOM -- xiom.rtxgi Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_rtxgi {
  name: "xiom.rtxgi";
  version: "0.1.0";
  description: "NVIDIA RTXGI-DDGI integration surface for XIOM -- reference-only dynamic-loader binding. Upstream (github.com/NVIDIAGameWorks/RTXGI-DDGI, tag v1.3.7) is NOT MIT as expected: it ships the proprietary NVIDIA RTX SDKs License, so no RTXGI code, headers, shaders or binaries ship here (NRD/FFmpeg precedent, PROVENANCE.md); the suite exercises a locally built shim DLL and classifies SKIP when absent.";
  categories: ["graphics"];
  keywords: ["rtxgi", "ddgi", "global-illumination", "probes", "nvidia", "reference-only", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.rtxgi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
