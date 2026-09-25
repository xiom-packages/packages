// XIOM -- xiom.hl7 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_hl7 {
  name: "xiom.hl7";
  version: "0.1.0";
  description: "HL7 v2.x pipe-delimited message codec with flat offset-based storage";
  categories: ["data"];
  keywords: ["hl7", "healthcare", "protocol", "message"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.hl7"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
