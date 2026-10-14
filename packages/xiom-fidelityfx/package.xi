// XIOM -- AMD FidelityFX SDK Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_fidelityfx {
  name: "xiom.fidelityfx";
  version: "0.1.0";
  description: "AMD FidelityFX SDK v2.3.0 surface bindings for XIOM: unified API loader (FSR2 / FSR3 upscaler / frame generation), FSR1 EASU+RCAS and SPD CPU constant helpers, vendored compiled swapchain shader blobs, provider version probes; typed SKIP when no effect DLL is present";
  categories: ["graphics"];
  keywords: ["fidelityfx", "fsr", "fsr2", "fsr3", "upscaler", "frame-generation", "spd", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.fidelityfx", "xiom.fidelityfx.gen_types", "xiom.fidelityfx.gen_structs", "xiom.fidelityfx.gen_surface"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
