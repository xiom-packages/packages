// XIOM -- xiom.flags package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_flags {
  name: "xiom.flags";
  version: "0.1.0";
  description: "Command-line flag and argument parsing with subcommand-friendly positionals and environment fallback";
  categories: ["tooling"];
  keywords: ["cli", "arguments", "flags", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.flags"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
