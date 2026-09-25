// XIOM -- xiom.can package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free (no `use`
// at all); the tests use xiom.test, xiom.io, xiom.string,
// xiom.string.compare and xiom.encoding.hex from it.

package xiom_can {
  name: "xiom.can";
  version: "0.1.0";
  description: "Classic CAN 2.0A/2.0B frame codec: identifiers, DLC, RTR and 16-byte containers";
  categories: ["protocol"];
  keywords: ["can", "bus", "automotive", "frame"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.can"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
