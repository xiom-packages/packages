# xiom.fidelityfx — SPEC

AMD FidelityFX SDK surface bindings for XIOM, pinned at **FidelityFX-SDK
`v2.3.0`** (`60f4ea81909200d8542eca14dccb2628b763a9a3`, 2026-06-24, "AMD FSR
SDK 2.3.0"). Scope: the engine upscaler / post family as exposed by the
pinned public headers — FSR1 (EASU/RCAS), FSR2, FSR3 upscaling, frame
generation (frame interpolation + optical flow), and SPD (single-pass
downsampler). CAS and LPM do **not** exist in the 2.3.0 headers (the 2.x SDK
moved past the image-processing kit) and are out of the declared surface by
construction.

## 1. Package layout

```
package.xi                  manifest (modules: xiom.fidelityfx + 3 generated)
fidelityfx.xi               root module: loader, unified API, builders, CPU helpers
src/ffx_bridge.cpp          hand-written C++20 bridge (CPU helpers, blobs, versions)
src/ffx_gen_abi.cpp         GENERATED ABI oracle (static_asserts + runtime probe)
src/ffx_gen_types.xi        GENERATED: enum values, #define constants, blob registry
src/ffx_gen_structs.xi      GENERATED: struct sizes/offsets + loop tables
src/ffx_gen_surface.xi      GENERATED: declared-function census records
tools/gen_fidelityfx.py     the generator (parses the vendored headers; --check)
tools/gen_golden_values.cpp golden-value maintenance aid (see PROVENANCE)
vendor/fidelityfx/**        verbatim MIT-listed headers + compiled blobs + LICENSE
docs/COVERAGE.md            GENERATED per-component coverage table + full census
docs/gen_manifest.json      GENERATED machine-readable surface census
tests/test_conformance.xi   the conformance suite (43 checks with the DLLs, 35 headless)
```

`modules:` in `package.xi` lists all four modules. The generator, the ABI
oracle, the struct/type/surface tables and COVERAGE.md are the single source
of truth for the surface: `python tools/gen_fidelityfx.py --check` fails on
any drift.

## 2. Vendoring and licensing

Everything under `vendor/fidelityfx/` is **byte-exact** upstream content
(`vendor/fidelityfx/PIN.md` records the per-file SHA256). The six compiled
shader-blob headers (`framegeneration/fsr3/dx12/FrameInterpolation*PS/VS.h`,
DXIL byte arrays used by the frame-generation swapchain) are vendored **as
shipped** — no shader is recompiled by this package. Every vendored file is
individually listed in the SDK's MIT exception list
(`Kits/FidelityFX/docs/license.md`; the vendored copy is
`vendor/fidelityfx/LICENSE.md`); no file under AMD's binary-redistribution
default license is vendored. The signed effect DLLs are **not** vendored or
committed — they are used only as local present-path evidence (see §6).

## 3. Declared surface and binding model

The declared C surface is the public header surface of the bound components,
per component (full generated table in `docs/COVERAGE.md`):

| Component | Declared fns | Callable | Metadata (typed runtime classification) |
|---|---|---|---|
| core (unified api + message helpers) | 10 | 6 | 4 |
| fsr2 | 13 | 0 | 13 |
| fsr3upscaler | 14 | 0 | 14 |
| spd (host + CPU setup) | 6 | 2 | 4 |
| fsr1 (EASU/RCAS CPU) | 3 | 3 | 0 |
| frameinterpolation | 9 | 0 | 9 |
| opticalflow | 6 | 0 | 6 |
| **total** | **61** | **11** | **50** |

Skips: **0**. No declared record is silently dropped.

Binding kinds (`surface_kind`):

* `unified` (5) — `ffxCreateContext` / `ffxDestroyContext` / `ffxConfigure` /
  `ffxQuery` / `ffxDispatch` from `ffx_api.h`. Resolved at runtime from any
  module exporting them (the shipped loader / upscaler / framegeneration
  DLLs each export exactly these five). Fully callable; descriptors are built
  into caller-owned XIOM byte buffers.
* `loader` (1) — the SDK's own `ffxLoadFunctions` helper from
  `ffx_api_loader.h`, compiled into the bridge over the vendored header;
  fills the five-pointer `ffxFunctions` table into an owned slot.
* `cpu` (5) — constant/config helpers compiled from the pinned GPU headers on
  their CPU path: FSR1 `ffxFsrPopulateEasuConstants`,
  `ffxFsrPopulateEasuConstantsOffset`, `FsrRcasCon`; SPD `ffxSpdSetup`
  (both overloads). Executed headless; results land in owned buffers.
* `hostapi` (48) + `inline` (2) — the per-effect host APIs (FSR2 `ffxFsr2*`,
  FSR3 `ffxFsr3Upscaler*`, `ffxFrameInterpolation*`, `ffxOpticalflow*`,
  `ffxSpd*`, plus two `ffxApi*DX12` inline helpers). These are *source-level*
  declarations: the 2.3.0 provider architecture ships them compiled into
  consumers, while the signed effect DLLs export the unified API only. The
  binding resolves every name by `dl_sym` at runtime and reports a **typed**
  result (observed: 50/50 `ABSENT` on the signed binaries; a source-built
  module exposing legacy names flips the count honestly). Their context
  objects are app-owned `uint32_t data[FFX_*_CONTEXT_SIZE]` blobs; the
  package exposes the exact staging sizes (e.g. FSR2 context = 524,288
  bytes, SPD = 37,200) and zero-fill/release lifecycle.

Data model: the generator emits every parsed struct as
`FFX_SIZEOF_<Struct>` + `FFX_OFFSET_<Struct>_<field>` constants (direct,
promoted anonymous-union, and one nested level such as
`FFX_OFFSET_ffxConfigureDescGlobalDebug_header_type`). `src/ffx_gen_abi.cpp`
independently pins all of them with `static_assert`s against the vendored
headers compiled as C++20, and the suite re-verifies at runtime through
compiler-computed `sizeof`/`offsetof` probes (70 structs / 1,553 offsets,
0 mismatches). The dx12 backend descriptor headers are parse-only (they
require DirectX-Headers); their metadata is emitted with a note and excluded
from the compiler-verified set.

## 4. Error taxonomy

Flat outcome structs only (no `Result[Option[T]]`). Classes (`FfxProbe.class`
/ `FfxContextOutcome.class`):

| Class | Meaning | Suite consequence |
|---|---|---|
| `FFX_CLASS_OK` (0) | success | PASS |
| `FFX_CLASS_ABSENT` (1) | no module resolved | typed SKIP |
| `FFX_CLASS_ABI` (2) | module present, entry point missing | FAIL |
| `FFX_CLASS_API_ERROR` (3) | API returned a non-zero code that is not the no-device signal | FAIL when unexpected |
| `FFX_CLASS_NO_DEVICE` (4) | device-requiring create refused without a device | typed SKIP/no-device evidence |

Bridge-local typed errors: `FFX_BRIDGE_NULL` (-1), `FFX_BRIDGE_RANGE` (-2),
`FFX_BRIDGE_ARG` (-3); `FFX_BRIDGE_OK` (0). Code names come from the bridge
(`ffx_bridge_return_code_name` / `ffx_bridge_bridge_error_name`).

Observed runtime matrix on the signed 2.3.0 modules (present-path, no device;
captured by the suite):

| Module | configure(GLOBALDEBUG) | create(unknown type) | create(upscale, no device) | versions(UPSCALE, device=null) |
|---|---|---|---|---|
| loader | 2 UNKNOWN_DESCTYPE (typed) | 2 | 1 ERROR -> NO_DEVICE | 0 OK, count 2 (`3.1.5` first) |
| upscaler | 0 OK | 4 NO_PROVIDER | 1 ERROR -> NO_DEVICE | 0 OK, count 2 |
| framegeneration | 0 OK | 4 NO_PROVIDER | 4 NO_PROVIDER -> NO_DEVICE | 0 OK, count 0 (1 for FRAMEGENERATION) |

The classifier maps `NO_PROVIDER` *and* generic `ERROR` on a
device-requiring effect descriptor (UPSCALE / FRAMEGENERATION /
FRAMEGENERATIONSWAPCHAIN) to `FFX_CLASS_NO_DEVICE`; every other non-zero code
is `FFX_CLASS_API_ERROR`.

## 5. Discipline compliance (v0.64.4)

* no `x as *UInt8` handle casts: handles cross as `Int`, pointers only via
  owned `Vec[UInt8]` (`as_mut_ptr`); no pointer arithmetic anywhere in the
  package (the bridge takes one out-buffer pointer per call and does its own
  byte offsets in C);
* no bare `null` to C: nullable pointer args are the `Int` literal `0`;
* no foreign-pointer reads: every out-param is copied by the bridge into an
  owned slot and read byte-indexed (`desc_get_*`, `Vec[i]`);
* one owned slot per out-param; no `&mut` of Result/struct-return temps; no
  `Result[Option[T]]`.
* Str equality uses `string.str_compare`.
* Two stdlib 0.64.4 defects found in-lane are worked around and recorded in
  `docs/BINDINGS-COMPILER-FINDINGS.md` (B-27, B-28):
  * `ffi.write_u32_at` / `ffi.write_u64_at` ignore their `offset` argument
    (always write at base+0) — the package uses local byte-store writers;
  * `Vec.reserve` mishandles `cap == 0`, so `Vec.with_len(n)` can
    under-allocate and then zero `n * 8` bytes (heap overflow, confirmed by
    ASan) — the package builds owned buffers with `owned_bytes()` (push
    growth) instead.

## 6. Evidence and how to run

```
# headless (no SDK binaries): 35 checks, runtime -> typed SKIP
scripts\port.ps1 -Package xiom.fidelityfx -TimeoutSec 300

# present-path (signed effect DLLs as local evidence; nothing committed):
$env:PATH = "<clone>\Kits\FidelityFX\signedbin;" + $env:PATH
scripts\port.ps1 -Package xiom.fidelityfx -TimeoutSec 300    # 43 checks
```

Both configurations are green (x2 recorded). The suite additionally passes
under `xiom --run --sanitize=address` with zero ASan findings. The blob
registry check reads each vendored blob through the bridge into an owned
buffer and compares size + SHA256 against the generated registry (payload
hashes are recorded in `docs/COVERAGE.md` and `src/ffx_gen_types.xi`); the
file-level hashes of the whole vendor tree are in `PIN.md`.

`STATUS.json` records the latest run (`stage: incubating`, suite
`tests/test_conformance.xi`).

## 7. Re-carve procedure (next release tag)

1. `git clone --depth 1 --branch <new-tag>` into `E:\repos\FidelityFX-SDK`;
   re-verify the license structure (MIT exception list vs binary default) and
   re-check that every vendored path is individually listed.
2. Re-copy the exact file set byte-for-byte; move/rename nothing.
3. `python tools/gen_fidelityfx.py` — review the diff (counts, offsets, blob
   hashes, census). `--check` must pass.
4. Rebuild the golden values with `tools/gen_golden_values.cpp` and update
   the suite constants if the pinned formulas changed.
5. Run the suite x2 (present + absent), re-record `STATUS.json`, append the
   diff summary to this SPEC.
