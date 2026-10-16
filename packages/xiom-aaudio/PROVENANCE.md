# xiom.aaudio -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public header (sysroot `usr/include`):
  `aaudio/AAudio.h` -- 67 `AAUDIO_API` declarations (measured
  2026-10-16 on the pinned NDK; includes the API-34 `getHardware*`
  additions and the API-32 channel-mask family).
- Link oracle: API-35 platform stubs, `libaaudio.so` (both
  architectures present in the sysroot; the stub additionally exports
  the three `AAudioTesting.h` runtime symbols -- documented exclusion).
- Function names, callback typedefs and constant values are API facts
  transcribed from the header; every constant in `aaudio.xi` was
  extracted from the pinned header on 2026-10-16.  The on-device driver
  (`docs/repro/aaudio_head_probe.c`) re-checks every transcribed value
  against the same header at build time and records the result.

## Code

- `src/aaudio_bridge.c`, `aaudio.xi`, `tests/test_conformance.xi`, the
  `docs/repro/` driver and this package's metadata are original XIOM
  code (MIT OR Apache-2.0), written for this repository; no upstream
  implementation code is vendored.
- No NDK headers are copied into the repository; the bridge compiles
  without them (self-declared pinned ABI facts only).  The repro driver
  includes `<aaudio/AAudio.h>` from the NDK at build time for the
  constants check only (not shipped as an artifact).

## License notes

- The NDK platform header (`aaudio/AAudio.h`) is distributed by Google
  under the Apache License 2.0 (bionic portions BSD-3-Clause).  This
  package interoperates with the public ABI; declarations here are
  facts of that interface, and the package itself ships no Google code.

## Touch log

- 2026-10-16: created (W2d AAudio head; per-touch PROVENANCE rule;
  `modules:` list recorded in `package.xi`).
