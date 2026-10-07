// XIOM -- xiom.inline-asm package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test and xiom.io.
//
// Naming note: the package (manifest) name is "xiom.inline-asm" as required,
// but the compiler module name must be a dotted identifier (v0.61.3 rejects
// '-' in `module` declarations: error[P001]), so the module is
// xiom.inline.asm.

package xiom_inline_asm {
  name: "xiom.inline-asm";
  version: "0.1.2";
  description: "Inline-assembly template parser, operand constraint classes and clobber lists";
  categories: ["tooling"];
  keywords: ["asm", "inline-asm", "template", "parser", "constraints"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.inline.asm"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
