// XIOM -- xiom.cidr package manifest
// Port task: create the greenfield xiom.cidr package (pure XIOM, no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string and xiom.convert
// from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.compare.

package xiom_cidr {
  name: "xiom.cidr";
  version: "0.1.0";
  description: "IPv4 addresses and CIDR blocks: parse, format, containment, and range math (addresses as 32-bit Ints)";
  categories: ["networking", "data"];
  keywords: ["cidr", "ipv4", "subnet", "networking"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cidr"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
