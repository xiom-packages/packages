// XIOM -- xiom.golden package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure-XIOM (no FFI, no filesystem I/O) golden-file
// comparison helpers: exact byte diff, normalized text diff, bounded line
// summaries, NUL-safe escape rendering, update-flag parsing and path
// conventions.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests
// additionally use xiom.test and xiom.io.

package xiom_golden {
  name: "xiom.golden";
  version: "0.1.0";
  description: "Golden-file comparison helpers: exact byte diff, CRLF-normalized text diff, bounded summaries, NUL-safe escaping and flag/path conventions";
  categories: ["testing"];
  keywords: ["golden", "snapshot", "testing", "diff", "compare"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.golden"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
