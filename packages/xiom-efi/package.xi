// XIOM -- xiom.efi package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.string (byte_at)
// from it; the tests use xiom.test, xiom.io, xiom.string,
// xiom.string.compare and xiom.encoding.hex. No FFI.

package xiom_efi {
  name: "xiom.efi";
  version: "0.1.0";
  description: "UEFI Firmware File System (FFS) file and section codec, documented subset";
  categories: ["systems"];
  keywords: ["uefi", "firmware", "ffs", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.efi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
