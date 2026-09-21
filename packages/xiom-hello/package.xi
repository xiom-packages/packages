// XIOM -- xiom.hello package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The tests use xiom.test/xiom.io from it; the library module
// itself imports nothing.

package xiom_hello {
  name: "xiom.hello";
  version: "0.1.0";
  description: "Minimal XIOM package -- the canonical first-publish example";
  categories: ["tooling"];
  keywords: ["example", "template", "hello", "getting-started"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.hello"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
