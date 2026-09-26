// XIOM -- xiom.hid package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Port task: greenfield pure-XIOM implementation (no FFI) of the xiom.hid
// placeholder.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free (no stdlib
// imports); the tests use xiom.test, xiom.io, xiom.string.compare and
// xiom.encoding.hex from it.

package xiom_hid {
  name: "xiom.hid";
  version: "0.1.0";
  description: "USB HID report-descriptor parsing, validation and canonical emission";
  categories: ["systems"];
  keywords: ["hid", "usb", "descriptor", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.hid"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
