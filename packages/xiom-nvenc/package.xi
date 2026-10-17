// XIOM -- NVIDIA NVENC + NVDEC bindings manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_nvenc {
  name: "xiom.nvenc";
  version: "0.1.0";
  description: "NVIDIA hardware video encode (NVENC) + decode (NVDEC/cuvid) bindings for XIOM (runtime-loaded nvEncodeAPI64.dll + nvcuvid.dll via nvcuda.dll; nothing vendored)"
  categories: ["media", "graphics"];
  keywords: ["nvidia", "nvenc", "nvdec", "cuvid", "video", "encode", "decode", "h264", "hevc", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.nvenc"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
