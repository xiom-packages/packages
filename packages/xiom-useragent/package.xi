// XIOM -- xiom.useragent package manifest
// Port task: create the greenfield xiom.useragent package (pure XIOM, no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_useragent {
  name: "xiom.useragent";
  version: "0.1.0";
  description: "User-Agent heuristics: browser, version, OS, bot and mobile detection";
  categories: ["networking", "text"];
  keywords: ["user-agent", "browser", "detection", "http"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.useragent"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
