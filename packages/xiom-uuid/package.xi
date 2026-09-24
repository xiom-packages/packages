// XIOM -- xiom.uuid package manifest
// Port task: create the xiom.uuid package (deterministic UUID tooling; the
// caller supplies the randomness for v4 construction).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module imports xiom.string and xiom.string.builder from it;
// the tests additionally use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex.

package xiom_uuid {
  name: "xiom.uuid";
  version: "0.1.0";
  description: "UUID formatting, parsing, validation, and v4 construction from caller-supplied randomness";
  categories: ["data","tooling"];
  keywords: ["uuid","identifier","format","v4"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.uuid"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
