// XIOM -- xiom.micropython package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from
// the registry install closure. The module imports xiom.string and
// xiom.string.builder from it; the tests add xiom.io, xiom.string.compare
// and xiom.encoding.hex.

package xiom_micropython {
  name: "xiom.micropython";
  version: "0.1.0";
  description: "Host-side MicroPython raw-REPL protocol client: control bytes, exec/eval framing, line pass-through; transport-agnostic";
  categories: ["embedded"];
  keywords: ["micropython", "repl", "serial", "embedded", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.micropython"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
