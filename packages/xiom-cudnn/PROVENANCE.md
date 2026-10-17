# PROVENANCE -- xiom.cudnn

Owner policy: `docs/UPSTREAM-FIRST.md` (upstream-first, exact pin) and the
bindings-lane licensing policy (`docs/BINDINGS-LANE.md` §4). This package
follows the CLOSED-SDK pattern: NVIDIA material is **reference-only** and
**nothing is vendored**.

## 1. Upstream and declared pin

- **Upstream project:** NVIDIA cuDNN -- https://developer.nvidia.com/cudnn
  (proprietary NVIDIA SDK; distributed through the
  `nvidia-cudnn-cu12` Python wheel).
- **Declared pin (G2):** `nvidia-cudnn-cu12` **9.27.0.42**, Windows x64
  wheel `nvidia_cudnn_cu12-9.27.0.42-py3-none-win_amd64.whl`
  (PyPI project: https://pypi.org/project/nvidia-cudnn-cu12/).

  | Item | Value |
  |------|-------|
  | Wheel bytes | 743,068,852 |
  | Wheel SHA256 | `06E9B0026F3BAD97D2B58666330FABEC04FE1672F776661ECB0CE0029C27F142` |
  | Fetched | 2026-10-17 (`pip download --no-deps`) |
  | Local (not committed) | `E:\repos\nvidia-cudnn\9.27.0.42\nvidia\cudnn` |
  | Runtime version | `cudnnGetVersion() == 92700` (9.27.0) |
  | Primary DLL | `nvidia\cudnn\bin\cudnn64_9.dll` (270,448 B) |
  | Fallback DLL | `cudnn64_8.dll` (loader path only; no 8.x live run) |

- **Header-set pin (reference oracle, not committed):** all nine
  `nvidia\cudnn\include\*.h` files, sorted-name SHA256 manifest, combined
  SHA256 `2EDFAA823755BFB62AFA0D69C38F4E1AAF7A521707953400D41EB2227E63B353`.
  Per-file hashes are in `SPEC.md` §2.  The headers were read only to
  transcribe interface facts (export names, signatures, enum values); no
  header text or code is present in this repository.

## 2. LICENSE CHECK (done before use)

- Wheel metadata: `License-Expression: LicenseRef-NVIDIA-Proprietary`,
  `License-File: License.txt`, `Classifier: Development Status :: 4 - Beta`.
- The wheel's `License.txt` is the **NVIDIA Software Development Kit
  License Agreement** ("LICENSE AGREEMENT FOR NVIDIA SOFTWARE DEVELOPMENT
  KITS"); SHA256 `49CF79BDB35734B52FE6203013B3BD759F81E998CD32AA2C65C51DB9A88C61D2`.
- The EULA permits installation/use of the SDK and distribution only of
  portions NVIDIA identifies as distributable, under its conditions. This
  package does **not** redistribute any NVIDIA file: the wheel/binaries are
  user-supplied at run time, headers are reference-only, and the committed
  material is an original interface description plus original C/XIOM code.
- Package code remains MIT OR Apache-2.0. There is no NVIDIA license text
  copied into this directory (nothing to relicense); users who install the
  wheel accept NVIDIA's EULA directly.

## 3. Companion runtime dependency

- cuDNN 9 wheels declare `Requires-Dist: nvidia-cublas-cu12`; the cuDNN
  sub-libraries dynamically load `cublasLt64_12.dll`. A live probe
  requires that user-supplied runtime as well.
- Probed reference: `nvidia-cublas-cu12` **12.9.2.10**, Windows x64 wheel
  SHA256 `623F43027D40D44CEADF0043F002BD25CF353E8F13CE90B9A87057019F560661`
  (not vendored; `tests` rely on it being on PATH or installed by pip).
- `nvcuda.dll` comes from the installed NVIDIA display driver (system
  component; no Toolkit required).

## 4. Derived vs independent

- **Derived interface facts:** export names, parameter shapes, enum values,
  version encoding and the soname set, transcribed from the pinned public
  headers / export table. These are facts of the ABI, not copyrightable
  expression copied from the headers.
- **Original:** `cudnn.xi`, `src/cudnn_bridge.c`, the loader search logic,
  the self-contained probe, tests and all documentation.
- **No vendoring:** no NVIDIA header, DLL, LIB, import library, source or
  documentation is committed. `git ls-files packages/xiom-cudnn` contains
  only the files listed in `COVERAGE.md`.

## 5. License ledger

| Material | License | In this repo? |
|----------|---------|---------------|
| xiom.cudnn source/docs | MIT OR Apache-2.0 | yes |
| `nvidia-cudnn-cu12` 9.27.0.42 | NVIDIA SDK EULA (proprietary) | no (user-supplied) |
| `nvidia-cublas-cu12` 12.9.2.10 | NVIDIA CUDA Toolkit EULA (proprietary) | no (user-supplied) |
| `nvcuda.dll` | NVIDIA display driver EULA | no (system component) |

## 6. Re-pin procedure

1. Download the new `nvidia-cudnn-cu12` wheel; verify and record the wheel
   SHA256 and version.
2. Recompute the sorted header manifest hash; update `SPEC.md` §2,
   `AUDIT.md` and this file.
3. Verify the 25 declared exports with
   `llvm-readobj --coff-exports <bin>\cudnn64_9.dll`.
4. Re-run the suite twice (`scripts/port.ps1 -Package xiom.cudnn
   -TimeoutSec 300`); update `STATUS.json` and `README.md`.
