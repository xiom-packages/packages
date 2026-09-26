// XIOM -- xiom.acpi package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.acpi placeholder.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string; the tests
// add xiom.test, xiom.io, xiom.string, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_acpi {
  name: "xiom.acpi";
  version: "0.1.0";
  description: "ACPI table-layer codec: RSDP, SDT headers and RSDT/XSDT table chains";
  categories: ["systems"];
  keywords: ["acpi", "firmware", "tables", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.acpi"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
