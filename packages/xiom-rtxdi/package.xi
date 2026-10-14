// XIOM -- xiom.rtxdi Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_rtxdi {
  name: "xiom.rtxdi";
  version: "0.1.0";
  description: "NVIDIA RTXDI (ReSTIR DI integration runtime) for XIOM -- reference-only dynamic-loader binding. Upstream (github.com/NVIDIAGameWorks/RTXDI, tag v3.1.0, runtime library RTXDI-Library @ f12037fa) is NOT MIT as expected: it ships the proprietary NVIDIA RTX SDKs License, so no RTXDI code, headers, shaders or binaries ship here (NRD/FFmpeg precedent, PROVENANCE.md); the suite exercises a locally built shim DLL and classifies SKIP when absent.";
  categories: ["graphics"];
  keywords: ["rtxdi", "restir", "direct-illumination", "nvidia", "reference-only", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.rtxdi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
