# xiom.serial -- Lane audit (build, probes, evidence)

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Toolchain: compiler pin **v0.64.5** (`$env:LOCALAPPDATA\xiom.new\bin\xiom.exe`,
verified `XIOM Compiler v0.64.5`), stdlib `E:\xiom-lang\stdlib`, worktree
`feat/serial-binding`, branch base `origin/bindings` @ `cdca3405`. Date:
2026-10-16. Owner instruction: v0.64.6 may land mid-build -- stay on the
pin and note it (it did not land during this build; nothing to re-point).

## 1. Pre-implementation ABI probes (all green before the module was written)

Probe source: `docs/repro/abi-probe.xi` (kept as the reproducible witness;
run: `xiom --run docs/repro/abi-probe.xi` from the package dir).

| Probe | Result |
|---|---|
| `dl.dl_open("kernel32.dll")` + `dl_sym` + fn-pointer cast through `xiom.ffi.dl` | loaded; handle non-zero |
| `GetCurrentProcessId` as `fn() -> UInt32` | live value returned (plausible PID, e.g. 65104); 32-bit return marshalling is sound |
| `GetLastError` as `fn() -> UInt32` immediately after a failing call | captured 2 (== `ERROR_FILE_NOT_FOUND`) -- the typed-error path is real, not synthesized |
| `CreateFileA("\\.\COM99", GENERIC_READ|GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL)` as `fn(*UInt8, UInt32, UInt32, Int, UInt32, UInt32, Int) -> Int` | `INVALID_HANDLE_VALUE` (-1) + err 2: string marshalling (`Str as *UInt8`), 7-arg shape, and the absent-device classification all proven live |
| `dl.dl_open("advapi32.dll")` + `RegOpenKeyExA(HKLM, "HARDWARE\\DEVICEMAP\\SERIALCOMM", 0, KEY_READ, &hKey)` as `fn(Int, *UInt8, UInt32, UInt32, *UInt8) -> UInt32` | rc 2 on this host -- the no-ports-at-all state; the enumeration call chain itself is live |

These five shapes are exactly the call families the module uses (14 entry
points are variations of them), so the loader struct and every call site
landed on measured ABI behavior, not assumption.

## 2. Oracle-verified semantics encoded in the module

- DCB offsets/sizes and the Flags bitfield come from `winbase.h` @559+ of
  the pinned SDK; parity/stop constants from @829-837; DTR/RTS control
  values from @548/@556. Hashes + line table in `PROVENANCE.md` sec. 2.2.
- `COMMTIMEOUTS` is the five-DWORD layout @590-595; the package's
  blocking/poll encodings are byte-identical to the libserialport
  reference paths (verified side by side; see `PROVENANCE.md` sec. 3).
- Error codes (2/5/6/87/109/122/234/259/1460) verified line-by-line in
  `winerror.h`.
- Enumeration semantics (SERIALCOMM key; absent key = zero ports, not an
  error; REG_SZ data carries the name) match the reference `list_ports`
  including the corner case this host exercises (key absent).
- DCB flag policy = fBinary=1 + fAbortOnError=0 "sane settings" set from
  the reference, combined with the flow/parity bits the SPEC table pins.

## 3. B-series / compiler discipline notes

- **T007 shape found during probes**: a function whose body is a single
  `unsafe { ... }` block must declare a `requires` clause (probe failed
  with `error[T001] ... whole-body unsafe block but declares no requires`
  until `requires: p != null` was added). Internal helpers in `serial.xi`
  carry such clauses; public entry points instead do graceful typed
  validation.
- **Public entry points never panic on input**: argument validation runs
  before state checks and returns `SerialError{kind: INVALID_ARG, code: 0}`
  -- input-condition `requires` clauses were deliberately NOT used on the
  public surface (a contract panic is hostile to a device-fleet call
  path; the suite asserts the graceful paths instead).
- The stdlib ffi has `ptr_write_u8/u32/u64` but **no u16 writer**; the
  package adds a local `wr_u16_le` for the DCB XonLim/XoffLim fields.
- Reference-to-pointer casts must sit inside an `unsafe` block
  (`&bytes[0] as *UInt8` -- the tls_libssl pattern; a top-level cast
  errors with "reference-to-pointer cast requires an `unsafe` block").
- Handles/symbols are `Int` fields; one call site per symbol; out-params
  are `Vec[UInt8].with_len` slots; no tuple returns; local `int_to_str`.
- `serial_ports` allocates fresh zeroed slots per registry value and
  closes the key on every exit path (error var hoisted, close before
  return) -- no leak paths in the enumeration loop.

## 4. Suite evidence (v0.64.5, 2026-10-16)

| Leg | Command | Run 1 | Run 2 | Logs |
|---|---|---|---|---|
| Default (this host: backend live, no device) | `scripts/port.ps1 -Package xiom.serial -TimeoutSec 300` | PASS 52/52 (exit 0) | PASS 52/52 (exit 0) | `%TEMP%\kilo\serial-runs\run-a.log`, `run-b.log` |

Highlights: loader + named re-load + unload + probe (14 entry points);
SERIALCOMM enumeration typed-empty (SKIP note); `COM255` -> NOT_FOUND +
win32 2 (live absent-device classification); 16 closed-port typed-error
checks covering every public call; DCB goldens 0x1011/0x2017/0x1311 +
5N1.5; 360/360 round-trip and 180/180 rejection matrix; COMMTIMEOUTS
blocking/poll goldens; 3 name catalogs; empty-name INVALID_ARG. The
live-device leg (open/configure/read-back/timeouts/flush/drain/read/
write/poll/close) auto-runs when a port is enumerated; this host has
none (SERIALCOMM absent), so it reports one explicit SKIP note. Runs on
a host with a real port execute it automatically -- see
`tests/test_conformance.xi` `test_live_port`.

## 5. Process notes for the next agent

- `port.ps1` runs suites with the package dir as cwd and cleans `a.exe`/
  `a.exe.ll`; nothing to do manually. Namespace check: 2 modules
  (`xiom.serial`, `serial_conformance`), 0 conflicts.
- The registry probe reproduces the no-ports state in one line:
  `reg query "HKLM\HARDWARE\DEVICEMAP\SERIALCOMM"` -> key not found.
- The DCB byte goldens double as a regression tripwire if the compiler's
  `UInt32` argument/return marshalling ever changes -- they exercise the
  exact `fn` shapes the Win32 calls use.
- If a future host has a real port on COM255, the absent-device check
  degrades to an explicit SKIP note instead of a false positive (by
  design); COM255 is effectively never a real device.

## 6. Re-verify

```powershell
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"   # v0.64.5 pin
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
.\scripts\port.ps1 -Package xiom.serial -TimeoutSec 300           # x2
xiom --run packages\xiom-serial\docs\repro\abi-probe.xi           # ABI witness
```
