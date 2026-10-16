# PROVENANCE: xiom.serial

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0
>
> Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% of the
> declared surface). This package is an **independent** implementation:
> no upstream code is vendored, ported, or copied.

## 1. Declaration

`xiom.serial` 0.1.0 is original work. There is **no vendored upstream**.
The implementation is a platform wrapper written against two
authoritative oracles (sec. 2) and cross-checked, reference-only, against
the canonical community library (sec. 3). The repository stays MIT OR
Apache-2.0; no third-party license text ships with the package because no
third-party code ships with it.

## 2. Implementation oracles (pinned)

### 2.1 Microsoft Win32 API documentation

The governing specification for the comm API surface: `CreateFile`
(device path `\\.\NAME`, `OPEN_EXISTING`, exclusive share mode),
`DCB` field semantics and flag bitfields, `COMMTIMEOUTS` read/write
timeout math, `ReadFile`/`WriteFile` behavior on serial handles,
`PurgeComm` (PURGE_RXCLEAR/TXCLEAR) and `FlushFileBuffers`,
`RegOpenKeyEx`/`RegEnumValue` enumeration of
`HKLM\HARDWARE\DEVICEMAP\SERIALCOMM`, and the `GetLastError` code
meanings. Consulted 2026-10-16 (learn.microsoft.com Win32 API pages).

### 2.2 Local Windows SDK headers (byte-verified on this host)

Path root: `C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0`
(installed 10.0.26100.0 tree; also present: 10.0.19041.0, 10.0.22621.0).

| File | SHA256 | Verified content (line nos in this pin) |
|---|---|---|
| `um\winbase.h` | `EC538199F5EBE8CEC2DFD4F1BA48316EF776C82D37277AED3A677965E494F192` | `typedef struct _DCB` @559 (offsets/sizes as encoded), `XonLim` @577, `XoffLim` @578, `ByteSize` @579, `Parity` @580, `StopBits` @581, `XonChar` @582, `XoffChar` @583, `typedef struct _COMMTIMEOUTS` @590 (five DWORDs @591-595), `DTR_CONTROL_ENABLE 0x01` @548, `RTS_CONTROL_HANDSHAKE 0x02` @556, `NOPARITY..SPACEPARITY` @829-833, `ONESTOPBIT/ONE5STOPBITS/TWOSTOPBITS` @835-837 |
| `shared\winerror.h` | `0284EA46280C14063BB714D08C9EC48DE18DE6A7F0384323B263FEC234428833` | `ERROR_FILE_NOT_FOUND 2` @252, `ERROR_ACCESS_DENIED 5` @279, `ERROR_INVALID_HANDLE 6` @288, `ERROR_INVALID_PARAMETER 87` @838, `ERROR_BROKEN_PIPE 109` @946, `ERROR_INSUFFICIENT_BUFFER 122` @1045, `ERROR_MORE_DATA 234` @1873, `ERROR_NO_MORE_ITEMS 259` @1927, `ERROR_TIMEOUT 1460` @10023 |

Every constant, struct offset and flag bit in `serial.xi` traces to one
of these two entries. The runtime system libraries (`kernel32.dll`,
`advapi32.dll`) are OS components resolved through `xiom.ffi.dl` at
runtime; nothing from them is redistributed.

### 2.3 Test vectors

The DCB/COMMTIMEOUTS goldens in `tests/test_conformance.xi` are derived
from the pinned header layouts (sec. 2.2), not imported from any
upstream test suite. The exhaustive matrix (360 valid / 180 invalid
combinations) is generated from the package's own validation rules, which
mirror the winbase.h DCB constraints (1.5 stop bits only with 5 data
bits; 2 stop bits never with 5).

## 3. Reference source: libserialport (reference-only, NEVER vendored)

| Field | Value |
|---|---|
| Upstream | https://github.com/sigrokproject/libserialport |
| License | **LGPL-3.0+** (`COPYING` = LGPLv3 text; confirmed via the GitHub license API 2026-10-16 and the local file) |
| Clone | `E:\repos\serial`, `--depth 1`, pinned `21b3dfe5f68c205be4086469335fd2fc2ce11ed2` (tip "Bump libtool and package versions to 1:1:1 and 0.1.2") |
| Status | **Reference-only.** No code, structure, or comments copied. Not a link dependency; not distributed. |
| Ledger | Registered in `E:\repos\CLEANUP.md` (row `serial`, review after 2026-12-01) |

Cross-checked semantics (read for behavioral verification; the package's
own implementation and constants come from sec. 2):

| Reference location | What was verified |
|---|---|
| `windows.c` `list_ports` (487-569) | SERIALCOMM is the enumeration key; an absent key means zero ports (not an error); `RegEnumValue` + REG_SZ data carries the COM name -- `serial_ports` matches this behavior exactly |
| `serialport.c` 623-627 | DCB "sane settings": `fBinary=TRUE`, `fAbortOnError=FALSE` (plus fDsrSensitivity/fErrorChar/fNull cleared) -- the package's deterministic flag patch uses the same set |
| `serialport.c` 1089-1095 | blocking read shape: interval 0, multiplier 0, constant = timeout_ms -- byte-identical encoding |
| `serialport.c` 1204-1211, 1312-1318 | poll shape: interval MAXDWORD, multiplier 0, constant 0 -- byte-identical encoding |
| `serialport.c` 516-524 | the reference resets COMMTIMEOUTS at open then applies a mode; the package instead applies documented default timeouts at open (deliberate deviation, SPEC sec. 6) |
| `serialport.c` 738-748 | flush mapping SP_BUF_INPUT/OUTPUT -> PURGE_RXCLEAR/PURGE_TXCLEAR -- the package's `serial_flush` mapping matches |
| `windows.c` `get_port_details` (356+) | SetupAPI friendly-name/VID/PID path -- NOT implemented here; recorded as a 0.2.0 roadmap item with the same device-class approach |

## 4. Owner instruction recorded (2026-10-16)

Light-clone protocol: `git clone --depth 1` into `E:\repos\serial`, no
history; license check BEFORE any use; MIT-or-compatible only for
vendoring. libserialport checked first and found LGPL-3.0+; per the
owner's restatement it is therefore **not vendored** -- the platform
wrapper is implemented directly against the Win32 comm API (live on this
host), with the POSIX termios leg documented for the Linux build
out). The clone with pinned commit is recorded in `CLEANUP.md` as
reference-only. No other upstream was consulted.

## 5. Re-carve / refresh procedure

1. **Oracle refresh:** re-hash the two SDK headers (sec. 2.2); diff the
   DCB/COMMTIMEOUTS layouts and error codes against the SPEC pin table.
   The headers change rarely; the pin's job is to prove it each time.
2. **Reference refresh:** `git -C E:\repos\serial fetch origin` + checkout
   the new tip, update the commit in this file and `CLEANUP.md`, and
   re-run the sec. 3 cross-check table. No code is ever taken from it.
3. **Vectors:** unchanged unless the header constants move (then update
   the goldens + matrix expectations together).
4. Record the refresh as a normal package touch (README/SPEC/STATUS in
   the same commit).
