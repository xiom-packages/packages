# Provenance -- xiom.tensorrt 0.1.0

## License check (done first)

| Component | License | Redistributed by this package? |
|---|---|---|
| NVIDIA TensorRT runtime (`tensorrt-cu12-libs` wheel, `nvinfer_10.dll` et al.) | **NVIDIA Software License Agreement (SLA, proprietary)** -- the wheel ships `LICENSE.txt` starting "This document is the Software License Agreement (SLA) for NVIDIA TensorRT..." | **No.** User-supplied at run time. |
| TensorRT reference headers (`NVIDIA/TensorRT`, tag `v10.16`) | Apache-2.0 (repository license) | **No.** Fetched for study only, outside the repo; not needed to build. |
| `xiom.tensorrt` package code (XIOM module, C++ bridge, tests, docs) | MIT OR Apache-2.0 | Yes (this repository). |

License conclusion: a loader-only binding is distributable under the package's
MIT/Apache-2.0 terms. The proprietary runtime is never copied into the repo,
never linked at build time, and never bundled in the package artifact. Users
obtain it from NVIDIA and accept the SLA themselves. This is the same
CLOSED-SDK pattern used by the other NVIDIA loader bindings in this repo.

## Upstream

- Project: NVIDIA TensorRT
- Upstream repository: https://github.com/NVIDIA/TensorRT
- Runtime distribution: PyPI/NVIDIA index, package `tensorrt-cu12-libs`
- Pinned runtime: **10.16.1.11** (TensorRT 10.16.1, Windows x64)
- Pinned header reference: tag **`v10.16`**, commit
  **`52399f555c2f80cb690a4a558b604e1a5f227e7c`** (headers version 10.16.0.72)
- 8.x is the documented fallback acquisition line; it is not enabled in 0.1.0.

## Artifacts fetched (outside the repository)

All under `E:\repos\tensorrt` (user-supplied runtime area):

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl` | 2,206,065,494 | `ED0D4536F1322AA2F76DA54FEB3F9BD2D14D89E4325CEF02165A98F3A2C1A493` |
| `tensorrt_cu12-10.16.1.11.tar.gz` (metapackage sdist) | 17,921 | `A044FE4A2E2E51FC205D806534102529C6F744402350B7730D221C99FFA6D269` |
| `tensorrt_cu12_libs-10.16.1.11.tar.gz` (libs sdist) | 15,757 | `53B45A3E82BEAD09638E7A3DDF4B927254B81FA0D924FE3FE594420A09EBF48B` |
| `tensorrt-10.16.1.11.tar.gz` (TensorRT metapackage) | 16,617 | `5C31EF98E1A1B53197ACC600327D6B1E4ABB503024119A2E66F21A5654EA3996` |
| `bindings.whl` (`tensorrt-cu12-bindings`) | 964,884 | `E4D7105B9700987B4FD9362ADACC0DFA7BEE3025C8AD147A86A4316B6362A85B` |
| Wheel `LICENSE.txt` (NVIDIA SLA) | -- | `C86915FD95BBEFBDDA3135AACE3E6AD6B4612846DCBDBC5D2F5A38B139DD88B4` |

The 2.2 GB platform wheel is the only artifact needed for the live leg.

Verification performed: the wheel SHA-256 matches the PyPI/NVIDIA index digest;
the wheel contains `tensorrt_libs/nvinfer_10.dll`, the
`nvinfer_builder_resource_*` DLLs, `nvinfer_plugin_10.dll` and
`nvonnxparser_10.dll`; it contains **no headers** and no CUDA runtime DLLs
(the live path uses the driver API `nvcuda.dll`). The bridge loads only
`nvinfer_10.dll`; the plugin/parser DLLs are not part of the 0.1.0 surface. The headers were
therefore fetched separately from the Apache-2.0 `NVIDIA/TensorRT` repository at
the matching `v10.16` tag into `E:\repos\tensorrt\include` as a reference
oracle. They are not in this repository and are not referenced by the build.

## What was derived vs. copied

No NVIDIA source, header, comment, or binary is reproduced in this package.

Derived (interface facts, independently written):

- the three C entry point names and signatures;
- the 10.16 wrapper layout (vptr + `mImpl` at byte 8) and release-by-`delete`
  rule;
- the `Dims64` (72-byte) and `Weights` (type, values, count) layouts;
- the vtable slot map in `SPEC.md` §3.2, obtained by inspecting the pinned
  headers and verifying each call against the live 10.16.1.11 DLL;
- enum numeric values (`DataType`, `BuilderFlag`, `MemoryPoolType`,
  `ElementWiseOperation`, `TensorIOMode`, `TensorLocation`, severities);
- the observation that 10.16 exposes `setFlag`/`clearFlag` as separate void
  methods rather than `setFlag(flag, bool)`.

The C++ bridge is original XIOM package code. The XIOM module's error model,
handle registry, logger capture, CUDA helpers, and test suite are original.

## Acquisition gate (honest)

- The runtime wheel is **2.2 GB** and requires accepting the NVIDIA SLA. It is
  not committed, cached in CI, or downloaded by the test suite.
- The wheel is **headerless**. Building this package does **not** require
  headers; the bridge declares the pinned ABI independently. Headers were used
  only as a development oracle and are optional for re-pinning.
- Without the runtime (or without an NVIDIA GPU), the conformance suite reports
  a typed SKIP and exits 0. The deterministic SKIP-path check always runs.
- Live verification was performed on an RTX 3070 Ti (compute capability 8.6,
  driver 616.92, CUDA UMD 13.4) with `XIOM_TENSORRT_DIR` pointing at the
  extracted `tensorrt_libs` directory.

## Reproduction

```powershell
# 1. License check: read the NVIDIA SLA shipped in the wheel/sdist.
# 2. Fetch the pinned runtime (user-supplied; accept the SLA).
curl.exe -L -o E:\repos\tensorrt\tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl `
  https://pypi.nvidia.com/tensorrt-cu12-libs/tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl
(Get-FileHash -Algorithm SHA256 E:\repos\tensorrt\tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl).Hash
# expect ED0D4536...

# 3. Extract and point the loader at it.
tar -xf E:\repos\tensorrt\tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl -C E:\repos\tensorrt\wheel
$env:XIOM_TENSORRT_DIR = "E:\repos\tensorrt\wheel\tensorrt_libs"

# 4. Run the suite twice (live).
.\scripts\port.ps1 -Package xiom.tensorrt -TimeoutSec 300
.\scripts\port.ps1 -Package xiom.tensorrt -TimeoutSec 300

# 5. Run without the runtime to verify the SKIP gate.
Remove-Item Env:XIOM_TENSORRT_DIR
.\scripts\port.ps1 -Package xiom.tensorrt -TimeoutSec 300
```

## Repository hygiene

`packages/xiom-tensorrt` contains only original source/docs/tests. Verify with:

```powershell
git ls-files packages/xiom-tensorrt | Select-String -Pattern 'NvInfer|nvinfer|\.dll|\.lib|\.whl'
# expected: no output
```

`trt-test.plan` is a local test artifact and is ignored by the package
`.gitignore`; it is never committed.
