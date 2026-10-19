// XIOM -- xiom.micropython package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Host-side MicroPython raw-REPL protocol client. Pure XIOM: the package
// owns the wire framing (Ctrl-A / Ctrl-B / Ctrl-C, code + Ctrl-D, OK +
// stdout/stderr EOF frames) and never opens a transport. Consumers write
// the returned frames to any byte link (UART, USB CDC, socket) and feed
// received bytes back into the decoder/session helpers.
//
// Upstream reference (reference-only, nothing vendored):
// micropython/micropython @ b70ae1aca657bb93e2857dac4e2a2d21a3803200,
// MIT. See PROVENANCE.md and SPEC.md.

package xiom_micropython {
  name: "xiom.micropython";
  version: "0.1.0";
  description: "Host-side MicroPython raw-REPL protocol client: enter (Ctrl-A), friendly exit (Ctrl-B), interrupt (Ctrl-C), exec framing (code + Ctrl-D, OK acknowledgement, stdout/stderr EOF frames), traceback pass-through, eval helpers and typed errors; transport-agnostic pure XIOM";
  categories: ["systems", "tooling"];
  keywords: ["micropython", "repl", "raw-repl", "mcu", "uart", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.micropython"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
