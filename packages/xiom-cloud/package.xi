// XIOM -- xiom.cloud package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports only xiom.string,
// xiom.string.compare and xiom.convert; it is a pure descriptor registry (no
// SDK bindings, no FFI, no network, no file I/O).

package xiom_cloud {
  name: "xiom.cloud";
  version: "0.1.0";
  description: "Pure-XIOM cloud provider/orchestration descriptor registry: provider, capability, region/zone and vendor tables plus a resolution and compatibility API; no SDK bindings, no FFI, no network";
  categories: ["systems"];
  keywords: ["cloud", "provider", "orchestration", "registry", "descriptor", "vendor", "region"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cloud"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
