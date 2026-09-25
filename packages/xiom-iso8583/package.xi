// XIOM -- xiom.iso8583 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module uses xiom.string and
// xiom.string.builder; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare from it. No FFI, no other dependencies.

package xiom_iso8583 {
  name: "xiom.iso8583";
  version: "0.1.0";
  description: "ISO 8583 ASCII message codec for a documented field subset";
  categories: ["data"];
  keywords: ["iso8583", "payments", "wire", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.iso8583"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
