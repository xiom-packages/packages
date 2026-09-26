// XIOM -- xiom.cab package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.cab placeholder:
// a Microsoft Cabinet (CFHEADER/CFFOLDER/CFFILE) header and directory codec.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string (byte_at); the
// tests additionally use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex.

package xiom_cab {
  name: "xiom.cab";
  version: "0.1.0";
  description: "Microsoft Cabinet header and directory codec: parse and build CAB index structures";
  categories: ["systems"];
  keywords: ["cab", "cabinet", "archive", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cab"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
