// XIOM -- xiom.fuzz package manifest
// Port task: promote the xiom.fuzz placeholder to a real, tested, pure-XIOM package.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.compare.

package xiom_fuzz {
  name: "xiom.fuzz";
  version: "0.1.0";
  description: "Deterministic byte and string mutation for fuzzing";
  categories: ["tooling","testing"];
  keywords: ["fuzz","mutation","testing","bytes"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.fuzz"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
