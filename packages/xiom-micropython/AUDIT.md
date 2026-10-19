# xiom.micropython -- AUDIT

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

Compiler pin: **v0.64.7** (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`,
stdlib `E:\xiom-lang\stdlib` at the pin). Suite entry:
`.\scripts\port.ps1 -Package xiom.micropython -TimeoutSec 300`.

## 1. Suite evidence (x2, committed tree)

Run on commit `<pending>` (branch `feat/micropython`), both runs identical:

```
port: xiom.micropython
  dir:      packages\xiom-micropython
  compiler: 0.64.7 (repo-release)
  stdlib:   E:\xiom-lang\stdlib
namespace-check: stdlib E:\xiom-lang\stdlib (2006 module namespaces)
  xiom.micropython         OK (1 module(s))
namespace-check: 1 package(s), 1 module(s), 0 conflict(s)
  suite:    tests/test_conformance.xi
=== xiom.micropython conformance tests ===
  [PASS] fixtures: 9 byte-trace scripts load
  [PASS] requests: Ctrl-A/B/C/D and prompt constants byte-exact
  [PASS] exec-request: code + 0x04; empty code -> 0x04
  [PASS] exec-request-eot: embedded 0x04 -> MP_ERR_ARG
  [PASS] enter: banner + prompt parsed, leading CRLF optional, consumed exact
  [PASS] enter-errors: missing banner / prompt are framing errors
  [PASS] exit: default >>> prompt parsed; missing prompt framed as error
  [PASS] exec-ok: OK/output/EOT/EOT/prompt parsed; consumed exact; trailing bytes kept
  [PASS] exec-error: traceback passed through; exec_ok false; eval reports MP_ERR_EXEC
  [PASS] exec-interrupt: partial stdout + KeyboardInterrupt traceback preserved
  [PASS] exec-soft-reset: OK CRLF only; empty-output frame stays a normal exec
  [PASS] exec-errors: missing OK / stdout EOT / stderr EOT / prompt all framed
  [PASS] lines: CRLF normalization, interior blanks, trailing LF, traceback frames
  [PASS] payload-lines: stdout one line; stderr traceback kept as three lines
  [PASS] eval-requests: print(EXPR) / print(repr(EXPR)); empty and EOT rejected
  [PASS] eval-value: trailing CRLF stripped, internal lines kept, empty output typed
  [PASS] eval-errors: traceback pass-through message; soft reset typed
  [PASS] exec-ok: success true; traceback frame and soft reset false
  [PASS] transport: SKIP -- no XIOM_MICROPYTHON_PORT (byte-trace suite only)
xiom.micropython: all tests passed
  exit code: 0
port: PASS (passed=19 failed=0 program_exit=0 exit=0)
```

The transport leg reports SKIP, never FAIL, when no device path is configured
(`XIOM_MICROPYTHON_PORT` unset) or the configured path cannot be opened.

## 2. Compiler findings

No new compiler defects were required to make this package green:

- Struct-typed `Result` returns (`Result[MpExec, MpError]`,
  `Result[Vec[UInt8], MpError]`) compile and behave correctly at v0.64.7.
- `&Vec[UInt8]` indexing with `(v[i] as Int) & 0xFF` is stable, as in the
  gps/nmea lanes.
- `mp_exec_ok`, `mp_eval_value`, `mp_output_lines` and `mp_error_lines` take
  `MpExec` **by value**. This deliberately avoids the by-reference struct
  field reads that the gps lane found unreliable on v0.64.5 (AUDIT 2.2
  there); the direct field expressions in the tests are the control.
- String literals with `\x04` produce a single 0x04 byte (verified by the
  embedded-EOT rejection test and the fixture traces).

## 3. Coverage limits (explicit)

- **No hardware leg.** The suite is byte-trace only. `test_transport_skip`
  proves the SKIP classification; it does not exercise a live UART/USB-CDC
  read loop. Transport adapters are ROADMAP 0.2.0.
- **No raw-paste.** Ctrl-E / window flow control is outside 0.1.0
  (SPEC 6.2). The docs' raw-paste example was read for context only.
- **Default prompt only.** `mp_parse_exit` requires the stock `>>> ` prompt;
  a custom `sys.ps1` is outside the declared subset (SPEC 6.4).
- **Complete traces only.** The parsers assume the transport has delivered a
  complete frame; incremental reassembly is explicitly a transport concern
  (SPEC 6.3).
- **EOT in payloads.** A program printing a literal 0x04 collides with the
  frame delimiters; this is an upstream protocol property, not a parser bug
  (SPEC 6.5).

## 4. Protocol fidelity checks

- Entry banner bytes match the upstream worked example byte-for-byte
  (`docs/reference/repl.rst`), with and without the friendly leading CRLF.
- Exec frames match `shared/runtime/pyexec.c`: `OK` is emitted before
  `parse_compile_execute`, `EXEC_FLAG_PRINT_EOF` emits one 0x04 after stdout
  and one after the exception text, and the raw loop emits `>` afterward.
- The soft-reset shape follows the empty-command branch: `OK`, `\r\n`, forced
  exit; `mp_parse_exec` recognizes it only when no EOT appears in the trace.
- Ctrl-C frames use the normal two-EOT shape with a `KeyboardInterrupt`
  traceback on the error side; the host request is the documented 0x03.
- Error text is never trimmed, classified or rewritten; only line framing
  normalizes CRLF.
- Control-byte builders emit the bare documented bytes. The CR prefix used by
  `tools/pyboard.py` is documented as an optional host convenience
  (SPEC 6.8).

## 5. Provenance/license audit

MicroPython's MIT license was verified from the clone's root `LICENSE` before
study. No upstream code, data or test vectors were copied; fixtures are
hand-built byte traces derived from the documented protocol. Details in
PROVENANCE.md.
