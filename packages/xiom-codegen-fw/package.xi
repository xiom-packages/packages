// XIOM -- xiom.codegen-fw package manifest
// Port task: promote the xiom.codegen-fw placeholder to a real, tested,
// pure-XIOM package (a deterministic code-generation framework: scoped
// symbol tables, label allocation with rollback, an opcode/operand IR model,
// an indenting text emitter, a peephole window rewriter and a module text
// renderer).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string.compare and
// xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_codegen_fw {
  name: "xiom.codegen-fw";
  version: "0.1.0";
  description: "Code-generation framework: scoped symbol tables, rollback-safe label allocator, opcode/operand IR, indenting emitter, peephole rewriter, module renderer";
  categories: ["tooling"];
  keywords: ["codegen", "compiler", "ir", "peephole", "emitter", "framework"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.codegen_fw"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
