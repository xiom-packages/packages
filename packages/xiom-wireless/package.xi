// XIOM -- xiom.wireless package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module is dependency-free (no `use`
// at all); the tests use xiom.test, xiom.io and xiom.string.compare from it.

package xiom_wireless {
  name: "xiom.wireless";
  version: "0.1.1";
  description: "IEEE 802.11 MAC frame structure parser: frame control, addressing matrix, sequence/QoS control, management bodies, information element walk";
  categories: ["network"];
  keywords: ["wifi", "802.11", "mac", "frame", "information-element"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.wireless"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
