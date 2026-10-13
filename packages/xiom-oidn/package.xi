// XIOM -- xiom.oidn package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from
// the registry install closure.

package xiom_oidn {
  name: "xiom.oidn";
  version: "0.1.0";
  description: "Intel Open Image Denoise bindings for XIOM (runtime loader over the public C API of OIDN v2.5.1; CPU device: device/buffer/filter lifecycle, RT and RTLightmap filters with owned byte buffers)";
  categories: ["graphics"];
  keywords: ["oidn", "denoise", "rendering", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.oidn"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
