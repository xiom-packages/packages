# PROVENANCE: xiom.micropython

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0
>
> Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% of the
> declared surface). This package is an **independent** implementation:
> no upstream code is vendored, ported, or copied.

## 1. Declaration

`xiom.micropython` 0.1.0 is original work written from the documented
MicroPython raw-REPL wire behavior. There is **no vendored upstream** and
no C, bridge or FFI code in the package. The repository stays MIT OR
Apache-2.0; no third-party license text ships with the package because no
third-party code ships with it.

## 2. Upstream reference (pinned, reference-only)

| Field | Value |
|---|---|
| Upstream | https://github.com/micropython/micropython |
| License | **MIT** (`LICENSE`, "The MIT License (MIT)", Copyright (c) 2013-2026 Damien P. George; verified on the clone) |
| Clone | `E:\repos\micropython`, `git clone --depth 1` (no history) |
| Pin | `b70ae1aca657bb93e2857dac4e2a2d21a3803200` (2026-10-16 18:21:01 -0700, "stm32/boards/ARDUINO_NICLA_VISION: Lower the QSPI clock to 66MHz.") |
| Status | **Reference-only.** No code, comments or test files copied. Not a link dependency; not distributed. |
| Ledger | Registered in `E:\repos\CLEANUP.md` (row `micropython`, review after 2026-12-01) |

### 2.1 Files read at the pin

| File | Lines | What was verified |
|---|---|---|
| `docs/reference/repl.rst` | 206-216 | Raw mode: entered with Ctrl-A, code + Ctrl-D, acknowledged by `OK`, errors/output returned, Ctrl-B leaves raw mode. |
| `docs/reference/repl.rst` | 281-305 | Example wire trace `\r\nraw REPL; CTRL-B to exit\r\n>` ... `123\r\n\x04\x04>`; raw-paste mode is an additional mode (not implemented in 0.1.0). |
| `docs/reference/repl.rst` | 154-176 | Ctrl-D soft reset in the friendly REPL (context for the empty-exec soft-reset path). |
| `shared/runtime/pyexec.c` | 60 | `EXEC_FLAG_PRINT_EOF` prints **two** EOF chars: one after normal output, one after exception output. |
| `shared/runtime/pyexec.c` | 63-160 | `parse_compile_execute`: stdout EOF on success (143-144), EOF after an uncaught exception (157-158); traceback printed to the error stream. |
| `shared/runtime/pyexec.c` | 222-223 | Final EOF after the execution (and debugging info). |
| `shared/runtime/pyexec.c` | 357-406 | Event-driven raw state machine: Ctrl-A resets and prints `raw REPL; CTRL-B to exit\r\n`; Ctrl-B returns to friendly mode; Ctrl-C clears the line; Ctrl-D ends input; device prints `OK` before executing; empty input is a soft reset; prompt `>` after each command. |
| `shared/runtime/pyexec.c` | 552-617 | Blocking raw loop with the same banner, `OK`, Ctrl-B/Ctrl-C/Ctrl-D handling and `>` prompt. |
| `tools/pyboard.py` | 400-443 | Host enter writes `\r\x03` (interrupt), drains, writes `\r\x01`; optional soft reset; exit writes `\r\x02`. |
| `tools/pyboard.py` | 446-463 | `follow`: read until the first `0x04` (stdout), then until the second `0x04` (stderr), stripping the terminators. |
| `tools/pyboard.py` | 497-536 | `exec_raw_no_follow`: waits for `>`, writes the UTF-8 command, writes `0x04`, reads exactly `OK`. |
| `tools/pyboard.py` | 538-552 | `exec_raw` = no-follow + follow; `eval(expression)` runs `print(<expr>)` (and `print(repr(<expr>))` with `parse=True`) and strips the result. |

Every constant and framing rule in `src/micropython.xi` traces to one of
these entries. The package intentionally does **not** copy pyboard.py's
`\r\x03` + drain prefix into `mp_enter_raw_frame`; it exposes the CR+Ctrl-A
variant separately and the caller composes the interrupt/flush policy.

## 3. What was *not* taken

* No source files, comments, parser code, raw-paste negotiation, or test
  fixtures were copied from the clone.
* No in-tree copy of `repl.rst`, `pyexec.c`, `pyboard.py` or `LICENSE`.
* No dependency on `micropython` or `mpremote` at build or run time.

## 4. Test vectors (synthetic, authored here)

`tests/fixtures/*.trace` are direction-aware scripts authored from the
framing rules in SPEC.md sec. 3. They are **not** upstream test files:
the traceback texts are representative MicroPython console text, and the
value/line traces are constructed to exercise the framing rules. The
fixture format itself is package-local test tooling (`W`/`R` tokens, hex
bytes, quoted text with escapes) and is parsed by the suite.

| Fixture | Exercises |
|---|---|
| `enter-exec-print.trace` | Banner, prompt, `OK`, stdout EOF, empty stderr EOF, trailing `>`, friendly exit. |
| `exec-multiline.trace` | Bare-`OK` response slice; CRLF and CR stdout line endings. |
| `exec-traceback.trace` | Empty stdout EOF + verbatim ValueError traceback + EOF. |
| `exec-syntax-error.trace` | Compile-time SyntaxError after the `OK` acknowledgement. |
| `exec-interrupt.trace` | Ctrl-C mid-exec -> KeyboardInterrupt in the stderr frame. |
| `eval-value.trace` / `eval-repr.trace` | `print(expr)` value extraction and `print(repr(expr))` literal output. |
| `exec-empty-output.trace` | Assignment with two adjacent EOF frames (empty stdout and stderr). |
| `exec-utf8.trace` | UTF-8 console bytes across the byte framing. |

## 5. Re-pin / refresh procedure

1. `git -C E:\repos\micropython fetch --depth 1 origin`; check out the new
   tip; re-read `LICENSE` (must remain MIT for this reference use).
2. Re-run the sec. 2.1 verification (line numbers may move; the pinned
   strings `raw REPL; CTRL-B to exit`, `OK`, `EXEC_FLAG_PRINT_EOF`, the
   two-EOF comment and the Ctrl-A/B/C/D branches must still match).
3. If framing changed, update SPEC.md sec. 3 and the fixtures in the same
   commit; never change a fixture to hide a package bug.
4. Update the pin and date here; update the `CLEANUP.md` review date if
   the clone is retained.
