// XIOM -- xiom.toml package manifest
// Port task: replace the xiom.toml placeholder with a real, tested, pure-XIOM
// package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_toml {
  name: "xiom.toml";
  version: "0.1.0";
  description: "TOML v1.0 subset parser with dotted-path lookups";
  categories: ["data"];
  keywords: ["toml", "parser", "config", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.toml"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
