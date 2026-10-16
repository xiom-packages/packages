# xiom.serial

> **Status:** `incubating` -- conformance-tested (**52/52 x2** on the
> compiler pin v0.64.5, including the live Win32 backend leg; the
> no-device SKIP legs -- empty enumeration, absent-device typed
> classification, closed-port typed errors -- are asserted on every run);
> not yet published.
> **Scope (0.1.0):** Win32 UART/serial-port bindings -- enumerate; open/
> close; configure baud/data-bits/parity/stop/flow; blocking and
> poll-mode reads with timeouts; writes; flush/drain; typed errors; a
> deterministic absent-device SKIP path.
> **Deps:** `xiom.std` only (the module imports `xiom.ffi.dl` and
> `xiom.ffi`); tests use `xiom.io`, `xiom.convert`, `xiom.string.compare`.

## What it is

`xiom.serial` is the MCU/host bridge foundation: UART/serial-port access
for the device fleet. It is a **platform wrapper over the Win32 comm API**
(kernel32 `CreateFileA`/DCB/`COMMTIMEOUTS`/`PurgeComm` + advapi32
SERIALCOMM enumeration) resolved through `xiom.ffi.dl` exactly like
`xiom.ssl`/`xiom.openssl`: **system libraries only, nothing vendored, no C
shipped**. The canonical cross-platform reference, libserialport, is
LGPL-3.0+ and therefore stays reference-only (owner restated
2026-10-16); the implementation oracle is the Microsoft Win32 API
documentation plus the local Windows SDK headers (see `PROVENANCE.md`).

No Win32 serial API on the host (non-Windows leg) or a genuinely absent
library classifies as `SERIAL_LOAD_ABSENT` -> the suite reports SKIP and
stays green. An absent **device** is a typed operational result:
`serial_open("COM255")` -> `SerialError{ kind: SERIAL_ERR_NOT_FOUND,
code: 2, ... }` (the MCU-fleet SKIP classification).

## Loader and backend

| Function | Returns | Description |
|---|---|---|
| `serial_load()` | `Result[SerialLibrary, SerialError]` | kernel32.dll + advapi32.dll, 14 resolved entry points (SKIP-safe). |
| `serial_load_named(name)` | `Result[SerialLibrary, SerialError]` | Explicit library (bogus names exercise the ABSENT classification deterministically). |
| `serial_unload(&lib)` | `Result[Unit, Str]` | Release both handles. |
| `serial_probe(&lib)` | `SerialBackendInfo` | API tag, library names, entry-point count. |

## Ports

| Function | Returns | Description |
|---|---|---|
| `serial_ports(&lib)` | `Result[Vec[SerialPortInfo], SerialError]` | Registry `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` enumeration; an absent key = no ports (empty list, not an error -- the reference behavior). |
| `serial_open(&lib, name)` | `Result[SerialPort, SerialError]` | Exclusive open (`\\.\NAME`), default timeouts 1000/1000 ms; line config stays as the driver presents it. Absent -> `SERIAL_ERR_NOT_FOUND`; busy/permission -> `SERIAL_ERR_ACCESS_DENIED`. |
| `serial_close(&lib, &port)` | `Result[Unit, SerialError]` | Close the handle (`serial_is_open` mirrors the state check). |

## Configuration

| Function | Returns | Description |
|---|---|---|
| `serial_configure(&lib, &port, &cfg)` | `Result[Unit, SerialError]` | `GetCommState` -> patch -> `SetCommState`; unmanaged DCB fields keep driver values. |
| `serial_get_config(&lib, &port)` | `Result[SerialConfig, SerialError]` | Read back baud/data-bits/parity/stop/flow. |
| `serial_set_timeouts(&lib, &port, &t)` | `Result[Unit, SerialError]` | `SetCommTimeouts`; see the timeout semantics below. |
| `serial_get_timeouts(&lib, &port)` | `Result[SerialTimeouts, SerialError]` | Read back both timeouts. |
| `serial_config_validate(&cfg)` | `Result[Unit, SerialError]` | Pure validation (baud 1..12,000,000; data bits 5..8; parity 0..4; stop combos per winbase.h; flow 0..2). Graceful `INVALID_ARG`, never a panic. |

Enums (values match the Win32 DCB constants): `SERIAL_PARITY_NONE/ODD/
EVEN/MARK/SPACE`; `SERIAL_STOP_ONE/ONE_POINT_FIVE/TWO`;
`SERIAL_FLOW_NONE/RTS_CTS/XON_XOFF`; flush selectors
`SERIAL_FLUSH_INPUT/OUTPUT/BOTH`.

## I/O

| Function | Returns | Description |
|---|---|---|
| `serial_read(&lib, &port, max)` | `Result[Vec[UInt8], SerialError]` | Blocking-with-timeout read: returns on the first byte(s) (interval timeout 0) up to `max`; zero bytes within the read timeout -> typed `SERIAL_ERR_TIMEOUT`; `read_ms == 0` (poll mode) -> `Ok` immediately (possibly empty). |
| `serial_write(&lib, &port, &bytes)` | `Result[Int, SerialError]` | `WriteFile` with the configured write timeout; returns the byte count accepted (partial writes reported as-is). Empty payload -> `Ok(0)`. |
| `serial_flush(&lib, &port, flags)` | `Result[Unit, SerialError]` | `PurgeComm` RX/TX clear (`SERIAL_FLUSH_*`; same mapping as the reference). |
| `serial_drain(&lib, &port)` | `Result[Unit, SerialError]` | `FlushFileBuffers` -- block until the transmit queue is empty. |

## Timeout semantics (COMMTIMEOUTS, verified byte-level)

| Requested | Encoded | Behavior |
|---|---|---|
| `read_ms > 0` | interval 0, mult 0, constant `read_ms` | Blocking; returns as soon as >= 1 byte arrives or the total timeout expires (`ERROR_TIMEOUT` -> `SERIAL_ERR_TIMEOUT`). |
| `read_ms == 0` | interval MAXDWORD, mult 0, constant 0 | Poll: return immediately with whatever is buffered (0 bytes is a valid `Ok(empty)`). |
| `write_ms` | mult 0, constant `write_ms` | Write total timeout; 0 = return as soon as the driver accepts the bytes. |

Encoders/decoders are public (`serial_dcb_encode/patch/decode`,
`serial_timeouts_encode/decode`) so the wire format is golden-tested on
any host.

## Example (MCU bridge)

```xi
use xiom.serial;

let lr = serial_load();
if !lr.is_ok {
  // SERIAL_LOAD_ABSENT -> non-Windows host: SKIP.
}
let lib: SerialLibrary = lr.value;

let ports = serial_ports(&lib);          // present COM ports
let op = serial_open(&lib, "COM3");
if !op.is_ok {
  // SERIAL_ERR_NOT_FOUND: port absent on this unit -> SKIP.
}
let port: SerialPort = op.value;
let std = SerialConfig{ baud: 115200; data_bits: 8; parity: SERIAL_PARITY_NONE;
                        stop_bits: SERIAL_STOP_ONE; flow: SERIAL_FLOW_NONE };
let cf = serial_configure(&lib, &port, &std);
let rr = serial_read(&lib, &port, 256);  // typed TIMEOUT when idle
if rr.is_ok {
  let frame: Vec[UInt8] = rr.value;
}
let wr = serial_write(&lib, &port, &frame);
let cl = serial_close(&lib, &port);
```

## Error model

`SerialError { kind, code, message }` with kinds: `SERIAL_LOAD_ABSENT`
(0, SKIP), `SERIAL_LOAD_ABI` (1, FAIL), `SERIAL_ERR_NOT_FOUND` (2),
`SERIAL_ERR_ACCESS_DENIED` (3), `SERIAL_ERR_INVALID_HANDLE` (4),
`SERIAL_ERR_INVALID_ARG` (5), `SERIAL_ERR_TIMEOUT` (6),
`SERIAL_ERR_DISCONNECTED` (7, `ERROR_BROKEN_PIPE`), `SERIAL_ERR_IO` (8).
`code` carries the Win32 error for OS failures (0 for local validation);
`serial_error_name`/`serial_win32_error_name` name them. Argument
validation always returns a typed error -- no panics on bad input.

## SKIP behavior

- No Win32 backend (non-Windows CI): `serial_load()` -> ABSENT -> the
  live leg collapses into one explicit SKIP pass; the pure codec /
  validation / catalog tests still run.
- No serial device present (this host): enumeration is typed empty (the
  canonical no-ports state), the absent-device path is asserted live
  (`COM255` -> NOT_FOUND + win32 2), and every closed-port path is
  asserted. When a real port exists, the full live leg (open ->
  configure -> read-back -> timeouts -> flush -> drain -> read/write ->
  poll -> close) runs automatically on the first enumerated port.

## Limitations (0.1.0)

- Windows x64 only; the POSIX termios leg is documented design in
  `ROADMAP.md` (layout mapped from `termios`; not compiled here).
- DTR/RTS explicit line control, modem status (CTS/DSR), break
  signalling and XON/XOFF trigger tuning are later phases (`ROADMAP.md`).
- Enumeration returns names only (no friendly description/VID/PID data;
  the SetupAPI path is a roadmap item).

## Evidence

- Suite: `scripts/port.ps1 -Package xiom.serial -TimeoutSec 300` --
  **52/52 x2** on v0.64.5 (logs `%TEMP%\kilo\serial-runs\run-a/b.log`;
  recorded in `STATUS.json`).
- Coverage table: `docs/COVERAGE.md`; oracle and pins: `SPEC.md`;
  provenance and the LGPL reference disposition: `PROVENANCE.md`; lane
  audit and ABI probes: `AUDIT.md` (+ `docs/repro/abi-probe.xi`).
