# PROVENANCE: xiom.cublas

Owner policy: upstream-first (`docs/UPSTREAM-FIRST.md`), 100% of the
declared surface, and the lane's CLOSED-SDK / loader-only doctrine
(`docs/BINDINGS-LANE.md` sec. 4/11): the NVIDIA runtime is **user-supplied
at run time**, is **never vendored, linked, downloaded or committed** by
this package, and the suite classifies a missing runtime as a typed SKIP.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | NVIDIA cuBLAS -- CUDA Toolkit math library |
| Distribution pin | PyPI wheel **`nvidia-cublas-cu12` 12.9.2.10** (`py3-none-win_amd64`) |
| Wheel bytes | 553,162,896 |
| Wheel SHA256 | `623F43027D40D44CEADF0043F002BD25CF353E8F13CE90B9A87057019F560661` |
| Vendored | **NOTHING** -- no NVIDIA code, header, lib or DLL in this repository |

Dependency wheels fetched for the live leg (external scratch only):
`nvidia-cuda-nvrtc-cu12` 12.9.86 (76,408,187 B, SHA256
`72972EBDCF504D69462D3BCD67E7B81EDD25D0FB85A2C46D3EA3517666636349`);
`nvidia-nvjitlink-cu12` 12.9.86 (35,584,936 B, SHA256
`CC6FCEC260CA843C10E34C936921A1C426B351753587FDD638E8CFF7B16BB9DB`) was
fetched for the cuSPARSE sibling and is not needed by cuBLAS itself.

## 2. License (checked before use)

- The wheel metadata declares **`License-Expression: LicenseRef-NVIDIA-Proprietary`**
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
  `cublas.xi`, `src/cublas_bridge.c`, tests and docs only).

## 3. Declaration oracle (read from the pin; never committed)

| File | Bytes | SHA256 |
|------|-------|--------|
| `include/cublas_api.h` | 381,551 | `B64E0CE339DB7EA9E7A4D79C57CB05CF258694E2929ADBB831F63E406E43DBEA` |
| `include/cublas_v2.h` | 15,938 | `C00D426FBC7AA24C10702492C0DF2530FCF45786FC3E78832A1DCCB3FBA2C4EE` |
| `include/cublas.h` | 42,137 | `917979843ED4B042674A0DF27B86C06FE1E28B2643C8E24E6709C1E0D85C8B41` |
| `include/cublasLt.h` | 106,822 | `02BDF192D7E2209E6340B2F4D473299D7DC709D73A00CC5B24B91F7D1C5A597A` |
| `include/cublasXt.h` | 38,073 | `A51299616004AFCC0ED44D3394508D4878C66D6E5FD241BA027BC17E4DCC4FB5` |
| `include/nvblas.h` | 24,165 | `0BEBAE64184148E78C709FD283616EC831F0802CA915F1951412A9185A627A0C` |

Entry-point names and signatures were verified against `cublas_api.h` and
the DLL export table (`llvm-objdump -p`): all 16 bound `_v2` symbols are
present. Status/op constants were read from the same header.

## 4. Runtime artifacts used for the live leg (NOT committed)

| Artifact | Bytes | SHA256 |
|----------|-------|--------|
| `cublas64_12.dll` | 102,518,272 | `52CE5BA0EC5327D39BE6021F0F9362D2ED4D64D7206F9B5AFC06398D827B8E82` |
| `cublasLt64_12.dll` (dependency) | 668,673,536 | `71705A7CF0923F4AB034D0D2620BBFC989FF669AC3D79F868B7A7C597CA559C5` |
| `nvrtc64_120_0.dll` (dependency) | 89,832,960 | `0CC63349FEDFFEEC1660B30955E8028B6E4E4C26CF1E41C56DC4569FD5ECA82C` |

Verification layout: `E:\repos\nvidia-math\` (`wheels\` downloads,
`extract\` wheel trees, `runtime\` flattened DLLs). This directory is
external scratch, outside the repository, and is never referenced by a
committed path.

## 5. Derived vs independent

**Independent (XIOM-authored, MIT OR Apache-2.0):**

- `cublas.xi` -- loader classification, typed handle/plan/buffer wrappers,
  status mapping, all `unsafe`/`extern` (G5).
- `src/cublas_bridge.c` -- our loader/ABI shim: `LoadLibraryExA` +
  `GetProcAddress`, CUDA context via the driver API, device-memory
  helpers, scalar-result cache. It links nothing from NVIDIA.
- `tests/test_conformance.xi` -- original checks; all numerical vectors are
  ours (no NVIDIA test vectors imported).
- docs (`README.md`, `SPEC.md`, `AUDIT.md`, `ROADMAP.md`).

**Upstream (studied at the pin, never committed):** the wheel's headers
(declaration oracle above) and DLLs (runtime oracle only).

## 6. Link model

No link step for the runtime: `port.args.json` compiles exactly one C TU
(`src/cublas_bridge.c`); the cuBLAS DLL is opened with `LoadLibraryExA` at
run time (explicit directory uses `LOAD_WITH_ALTERED_SEARCH_PATH` so
`cublasLt64_12.dll` resolves from the same directory). `nvcuda.dll` is a
system component of the installed NVIDIA driver.

## 7. Evidence

- Suite: **62/62 x2** live (xiom v0.64.6, RTX 3070 Ti, driver 13.4,
  cuBLAS 12.9.2 -> version 120902) and **5/5 x1** on the deterministic
  SKIP path; recorded in `STATUS.json` and `AUDIT.md`.
