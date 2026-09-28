// XIOM -- xiom.perf package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert.int (for
// decimal byte offsets in error messages); the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_perf {
  name: "xiom.perf";
  version: "0.1.0";
  description: "Pure-XIOM Linux perf.data structure parser: header, attrs, event records and feature sections";
  categories: ["systems", "data"];
  keywords: ["perf", "perf.data", "linux", "tracing", "profiling", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.perf"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
