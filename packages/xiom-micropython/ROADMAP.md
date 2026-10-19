# xiom.micropython -- ROADMAP

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

## 0.1.0 -- shipped (this wave)

- Raw-REPL control bytes: Ctrl-A enter, Ctrl-B friendly exit, Ctrl-C
  interrupt, Ctrl-D exec/soft reset.
- Exec framing: command + `0x04`, `OK` + stdout + `0x04` + stderr + `0x04`
  + `>`; `consumed` accounting for transport buffering.
- Soft-reset reply recognition (`OK\r\n`, no EOT pair).
- Eval helpers: `print(EXPR)` and `print(repr(EXPR))`, typed value
  extraction and traceback pass-through errors.
- Line framing (`mp_lines`, `mp_output_lines`, `mp_error_lines`).
- Fixture-driven byte-trace suite, transport-agnostic core, SKIP-safe
  absent-transport leg.

## 0.2.0 -- planned

- **Raw-paste mode.** Ctrl-E / `05 41 01`, `R\x01`, the little-endian
  window increment and flow-control accounting, including the `R\x00`
  fallback and the legacy `raw REPL; CTRL-B to exit` discard path.
- **Transport adapters.** A UART/USB-CDC adapter (thin wrapper over
  `xiom.serial` or a platform handle), a TCP adapter for networked boards,
  and a process-pipe adapter for unix-port/CI. Adapters stay separate from
  the core module and take a deadline so the byte layer remains pure.
- **Incremental parser.** A resumable `MpSession` that accepts partial
  chunks and emits frames, instead of requiring a complete trace.
- **Prompt configuration.** `mp_parse_exit_with_prompt(trace, prompt)` for
  boards that override `sys.ps1`/`sys.ps2`.
- **File transfer helpers.** Pyboard-compatible `fs_list/fs_stat/fs_cat/
  fs_write/fs_read` command builders on top of exec/eval (no new wire
  protocol).

## 0.3.0 -- candidate

- **Soft-reset orchestration and boot capture.** Explicit `OK\r\n` +
  boot-banner collection with a deadline, so CI can wait for a known prompt
  after reset.
- **Exception envelope (opt-in).** Parse the leading `Traceback` line and
  the final `Type: message` line into typed fields while keeping the full
  text; do not classify by default.
- **Fleet helpers.** Probe several transports for a raw prompt, identify
  boards by `sys.implementation` / `os.uname()` eval, and route commands.
- **Publish readiness.** Registry scope for `xiom.micropython`, allowlist
  entry and staging canary (see README publish checklist in the repository).

## Later / ideas

- WebREPL (WebSocket) adapter, kept out of the core.
- Raw-paste throughput benchmark and window tuning guidance.
- Frozen-module / mpy deployment helpers.
- Hardware-in-the-loop matrix (ESP32, RP2040, STM32, unix port) behind the
  same byte-trace contract.
