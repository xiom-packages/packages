// XIOM -- xiom.humanize package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.convert from it;
// the tests additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_humanize {
  name: "xiom.humanize";
  version: "0.1.0";
  description: "Human-readable bytes, durations, counts, ordinals, and lists";
  categories: ["text", "tooling"];
  keywords: ["humanize", "format", "bytes", "duration"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.humanize"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
