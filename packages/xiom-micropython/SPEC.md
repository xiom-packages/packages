# xiom.micropython -- SPEC (declared surface, phase 1)

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

This document is the contract for **xiom.micropython 0.1.0**. The package
declares exactly the surface below; "100% of the declared set" is the lane's
done-definition. Upstream oracle: **micropython/micropython** at pin
`b70ae1aca657bb93e2857dac4e2a2d21a3803200` (MIT), specifically
`docs/reference/repl.rst` (raw REPL description), `shared/runtime/pyexec.c`
(device state machine and framing) and `tools/pyboard.py` (host reference).
File-level provenance is in PROVENANCE.md; no upstream code is copied.

Module: `xiom.micropython` (single module, `src/micropython.xi`). Imports:
`xiom.string`, `xiom.string.builder`. Platform dep `xiom.std`. The module has
no socket, serial, FFI or hardware dependency; callers own the transport.

## 1. Constants

| Constant | Value | Meaning |
|---|---|---|
| `MP_CTRL_A` | 1 | Ctrl-A: enter the raw REPL. |
| `MP_CTRL_B` | 2 | Ctrl-B: leave the raw REPL for the friendly REPL. |
| `MP_CTRL_C` | 3 | Ctrl-C: interrupt the program currently running. |
| `MP_CTRL_D` | 4 | Ctrl-D: end of command input (EOT). |
| `MP_PROMPT` | 62 (`>`) | The raw-REPL prompt byte. |
| `MP_ERR_FRAMING` | 0 | The device trace violates the declared framing. |
| `MP_ERR_EXEC` | 1 | The command ran but the device reported an exception. |
| `MP_ERR_ARG` | 2 | A request argument cannot be framed safely. |

## 2. Wire protocol

The package models the documented **raw REPL**, not raw-paste mode. All
sequences below are exact bytes; no timing, flow control or echo handling is
part of the declared surface.

### 2.1 Enter raw mode

Host writes `01` (Ctrl-A).

Device reply, entering from the friendly REPL:

```
0D 0A 72 61 77 20 52 45 50 4C 3B 20 43 54 52 4C 2D 42 20 74 6F 20 65 78 69 74 0D 0A 3E
\r \n  r  a  w     R  E  P  L  ;     C  T  R  L  -  B     t  o     e  x  i  t  \r \n  >
```

i.e. `\r\nraw REPL; CTRL-B to exit\r\n>`. When the device is already in raw
mode the leading `\r\n` is absent. `mp_parse_enter` accepts both and stops at
the prompt; any following bytes are left to the caller.

### 2.2 Exec

Host writes the command bytes followed by `04` (Ctrl-D).

Device reply for a completed command:

```
"OK" output 04 error 04 ">"
```

- `output` is everything between `OK` and the first `04` (stdout, verbatim,
  including CRLF).
- `error` is everything between the first `04` and the second `04` (stderr or
  traceback text, verbatim).
- The trailing `>` is the raw prompt. `consumed` counts through this prompt.

Examples (also fixtures):

| Command | Device reply |
|---|---|
| `print(123)\x04` | `OK123\r\n\x04\x04>` |
| `pass\x04` | `OK\x04\x04>` |
| `1/0\x04` | `OK\x04Traceback (most recent call last):\r\n  File "<stdin>", line 1, in <module>\r\nZeroDivisionError: divide by zero\r\n\x04>` |
| `04` (empty command) | `OK\r\n` (soft reset, no EOT pair) |

A Ctrl-C during execution ends the same frame with a `KeyboardInterrupt`
traceback in `error`; the host interrupt request itself is `03`.

### 2.3 Soft reset

Ctrl-D with an empty command line (`04`) is the upstream soft-reset form. The
device acknowledges `OK\r\n` and exits the raw REPL for a reboot. The parser
recognizes this shape only when no `04` appears in the trace, sets
`soft_reset = true`, and consumes `OK\r\n` (4 bytes).

### 2.4 Exit to friendly REPL

Host writes `02` (Ctrl-B). The device leaves raw mode and prints its
board-specific banner followed by the default prompt `>>> ` (four bytes).
`mp_parse_exit` searches for `">>> "` and requires it; custom `sys.ps1` values
are outside the declared subset.

### 2.5 Eval helper

| Helper | Host command |
|---|---|
| `mp_eval_request(expr)` | `print(EXPR)\x04` |
| `mp_eval_repr_request(expr)` | `print(repr(EXPR))\x04` |

`mp_eval_value` returns the output with trailing CR/LF removed. A non-empty
`error` payload is an `MP_ERR_EXEC` whose message includes the full traceback
(pass-through, not classification). Empty output and soft reset are also
typed `MP_ERR_EXEC`.

### 2.6 Line framing

`mp_lines` splits on LF, removes one trailing CR from each line, does not emit
an extra empty line for a final LF, and preserves interior empty lines. This
keeps traceback frames line-aligned without interpreting them.

## 3. Types

### 3.1 MpError

```
MpError { kind: Int, message: Str }
```

`kind` is one of `MP_ERR_FRAMING`, `MP_ERR_EXEC`, `MP_ERR_ARG`; every message
starts with `"mp: "`.

### 3.2 MpExec

```
MpExec { output: Str, error: Str, soft_reset: Bool, consumed: Int }
```

`output`/`error` are byte-for-byte pass-throughs. `consumed` counts the trace
bytes up to and including the prompt (or `OK\r\n` for a soft reset). Trailing
bytes are not consumed, so a transport can retain them for the next frame.

## 4. Request builders

| Function | Returns | Contract |
|---|---|---|
| `mp_repl_enter_request()` | `Vec[UInt8]` | `[0x01]`. |
| `mp_repl_exit_request()` | `Vec[UInt8]` | `[0x02]`. |
| `mp_repl_interrupt_request()` | `Vec[UInt8]` | `[0x03]`. |
| `mp_repl_soft_reset_request()` | `Vec[UInt8]` | `[0x04]`. |
| `mp_repl_exec_request(code)` | `Result[Vec[UInt8], MpError]` | `code` bytes + `0x04`; an embedded `0x04` is `MP_ERR_ARG`; empty code yields `[0x04]` (soft reset). |
| `mp_eval_request(expr)` | `Result[Vec[UInt8], MpError]` | `print(EXPR)` + `0x04`; empty expression is `MP_ERR_ARG`. |
| `mp_eval_repr_request(expr)` | `Result[Vec[UInt8], MpError]` | `print(repr(EXPR))` + `0x04`; empty expression is `MP_ERR_ARG`. |

## 5. Response parsers and helpers

| Function | Returns | Contract |
|---|---|---|
| `mp_parse_enter(trace)` | `Result[Int, MpError]` | Require `raw REPL; CTRL-B to exit\r\n` + `>`; optional leading CRLF; return consumed bytes through `>`. Missing banner/prompt is `MP_ERR_FRAMING`. |
| `mp_parse_exit(trace)` | `Result[Int, MpError]` | Require the default `>>> ` friendly prompt; return consumed bytes through it. |
| `mp_parse_exec(trace)` | `Result[MpExec, MpError]` | Require `OK`, stdout EOT, stderr EOT and `>`; soft-reset shape `OK\r\n` with no EOT is recognized separately. Missing pieces are `MP_ERR_FRAMING`. |
| `mp_exec_ok(r)` | `Bool` | True iff not a soft reset and `error.len() == 0` (the upstream pyboard `exec_` rule). |
| `mp_eval_value(r)` | `Result[Str, MpError]` | Eval value with trailing CR/LF removed; soft reset, non-empty error or empty output is `MP_ERR_EXEC`. |
| `mp_output_lines(r)` | `Vec[Str]` | `mp_lines(r.output)`. |
| `mp_error_lines(r)` | `Vec[Str]` | `mp_lines(r.error)`; traceback frames unchanged. |
| `mp_lines(text)` | `Vec[Str]` | Line framing rule in 2.6. |

`mp_exec_ok`, `mp_eval_value`, `mp_output_lines` and `mp_error_lines` take
`MpExec` **by value** (this keeps struct field reads reliable on the pinned
compiler). Parse the same trace twice, or read `output`/`error` directly,
when both views are needed.

## 6. Declared divergences and limitations

1. **Transport-agnostic by design.** There is no serial/socket client in
   0.1.0. The caller writes the builder bytes to its transport and feeds the
   accumulated device bytes to the parser. This is what makes the package
   fixture-testable without hardware and usable over UART, USB-CDC, TCP or a
   process pipe alike.
2. **No raw-paste mode.** Ctrl-E / `05 41 01` flow control is deferred to
   0.2.0 (ROADMAP). Only the standard raw REPL is declared.
3. **Complete frames.** `mp_parse_exec` expects a complete trace ending at the
   prompt; incremental/streaming reassembly is the transport's job. A trace
   that is `OK\r\n`-prefixed with no EOT anywhere is classified as the
   soft-reset reply by the upstream rule.
4. **Default prompt.** `mp_parse_exit` requires the stock `>>> ` prompt; a
   device with a custom `sys.ps1` is outside the declared subset.
5. **EOT ambiguity.** A Python program that writes a literal `0x04` to stdout
   or stderr collides with the frame delimiters; this is an upstream protocol
   property, not something the parser can disambiguate.
6. **No exception classification.** Error payloads are tracebacks and are
   passed through verbatim; the package does not parse exception type,
   message or stack frames.
7. **No timeout policy.** Deadlines belong to the transport. The package is
   pure and never blocks.
8. **Bare control bytes.** The interrupt and exit requests are the documented
   control bytes alone (`0x03`, `0x02`). Upstream `tools/pyboard.py` prepends
   a CR (`\r\x03`, `\r\x02`) as a host convenience; a caller that needs to
   clear a partial friendly-REPL line can prepend `0x0D` itself. The raw
   device mode handles Ctrl-B/Ctrl-C wherever they appear, so the bare byte
   is the faithful protocol form.

## 7. Coverage table (100% of the declared set)

Test names refer to `tests/test_conformance.xi`. Every public constant, type
and function is listed.

| Declared item | Test(s) | Evidence |
|---|---|---|
| `MP_CTRL_A`/`B`/`C`/`D`, `MP_PROMPT` | `test_request_controls`, `test_parse_*` | Byte-exact builders and parsed prompts. |
| `MP_ERR_FRAMING`, `MP_ERR_EXEC`, `MP_ERR_ARG` | `test_parse_enter_errors`, `test_parse_exec_framing_errors`, `test_parse_exec_error`, `test_request_exec_eot_arg`, `test_eval_errors` | Every kind is produced by at least one path and checked. |
| `MpError` | all error tests | `kind` + `"mp: "` message prefix. |
| `MpExec` | `test_parse_exec_ok`, `test_parse_exec_error`, `test_parse_exec_interrupt`, `test_parse_exec_soft_reset` | `output`, `error`, `soft_reset`, `consumed` all asserted. |
| `mp_repl_enter_request` | `test_request_controls`, `test_parse_enter` | `01` and its banner/prompt. |
| `mp_repl_exit_request` | `test_request_controls`, `test_parse_exit` | `02` and friendly prompt. |
| `mp_repl_interrupt_request` | `test_request_controls`, `test_parse_exec_interrupt` | `03` and the KeyboardInterrupt frame. |
| `mp_repl_soft_reset_request` | `test_request_controls`, `test_parse_exec_soft_reset` | `04` and `OK\r\n`. |
| `mp_repl_exec_request` | `test_request_exec`, `test_request_exec_eot_arg` | code+EOT, empty command, embedded-EOT rejection. |
| `mp_eval_request` | `test_eval_requests`, `test_eval_value`, `test_eval_errors` | `print(EXPR)`, empty-argument error, value extraction. |
| `mp_eval_repr_request` | `test_eval_requests`, `test_eval_value` | `print(repr(EXPR))` and the recorded repr trace. |
| `mp_parse_enter` | `test_parse_enter`, `test_parse_enter_errors` | Both banner shapes, consumed count, two framing errors. |
| `mp_parse_exit` | `test_parse_exit` | Recorded friendly banner + default prompt; missing prompt. |
| `mp_parse_exec` | `test_parse_exec_ok`, `test_parse_exec_error`, `test_parse_exec_interrupt`, `test_parse_exec_soft_reset`, `test_parse_exec_framing_errors` | Success, traceback, interrupt, soft reset, five framing failures. |
| `mp_exec_ok` | `test_parse_exec_ok`, `test_parse_exec_error`, `test_parse_exec_soft_reset`, `test_exec_ok` | True on success; false on traceback and soft reset. |
| `mp_eval_value` | `test_eval_value`, `test_eval_errors`, `test_parse_exec_error` | CRLF trim, multi-line keep, empty/soft-reset/traceback errors. |
| `mp_output_lines` | `test_output_error_lines` | One stdout line from the interrupt trace. |
| `mp_error_lines` | `test_output_error_lines`, `test_parse_exec_error` | Three traceback lines preserved. |
| `mp_lines` | `test_lines_framing`, `test_output_error_lines` | Empty, CRLF, interior blanks, trailing LF, traceback text. |

Fixture scripts (`tests/fixtures/*.trace`) back the happy paths; malformed
traces are inline hex vectors. The transport leg reports a typed SKIP when
`XIOM_MICROPYTHON_PORT` is unset (or cannot be opened), so the suite is green
on a host with no device attached.

## 8. Non-goals (phase 1)

Raw-paste flow control, file transfer (`fs_*`), soft-reset orchestration,
friendly-REPL command parsing, prompt customization, serial port discovery,
timeouts/retries, streaming incremental reassembly, exception classification,
and any device-side (MicroPython) library.
