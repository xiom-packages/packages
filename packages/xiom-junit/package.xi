// XIOM -- xiom.junit package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module imports xiom.string, xiom.string.builder and
// xiom.string.compare from it; the tests also use xiom.test and xiom.io.

package xiom_junit {
  name: "xiom.junit";
  version: "0.1.0";
  description: "Pure-XIOM JUnit XML report codec for a documented subset (parse, access, emit)";
  categories: ["testing"];
  keywords: ["junit", "xml", "testing", "report"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.junit"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
