// XIOM -- xiom.validation package manifest
// Port task: create the greenfield xiom.validation package (pure XIOM, no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_validation {
  name: "xiom.validation";
  version: "0.1.0";
  description: "Format validators: email, IPv4/IPv6, hex, UUID, slug, dates, ports";
  categories: ["text", "safety"];
  keywords: ["validation", "email", "ipv6", "uuid", "slug"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.validation"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
