# xiom.epos

XIOM bindings for the **maxon EPOS Command Library** -- the runtime of the
EPOS / EPOS2 / EPOS4 positioning-controller family -- via the XIOM dynamic
loader.  Closed-SDK loader slice (`0.1.0`): **nothing from the SDK is
vendored, linked, or redistributed**; the closed runtime is loaded from the
OS search path at run time and the suite reports a typed **SKIP** when it is
absent.

- Declared surface: **179 entry points** (`177 VCS_*` + 2 Linux-layer
  helpers) measured from the public declaration-header oracle
  (see PROVENANCE.md); **177/177** resolved and ABI-checked on the measured
  Windows artifact.
- Multi-soname loader: `EposCmd64.dll` -> `EposCmd.dll` -> `libEposCmd.so`.
- Typed classification: `EPOS_LOAD_ABSENT` (SKIP) / `EPOS_LOAD_ABI` (FAIL).
- Flat typed outcomes carrying the maxon `rc` **and** the library/device
  `error_code` on every call.
- Suite: `tests/test_conformance.xi` (29 reports; SKIP x2 + present x2 green
  on compiler v0.64.5).

```xiom
use xiom.epos;
use xiom.epos.system;
use xiom.epos.motion;

let l = epos_load();                       // multi-soname, SKIP-safe
if !l.is_ok {
  // l.error.kind == EPOS_LOAD_ABSENT -> no EPOS runtime on this machine
  return 0;
}
let lib: EposLibrary = l.value;

// VCS_GetDriverInfo -> "maxon motor ag - EPOS Command Library - 64-Bit", "6.6"
let info = epos_get_driver_info(&lib);

let h = epos_open_device(&lib, "EPOS4", "MAXON SERIAL V2", "USB", "USB0");
if h.ok {
  let s = epos_set_enable_state(&lib, h.handle, 1);
  let m = epos_activate_profile_position_mode(&lib, h.handle, 1);
  let v = epos_set_position_profile(&lib, h.handle, 1, 1000, 10000, 10000);
  let g = epos_move_to_position(&lib, h.handle, 1, 5000, true, true);
  let w = epos_wait_for_target_reached(&lib, h.handle, 1, 5000);
  let d = epos_set_disable_state(&lib, h.handle, 1);
  let c = epos_close_device(&lib, h.handle);
}
let done = epos_close(&lib);
```

## Modules

| Module | Entries | Content |
|---|---|---|
| `xiom.epos` | loader | sonames, classification, 150 type constants, slot helpers, numeric codecs, flat outcome types, the 177-entry table (`EPOS_FN_*` indices), multi-soname loader, probe |
| `xiom.epos.system` | 26 | communication/device handles, gateway, sub-device, driver/version/error info, name/port/baudrate selection, Linux-layer helpers |
| `xiom.epos.config` | 44 | object dictionary, motor, sensor, safety, controller gains, I/O configuration, velocity units, compatibility regulators |
| `xiom.epos.operate` | 31 | operation mode, state machine, error handling, motion info, mode activation |
| `xiom.epos.motion` | 51 | profile position/velocity, homing, IPM (PVT), position/velocity/current modes incl. analog setpoints, master encoder, step/direction |
| `xiom.epos.io` | 27 | digital/analog I/O, position compare, position marker, CAN layer |

All module files live under `src/` (load-bearing for the current toolchain --
see AUDIT.md toolchain findings).

## Building and running

The runtime is a **closed SDK** (maxon EPOS Command Library, proprietary; see
PROVENANCE.md).  This package never ships it.  To run against a real
installation:

1. Acquire the EPOS Command Library from maxon (product download; account
   required).  Windows artifacts: `EposCmd64.dll` (64-bit), `EposCmd.dll`
   (legacy 32-bit); Linux: `libEposCmd.so`.  Record your own sha256 locally.
2. Make the DLL discoverable by the process (its install directory on
   `PATH`, or system-wide placement).  `epos_load()` does the rest.
3. Run the suite:

```powershell
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"   # v0.64.5 pin
.\scripts\port.ps1 -Package xiom.epos -TimeoutSec 300
.\scripts\status.ps1 -Action update -Package xiom.epos -TestsStatus pass -Passed 29 -Failed 0 -RunBy <agent> -Commit <sha>
```

Without the runtime every host stays green: the probe classifies
`EPOS_LOAD_ABSENT` and reports SKIP; deterministic ABSENT/ABI classification
checks still run.  Note: the suite runs ~127 s (large load + 177-entry
resolution + full-surface compile), above port.ps1's 120 s default watchdog --
pass `-TimeoutSec 300`.

## Known measured behaviors (real 6.6 artifact)

- `VCS_GetErrorInfo` fills the buffer **and returns rc=0** for an undefined
  code ("Unknown Error"); the wrapper's `ok` reflects a non-empty message and
  keeps `rc` visible.
- `CreateCommunication` / `DeleteCommunication` are declared only in the
  Linux-layer header; the Windows DLL does not export them.  They resolve
  opportunistically and return the typed `EPOS_NOT_AVAILABLE` sentinel on
  Windows (never a null call-through).
- `VCS_GetDeviceNameSelection` returns correct data ("EPOS4") but the 6.6
  sample leaves the process in a state whose **teardown** fails fast
  (exit `0xC0000409`) after `main` returned; isolated in this lane (also with
  the library left loaded).  Do device-name enumeration in a short-lived
  helper process.  Full repro in SPEC.md sec. 4.

## Provenance / license

- XIOM code: MIT OR Apache-2.0.
- The EPOS Command Library is proprietary; its DLLs/SOs are **not**
  redistributed here.  The declaration oracle is the public maxon
  `Definitions.h` header (11.2018) redistributed in the public reference
  clone `iwata-lab/maxon_epos_ros`; the official public documentation URL is
  recorded.  Pins, hashes and the lane's present-path evidence live in
  PROVENANCE.md.
