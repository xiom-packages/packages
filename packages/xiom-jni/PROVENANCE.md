# xiom.jni -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public headers (sysroot `usr/include`):
  `jni.h` (1141 lines: primitive typedefs, `jvalue`, `jobjectRefType`,
  `JNINativeMethod`, the 233-slot `JNINativeInterface`, the 8-slot
  `JNIInvokeInterface`, `JavaVM*` init structs, the `JNI_VERSION_*` /
  `JNI_*` manifest macros) and `android/bitmap.h` (265 lines:
  `AndroidBitmapInfo` 20-byte struct, result codes, format/alpha/
  compress enums, the 6 `AndroidBitmap_*` prototypes; `getPixels` is
  NOT declared in r27b -- pre-NDK inline, see SPEC).
- Link oracle: API-35 platform stubs in the sysroot
  (`libjnigraphics.so`: 6 `AndroidBitmap_*` exports of its 40 total --
  the other 34 are `AImageDecoder_*` from `android/imagedecoder.h`, a
  different head; `libnativehelper.so` API 31+: `JNI_CreateJavaVM`,
  `JNI_GetCreatedJavaVMs`, `JNI_GetDefaultJavaVMInitArgs` +
  `AFileDescriptor_*` (not jni.h; excluded)).  Cross-checked against
  the LIVE API-36 emulator libs: per-library `dlsym` provider map in
  `docs/repro/recorded-shell.txt` (all 9 resolve; the `JNI_*` trio is
  reachable through either handle because `libjnigraphics.so` depends
  on `libnativehelper.so`, hence "both" in the map).
- Function names, table order (`JNINativeInterface` 233 slots), struct
  layouts and constant values are API facts transcribed from the
  headers.  The transcription is checked at BUILD TIME against the real
  headers in `docs/repro/jni_head_probe.c`: `_Static_assert`s for every
  module constant (JNI versions/codes/ref types; bitmap result codes,
  formats, alpha flags, the 2^31 hardware flag, compress formats),
  `sizeof(jvalue)==8`, `sizeof(JNINativeMethod)==3*sizeof(void*)` +
  member offsets, `sizeof(struct JNINativeInterface)==233*sizeof(void*)`,
  `sizeof(AndroidBitmapInfo)==20` + member offsets; and the bridge's
  numeric offset table (`xj_abi_offset` etc.) is compared **at runtime**
  against the header's `offsetof` for all 56 used table members + 3
  invoke members + 5 bitmap-info members + 3 native-method members --
  all identical on the API-36 emulator.
- Measurement reconciliation (task shorthand -> header truth): the A11
  row names `AndroidBitmap_getPixels` -- absent from r27b (legacy
  inline); the declared read path is getInfo+lockPixels (SPEC).  The
  libnativehelper cluster here is exactly the three VM entry points
  `jni.h` labels "the only symbols exported for JNI by the VM".
- Live seam evidence (not vendored code): the `app_process` run of
  `docs/repro/Probe.java` + `libxjniprobe.so` proves the consumer
  contract (JNI_OnLoad-supplied vm -> env -> table calls -> bitmap
  roundtrip -> Java-side readback) on the API-36 x86_64 emulator;
  recorded in `docs/repro/recorded-app.txt`.

## Code

- `src/jni_bridge.c`, `src/jni.xi`, `tests/test_conformance.xi`,
  `docs/repro/*` and this package's metadata are original XIOM code
  (MIT OR Apache-2.0), written for this repository; no upstream
  implementation code is vendored.  The bridge compiles without any
  NDK header: it self-declares the pinned ABI facts (tables, structs,
  enums) from the headers -- declarations of interface facts, nothing
  copied.  The on-device drivers `#include <jni.h>` /
  `<android/bitmap.h>` at build time only (oracle gate), never shipped.

## License notes

- `jni.h` as distributed in the NDK carries the AOSP/Sun-interface
  notice (Apache-2.0; the JNI specification text notes the interfaces
  are expected to be VM-neutral).  `android/bitmap.h` carries the
  Apache License 2.0 AOSP notice; bionic-derived portions of the NDK
  sysroot are BSD-3-Clause.  The NDK distribution additionally carries
  Apache-2.0 WITH LLVM-exception notices for its compiler-rt/glue-
  derived sources; neither `jni.h` nor `android/bitmap.h` falls in that
  group (both carry the plain Apache-2.0 AOSP notice above).  This
  package interoperates with the public ABI; declarations here are
  facts of that interface, and the package itself ships no Google/Sun
  code.
- Independent declaration: none of these headers, in whole or in part,
  is copied or vendored here -- only the public interface facts (names,
  signatures, table order, enum values, struct layout) are transcribed
  and the `docs/repro/` drivers `#include` the real headers at build
  time only.

## Touch log

- 2026-10-16: created (A11 head 0.1.0): declared surface 97 C helpers +
  9 probe-only diagnostics; module 90 pub fn / 46 consts / 13 types;
  9-symbol export set across libjnigraphics.so + libnativehelper.so;
  suite 89 checks (SKIP-safe null battery); on-device shell probe PASS
  (56/56 offsets, 9/9 exports, honest no-VM in shell); app_process app
  probe PASS (live env seam battery + bitmap write/read/compress +
  Java-side pixel readback); B-series notes: single deref of the C
  env/vm mapping (found by the probe: first version segfaulted),
  `xj_note_exception` table deref fixed (found by the probe: crash on
  the null-return path with a live env), premultiplied-alpha +
  little-endian byte-order observations recorded in the probe README.
