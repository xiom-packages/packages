// XIOM -- stb codecs Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_stb {
  name: "xiom.stb";
  version: "0.3.0";
  description: "stb image codecs for XIOM (vendored stb_image + stb_image_write single headers; in-memory PNG encode/decode + BMP decode probe + the full HDR class surface: stbi_loadf family, stbi_is_hdr family, hdr/ldr conversion knobs)";
  categories: ["graphics", "media"];
  keywords: ["stb", "stb-image", "textures", "png", "image", "hdr", "radiance", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.stb"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
