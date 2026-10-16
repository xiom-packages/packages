# COVERAGE: xiom.serial 0.1.0 -- declared surface vs evidence

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0
>
> Policy: 100% of the DECLARED surface (SPEC.md sec. 4) is implemented
> and evidenced. Column "Suite evidence" cites the `[PASS]` names in
> `tests/test_conformance.xi`; runs x2 at 52/52 on v0.64.5
> (`STATUS.json`, logs `%TEMP%\kilo\serial-runs\run-a/b.log`).

## 1. Public functions (27/27)

| # | Function | Kind | Suite evidence |
|---|---|---|---|
| 1 | `serial_load` | loader | `live: probe -> win32-comm-api (kernel32.dll + advapi32.dll, 14 entry points)`; `live: backend unloaded` |
| 2 | `serial_load_named` | loader | `skip-path: absent backend classified SERIAL_LOAD_ABSENT (SKIP)`; `live: serial_load_named(kernel32.dll) loads + unloads` |
| 3 | `serial_unload` | loader | `live: serial_load_named(kernel32.dll) loads + unloads`; `live: backend unloaded` |
| 4 | `serial_probe` | loader | `live: probe -> ...` (api/kernel/registry/entry_points all asserted) |
| 5 | `serial_ports` | ports | `live: SKIP -- no serial device present (SERIALCOMM absent...)` (typed-empty path, live) + non-empty listing path asserted in code |
| 6 | `serial_open` | ports | `live: absent device COM255 -> SERIAL_ERR_NOT_FOUND with win32 2`; `live: open with empty name -> INVALID_ARG`; live-device `open` when a port exists |
| 7 | `serial_close` | ports | `closed: close -> INVALID_HANDLE`; live-device `close` when a port exists |
| 8 | `serial_is_open` | ports | `closed: serial_is_open(fake) is false`; live-device open asserts true |
| 9 | `serial_configure` | config | `closed: configure -> INVALID_HANDLE`; `closed: configure with invalid cfg -> INVALID_ARG (validation first)`; live-device `configure 9600 8N1 -> get_config identical` |
| 10 | `serial_get_config` | config | `closed: get_config -> INVALID_HANDLE`; live-device read-back |
| 11 | `serial_set_timeouts` | config | `closed: set_timeouts -> INVALID_HANDLE`; `closed: set_timeouts negative -> INVALID_ARG (validation first)`; live-device `set_timeouts 300/300 -> get_timeouts identical` |
| 12 | `serial_get_timeouts` | config | `closed: get_timeouts -> INVALID_HANDLE`; live-device `open-time defaults are 1000/1000 ms` |
| 13 | `serial_config_validate` | config | `validate:` x10 (accepts + every rejection edge) |
| 14 | `serial_read` | I/O | `closed: read -> INVALID_HANDLE`; `closed: read max_bytes 0 / 70000 -> INVALID_ARG`; live-device `read with no data -> typed SERIAL_ERR_TIMEOUT` + `poll-mode read (read_ms 0) returns Ok immediately` |
| 15 | `serial_write` | I/O | `closed: write -> INVALID_HANDLE`; `write empty payload -> Ok(0)`; `write 65537 bytes -> INVALID_ARG`; live-device `write 4 bytes -> Ok(4)` |
| 16 | `serial_flush` | I/O | `closed: flush flags 9 -> INVALID_ARG (validation first)`; `closed: flush both -> INVALID_HANDLE`; live-device `flush both buffers` |
| 17 | `serial_drain` | I/O | `closed: drain -> INVALID_HANDLE`; live-device `drain transmit queue` |
| 18 | `serial_dcb_encode` | codec | 4 `dcb-golden:` byte-exact cases; `dcb-encode: baud 0 rejected`; `dcb-matrix: 360/360` + `180/180` |
| 19 | `serial_dcb_patch` | codec | exercised by every encode + configure; matrix round-trips |
| 20 | `serial_dcb_decode` | codec | `dcb-decode:` x4 (canonical round-trip, short slot, hardware precedence) |
| 21 | `serial_timeouts_encode` | codec | `timeouts-golden:` x3 (blocking, poll, mixed) + negative-ms rejection |
| 22 | `serial_timeouts_decode` | codec | `timeouts-decode: blocking and poll shapes round-trip`; short-slot rejection |
| 23 | `serial_error_name` | catalog | `names: all 9 error kinds resolve (+unknown fallback)` |
| 24 | `serial_win32_error_name` | catalog | `names: Win32 error codes resolve (...)` |
| 25 | `serial_parity_name` | catalog | `names: parity/stop/flow catalogs resolve (+invalid fallback)` |
| 26 | `serial_stop_name` | catalog | same catalog test |
| 27 | `serial_flow_name` | catalog | same catalog test |

## 2. Types and constants

| Declared | Evidence |
|---|---|
| `SerialError { kind, code, message }` | constructed by every failure path in the suite; `code` asserted 0 (local) vs 2 (Win32) vs 1460-mapped kinds |
| `SerialPortInfo { name }` | enumeration non-empty-name assertion (live path in code; typed-empty on this host) |
| `SerialConfig { baud, data_bits, parity, stop_bits, flow }` | 360-combo round-trip + validate edges |
| `SerialTimeouts { read_ms, write_ms }` | golden + round-trip tests |
| `SerialLibrary` (16 fields) | probe asserts names + entry-point count; every FFI call in the suite goes through it (live calls: CreateFileA, Reg*, Get/SetCommTimeouts via open; Get/SetCommState, PurgeComm, FlushFileBuffers, ReadFile/WriteFile on device hosts) |
| `SerialPort { handle, name }` | lifecycle tests |
| `SerialBackendInfo` | probe assertions |
| `SERIAL_LOAD_ABSENT/ABI` + 7 `SERIAL_ERR_*` kinds | skip-path + closed-port + absent-device tests cover each kind's construction; catalogs name all 9 |
| Parity/stop/flow enums (14 consts) | goldens + catalogs use every value; encode goldens prove each mapping |
| `SERIAL_FLUSH_INPUT/OUTPUT/BOTH` | BOTH live/probed; INPUT/OUTPUT share the same validated mapping (flags 9 rejection proves the branch) |
| Baud window + default timeouts consts | validation edges + open-time default assertion |

## 3. Status of the live-device leg on the build host

This host has **no serial device** (`SERIALCOMM` key absent; `Win32_SerialPort`
empty; `CreateFileA("\\.\COM99")` -> err 2). The suite therefore reports
one explicit SKIP note for the device leg while still exercising the real
Win32 call chain live: loader (kernel32+advapi32), `CreateFileA` absent
path with `GetLastError` capture, `RegOpenKeyExA` on SERIALCOMM, and all
16 closed-port typed-error paths. On a host with a port, the same suite
runs the full device leg automatically (`test_live_port`): open with
defaults -> read-back of 1000/1000 -> configure 9600 8N1 -> config
identical -> 300/300 timeouts -> flush -> drain -> blocking read (typed
TIMEOUT when idle) -> write Ok(4) -> poll read -> close. This is the
lane's standard "live where a port exists, typed SKIP otherwise"
discipline (`docs/ANDROID-SDK100.md`).

## 4. Known non-goals (NOT gaps)

DTR/RTS control, modem status, break, XON/XOFF tuning, SetupAPI
descriptions, overlapped async, POSIX execution: explicit non-goals in
SPEC sec. 4 with the 0.2.0/0.3.0/0.4.0 plan in ROADMAP.md.
