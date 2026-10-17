# PROVENANCE: xiom.cufft

Owner policy: upstream-first (`docs/UPSTREAM-FIRST.md`), 100% of the
declared surface, and the lane's CLOSED-SDK / loader-only doctrine
(`docs/BINDINGS-LANE.md` sec. 4/11): the NVIDIA runtime is **user-supplied
at run time**, is **never vendored, linked, downloaded or committed** by
this package, and the suite classifies a missing runtime as a typed SKIP.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | NVIDIA cuFFT -- CUDA Toolkit FFT library |
| Distribution pin | PyPI wheel **`nvidia-cufft-cu12` 11.4.1.4** (`py3-none-win_amd64`) |
| Wheel bytes | 200,067,309 |
| Wheel SHA256 | `8E5BFAAC795E93F80611F807D42844E8E27E340E0CDE270DCB6C65386D795B80` |
| Vendored | **NOTHING** -- no NVIDIA code, header, lib or DLL in this repository |

The wheel metadata lists `nvidia-nvjitlink-cu12` as a dependency; the
pinned `cufft64_11.dll` import table contains only `KERNEL32.dll`, so no
nvJitLink (or nvrtc) DLL is needed for the bound surface. The wheel's
sibling `cufftw64_11.dll` (FFTW compatibility shim) is not used.

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
  names, entry-point signatures, enum/result values). No header text or
  code is copied into the package.
- Package license: MIT OR Apache-2.0 (applies to the XIOM-authored
  `cufft.xi`, `src/cufft_bridge.c`, tests and docs only).

## 3. Declaration oracle (read from the pin; never committed)

| File | Bytes | SHA256 |
|------|-------|--------|
| `include/cufft.h` | 13,503 | `1FCA833C4E5C3A533C3C832A782FC8C8ED08AA73D310E52AB5EA25127DAC3F5C` |
| `include/cufftXt.h` | 13,223 | `420EB4CECA7E603C4A483B681D70859518E7E2A869FAF09C696312BDC31CDAA7` |
| `include/cufftw.h` | 20,516 | `64AFCC68790A4E46A5B2556EAD6502F66CA23AD45EA88EE5B36865B4CF4D335A` |
| `include/cudalibxt.h` | 4,202 | `A1680320630E760CB28223BE86F720178B1B9777F1D53638665AB1EEBB274591` |

Entry-point names and signatures were verified against `cufft.h` and the
DLL export table (`llvm-objdump -p`): all 12 bound symbols are present.
Transform-type, direction and result constants were read from the same
header.

## 4. Runtime artifact used for the live leg (NOT committed)

| Artifact | Bytes | SHA256 |
|----------|-------|--------|
| `cufft64_11.dll` | 287,136,768 | `5B90655CA9CDF5D91CBDF2C72B995EC937EED0AEF2D6954370C711B45C929B35` |

Verification layout: `E:\repos\nvidia-math\` (`wheels\` downloads,
`extract\` wheel trees, `runtime\` flattened DLLs). This directory is
external scratch, outside the repository, and is never referenced by a
committed path.

## 5. Derived vs independent

**Independent (XIOM-authored, MIT OR Apache-2.0):**

- `cufft.xi` -- loader classification, typed plan/exec/buffer wrappers,
  result mapping, all `unsafe`/`extern` (G5).
- `src/cufft_bridge.c` -- our loader/ABI shim: `LoadLibraryExA` +
  `GetProcAddress`, CUDA context via the driver API, device-memory
  helpers, optional version resolution. It links nothing from NVIDIA.
- `tests/test_conformance.xi` -- original checks; all numerical vectors are
  ours (no NVIDIA test vectors imported).
- docs (`README.md`, `SPEC.md`, `AUDIT.md`, `ROADMAP.md`).

**Upstream (studied at the pin, never committed):** the wheel's headers
(declaration oracle above) and DLLs (runtime oracle only).

## 6. Link model

No link step for the runtime: `port.args.json` compiles exactly one C TU
(`src/cufft_bridge.c`); the cuFFT DLL is opened with `LoadLibraryExA` at
run time (explicit directory uses `LOAD_WITH_ALTERED_SEARCH_PATH`).
`nvcuda.dll` is a system component of the installed NVIDIA driver.

## 7. Evidence

- Suite: **45/45 x2** live (xiom v0.64.6, RTX 3070 Ti, driver 13.4,
  cuFFT 11.4.1 -> version 11401) and **5/5 x1** on the deterministic SKIP
  path; recorded in `STATUS.json` and `AUDIT.md`.
