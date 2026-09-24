// XIOM -- xiom.envsubst package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Shell-style ${VAR} expansion with caller-supplied variables and strict or
// lenient missing-value handling. Greenfield package: pure XIOM, no FFI, no
// environment access -- the variable table is entirely caller-supplied.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_envsubst {
  name: "xiom.envsubst";
  version: "0.1.0";
  description: "Shell-style ${VAR} expansion with caller-supplied variables and strict or lenient missing-value handling";
  categories: ["text", "tooling"];
  keywords: ["envsubst", "variables", "expansion", "template"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.envsubst"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
