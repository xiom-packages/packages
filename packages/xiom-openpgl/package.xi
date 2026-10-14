// XIOM -- xiom.openpgl Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_openpgl {
  name: "xiom.openpgl";
  version: "0.1.0";
  description: "Intel Open Path Guiding Library (Open PGL) v0.7.1 bindings: vendored C++ core (oneTBB runtime included), public C API subset -- sample storage, guiding field training, surface sampling distribution queries, field statistics";
  categories: ["graphics"];
  keywords: ["openpgl", "path-guiding", "rendering", "sampling", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.openpgl", "xiom.openpgl.ffi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
