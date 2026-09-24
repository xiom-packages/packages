// XIOM -- xiom.term package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The tests use xiom.test/xiom.io from it; the library module
// imports xiom.string and xiom.string.builder only.

package xiom_term {
  name: "xiom.term";
  version: "0.1.0";
  description: "ANSI/VT escape handling: detect, strip, count, and visible-aware truncation";
  categories: ["text","tooling"];
  keywords: ["ansi","escape","terminal","vt100"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.term"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
