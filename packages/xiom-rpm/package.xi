// XIOM -- xiom.rpm package manifest
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.rpm placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string; the tests
// additionally use xiom.test, xiom.io, xiom.string, xiom.string.compare and
// xiom.encoding.hex.

package xiom_rpm {
  name: "xiom.rpm";
  version: "0.1.0";
  description: "RPM package lead and header parser: tags, types and metadata lookups";
  categories: ["systems", "data"];
  keywords: ["rpm", "package", "redhat", "linux", "header", "lead"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.rpm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
