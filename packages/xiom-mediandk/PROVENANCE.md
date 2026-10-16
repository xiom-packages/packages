# xiom.mediandk -- PROVENANCE

## Oracle

- **Headers**: NDK r27b `27.1.12297006` public headers (sysroot
  `usr/include/media/`): `NdkMediaCodec.h`, `NdkMediaCrypto.h`,
  `NdkMediaFormat.h`, `NdkMediaExtractor.h`, `NdkMediaMuxer.h`,
  `NdkMediaDataSource.h`, `NdkMediaDrm.h`, `NdkMediaError.h`
  (exact filenames verified on 2026-10-16; note `NdkMediaDrm.h`, not
  "NdkMediaDRM.h").  All function names, enum values and signatures in
  `mediandk.xi` / the bridge are API facts transcribed from these
  headers.
- **Link oracle**: `sysroot/usr/lib/x86_64-linux-android/35/
  libmediandk.so` (API-35 link stub) dynamic symbol table, dumped with
  `llvm-readelf --dyn-syms` on 2026-10-16: 276 AMedia* symbols =
  exactly the declared r27b surface intersected with the shipped set.
- **Runtime oracle (device)**: `libmediandk.so` from the API-36 x86_64
  emulator (`/system/lib64/libmediandk.so`), same dump: identical
  intersection (reports the same 276 declared symbols resolved; 37
  additional non-r27b-declared symbols out of scope).
- **Key string values**: `AMEDIAFORMAT_KEY_*` / `AMEDIACODEC_KEY_*`
  values are data definitions of the runtime library; the 143 values in
  `mediandk.xi` were dumped from the device library and are re-verified
  exhaustively by `docs/repro/mediandk-probe/` (143/143 exact).

## Code

- `src/mediandk_bridge.c`, `mediandk.xi`, `tests/test_conformance.xi`,
  the repro driver and this package's metadata are original XIOM code
  (MIT OR Apache-2.0), written for this repository; no upstream
  implementation code is vendored.
- No NDK headers are copied into the repository; the bridge compiles
  without them (self-declared pinned ABI facts only).

## License notes

- The NDK media headers (`media/*`, AOSP) are distributed by Google
  under the Apache License 2.0.  This package interoperates with the
  public ABI; declarations here are facts of that interface, and the
  package itself ships no Google code.

## Touch log

- 2026-10-16: created (A7 core media head; per-touch PROVENANCE rule);
  export set 276 symbols pinned from the stub + device runtime;
  143 key constants transcribed from the device library and
  re-verified on-device (mismatches=0).
