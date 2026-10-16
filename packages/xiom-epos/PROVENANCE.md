# xiom.epos -- provenance

All facts below were measured in this lane (bindings R2 wave, 2026-10-16) on
windows-x64 with compiler **v0.64.5** (`$env:LOCALAPPDATA\xiom.new\bin\xiom.exe`)
and stdlib `E:\xiom-lang\stdlib`.  Pins are commit hashes; hashes are SHA-256.

## 1. License / availability decision (FIRST)

The maxon EPOS Command Library is a **closed SDK**: proprietary, no source,
no redistributable headers, no permission to redistribute
`EposCmd.dll` / `EposCmd64.dll` / `libEposCmd.so`.  Therefore, per the
closed-SDK doctrine (same shape as the `xiom.xess` prep):

- **Nothing from the SDK is vendored, linked, or committed.**
- The typed surface is declared from a **public declaration-header oracle**
  (sec. 2) and corroborated by the official public documentation (sec. 3).
- The runtime is loaded from the OS search path; absent -> typed SKIP.
- The SDK-acquisition contract (sec. 5) records the exact artifact names and
  placement; users hash their own acquired artifacts (the SDK is not
  redistributable, so no canonical upstream hash can be pinned).

## 2. Public declaration oracle (cloned, pinned)

| Item | Value |
|---|---|
| Reference repo | `https://github.com/iwata-lab/maxon_epos_ros` (public ROS driver that redistributes the vendor header) |
| Repo license | MIT (the redistributed maxon headers inside remain maxon's) |
| Clone | `E:\repos\maxon_epos_ros`, `--depth 1`, 2026-10-16 |
| **Pinned commit** | `8f3c954abdfa739c4fb26aeaa8ed8d0dfd9869b6` (2019-06-10) |
| Oracle file | `maxon_epos_driver/include/maxon_epos_driver/Definitions.h` |
| Oracle sha256 | `FD76A696575447B3E8FC1244495DB249E71159C72BFC164D95DCA593908FE8A0` |
| Header identity | maxon "Definitions.h", Date 11.2018, "Functions for Linux shared library" |

Measured from the oracle (mechanical counts, reproduced by regex over the
header): **177 `VCS_*` function declarations** + **2 Linux-layer helpers**
(`CreateCommunication`, `DeleteCommunication`) = **179 declared entries**;
**150 type constants** in 21 clusters.

Nothing from the clone is copied into the package; it is a study/declaration
oracle only.  Shared-pool row: `E:\repos\CLEANUP.md` (`maxon_epos_ros`).

## 3. Public documentation (URL only)

- Official "EPOS Command Library" documentation PDF (product page / support
  media on maxongroup.com; e.g.
  `https://www.maxongroup.com/medias/sys_master/root/9157360353310/EPOS-Command-Library-En.pdf`).
  Direct fetch from this host is blocked (403, Akamai); the URL and search
  snippets were used only to corroborate artifact names (Windows
  `EposCmd.dll`/`EposCmd64.dll`; Linux `libEposCmd.so`) and the dialog/
  selection workflow.  No content is vendored.

## 4. Present-path evidence (runtime sample; NOT the pin)

| Item | Value |
|---|---|
| Sample | `EposCmd64.dll` (64-bit), 25,758,208 bytes |
| Sample site | public third-party mirror `mkhorasani/maxon_python_windows_64` (raw GitHub) |
| Sample sha256 | `25224DFCF8F56FF06EF239FA46D7908DD1D112945C3984D94ABB8B3882144B22` |
| Local location | `E:\repos\maxon-epos-samples\EposCmd64.dll` (evidence only; never committed) |
| Identity (measured) | `VCS_GetDriverInfo` -> `"maxon motor ag - EPOS Command Library - 64-Bit"`, version **6.6** |

This hash is **an observed public sample, not a canonical upstream pin**
(official artifacts are registration-gated and versioned by maxon).  It was
loaded read-only for present-path verification; the same `VCS_GetDriverInfo`
check is what consumers should use to identify their own artifact.

Measured live results (both present-path port runs, sec. 6):

- `VCS_GetDriverInfo` rc=1, name/version as above.
- `VCS_GetDeviceNameSelection(StartOfSelection=1)` rc=1, `"EPOS4"`,
  `pEndOfSelection=0`.
- `VCS_GetErrorInfo(1)` rc=0 with buffer `"Unknown Error"` (see SPEC sec. 4).
- Export sweep: **177/177** declared `VCS_*` names resolved by
  `GetProcAddress`; `CreateCommunication`/`DeleteCommunication` **absent**
  (Linux-layer only, declared-but-not-exported on Windows -- SPEC delta).

### Isolated teardown finding (recorded, not a wrapper bug)

Calling `VCS_GetDeviceNameSelection` leaves the 6.6 sample in a state whose
process **teardown** fails fast (`exit 0xC0000409`) after `main` returned:

- reproduced 4/4 via the xiom suite and one-shot probes (with `dl_close`,
  without `dl_close`, and with the enumeration loop);
- correct data returned every time; `VCS_GetDriverInfo`/`VCS_GetErrorInfo`
  alone leave the process clean (exit 0);
- a PowerShell one-shot host performing the same call exited clean, so this
  is an artifact/teardown property of the closed DLL on this host, not a
  wrapper or ABI defect.

The suite therefore does not call it live (compile coverage still covers the
wrapper).  Full repro in SPEC.md sec. 4.

## 5. SDK-acquisition contract (exact artifacts + placement)

| Artifact | Bitness | Where it comes from | Placement for xiom.epos |
|---|---|---|---|
| `EposCmd64.dll` | x64 | maxon "EPOS Command Library" product download (installer, registration) | its install dir on `PATH` (or system dir); loaded by name |
| `EposCmd.dll` | x86 legacy | same installer | same (32-bit targets out of scope in 0.1.0) |
| `libEposCmd.so` | Linux | same package (Linux variant) | `LD_LIBRARY_PATH` / standard soname search (LP64 delta -- SPEC sec. 3) |
| `Definitions.h`/`EposCmd.h` headers | -- | ship with the SDK installer | NOT needed by this package (declaration oracle is public; nothing vendored) |

Hash policy: hash the artifacts you acquire locally and record them with your
deployment record; this repository intentionally contains **no** SDK hash
pin because the SDK is not redistributable.  Runtime self-identification via
`VCS_GetDriverInfo` is the supported check.

## 6. Lane verification record (2026-10-16, v0.64.5)

| Run | Command shape | Result |
|---|---|---|
| SKIP x2 | `.\scripts\port.ps1 -Package xiom.epos -TimeoutSec 300` | **29/29 PASS** x2 (`all tests passed (SKIP path -- no runtime)`), ~127 s per run (above port.ps1's 120 s default watchdog) |
| Present x2 | same with `E:\repos\maxon-epos-samples` prepended to `PATH` | **29/29 PASS** x2 (`present path exercised`): load -> 177/177 table -> 177/177 dl sweep -> live `VCS_GetDriverInfo`/`VCS_GetErrorInfo` -> typed helper NOT_AVAILABLE -> close |
| Compile | `--emit-ir` on each of the 6 modules | exit 0 each |
| Namespace | `scripts/namespace-check.ps1` via port.ps1 | `xiom.epos OK (6 module(s))`, 0 conflicts |

Suite totals: 29 reports per run; deterministic classification checks
(ABSENT x2, ABI x2) plus a compile-evidenced 179/179 wrapper-shape coverage
function run on every host.
