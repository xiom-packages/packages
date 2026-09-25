// XIOM -- xiom.osrelease package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// os-release (/etc/os-release, systemd spec) parsing and canonical emitting.
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_osrelease {
  name: "xiom.osrelease";
  version: "0.1.0";
  description: "systemd os-release (/etc/os-release) parsing and canonical emitting";
  categories: ["systems"];
  keywords: ["os-release", "systemd", "config", "linux"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.osrelease"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
