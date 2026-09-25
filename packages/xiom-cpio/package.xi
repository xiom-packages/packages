// XIOM -- xiom.cpio package manifest
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.cpio placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string (byte_at);
// the tests additionally use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex.

package xiom_cpio {
  name: "xiom.cpio";
  version: "0.1.0";
  description: "Cpio archive header codec: parse and build newc and odc entries";
  categories: ["data"];
  keywords: ["cpio", "archive", "format", "unix"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cpio"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
