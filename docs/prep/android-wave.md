# Android prep wave (W2) -- brief

Program: `docs/ANDROID-SDK100.md`.  W2 authors the SKIP-safe heads of
slices A1 (window-core), A2 (lifecycle-glue), A5 (assets-storage) and
A6 (audio) against the NDK r27b headers.  Authoring is Windows-side and
naming-gated only lightly (see Naming); full on-device runs are gated on
G1 (compiler emission target).  All C-level mechanics are already
proven by the W1 spike (`docs/repro/bindings-pilot/android-ndk-spike/`).

## Head modules (oracle sizes measured 2026-10-15 from r27b sysroot)

| Slice | Module head (candidate) | Oracle headers (protos) | Lib (runtime-load) |
|---|---|---|---|
| A1 | window-core | `native_window.h` (18) + `native_window_jni.h` (3) + `hardware_buffer.h` (13) + `hardware_buffer_jni.h` (3) | libandroid + libnativewindow |
| A2 | lifecycle-glue | `looper.h` (11) + `native_activity.h` (24) + `configuration.h` (52) | libandroid (+ native_app_glue, a source) |
| A5 | assets-storage | `asset_manager.h` (18) + `storage_manager.h` (8) + `sharedmem.h` (8) | libandroid |
| A6 | audio | `aaudio/AAudio.h` (72) + `amidi/AMidi.h` (15) | libaaudio, libamidi (OpenSL ES = legacy, see below) |

`SLES/OpenSLES.h` is huge (279 protos / 367 defines) but interface-based
(SLObjectItf/SLInterfaceItf vtables, not flat functions) -- the modern
head is AAudio; OpenSL ES binds second (or on demand from the engine),
as an interface-query wrapper rather than a flat export map.

## SKIP-safe semantics (desktop)

- Modules declare the surface via `xiom.ffi` externs + constants
  (100% of the header's declared cluster, typed per the B-series
  discipline).
- Library resolution uses the runtime-load pattern (like `xiom.gles`/
  `xiom.sdl3`): load `libandroid.so` / `libaaudio.so` by name at run
  time; when absent (Windows dev box) the suite reports the SKIP-style
  error and the module stays usable for type-check/emit-ir.
- On the API-36 emulator the same suites become real (libraries present
  on every Android device); the W1 harness pattern (push + run) is the
  interim runner until G1 lands.

## Naming (TBD gate)

Candidates: one package per head (`xiom.android-core`,
`xiom.aaudio`, ...) vs folding A1/A2/A5 into `xiom.android`.  Decision
waits on the compiler reply to `REL-20261015-1109-bindings`
(feasibility + target naming) and the owner's preference; the brief
and modules are authored so the rename is mechanical (module name in
`package.xi` + dir).

## Authoring recipe (follow the fleet pattern)

1. `python tools/gen_*.py`-style generation is NOT required where the
   header is parseable by hand; follow the `xiom.opus`/`xiom.sqlite`
   pattern: `src/*.xi` modules (types + externs + constants),
   `tests/test_conformance.xi` suite, `SPEC.md`, `STATUS.json`,
   `PROVENANCE.md` (independent declaration vs NDK headers, Apache-2.0
   NDK license note), `port.args.json` only if C is compiled.
2. Everything typed per B-series rules: out-params as owned byte slots,
   handles as `Int` (never cast to pointers), no pointer arithmetic.
3. Suite shape: `check()` per cluster; a first `SKIP-on-absence` gate
   that resolves the .so and reports the SKIP-style error.
4. PROVENANCE: NDK headers are the oracle (Apache-2.0 WITH
   LLVM-exception / BSD-3 for bionic parts -- record per header group);
   no upstream source code is vendored here (headers only) except
   native_app_glue (source, compile into the consumer -- not a package
   artifact).

## Reusable spike findings (apply to every Android build)

- Flat vendored trees need explicit subdir `-I`s (opus: root + float +
  fixed).
- Float/math C code must link `-lm` on Android or dlopen fails
  (`cannot locate symbol "exp"`).
- Pin `-Wl,-soname,libX.so` for the runtime-load model.
- Runner: `adb push` to `/data/local/tmp/...`, `chmod +x`, run;
  emulator = AVD `Medium_Phone_API_36.0`, headless (`-no-window
  -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect`).

## Definition of done (per head)

- Module compiles on the pinned toolchain (`port.ps1 -NoRun`) and the
  suite reports SKIP-style on Windows (no false green).
- 100% of the measured oracle cluster is declared (delta list empty or
  documented).
- STATUS.json declares `platforms: [windows-x64, android-arm64,
  android-x86_64]` + `runtime_deps` (lib names; SKIP when absent) --
  first users of the new Android platform tokens (coordinate with
  packages).
- Repro/evidence path documented for the emulator run.

## Order

W2a: A1 window-core (smallest head, exercises the full pattern).
W2b: A5 assets-storage.  W2c: A2 lifecycle-glue (+ native_app_glue C
unit).  W2d: A6 audio (AAudio first; AMidi; OpenSL ES last).
