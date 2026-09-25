// XIOM -- xiom.miniseed package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string from it (byte_at,
// str_trim; Str::from_utf8 is a compiler builtin); the tests additionally use
// xiom.test, xiom.io and xiom.string.compare.

package xiom_miniseed {
  name: "xiom.miniseed";
  version: "0.1.0";
  description: "miniSEED fixed 48-byte record header codec: parse, validate and build";
  categories: ["science"];
  keywords: ["miniseed", "seismic", "records", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.miniseed"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
