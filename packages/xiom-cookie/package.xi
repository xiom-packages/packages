// XIOM -- xiom.cookie package manifest
// Port task: create the greenfield xiom.cookie package (pure XIOM, no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_cookie {
  name: "xiom.cookie";
  version: "0.1.0";
  description: "Cookie and Set-Cookie header parsing and serialization";
  categories: ["networking", "text"];
  keywords: ["cookie", "http", "header", "parsing"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cookie"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
