# xiom.fidelityfx — PROVENANCE

## Upstream pin

| Field | Value |
|---|---|
| Upstream | https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK |
| Release tag | `v2.3.0` (latest release tag; annotated release "AMD FSR SDK 2.3.0") |
| Commit | `60f4ea81909200d8542eca14dccb2628b763a9a3` |
| Commit date | 2026-06-24 |
| Clone | shallow (`--depth 1 --branch v2.3.0`, LFS smudge skipped) at `E:\repos\FidelityFX-SDK` |
| Ledger | `E:\repos\CLEANUP.md` row `FidelityFX-SDK` (clone / upstream+license / date / lane / review-after) |

## License verification (clone, not premise)

The task premise said "MIT — verify LICENSE in the clone". Verification
result:

* The 2.3.0 tree has **no root `LICENSE.txt`** (unlike 1.x, which was
  MIT at the root). The operative document is
  `Kits/FidelityFX/docs/license.md` (894 lines; vendored verbatim as
  `vendor/fidelityfx/LICENSE.md`).
* Its structure: the **default** license (applies to all files except as
  noted) is AMD's *binary-redistribution* license (no source redistribution,
  no reverse engineering). An explicit **exception list** (~840 entries) is
  granted under the standard MIT text at the end of the document.
* **Every file this package vendors is individually listed in the MIT
  exception list** — verified programmatically (91/91 vendored files matched
  `Kits\FidelityFX\<path>`) and by spot-checking representative lines:
  core headers (`api/include/ffx_api.h` line 386, `ffx_api_types.h` 385,
  `ffx_api_loader.h` 384, `dx12/ffx_api_dx12.h` 382), the internal support
  chain (lines 391–409), component headers (`ffx_upscale.h` 659,
  `ffx_fsr2.h` 589, `ffx_fsr3upscaler.h` 590, `ffx_spd.h` 593,
  `gpu/fsr1/ffx_fsr1.h` 594, `gpu/spd/ffx_spd.h` 627,
  `ffx_framegeneration.h` 575, `ffx_frameinterpolation.h` 514,
  `ffx_opticalflow.h` 515), the compiled swapchain blobs
  (`framegeneration/fsr3/dx12/*` lines 511–513), and the prebuilt
  `signedbin/*` binaries (lines 581–586).
* The vendored headers also carry MIT banners in-file (e.g. `ffx_api.h`,
  `ffx_fsr2.h`), consistent with the exception list.
* Nothing outside the MIT list is vendored or committed. The signed effect
  DLLs (MIT-listed) are additionally *not* committed — they are used solely
  as local present-path evidence (§Evidence below).

## Vendored surface (byte-exact)

`vendor/fidelityfx/` mirrors the upstream `Kits/FidelityFX` layout for the
bound components; 91 files, copied byte-for-byte and never edited.
`vendor/fidelityfx/PIN.md` records upstream/tag/commit plus the **per-file
SHA256 and size**; re-carve diffs are reviewable there. The vendor tree
contains:

* `api/include/**` — the unified API, types, loader helper, dx12 backend
  descriptors.
* `api/internal/**` — the support chain the component headers compile
  against (`ffx_interface.h`, `ffx_internal_types.h`, `ffx_error.h`,
  `ffx_assert.h`, `ffx_util.h`, `ffx_message.h`, `gpu/**`).
* `upscalers/**` — `ffx_upscale.h`, FSR2 + FSR3-upscaler + SPD host headers,
  and the shader-side `gpu/**` trees (FSR1, FSR2, FSR3, FSR3-upscaler, SPD).
* `framegeneration/**` — unified frame-generation descriptors, frame
  interpolation + optical flow host headers, shader-side `gpu/**` trees, and
  the **six compiled shader-blob headers** under `fsr3/dx12/` (DXIL byte
  arrays shipped by AMD; vendored as-is, never recompiled).
* `LICENSE.md` — the SDK license document (verbatim).

## Generated artifacts

`tools/gen_fidelityfx.py` parses the vendored headers with a fail-loud C
parser (preprocessor conditionals evaluated for the `FFX_CPU` path; structs,
unions, enums, typedefs, function pointer typedefs, macro-expression
evaluation) and emits the type/struct/surface modules, the ABI oracle, the
coverage table, the manifest and `PIN.md`. The generator is the only writer
of `src/ffx_gen_*.xi|.cpp`, `docs/COVERAGE.md`, `docs/gen_manifest.json` and
`vendor/fidelityfx/PIN.md`; `--check` verifies committed == regenerated.

## Golden data

The CPU-helper golden values embedded in the suite (FSR1 EASU/RCAS constants,
SPD dispatch setup, version probes) were produced from the **pinned vendored
headers themselves** by `tools/gen_golden_values.cpp` (a maintainer aid; the
header comment records the exact compile+run line). They are regression
anchors for the bridge plumbing: if a re-pin changes the formulas, the suite
fails until the golden values are regenerated and reviewed.

## Evidence

* Two recorded suite runs (43/43, present-path with the signed DLLs on PATH —
  `Kits/FidelityFX/signedbin` from the pinned clone; nothing under that path
  is committed here).
* Headless no-DLL run: 35/35, runtime classified as typed SKIP (CI-safe).
* ASan run (`xiom --run --sanitize=address`): green, zero sanitizer findings
  after the B-28 workaround.
* The SHA256 of every vendored blob payload and every vendored file is
  recorded (PIN.md / COVERAGE.md) and re-checked by the suite at runtime.

## Package license

`MIT OR Apache-2.0` (this package's own code, tools, tests and docs).
Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
