# SPEC: xiom.serial -- UART/serial-port bindings (Win32 comm API, platform wrapper)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.serial` |
| Version | 0.1.0 |
| Kind | binding (platform wrapper; `keywords: ["binding"]`) |
| Target API | Win32 communications API (kernel32 `CreateFileA`, DCB, COMMTIMEOUTS, `PurgeComm`, `FlushFileBuffers`; advapi32 `RegOpenKeyExA`/`RegEnumValueA`/`RegCloseKey`) |
| Implementation oracle | Microsoft Win32 API documentation + local Windows SDK headers (winbase.h / winerror.h, 10.0.26100.0; hashes in `PROVENANCE.md`) |
| Reference source (NOT vendored) | libserialport (sigrokproject), LGPL-3.0+ -- reference-only per owner 2026-10-16; semantics cross-check only, no code copied |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (declared); POSIX termios leg is documented design only (`ROADMAP.md`) |
| Compiler pin | v0.64.5 |
| Landing | bindings lane wave 2026-10-16 (serial first pick; `BINDINGS-SESSION.md`) |

## 2. Decision: platform wrapper, not a vendored upstream

The canonical cross-platform UART library is **libserialport**, which is
**LGPL-3.0+** -- outside the vendoring policy entirely (doctrine
`docs/UPSTREAM-FIRST.md` sec. 2). The owner restated this for the serial
pick: *"LGPL-class (e.g. libserialport) must NOT be vendored: either
loader-with-absent-SKIP or skip the upstream and implement the platform
wrapper directly (Win32 comm API live on this host; POSIX termios layout
documented for the Linux leg)"*.

Decision: **implement the platform wrapper directly** over the Win32 comm
API, resolved through `xiom.ffi.dl` (the `xiom.ssl`/`xiom.openssl`
loader pattern). kernel32/advapi32 are OS components -- nothing is
vendored, no C is shipped. A shallow libserialport clone
(`E:\repos\serial @ 21b3dfe5`) is kept as a **reference-only**
cross-check (`PROVENANCE.md` records exactly what was compared).

Enumeration uses the registry `SERIALCOMM` device map rather than
SetupAPI: it is the canonical fast path (the reference uses the same key
in `list_ports`, including the **absent-key = no ports** semantics), it
needs only advapi32, and it returns the port names callers open. The
SetupAPI friendly-name/VID/PID path is a roadmapped enrichment, not a
coverage gap.

## 3. Pin: libraries, entry points, layouts, codes

**Libraries (load order):** `kernel32.dll` (comm API), `advapi32.dll`
(registry enumeration). Both are always present on Windows; a failed
kernel32 load classifies as `SERIAL_LOAD_ABSENT` (SKIP).

**Resolved entry points (14):** `CreateFileA`, `CloseHandle`, `ReadFile`,
`WriteFile`, `GetCommState`, `SetCommState`, `GetCommTimeouts`,
`SetCommTimeouts`, `PurgeComm`, `FlushFileBuffers`, `GetLastError`
(kernel32); `RegOpenKeyExA`, `RegEnumValueA`, `RegCloseKey` (advapi32).
Missing entry points after a successful library load -> `SERIAL_LOAD_ABI`
(FAIL). `serial_probe` reports the count; the suite asserts 14.

**DCB layout (28 bytes; oracle winbase.h @559-588, Windows SDK
10.0.26100.0):**

| Offset | Field | Width | Notes |
|---|---|---|---|
| 0 | `DCBlength` | u32 | 28 |
| 4 | `BaudRate` | u32 | 1 .. 12,000,000 (package validation window) |
| 8 | `Flags` | u32 | bitfield: fBinary=1 (bit 0), fParity (1), fOutxCtsFlow (2), fOutxDsrFlow (3), fDtrControl (4-5), fDsrSensitivity (6), fTXContinueOnXoff (7), fOutX (8), fInX (9), fErrorChar (10), fNull (11), fRtsControl (12-13), fAbortOnError (14) |
| 12 | `wReserved` | u16 | 0 |
| 14 | `XonLim` | u16 | 2048 (encode default) |
| 16 | `XoffLim` | u16 | 512 (encode default) |
| 18 | `ByteSize` | u8 | 5..8 |
| 19 | `Parity` | u8 | 0..4 = none/odd/even/mark/space (winbase.h @829-833) |
| 20 | `StopBits` | u8 | 0/1/2 = 1/1.5/2 (winbase.h @835-837) |
| 21 | `XonChar` | u8 | 0x11 (encode default) |
| 22 | `XoffChar` | u8 | 0x13 (encode default) |
| 23-25 | `ErrorChar`/`EofChar`/`EvtChar` | u8 | 0 |
| 26 | `wReserved1` | u16 | 0 |

Flag policy (deterministic patch): fBinary=1; fParity set for any
non-NONE parity; `SERIAL_FLOW_RTS_CTS` -> fOutxCtsFlow +
RTS_CONTROL_HANDSHAKE (0x02); `SERIAL_FLOW_XON_XOFF` -> fOutX + fInX +
RTS_CONTROL_ENABLE (0x01); flow NONE -> RTS_CONTROL_ENABLE;
DTR_CONTROL_ENABLE (0x01) always; fAbortOnError/fErrorChar/fNull/
fDsrSensitivity/fOutxDsrFlow cleared (the reference's "sane settings"
set, cross-checked). `serial_configure` patches a live DCB taken from
`GetCommState`, so unmanaged fields keep driver values.

**COMMTIMEOUTS layout (20 bytes; oracle winbase.h @590-595):**
`ReadIntervalTimeout`, `ReadTotalTimeoutMultiplier`,
`ReadTotalTimeoutConstant`, `WriteTotalTimeoutMultiplier`,
`WriteTotalTimeoutConstant` (all u32). Encoding:
`read_ms > 0` -> (0, 0, read_ms); `read_ms == 0` -> (MAXDWORD, 0, 0);
writes -> (0, write_ms). Both shapes are byte-identical to the
libserialport encodings (serialport.c timeout blocks).

**Win32 error codes (oracle winerror.h, Windows SDK 10.0.26100.0; all
verified at their #define lines):**

| Code | Name | Mapped kind |
|---|---|---|
| 2 | `ERROR_FILE_NOT_FOUND` | `SERIAL_ERR_NOT_FOUND` |
| 5 | `ERROR_ACCESS_DENIED` | `SERIAL_ERR_ACCESS_DENIED` |
| 6 | `ERROR_INVALID_HANDLE` | `SERIAL_ERR_INVALID_HANDLE` |
| 87 | `ERROR_INVALID_PARAMETER` | `SERIAL_ERR_INVALID_ARG` |
| 109 | `ERROR_BROKEN_PIPE` | `SERIAL_ERR_DISCONNECTED` |
| 122 | `ERROR_INSUFFICIENT_BUFFER` | `SERIAL_ERR_IO` |
| 234 | `ERROR_MORE_DATA` | (enumeration: skip entry) |
| 259 | `ERROR_NO_MORE_ITEMS` | (enumeration: end of values) |
| 1460 | `ERROR_TIMEOUT` | `SERIAL_ERR_TIMEOUT` |

## 4. Declared surface (0.1.0) -- 27 public functions

Loader: `serial_load`, `serial_load_named`, `serial_unload`,
`serial_probe`. Ports: `serial_ports`, `serial_open`, `serial_close`,
`serial_is_open`. Configuration: `serial_configure`, `serial_get_config`,
`serial_set_timeouts`, `serial_get_timeouts`, `serial_config_validate`.
I/O: `serial_read`, `serial_write`, `serial_flush`, `serial_drain`.
Pure codecs: `serial_dcb_encode`, `serial_dcb_patch`, `serial_dcb_decode`,
`serial_timeouts_encode`, `serial_timeouts_decode`. Catalogs:
`serial_error_name`, `serial_win32_error_name`, `serial_parity_name`,
`serial_stop_name`, `serial_flow_name`. Classification constants:
`SERIAL_LOAD_ABSENT` (SKIP) / `SERIAL_LOAD_ABI` (FAIL) + 7 error kinds +
4 enum families + flush selectors + baud window + default timeouts.

**Non-goals (explicit):** DTR/RTS line control and modem-status reads;
break signalling; XON/XOFF trigger-character tuning; SetupAPI device
properties (descriptions, VID/PID, transport); overlapped/event-driven
async I/O; POSIX termios execution (design only); RS-485 modes. See
`ROADMAP.md`.

## 5. Design and safe boundary (G5)

`serial.xi` is the only module and holds every `unsafe` block. All FFI
goes through fn-pointer casts over `xiom.ffi.dl`; handles/symbols are
`Int` fields and casts happen only at call sites. Structs travel through
XIOM-owned `Vec[UInt8]` slots (`with_len`; zero-initialized) written with
the ffi byte helpers -- the W-2 out-param recipe; no C malloc/free and no
tuple returns. `int_to_str` is module-local (BINDINGS-COMPILER-FINDINGS
pattern). Argument validation runs **before** state checks and returns
typed `SERIAL_ERR_INVALID_ARG` (kinds/codes carry the full context) --
public entry points never panic on user input (no input-condition
`requires` clauses; whole-body-unsafe helpers that need one declare it).

Reads copy out of the slot into a fresh `Vec[UInt8]` clamped to the
reported byte count; writes pass `&bytes[0] as *UInt8` (the tls_libssl
pattern). `serial_open` is exclusive (`dwShareMode = 0`), targets
`\\.\NAME` with `OPEN_EXISTING` and applies default timeouts
(1000/1000 ms) so an open port is immediately readable.

Classification: `SERIAL_LOAD_ABSENT` -> SKIP; `SERIAL_LOAD_ABI` -> FAIL;
absent device -> `SERIAL_ERR_NOT_FOUND` (the device-fleet SKIP
classification, deterministic via `COM255`); all other OS failures ->
typed kinds above.

## 6. Deliberate deviations from the reference (documented)

1. **Open-time default timeouts** (read 1000 ms blocking, write 1000 ms):
   libserialport opens with all-zero (immediate-return) timeouts and
   defers mode selection; for an MCU bridge an open port being readable
   is the useful default. The wire encodings for both modes are
   byte-identical.
2. **Data bits 5..8**: winbase.h's DCB comment says "4-8"; 5..8 matches
   the reference (SP_BITS) and common practice.
3. **Single-axis flow enum**: one `flow` value (none/rts-cts/xon-xoff)
   instead of the reference's separate rts/cts/dtr/dsr/xon_xoff axes;
   the underlying DCB flags set is the reference's canonical combination.
4. **Validation window on baud** (1..12,000,000) and read/write payload
   bounds (<= 65,536 bytes per call) are package policy with typed errors.

## 7. Suite matrix (what proves the surface; see docs/COVERAGE.md)

- Pure: 4 DCB byte-goldens (flags 0x1011 / 0x2017 / 0x1311 / 5N1.5),
  decode round-trips, too-short slots, hardware-flow decode precedence,
  **360/360 valid-combo round-trip + 180/180 invalid-combo rejection**
  exhaustive matrix, 13 validation edges, 5 COMMTIMEOUTS goldens/decodes,
  3 name catalogs.
- Live (always on Windows): loader + named re-load + unload + probe (14
  entry points); SERIALCOMM enumeration (typed empty = SKIP note);
  absent device `COM255` -> NOT_FOUND/win32 2; empty-name -> INVALID_ARG;
  16 closed-port typed-error checks (every public call, validation-order
  included).
- Live device (auto-runs on the first enumerated port when present):
  open with defaults, get_timeouts = 1000/1000, configure 9600 8N1 ->
  read-back identical, set/get 300/300, flush both, drain, blocking read
  (typed TIMEOUT when idle), write Ok(4), poll-mode read, close.

## 8. Re-pin procedure

1. Re-hash the SDK headers (winbase.h/winerror.h); if the toolchain host
   moves to a new SDK, verify the DCB/COMMTIMEOUTS offsets and the error
   codes again (they are stable but the pin's job is to prove it).
2. If the libserialport reference moves, `git -C E:\repos\serial fetch`
   the new commit, update `PROVENANCE.md` (commit + what was compared),
   nothing to re-port (independent implementation).
3. Re-run `scripts/port.ps1 -Package xiom.serial -TimeoutSec 300` x2 and
   record; update README/SPEC rows in one commit.
