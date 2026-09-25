// XIOM -- xiom.smtlib package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_smtlib {
  name: "xiom.smtlib";
  version: "0.1.0";
  description: "SMT-LIB2 command/term parser and canonical emitter for a documented subset";
  categories: ["safety"];
  keywords: ["smtlib", "smt", "parser", "verification"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.smtlib"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
