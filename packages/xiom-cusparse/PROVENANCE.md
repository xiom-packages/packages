# PROVENANCE: xiom.cusparse

Owner policy: upstream-first (`docs/UPSTREAM-FIRST.md`), 100% of the
declared surface, and the lane's CLOSED-SDK / loader-only doctrine
(`docs/BINDINGS-LANE.md` sec. 4/11): the NVIDIA runtime is **user-supplied
at run time**, is **never vendored, linked, downloaded or committed** by
this package, and the suite classifies a missing runtime as a typed SKIP.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | NVIDIA cuSPARSE -- CUDA Toolkit sparse math library |
| Distribution pin | PyPI wheel **`nvidia-cusparse-cu12` 12.5.10.65** (`py3-none-win_amd64`) |
| Wheel bytes | 362,504,719 |
| Wheel SHA256 | `9E487468A22A1EAF1FBD1D2035936A905FEB79C4CE5C2F67626764EE4F90227C` |
| Runtime dependency pin | PyPI wheel **`nvidia-nvjitlink-cu12` 12.9.86** (35,584,936 B, SHA256 `CC6FCEC260CA843C10E34C936921A1C426B351753587FDD638E8CFF7B16BB9DB`) |
| Vendored | **NOTHING** -- no NVIDIA code, header, lib or DLL in this repository |

`cusparse64_12.dll` imports `nvJitLink_120_0.dll` (plus `KERNEL32.dll`),
so the nvJitLink wheel is required for the live leg. `nvidia-cublas-cu12`
is not imported by the pinned cuSPARSE DLL for the bound surface.

## 2. License (checked before use)

- The wheel metadata declares **`License: LicenseRef-NVIDIA-Proprietary`**
  and ships `licenses/License.txt`, the **NVIDIA CUDA Toolkit End User
  License Agreement** ("NVIDIA Proprietary Software"). The license text is
  reproduced neither here nor in the package.
- NVIDIA publishes these runtime wheels on PyPI under that EULA. The EULA
  permits redistribution of the runtime components as part of an
  application; **this package does not redistribute them**: the loader
  opens the user's own installation (or the wheel extracted by the user)
  at run time and nothing NVIDIA is committed.
- The public headers are used only as the **declaration oracle** (export
  names, entry-point signatures, enum/status values). No header text or
  code is copied into the package.
- Package license: MIT OR Apache-2.0 (applies to the XIOM-authored
  `cusparse.xi`, `src/cusparse_bridge.c`, tests and docs only).

## 3. Declaration oracle (read from the pin; never committed)

| File | Bytes | SHA256 |
|------|-------|--------|
| `include/cusparse.h` | 302,927 | `5A5DDA54552ABC3CED2D7DB04C65E2B31C57D363C9AB973AE433AFE02631757B` |
| `include/cusparse_v2.h` | 2,641 | `A7A7078E7A404315E0B68D0834EDB87094B91129EA3E683DBB8009DBFC29697F` |

Entry-point names and signatures were verified against `cusparse.h` and
the DLL export table (`llvm-objdump -p`): all 18 bound symbols are present.
Index/order/algorithm/data-type constants were read from the same header.

## 4. Runtime artifacts used for the live leg (NOT committed)

| Artifact | Bytes | SHA256 |
|----------|-------|--------|
| `cusparse64_12.dll` | 477,564,928 | `311D441E26746331746D6EFED76982E542C6398C622758939FCB33916E0222FB` |
| `nvJitLink_120_0.dll` (dependency) | 87,359,488 | `998494A8EFF0D8382B41BA443D668E3EAEA7B67852256CA2982C841CD5BED47A` |

Verification layout: `E:\repos\nvidia-math\` (`wheels\` downloads,
`extract\` wheel trees, `runtime\` flattened DLLs). This directory is
external scratch, outside the repository, and is never referenced by a
committed path.

## 5. Derived vs independent

**Independent (XIOM-authored, MIT OR Apache-2.0):**

- `cusparse.xi` -- loader classification, typed handle/descriptor/buffer
  wrappers, scalar marshalling, status mapping, all `unsafe`/`extern` (G5).
- `src/cusparse_bridge.c` -- our loader/ABI shim: `LoadLibraryExA` +
  `GetProcAddress`, CUDA context via the driver API, device-memory
  helpers (f32/f64/i32), HOST alpha/beta pointers. It links nothing from
  NVIDIA.
- `tests/test_conformance.xi` -- original checks; all numerical vectors are
  ours (no NVIDIA test vectors imported).
- docs (`README.md`, `SPEC.md`, `AUDIT.md`, `ROADMAP.md`).

**Upstream (studied at the pin, never committed):** the wheel's headers
(declaration oracle above) and DLLs (runtime oracle only).

## 6. Link model

No link step for the runtime: `port.args.json` compiles exactly one C TU
(`src/cusparse_bridge.c`); the cuSPARSE DLL is opened with
`LoadLibraryExA` at run time (explicit directory uses
`LOAD_WITH_ALTERED_SEARCH_PATH` so `nvJitLink_120_0.dll` resolves from the
same directory). `nvcuda.dll` is a system component of the installed
NVIDIA driver.

## 7. Evidence

- Suite: **54/54 x2** live (xiom v0.64.6, RTX 3070 Ti, driver 13.4,
  cuSPARSE 12.5.10 -> version 12510) and **5/5 x1** on the deterministic
  SKIP path; recorded in `STATUS.json` and `AUDIT.md`.
