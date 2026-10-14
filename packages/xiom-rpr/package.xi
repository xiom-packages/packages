// XIOM -- xiom.rpr Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_rpr {
  name: "xiom.rpr";
  version: "0.1.0";
  description: "AMD Radeon ProRender SDK v3.1.7.1 core-API bindings (runtime DLL loader, no SDK binaries vendored; context/scene/camera/light/PBR material/mesh/framebuffer render + read-back)";
  categories: ["graphics"];
  keywords: ["rpr", "radeon-prorender", "prorender", "path-tracer", "render", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.rpr", "xiom.rpr.ffi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
