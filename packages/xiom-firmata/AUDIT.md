# xiom.firmata -- Lane audit (build, probes, evidence)

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Toolchain: compiler pin **v0.64.7** (`E:\xiom-lang\xiom\target\release\xiom.exe`,
resolved via `scripts/xiom.ps1 -Info`), stdlib `E:\xiom-lang\stdlib`,
worktree `feat-firmata-c2ee985b27c207c9`, branch `feat/firmata`, base
`origin/bindings` @ `5eaf3d0d`. Date: 2026-10-19. No FFI, no C, no
hardware, no transport.

## 1. Pre-implementation language probes (all green before the module)

The package relies on a few value shapes that older bindings-lane notes
flagged as risky. Each was measured on v0.64.7 before writing the module
(probes kept out of the package; results below):

| Probe | Result |
|---|---|
| `pub type T = enum { Variant(v: Struct), Text(v: Str), Empty }` + construct/match/return | green: struct payloads, Str payloads and bare variants all lower and run |
| `match` on a **borrowed** enum (`fn observe(m: &Msg)` with `Variant(v) => ...`) | green: fields read through the borrow without a copy |
| `Result[Option[Enum], FirmataError]` and `Ok(None)` / `Some(msg)` | green: the session poll shape compiles and runs |
| `&struct.field` passed to `&Vec[UInt8]` / `&mut struct.field` passed to `&mut Vec[UInt8]` | green: **the old CAN/`xiom.can` note no longer applies on v0.64.7** (direct field references work) |
| Direct `Ok(...)` / `Err(...)` construction inside ordinary functions | green (no leaf-helper workaround needed) |
| `xiom.string.builder` (`sb_new`/`sb_push_byte`/`sb_to_str`) + `xiom.utf8.utf8_encode` | green: 2 x 7-bit characters decode to UTF-8, including U+00E9 |

These probes removed the need for the B-series workarounds (leaf
`_ok_*`/`_err_*` constructors, copied field locals) that older packages
carry. The module still keeps free functions only (no methods/lambdas).

## 2. Oracle-verified semantics encoded in the module

- Status bases and frame lengths come from `protocol.md` (2.8.0) "Message
  Types" and "Data Message Expansion": 3-byte analog/digital reports,
  2-byte report toggles, 3-byte set-mode/set-pin, 1-byte reset, sysex
  framed by `f0`/`f7`. Hashes/pins in `PROVENANCE.md` sec. 2.1.
- The 7-bit pair math (`value = lsb + msb*128`) is cross-checked against
  `firmata.js` `ANALOG_MESSAGE`/`DIGITAL_MESSAGE` handlers and
  `writeDigitalPort`; the session's port shadow/bit math matches
  `digitalWrite` (`port = pin/8`, bit = `pin%8`).
- Firmware/string pairs follow the protocol's 14-bit character definition
  (the reference client masks to 8 bits); the deliberate deviation is
  documented in SPEC sec. 8. ASCII names are byte-identical.
- The handshake order (`f9` then `f0 79 f7`) matches the reference
  client's `reportVersion()`/`queryFirmware()` queries; readiness requires
  both reports (stricter than the client's timeout-driven state).

## 3. Compiler discipline notes

- No `unsafe` blocks, no extern C, no FFI: the package is pure XIOM. There
  is no whole-body-unsafe T007 surface.
- Public entry points validate arguments before state changes and return
  `FirmataError{kind, code, message}`; public functions carry no
  input-condition `requires` clauses, so bad input is a typed result, not
  a contract panic.
- Wire bytes widen with `(b as Int) & 0xFF`; multi-byte values use
  multiplication/addition (`lsb + msb*128`, `value % 128`,
  `(value / 128) % 128`). No multi-byte value exceeds 14 bits, so no
  bit-31 edge is reachable.
- The session uses `Vec[UInt8]` receive/output buffers, `Vec[Int]` for the
  16-port shadow, and `Vec.extend`/`Vec.clear`; frame consumption is a
  rebuild-from-tail helper (no reliance on `Vec.remove` semantics).
- `firmata_session_poll` on decode failure consumes the whole malformed
  frame; on a framing failure it consumes one byte. Both paths are
  asserted by the resync tests, so a stall cannot regress silently.
- No silent failures: every `Result` is checked at each call site; error
  kinds/codes/messages are asserted in the suite.

## 4. Suite evidence (v0.64.7, 2026-10-19)

| Leg | Command | Run 1 | Run 2 | Logs |
|---|---|---|---|---|
| Pure/fixture (this host; no transport) | `scripts/port.ps1 -Package xiom.firmata -TimeoutSec 300` | PASS 122/122 (exit 0) | PASS 122/122 (exit 0) | `%TEMP%\kilo\firmata-runs\run-a.log`, `run-b.log` (PowerShell transcripts) |

Highlights: every encoder byte golden + the concatenated host-command
stream; 17 framing checks; handshake (Version 2.5 + `StandardFirmata`);
10 IO/report/set/reset frames; 4 string forms (ASCII, 14-bit U+00E9,
NUL-terminated, empty); 9 decode error shapes; the session shadow
accumulate/clear and incoming-report update; the short-shadow guard
(`INVALID_ARG`, no panic); 4 resynchronization scenarios; reset; the
explicit transport SKIP note. Namespace check:
1 module (`xiom.firmata`), 0 conflicts (stdlib namespace 2006 modules).

## 5. Process notes for the next agent

- `port.ps1` runs the suite with the package dir as cwd and cleans
  `a.exe`/`a.exe.ll`; fixtures load from `tests/fixtures/` with a
  repo-root fallback for runners that start elsewhere.
- A missing fixture is a FAIL (repository artifact); absent hardware is
  the SKIP note and never a failure.
- `STATUS.json` records the code commit `4113fb53` and the x2 run count.
  If the suite is re-run after a code change, update `STATUS.json` (run
  `scripts/status.ps1 -Action update ...` or edit the fields in the same
  commit as the change).
- `firmata_frame_len` is the streaming primitive: if a future feature
  adds a status, add it in `frame_len` and `decode_frame` together, plus a
  fixture/frame-length check.
- The host loop owns time; do not add sleeping/timeouts inside the
  session (keeps the pure leg deterministic).

## 6. Re-verify

```powershell
$env:XIOM_COMPILER = "E:\xiom-lang\xiom\target\release\xiom.exe"   # v0.64.7 pin
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
.\scripts\port.ps1 -Package xiom.firmata -TimeoutSec 300           # x2
```
