// XIOM -- xiom.wasm package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module imports xiom.string.builder from it; the tests
// additionally use xiom.test, xiom.io, xiom.string, xiom.string.compare and
// xiom.encoding.hex.

package xiom_wasm {
  name: "xiom.wasm";
  version: "0.1.0";
  description: "WebAssembly binary module structure: LEB128, section walk, export names";
  categories: ["data", "tooling"];
  keywords: ["wasm", "webassembly", "leb128", "binary"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.wasm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
