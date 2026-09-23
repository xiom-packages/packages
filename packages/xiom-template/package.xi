// XIOM -- xiom.template package manifest
// Port task: replace the xiom.template placeholder with a real, tested,
// documented, pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_template {
  name: "xiom.template";
  version: "0.1.0";
  description: "Mustache-style template rendering with strict and lenient key handling";
  categories: ["text", "tooling"];
  keywords: ["template", "mustache", "render", "text"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.template"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
