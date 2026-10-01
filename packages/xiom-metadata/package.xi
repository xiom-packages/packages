// XIOM -- xiom.metadata package manifest
// Port task: promote the xiom.metadata placeholder to a real, tested,
// pure-XIOM package (ordered metadata blocks with case-insensitive dotted
// keys, duplicate-key policies, scoping/nesting, merge with precedence and
// provenance, diff, canonical serialization + parse round-trip, validation
// catalog).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_metadata {
  name: "xiom.metadata";
  version: "0.1.0";
  description: "Ordered metadata blocks with case-insensitive dotted keys: duplicate-key policies, scoping and nesting, merge with precedence and provenance, diff, canonical serialization and parse round-trip";
  categories: ["data","tooling"];
  keywords: ["metadata","tags","blocks","merge","provenance","diff","serialization"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.metadata"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
