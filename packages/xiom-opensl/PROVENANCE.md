# xiom.opensl -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public headers (sysroot `usr/include`):
  `SLES/OpenSLES.h`, `SLES/OpenSLES_Android.h`,
  `SLES/OpenSLES_AndroidConfiguration.h`,
  `SLES/OpenSLES_AndroidMetadata.h`, `SLES/OpenSLES_Platform.h`,
  `OMXAL/OpenMAXAL.h`, `OMXAL/OpenMAXAL_Android.h`,
  `amidi/AMidi.h`, `media/NdkMediaError.h`.
- Link oracle: API-35 platform stubs `libOpenSLES.so` / `libOpenMAXAL.so`
  / `libamidi.so` (x86_64 + aarch64 in the sysroot); export sets
  llvm-nm-verified: 56 (3 fns + 53 `SL_IID_*`), 44 (3 + 41 `XA_IID_*`),
  14 (`AMidi*`).
- Device oracle (on-device evidence run): API-36 x86_64 emulator
  `/system/lib64/` copies of the same three libraries -- identical
  export sets (llvm-nm re-verified 2026-10-15), constants transcribed
  from the r27b headers, cross-read from the real headers by the
  `docs/repro/opensl-probe/driver.c` harness.
- Every constant in `opensl.xi` was extracted from the pinned r27b
  header set on 2026-10-15.  `SPEED_OF_SOUND` has **no occurrence** in
  the r27b sysroot headers (grep-verified) and is therefore excluded.

## Code

- `src/opensl_bridge.c`, `opensl.xi`, `tests/test_conformance.xi`, the
  `docs/repro/opensl-probe/` harness, and this package's metadata are
  original XIOM code (MIT OR Apache-2.0), written for this repository;
  no upstream implementation code is vendored.
- No NDK headers are copied into the repository; the bridge compiles
  without them (self-declared pinned ABI facts only): SLresult/SLboolean
  are 32-bit and the `SLObjectItf_` vtable slots used here are
  Realize=0 / GetState=2 / Destroy=6, per the r27b declaration order.

## License notes

- The NDK platform headers for SLES/OMXAL are Khronos-style headers
  distributed by Google under Apache License 2.0 (with LLVM exception;
  bionic portions BSD-3-Clause); `amidi/AMidi.h` and
  `media/NdkMediaError.h` are Apache-2.0 AOSP headers.  This package
  interoperates with the public ABI; declarations here are facts of
  that interface, and the package itself ships no Google/Khronos code.

## Touch log

- 2026-10-15: created (A6 legacy tail; W2d head; per-touch PROVENANCE
  rule).  114-symbol export table + engine lifecycle functional head +
  AMidi count-attempt verdict; on-device run recorded in the package
  repro dir.
