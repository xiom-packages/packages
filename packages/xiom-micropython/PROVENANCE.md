# xiom.micropython -- PROVENANCE

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

## Upstream project

| | |
|---|---|
| Project | **MicroPython** -- a lean and efficient Python implementation for microcontrollers and constrained systems |
| Canonical repo | `https://github.com/micropython/micropython` |
| Clone pin | `b70ae1aca657bb93e2857dac4e2a2d21a3803200` (2026-10-16, commit "stm32/boards/ARDUINO_NICLA_VISION: Lower the QSPI clock to 66MHz.") |
| Clone | `git clone --depth 1 https://github.com/micropython/micropython E:\repos\micropython` (light clone; working tree clean at the pin) |
| License | **MIT** -- verified FIRST, before any study: the repo root `LICENSE` is "The MIT License (MIT), Copyright (c) 2013-2026 Damien P. George" plus the MicroPython contributors. Every source file reviewed carries the MIT header ("Permission is hereby granted, free of charge..."). |
| Permissiveness check | MIT is permissive, no copyleft, no runtime linking obligation -- suitable for reference under this package's MIT OR Apache-2.0. |

## What was consulted (no code copied)

The package is a **pure-XIOM re-implementation** of the documented raw-REPL
protocol. Upstream material was read as an oracle; nothing was translated,
copied or vendored.

| Upstream path | Used for |
|---|---|
| `docs/reference/repl.rst` | The raw-mode description and the worked raw-paste trace: Ctrl-A enters raw mode, code + Ctrl-D executes, Ctrl-B returns to friendly mode; the exact `\r\nraw REPL; CTRL-B to exit\r\n>` entry banner; the `OK` acknowledgement. |
| `shared/runtime/pyexec.c` | Device state machine and framing: `pyexec_raw_repl_process_char` (Ctrl-A/B/C/D handling, `OK`, `>`, soft reset), `parse_compile_execute` (`EXEC_FLAG_PRINT_EOF` emits one `0x04` after stdout and one after the exception text), `do_reader_stdin` (raw-paste, a declared non-goal). |
| `tools/pyboard.py` | Host-side reference: `enter_raw_repl` / `exec_raw_no_follow` / `follow` / `exec_` (the `OK` check, the two-EOF read and the "stderr means exception" rule), `eval` (`print(expr)` and `print(repr(expr))` forms), `exit_raw_repl` (Ctrl-B). |
| `py/repl.c`, `py/builtinhelp.c`, `shared/readline/readline.c` | Confirmation of the control-byte meanings (Ctrl-A raw, Ctrl-B friendly, Ctrl-C break, Ctrl-D soft reset) and the default `>>> ` friendly prompt. |

## Fixtures

Fixture files under `tests/fixtures/` are **hand-built byte traces** derived
from the documented protocol. The worked example in `repl.rst` (Ctrl-A entry
and the `OK`/EOT shape) is cited in the fixture header; the traceback and
soft-reset traces are protocol-conformant synthetic frames, not captured
device recordings. No upstream source text or test data is copied. The
fixture format (`>HEX` host bytes, `<HEX` device bytes, `#` comments) is this
package's own.

`tests/fixtures/enter-friendly.trace` reproduces the exact bytes shown in the
upstream example (`write b"\x01"`, `read b"\r\nraw REPL; CTRL-B to exit\r\n>"`);
the hex encoding is a transcription of that documented exchange.

## Third-party dependencies at runtime

None beyond the XIOM standard library (`xiom.std`): string helpers come from
`xiom.string`/`xiom.string.builder`. There is no serial/socket/FFI dependency
and no data file is read at runtime. The tests additionally use `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex` from the same standard library
to load the fixture scripts.
