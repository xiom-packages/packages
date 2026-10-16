# xiom.epos 0.1.0 -- SPEC

## 1. Target identity

| | |
|---|---|
| SDK | maxon EPOS Command Library (EPOS / EPOS2 / EPOS4 positioning controllers), **closed / proprietary** |
| Runtime candidates | `EposCmd64.dll` (x64), `EposCmd.dll` (x86 legacy), `libEposCmd.so` (Linux) |
| Binding mode | dynamic loader (`xiom.ffi.dl`); OS search path; **nothing vendored** |
| Platform row | `windows-x64` (measured); Linux `.so` declared, LP64 delta sec. 3 |
| Measured artifact | public `EposCmd64.dll` sample, "EPOS Command Library 6.6 (64-Bit)" (PROVENANCE sec. 4) |
| Declaration oracle | maxon `Definitions.h` (Date 11.2018) redistributed by public clone `iwata-lab/maxon_epos_ros` @ `8f3c954a` |

## 2. Declared surface (measured 2026-10-16)

**179 entries** = 177 `VCS_*` + 2 Linux-layer helpers (`CreateCommunication`,
`DeleteCommunication`).  Every entry is exposed as a typed wrapper; the
authoritative alphabetical table (order of the `EPOS_FN_*` index constants
and `epos_entry_names()`) lives in `src/epos.xi`.

| Cluster (oracle section) | Entries | Wrappers in |
|---|---|---|
| Communication / gateway / sub-device / info / selection | 24 (+2 helpers) | `xiom.epos.system` |
| Object dictionary + persistence | 4 | `xiom.epos.config` |
| Motor (DC/EC) | 6 | `xiom.epos.config` |
| Sensor (encoder/hall/SSI/SSI-Ex) | 10 | `xiom.epos.config` |
| Safety (following error, profile velocity/acceleration) | 6 | `xiom.epos.config` |
| Controller gains (`VCS_Set/GetControllerGain`) | 2 | `xiom.epos.config` |
| I/O configuration (digital/analog) | 4 | `xiom.epos.config` |
| Velocity units | 2 | `xiom.epos.config` |
| Compatibility regulators (10 calls) | 10 | `xiom.epos.config` |
| Operation mode | 2 | `xiom.epos.operate` |
| State machine | 11 | `xiom.epos.operate` |
| Error handling | 2 | `xiom.epos.operate` |
| Motion info (pos/vel/current, wait) | 7 | `xiom.epos.operate` |
| Mode activation | 9 | `xiom.epos.operate` |
| Profile position | 7 | `xiom.epos.motion` |
| Profile velocity | 7 | `xiom.epos.motion` |
| Homing | 7 | `xiom.epos.motion` |
| Interpolated position (PVT buffer) | 8 | `xiom.epos.motion` |
| Position mode (+analog setpoint) | 6 | `xiom.epos.motion` |
| Velocity mode (+analog setpoint) | 6 | `xiom.epos.motion` |
| Current mode (+analog setpoint) | 6 | `xiom.epos.motion` |
| Master encoder | 2 | `xiom.epos.motion` |
| Step/direction | 2 | `xiom.epos.motion` |
| Digital/analog I/O read/write | 9 | `xiom.epos.io` |
| Position compare | 7 | `xiom.epos.io` |
| Position marker | 7 | `xiom.epos.io` |
| CAN layer (frames + NMT) | 4 | `xiom.epos.io` |

Totals: 24+2 (system) + 44 (config) + 31 (operate) + 51 (motion) + 27 (io)
= **179**.

Type constants: **150** declared in the oracle header, exposed verbatim in
`xiom.epos` across 20 clusters -- `DM_*` 4, `MT_*` 3, `ST_*` 14 (10 sensor
types + 4 states), `DIC_*` 16, `DOC_*` 10, `AIC_*` 11, `AOC_*` 2, `VD_*` 1,
`VN_*` 4, `OMD_*` 9, `HM_*` 15, `PET_*` 3, `PM_*` 3, `PCO_*` 2, `PCI_*` 3,
`PCD_*` 3, `DR_*` 4, `NCS_*` 5, `EC_*` 5, `EG_*` 33.

Helpers: `(EposLibrary)`, `epos_load_named` / `epos_load` / `epos_close` /
`epos_probe_default`, `epos_entry_names`, `epos_helper_names`,
`epos_slot`, `epos_wr_u16/u32/u64`, `epos_rd_u8/u16/u32/u64/i8/i16/i32`,
`epos_str_from_slot`, `epos_slot_copy`.

## 3. ABI rules (win-x64) + declared deltas

* Handle `void* KeyHandle` and every pointer value cross as `Int`
  end-to-end; `void*` returns cross as `*UInt8` and convert `as Int`
  (pointer -> Int only; never `Int as *UInt8`).
* `char*` out-params write into pre-zeroed owned `Vec[UInt8]` slots; strings
  are read back with `Str::from_c_str(slot.as_ptr())` (NUL-terminated by the
  library; untouched tails read empty).
* Integer in-args cross as `Int32` (the win-x64 register convention: the
  callee reads the declared low bits); `unsigned long long`/pointer args as
  `Int`; `float` args as `Float32`; `int` returns as `Int32`.
* Out-params: one owned slot each, read byte-indexed
  (`epos_rd_u8/u16/u32/u64/i8/i16/i32`); no foreign reads, no pointer
  arithmetic.
* Outcomes are flat structs carrying `ok` (`rc == 1`), `rc`, and the
  trailing `unsigned int* pErrorCode` value as `error_code` (B-26; no
  `Result[Option[T]]`).  `VCS_OpenDevice`/`VCS_OpenSubDevice` return the
  handle (not an int): `rc` is synthesized 1/0 from the non-NULL handle and
  `handle` carries the value.

Declared deltas:

| # | Delta | Status |
|---|---|---|
| D1 | Oracle is the **LP64 Linux** header (C `long` = 64-bit); win-x64 is **LLP64** (`long` = 32-bit). The package binds the win-x64 ABI (`long` fields as Int32); the Linux `libEposCmd.so` binding is declared but **not exercised** on this lane. | documented; Linux lane may add a second ABI binding |
| D2 | `CreateCommunication` / `DeleteCommunication` are declared in the Linux-layer header but **not exported** by the measured Windows DLL (177/177 VCS_* resolved; helpers 0/2). | typed `EPOS_NOT_AVAILABLE` sentinel; wrapper never null-calls |
| D3 | `VCS_GetErrorInfo` fills the buffer yet returns `rc=0` for an undefined code ("Unknown Error"). | wrapper `ok` = non-empty message; raw `rc`/`error_code` stay visible |
| D4 | `VCS_GetDeviceNameSelection` live call leaves the 6.6 artifact's process teardown failing fast (sec. 4). | finding recorded; wrapper bound + compile-covered; live call not in the suite |

## 4. Measured behaviors / repro appendix

Repro for D4 (windows-x64, sample sha256
`25224DFC...144B22`, on `PATH`), any of:

```
. scripts\port.ps1  # with the suite's selection call re-enabled
# one-shot probes used in-lane:
#   load -> VCS_GetDeviceNameSelection(1) -> print -> close   -> exit 0xC0000409
#   load -> VCS_GetDeviceNameSelection(1) -> print -> NO close -> exit 0xC0000409
#   load -> VCS_GetDriverInfo only -> close                   -> exit 0
```

All cases returned correct data (`"EPOS4"`, rc=1, end=0) before teardown; the
same call in a PowerShell host exited clean.  Classified: artifact/teardown
property of the closed DLL on this host.

Other live measurements (present-path runs): `VCS_GetDriverInfo` ->
`"maxon motor ag - EPOS Command Library - 64-Bit"` / `"6.6"`; `VCS_GetErrorInfo(1)`
-> `"Unknown Error"` (rc=0).

## 5. Toolchain notes (load-bearing for this package layout)

* All module files live under `src/` (`src/epos.xi` is the root module
  `xiom.epos`).  Reason: the current compiler's project-graph source-root
  resolution returns `[<pkg>/src]` whenever a `src/` directory exists, so a
  root module file placed at the package root is **not indexed** for
  suite/`tests` compiles ("unresolved import").  Keeping every module inside
  `src/` makes the package resolve under `port.ps1` unchanged (verified; the
  same shape currently affects other multi-module packages with root files
  outside `src/`).
* Files written with a UTF-8 **BOM** are invisible to the compiler's
  header-scan module index (`read_module_header` rejects the BOM as an
  unexpected token -> module not indexed -> "unresolved import").  Write
  package sources without a BOM (git-safe; PowerShell 5.1
  `Set-Content -Encoding UTF8` adds one -- use `[IO.File]::WriteAllText`
  with `UTF8Encoding($false)` or the editor tools).

## 6. Coverage / verification (v0.64.5, 2026-10-16)

* Declared cluster: **179/179** typed wrappers; a compile-evidenced coverage
  function in the suite invokes all 179 (26+44+31+51+27) on every compile.
* `--emit-ir` exit 0 for each of the 6 modules; namespace-check OK
  (`6 module(s)`, 0 conflicts).
* Suite `tests/test_conformance.xi`: **29/29 PASS x2** without a runtime
  (SKIP path, deterministic ABSENT x2 + ABI x2) and **29/29 PASS x2** with
  the 6.6 sample on `PATH` (177/177 table, 177/177 `GetProcAddress` sweep,
  live driver-info/error-info, typed helper NOT_AVAILABLE, clean close).
* Known limit: suite wall time ~127 s -- run port.ps1 with
  `-TimeoutSec 300`.
