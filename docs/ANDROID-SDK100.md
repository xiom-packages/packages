# ANDROID-SDK100 -- Android native surface coverage (program ledger)

Started 2026-10-15 (owner directive: Android first).  The Android mirror
of SDK100-COVERAGE.md: 100% coverage of the **Android native surface --
the NDK** -- because a native-first language binds the NDK, not the Java
SDK.  The Java world is reachable through the JNI seam (libjnigraphics +
jni.h), tracked as one slice below; binding the Java SDK itself is out of
scope by design.

## Scope (the oracles)

- **Header oracle**: NDK r27b (`27.1.12297006`) sysroot `usr/include` --
  families: `android/` (68 headers), `vulkan/` (20), `SLES/` (5),
  `EGL/` (5), `GLES3/`+`GLES2/`+`GLES/`+`KHR/`, `aaudio/` (1), `media/`,
  `camera/`, `amidi/`, `OMXAL/`, `unicode/`, `jni.h`.
- **Link oracle**: the platform stubs, present for BOTH
  `aarch64-linux-android` and `x86_64-linux-android` (sysroot API dirs
  21..35; the SDK has an android-36 platform but the r27b NDK links up
  to API 35): **26 shared libs** --
  libaaudio libamidi libandroid libbinder_ndk libc++ libc libcamera2ndk
  libdl libEGL libGLESv1_CM libGLESv2 libGLESv3 libicu libjnigraphics
  liblog libm libmediandk libnativehelper libnativewindow
  libneuralnetworks libOpenMAXAL libOpenSLES libstdc++ libsync
  libvulkan libz

Evidence: `clang --target=aarch64-linux-android26 -fPIC -shared` smoke
-> ELF64/AArch64 .so on this box (2026-10-15; BINDINGS-SESSION 11:35Z
UPDATE carries the full trail).

## Slices

| # | Slice | Oracle (headers -> libs) | Delta vs existing portfolio | Gate |
|---|---|---|---|---|
| A1 | window-core | `android/native_window*.h`, `hardware_buffer*.h` -> libnativewindow, libandroid | new | G1 |
| A2 | lifecycle-glue | `android/native_activity.h` / `configuration.h` / `looper.h` + native_app_glue (source) -> libandroid | new | G1 |
| A3 | input | `android/input.h`, `keycodes.h`, looper event integration -> libandroid | new | G1 |
| A4 | sensors | `android/sensor.h` -> libandroid | new | G1 |
| A5 | assets-storage | `android/asset_manager*.h`, `storage_manager.h`, `sharedmem.h` -> libandroid | new | G1 |
| A6 | audio | `aaudio/AAudio.h`, `SLES/*`, `OMXAL/*`, `amidi/AMidi.h` -> libaaudio, libOpenSLES, libOpenMAXAL, libamidi | new (miniaudio/portaudio are desktop APIs) | G1 |
| A7 | media | `media/NdkMedia*.h`, `NdkImage*.h` -> libmediandk | new | G1 |
| A8 | camera | `camera/NdkCamera*.h` -> libcamera2ndk | new | G1 |
| A9 | graphics-gl | `EGL/`, `GLES/2/3`, `KHR/`, EGL_ANDROID_* -> libEGL, libGLESv1_CM/v2/v3 | `xiom.gles` 0.1.0 (ANGLE/Windows); android leg = system lib names + android extensions | G1 |
| A10 | graphics-vk | `vulkan/`, `vk_video/` -> libvulkan | `xiom.vulkan` 0.6.0+ (OWNER lane); android delta = VK_KHR_android_surface | G1 + OWNER |
| A11 | jni-seam | `jni.h`, `android/bitmap.h` -> libnativehelper, libjnigraphics | new | G1 |
| A12 | system-misc | `android/log.h`, `sync.h`, `zlib.h`, binder surfaces, NNAPI, icu subset -> liblog, libsync, libz, libbinder_ndk, libneuralnetworks, libicu | partial (new) | G1 |

Coverage standard = the fleet standard: 100% of each slice's declared
surface behind a XIOM module, a suite proving it (SKIP-style when the
device lib is absent), PROVENANCE per the per-touch rule.

## Gates (blockers, by lane)

- **G1 -- compiler (THE hard gate)**: an `android-arm64` (aarch64-linux-
  android) and/or `android-x86_64` emission target + bionic runtime
  (threads, file IO, clocks, allocator, dlopen).  Feasibility inquiry
  `REL-20261015-1109-bindings` is OPEN (11:09Z; addendum pushed 11:55Z
  with toolchain/emulator evidence + the x86_64-first validation note).
  Nothing end-to-end runs until this lands; all other work can prep.
- **G2 -- stdlib**: android runtime gaps (the inquiry's Q3); scoping
  rides the G1 reply.
- **G3 -- packages/eco**: android artifacts in the publish pipeline +
  new platform tokens in `STATUS.json` / platform matrix
  (`android-arm64`, `android-x86_64`).  Coordination + retrofit-at-
  touch; not a start-gate.
- **G4 -- validation infra (local, available NOW)**: API-36 x86_64
  system image + AVD `Medium_Phone` + adb + emulator.exe on this box.
  arm64 on-device validation = a physical device or an arm64 image
  (would need an owner SDK add; NO sdkmanager installs under the
  read-only rule).  Emulator-first harness work targets x86_64; arm64
  is validated at the C-bundle level (cross-build + readelf) until a
  device exists.
- **G5 -- bindings (ours, no blockers)**: prep surfaces (SKIP-safe) +
  vendor-C cross-build spike + this coverage program.

Non-blockers: ops (Windows-hosted cross-build; no new distribution);
engine (consumer, not a gate).

## Validation path available TODAY (pre-G1)

The vendor-C half (port.args.json + C bundle -> .so + load semantics)
can be proven without the compiler target:

1. cross-build opus (canary) against the NDK for BOTH
   aarch64-linux-android26 and x86_64-linux-android26;
2. push + run a tiny native harness on the API-36 emulator via adb --
   proves the .so loads and works on-device;
3. that is exactly the packaging half every A-slice will reuse.

## Immediate wave (bindings lane)

- **W0 (DONE 2026-10-15)**: toolchain located + verified; this program
  doc; inquiry addendum; cross-smoke.
- **W1 (DONE 2026-10-15)**: vendor-C spike -- opus cross-built for
  x86_64 + aarch64; harness `dlopen` roundtrip **PASSED on the API-36
  x86_64 emulator** (repro: `docs/repro/bindings-pilot/android-ndk-spike/`;
  findings: flat-vendor include dirs + required `-lm` DT_NEEDED).
- **W2 (STARTED 2026-10-15)**: brief `docs/prep/android-wave.md`
  (oracle sizes per head, SKIP semantics, naming gate, order W2a-d);
  surfaces for the A1/A2/A5/A6 heads follow the brief; suites SKIP on
  desktop.
- **W2a (DONE 2026-10-15)**: `xiom.android` 0.1.0 A1 window-core head
  -- suite 4/4 on Windows (SKIP path); on-device probe on the API-36
  emulator: load rc=0, **0 missing exports of 27**, HWB 64x64 RGBA8
  allocate/describe/lock-write/lock-read roundtrip exact (0x11223344);
  repro `docs/repro/bindings-pilot/android-core-probe/`.
- **W2b (DONE 2026-10-15)**: `xiom.android` 0.2.0 A5 assets-storage head
  -- export set 27 -> 53 (asset_manager 17 + storage_manager 6 +
  sharedmem 3); suite green on Windows (SKIP leg); on-device:
  **0 missing exports of 53**, ASharedMemory 4096 memfd
  create/setProt/map-probe roundtrip exact (0x11223344).
- **W3**: on G1 -- first end-to-end suite on the emulator, then fan out
  slices A1-A12 as parallel agent sessions.

## Status (2026-10-15, evening)

- **A1 window-core**: DONE (`xiom.android` 0.1.0; on-device 27/27 +
  HWB roundtrip).
- **A5 assets-storage**: DONE (`xiom.android` 0.2.0; on-device 53/53 +
  SHM roundtrip).
- **A2 lifecycle-glue**: IN FLIGHT (`android/w2c-lifecycle`; looper
  functional on-device).
- **A6 audio**: AAudio head IN FLIGHT (`android/aaudio`);
  legacy tail (AMidi/OpenSL ES/OMXAL) IN FLIGHT (`android/opensl`).
- **A7 media**: core IN FLIGHT (`android/mediandk`).
- **A8 camera**: head IN FLIGHT (`android/camera2ndk`).
- **A12 starter (log+sync)**: IN FLIGHT (`android/android-sys`).
- **A3 input + A4 sensors**: NEXT WAVE (serial to W2c -- same package).
- **A9 graphics-gl**: NEXT WAVE (delta over `xiom.gles`: system lib
  names + EGL_ANDROID_*; generated package -- needs a
  generator-aware pass).
- **A10 graphics-vk**: OWNER lane (android delta =
  VK_KHR_android_surface).
- **A11 JNI seam**: NEXT WAVE (design: env/object slots supplied by
  the consumer app; gates every live Surface/Context/asset wrapper).
- **A12 remainder** (binder_ndk / NNAPI / icu / z): later waves.
- **G1 (compiler android target)**: OPEN -- owner call on the v0.64.6
  roadmap; the true end-to-end gate for XIOM-on-Android.
- **G3 (packages tokens)**: relay item filed (`REL-20261015-2210-bindings`)
  -- android-arm64/x86_64 tokens; NO vendored artifacts needed (all
  system libs).

## Evidence log

- 2026-10-15T11:35Z: SDK `C:\Android\sdk` verified -- NDK r27b (clang
  18.0.2 Android r522817b); smoke GREEN (ELF64/AArch64/DYN .so);
  headers + native_app_glue + CMake/ninja; emulator/AVD present.
- 2026-10-15T11:55Z: oracles pinned -- header counts (android 68,
  vulkan 20, SLES 5, EGL 5, GLES3 5, aaudio 1, + jni.h) and the
  link-stub list (26 libs x2 arch; API dirs 21..35).
- 2026-10-15T12:15Z: **W1 spike green** -- both arches built (ELF64;
  aarch64 machine = AArch64); on-device (API-36 x86_64 emulator):
  dlopen OK, encoder_size=31668, enc+dec create OK, encode 127 B,
  decode 960 samples, SPIKE RESULT: PASS.
- 2026-10-15T18:30Z: **W2a on-device** -- xiom.android bridge PASS on
  the API-36 x86_64 emulator (export set 27/27 resolved; HWB roundtrip
  exact); package suite 4/4 on v0.64.4 (SKIP path).
- 2026-10-15T21:10Z: **W2b on-device** -- xiom.android 0.2.0: 53/53
  exports resolved; ASharedMemory roundtrip exact; HWB evidence
  unchanged.
