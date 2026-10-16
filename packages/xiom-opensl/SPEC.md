# xiom.opensl -- SPEC

Android legacy-audio bindings for XIOM -- the **A6 legacy tail** of the
Android SDK100 program (`docs/ANDROID-SDK100.md`): OpenSL ES, OpenMAX AL
and AMidi, all behind a runtime bridge with SKIP semantics.

## Scope (NDK r27b oracle)

- `SLES/OpenSLES.h` + `SLES/OpenSLES_Android.h` (+ the
  `_AndroidConfiguration` / `_AndroidMetadata` headers):
  - **flat exports (3)**: `slCreateEngine`,
    `slQueryNumSupportedEngineInterfaces`,
    `slQuerySupportedEngineInterfaces` (all present in the r27b headers
    and in the API-35 link stubs / API-36 device libs; the first two are
    `SL_API_DEPRECATED(30)` in the header but still exported);
  - **`SL_IID_*` interface-ID GLOBALS (53)**: 44 from `OpenSLES.h`
    (`SL_IID_NULL` .. `SL_IID_THREADSYNC`) + 9 Android extensions
    (`SL_IID_ANDROIDEFFECT` .. `SL_IID_ANDROIDNOISESUPPRESSION`).
- `OMXAL/OpenMAXAL.h` + `OMXAL/OpenMAXAL_Android.h`:
  - **flat exports (3)**: `xaCreateEngine`,
    `xaQueryNumSupportedEngineInterfaces`,
    `xaQuerySupportedEngineInterfaces`;
  - **`XA_IID_*` globals (41)**: 40 from `OpenMAXAL.h` + 
    `XA_IID_ANDROIDBUFFERQUEUESOURCE`.
- `amidi/AMidi.h` (+ `media/NdkMediaError.h` for `media_status_t`):
  the **14 declared functions** (`AMidiDevice_*` 6, `AMidiOutputPort_*`
  3, `AMidiInputPort_*` 5).
- Constants transcribed (see `opensl.xi`): the 17 `SL_RESULT_*` + 17
  `XA_RESULT_*`, booleans, object states/events/IDs, play
  states/events, `SL_TIME_UNKNOWN`, prefetch/seek, default device IDs,
  data locators/formats, byte order, key PCM building blocks
  (`SL_SAMPLINGRATE_44_1`/`_48`, `SL_PCMSAMPLEFORMAT_FIXED_16`, front
  speakers), priority levels, the `SL_ANDROID_*` extension family
  (PCM representation, buffer-queue item keys/events, data locators,
  recording presets, stream types, performance modes), the mirrored
  `XA_*` set, and the `AMIDI_*` opcodes/device types/device protocols +
  the `AMEDIA_*` status subset used by the AMidi surface.

### Verified exclusions (measured against the r27b oracle)

- `SPEED_OF_SOUND` (`SL_SPEED_OF_SOUND` in the Khronos base spec) is
  **not present in the r27b NDK headers** (grep over the whole
  `sysroot/usr/include` = 0 hits).  Constants are transcribed only
  "as verified"; nothing was invented.
- `AMidi_getDeviceInfo` is **not declared by `amidi/AMidi.h`** (r26.3 /
  r27.0 / r27b all declare 14 functions) and **not exported by the
  API-35 link stubs or the API-36 device `libamidi.so`** (llvm-nm,
  14/14 `AMidi*` symbols).  The bridge still ATTEMPTS the symbol at
  runtime and records the verdict (`amidi_device_count_attempt` -> -1
  absent on every oracle measured; -2 if a future platform exports it
  with an ABI beyond this oracle).  Native MIDI device objects arrive
  only via the JNI-typed `AMidiDevice_fromJava` route.
- `OpenSLES_Platform.h` type remaps (`sl_int32_t` etc.) are C typedef
  facts, not API constants; `_AndroidMetadata.h` keys are `const char*`
  strings, not Int constants (documented out).
- Long-tail constant families (container types, full speaker masks,
  the full sampling-rate ladder beyond 44.1/48) are declared out for
  0.1.0; add on demand.

## SLES interface-table model (why this surface is different)

OpenSL ES is **not a flat C API**.  The flat exports are only the engine
entry trio; everything else is object/interface-based:

- An `SLObjectItf` is a handle to a **vtable of function pointers**
  (`struct SLObjectItf_`: `Realize` slot 0, `Resume` 1, `GetState` 2,
  `GetInterface` 3, `RegisterCallback` 4, `AbortAsyncOperation` 5,
  `Destroy` 6, ...).  You call methods THROUGH the handle:
  `(*pEngine)->Realize(pEngine, SL_BOOLEAN_FALSE, ...)`.
- The `SL_IID_*` symbols are **runtime GUIDs** (addresses of 128-bit
  `SLInterfaceID_` structs), not functions.  Applications pass them to
  `CreateXxx` / `GetInterface` to select interfaces (play, buffer
  queue, engine, ...).
- OpenMAX AL follows the same model with `XA_IID_*` GUIDs and the
  `xaCreateEngine` entry trio.

This bridge therefore:

1. ABI-checks the whole export table (3 + 53 + 3 + 41 + 14 = **114
   symbols**) and additionally verifies every `SL_IID_*` slot holds a
   non-null GUID pointer (`sl_iid_null_values`);
2. exercises the flat trio FUNCTIONALLY: `slCreateEngine` -> non-null
   engine -> `Realize(engine, SL_BOOLEAN_FALSE)` -> `GetState` (must be
   `SL_OBJECT_STATE_REALIZED` = 2) -> `Destroy(engine)`;
3. runs `slQueryNumSupportedEngineInterfaces` +
   `slQuerySupportedEngineInterfaces(index)` for every index, counting
   queries that return `SL_RESULT_SUCCESS` with a non-null
   `SLInterfaceID`.

**All vtable calls stay inside the C bridge**: the engine handle never
crosses the boundary (B-25 discipline); the XIOM module sees only Int
statuses (and the recorded state via `sl_engine_last_state`).

## Classification

| Probe outcome | Marker | Suite result |
|---|---|---|
| all three libs absent (Windows, bogus trio) | `OPENSL_LOAD_ABSENT` | SKIP (green) |
| partial load / exports missing / broken install | `OPENSL_LOAD_ABI` | FAIL |
| full 114-symbol export sets + working engine | Ok | live checks |

## Design (bridge)

- `src/opensl_bridge.c` is a self-contained runtime loader (no
  link-time dependency, no NDK headers needed to compile): `dlopen` on
  Android/Linux, `LoadLibraryA` on Windows.  Missing names are reported
  per library (`xo_sl_missing` / `xo_xa_missing` / `xo_amidi_missing`).
- Pinned ABI facts are self-declared: `SLresult`/`SLboolean` are 32-bit;
  the `SLObjectItf_` vtable slot order (`Realize`=0, `GetState`=2,
  `Destroy`=6) is taken from the r27b `OpenSLES.h` declaration order.
- Handles cross as `Int`; pointers never cross.

## Documented exclusions (0.1.0)

- `AMidiDevice_fromJava` / JNI-typed routes: JNI seam, slice A11.
- Full object construction (audio player/recorder/output mix creation):
  needs the interface GUID table + datalocator structs; the engine
  lifecycle + interface-table probes are the functional head here.
- `SLAndroidConfigurationItf` Java-proxy calls: JNI seam (A11).

## Build

`scripts/port.ps1 -Package xiom.opensl -TimeoutSec 300` (compiles
`src/opensl_bridge.c` via `port.args.json`; suite SKIPs on Windows,
runs live on Android).
