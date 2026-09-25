// XIOM -- xiom.systemd package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The module imports xiom.string, xiom.string.builder and
// xiom.string.compare from it; the tests additionally use xiom.test and
// xiom.io.

package xiom_systemd {
  name: "xiom.systemd";
  version: "0.1.0";
  description: "systemd unit-file parsing and emitting for in-memory Str documents";
  categories: ["systems"];
  keywords: ["systemd", "unit", "config", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.systemd"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
