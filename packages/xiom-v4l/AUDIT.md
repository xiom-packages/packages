# xiom.v4l -- AUDIT

Audit of the 0.1.0 declaration and its evidence chain.  Every claim below
is backed by a file in this package or a recorded run; anything not yet
run is called out as such.

## 1. Upstream fidelity

- Pin: `torvalds/linux` v6.19 = `05f7e89ab9731565d8a62e3b5d1ec206485eeb0b`
  (light sparse clone; `git rev-parse` recorded in the generator output and
  PROVENANCE.md).  No full kernel clone, no history blobs (clone command
  recorded; ledger row in `E:\repos\CLEANUP.md`).
- Every declared value is compiler-evaluated from the pinned text; the raw
  dump (`docs/repro/gen/v4l2_consts_dump.txt`) plus the 3107-assert gate
  (`docs/repro/gen/v4l2_const_asserts.h`) are the evidence.  The generator
  fails loudly when a name cannot be placed in the name-by-name ownership
  split (no silent drops).
- Two upstream quirks are documented, not papered over: the
  `linux/compiler.h` include absent from the UAPI tree (shim =
  headers_install-equivalent, 3 lines, recorded) and the two `GENMASK`
  FWHT mask macros (same-pin equivalence, recorded).
- License: UAPI syscall-note position recorded in PROVENANCE.md; package
  code is original + MIT/Apache-2.0; no vendored library, no copied header
  text in the package source (the pinned clone lives outside the repo).

## 2. Coverage vs claims

| Claim | Evidence |
|---|---|
| 2079 constants (841 + 1238) | `v4l2_coverage.tsv` totals + module line counts; each value == dump entry |
| 1028 layout facts / 122 structs | dump `L` lines + `layout.xi`; suite spots cover the ioctl-carrying structs |
| 29 macro mirrors | generator summary lists exactly 29 function-like `V4L2_*`/`VIDIOC_*` macros; suite exercises all families (fourcc, type/field predicates, map defaults, ctrl id helpers, DV-BT arithmetic, H264/VP8/VP9/AV1 helpers) |
| ABI 3-layer gate | Linux repro build compiled the full 3107-assert gate (`gen/v4l2-linux-abi-probe.txt`); bridge-local asserts compile on Windows; runtime `v4l_abi_check()` green on both hosts |
| SKIP path deterministic | suite proves `V4L_LOAD_ABSENT` for a bogus dir on both hosts; Windows probe is absent by construction |

Suite: **14/14 green** on the Windows host (two consecutive port.ps1 runs
recorded in STATUS.json) with the device runtimes on the recorded SKIP leg.

## 3. Found and fixed during the wave

1. **`type` is a reserved word in XIOM** -- the extern block used
   `type: Int64` parameter names; the parser derailed and silently dropped
   the whole `extern "C"` block (203 downstream errors).  Fixed: `ty`.
   Same class: `ref` renamed to `motion_ref`.
2. **UTF-8 BOM breaks catalog module indexing (compiler quirk)** -- a
   module file starting with a BOM is silently dropped from the catalog
   index (`read_module_header` returns None; the loud symptom is only
   `unresolved import 'xiom.v4l'` plus a cascade of undefined-variable
   errors).  Both hand-written `.xi` files in this package had been
   written with a BOM; stripped (precedent packages are BOM-free; the
   generator always writes BOM-free).  Root-caused by bisection against
   the compiler source (`catalog.rs read_module_header`); reproducible with
   a 6-line module.  Recommendation (recorded for the toolchain lane):
   make `read_module_header` skip a leading U+FEFF.
3. **Move-analysis warnings in the live-path walk** -- `t_live_path` closed
   the device after a potential move; resolved by borrowing
   (`t_live_capture(dev: &V4lDevice)`, `v4l_close(dev: &V4lDevice)`).
   Suite is warning-clean.
4. **-Wall/-Wextra cleanliness for the bridge** -- snprintf truncation
   warnings fixed by sizing the error/path buffers to the worst case; the
   Linux repro build is warning-clean.

## 4. Honest limits (not yet proven)

- **The live capture path has not executed against a real camera yet.**
  Both recorded hosts (Windows; WSL Linux) classify ABSENT and take the
  SKIP leg.  The pipeline code is compiled, ABI-gated and reviewed, but
  "runs on real hardware" is the Pi arm64 drill on the roadmap -- until
  then the suite's live leg is exercised only by construction.
- Functional coverage is the camera-capture head (9 ioctls); the remaining
  `VIDIOC_*` surface is declared + gated but not functionally drilled
  (explicit non-goals in SPEC.md, roadmap items 2-7).
- The LP64 claim for aarch64 is by ABI equivalence (no pointer-size or
  `long` differences in the declared structs); the arm64 compile gate is
  part of the Pi drill.
- `v4l2_format`'s union is pinned as `type + 8-byte-aligned 200-byte
  payload` (the ioctl size is what matters); per-member access beyond
  `.pix` is a roadmap item, not a claim.

## 5. Reproduce

```
pwsh packages/xiom-v4l/docs/repro/gen-v4l2-consts.ps1        # dump + modules + asserts
wsl -d Ubuntu -e bash -lc "bash <pkg>/docs/repro/run-linux-abi-probe.sh <pkg>"
.\scripts\port.ps1 -Package xiom.v4l -TimeoutSec 300          # the suite
```
