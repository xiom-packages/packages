# xiom.micropython -- ROADMAP

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.

## 0.1.0 -- shipped (this wave)

- Standard raw-REPL framing: enter (Ctrl-A), friendly exit (Ctrl-B),
  interrupt (Ctrl-C), exec (UTF-8 code + Ctrl-D), soft reset (Ctrl-D
  alone) and the CR+Ctrl-A pyboard-compatible enter variant.
- `OK` acknowledgement + stdout/stderr EOF framing, including compile and
  runtime tracebacks and `KeyboardInterrupt` mid-exec.
- Incremental decoder (`PRELUDE -> OK -> STDOUT -> STDERR -> DONE`) with
  chunk-boundary robustness, reset/reuse, error state and trailing-byte
  tolerance; full-slice helpers.
- Output/error line framing (CRLF/LF/CR), traceback pass-through and
  final-exception extraction; eval / repr-eval frame + extract helpers.
- Typed error catalog with the `MP_ERR_ABSENT` SKIP classification for
  hosts without a transport.
- Fixture-driven, hardware-free suite: 19 checks x2 on v0.64.7.

## 0.2.0 -- planned

- **Raw-paste mode** (Ctrl-E `A` Ctrl-A, `R\x00`/`R\x01` capability,
  16-bit little-endian window increment, `0x01`/`0x04` flow bytes) for
  faster/lower-RAM code transfer. This is the next documented mode in
  `repl.rst`.
- **Live transport adapters** (outside this package or behind an optional
  dependency): `xiom.serial` for UART/USB CDC and a TCP adapter for
  network-enabled ports, with an `XIOM_MICROPYTHON_PORT`-style selection
  and the existing absent -> SKIP classification.
- **Enter/reset orchestration**: a helper that composes Ctrl-C + drain +
  CR+Ctrl-A (+ optional Ctrl-D soft reset) with a caller-supplied
  write/read seam, matching `pyboard.py` without hiding the primitives.
- **Deadline/retry policy**: response deadlines, partial-response
  recovery (re-sync at the next `>`), and bounded retries classified as
  `MP_ERR_TIMEOUT`.
- **File transfer subset**: `mpremote`-style `fs put/get/ls` built on
  exec frames and chunked base64/hex (binary-safe), not on raw-paste
  alone.
- **Typed traceback model**: optional parse of the last line into
  exception type + message while keeping the verbatim text; no lossy
  reformatting.

## Non-goals (documented)

- Friendly-REPL line editing, auto-indent, paste mode and completion.
- A Python-subset parser or MicroPython emulator.
- Flashing, firmware updates, or board discovery (`xiom.uf2` handles
  flashing; this package starts at an already-open byte link).
- Encoding/escaping `0x04` inside payloads; MicroPython itself does not
  escape it, so binary data must be encoded on-device.
