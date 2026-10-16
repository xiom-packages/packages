# ROADMAP: xiom.serial

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Current shipped surface: 0.1.0 (`SPEC.md` sec. 4). Everything below is
unshipped and explicitly out of the declared 0.1.0 surface.

## 0.2.0 -- line control + device identity (proposed)

| Item | Basis |
|---|---|
| DTR/RTS explicit control (`serial_set_dtr`, `serial_set_rts`) | Win32 `EscapeCommFunction` (SETDTR/CLRDTR/SETRTS/CLRRTS); the reference exposes per-line control via DCB + escape |
| Modem status reads (CTS/DSR/RING/CAR) | Win32 `GetCommModemStatus`; needed by MCU bridges that gate on DSR |
| Break signalling (`serial_set_break`) | Win32 `SetCommBreak`/`ClearCommBreak` |
| XON/XOFF trigger tuning (XonLim/XoffLim/XonChar/XoffChar) | DCB fields already encoded; surface them with typed validation |
| Flush error-queue introspection (`ClearCommError` -> COMSTAT/errors) | Win32 `ClearCommError`; useful for disconnect diagnosis alongside `ERROR_BROKEN_PIPE` |
| Friendly-name/VID/PID enumeration enrichment | SetupAPI device instances (GUID_DEVCLASS_PORTS) like the reference's `get_port_details`; adds a `description` field to `SerialPortInfo` |

## 0.3.0 -- POSIX termios leg (Linux/macOS) (proposed)

`serial_load()` grows a POSIX backend branch: the same public surface
implemented over `open(2)` + `termios` (`tcgetattr`/`tcsetattr`, baud
`cfsetispeed`/`cfsetospeed`, `VMIN/VTIME` for the read-timeout mapping,
`tcflush` TCIOFLUSH/TCIFLUSH/TCOFLUSH for `serial_flush`, `tcdrain` for
`serial_drain`, `TIOCMGET`/`TIOCMSET` for the 0.2.0 line-control calls).
Design invariants to preserve:

- `serial_read` semantics: `read_ms > 0` -> `VMIN=0, VTIME=read_ms/100` ms
  granularity; `read_ms == 0` -> `VMIN=1, VTIME=0` nonblocking.
- Enumeration on Linux: `/dev/serial/by-id/*` + `/sys/class/tty/*/device`
  scan; macOS: `IOSerialBSDClient` via IOKit or `/dev/cu.*` glob.
- The ABSENT classification stays the SKIP path: on a host without
  `/dev/tty*` access or without the platform layer, the suite SKIPs.

## 0.4.0 -- async / event-driven I/O (proposed)

- Overlapped `ReadFile`/`WriteFile` + `OVERLAPPED` events, or a
  `WaitCommEvent`-driven line-state surface (`EV_CTS`, `EV_RXCHAR`).
- A small reader-pump helper for the fleet host pattern (background
  read loop drained by a bounded queue) without callback bridging (the
  current FFI has no C callback support -- the ssl SPEC documents the
  same limitation; a pump built from `serial_read` in poll mode is the
  callback-free substitute if needed sooner).

## 1.0.0 -- stable (per doctrine sec. 7)

Promotion requires the full declared surface published + at least one
settle cycle + no open defects. Candidate gates:

- [ ] 0.2.0 surface live and conformance-green x2 on a host with a real
      port (definitions above; the 0.1.0 live-device leg auto-runs).
- [ ] POSIX leg executed on Linux CI (0.3.0) or explicitly deferred.
- [ ] No open relay items referencing the package; coverage table
      reaffirmed against the then-current SPEC.

## Non-goals (indefinite)

- USB-serial device driver management (driver install/binding).
- Modem/AT command engines, line disciplines, PPP.
- Raw USB CDC access (that is a different device class; see xiom.usb
  when it exists).
