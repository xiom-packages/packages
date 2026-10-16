# xiom.android-sys -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.  This package is the A12 system head (five
runtime-load units); remaining A12-adjacent families land additively.

## 0.2.0 -- A12 remainder (current)

- [x] log + sync starter head (0.1.0 content, unchanged; 11 core + 10
  ext reported; green).
- [x] binder head (`libbinder_ndk.so`): AIBinder core cluster
  (class define/new/inc/dec/associate/isAlive/isRemote/ping/getClass/
  descriptor/refcount + calling identity) -- 12 core ABI-gated + 3 ext
  reported; class lifecycle smoke green on-device.
- [x] NNAPI head (`libneuralnetworks.so`): offline model build
  (canonical `ADD(x, y, activation)` form), compilation
  create/finish/free, execution create/free, device query -- 12 core
  ABI-gated + 7 device-query ext reported; model build + compilation
  finish green on-device.
- [x] zlib head (`libz.so`): version, one-shot compress/uncompress
  roundtrip, crc32/adler32 known answers, streaming
  deflate/inflate init/step/end -- 12 core ABI-gated; both roundtrips
  byte-exact on-device.
- [x] ICU subset head (`libandroidicu.so`): u_errorName,
  u_strToUTF8/u_strFromUTF8, u_toupper/u_tolower (declared subset by
  design); u_strlen optional (header-announced, not exported by the
  API-36 shim -- reported); UTF roundtrip byte-exact on-device.
- [x] Per-lib SKIP classification, independent load/unload, suite x2
  green; on-device evidence in `docs/repro/android-sys-probe/`
  (per-lib export resolution counts + functional smokes + logcat).
- [x] Platform declaration: `windows-x64`, `android-x86_64`,
  `android-arm64` + full `runtime_deps` (STATUS.json).

## Next

- Real-fence functional path (log+sync): once a producer exists
  (camera/media/GPU fence on-device), exercise sync_file_info +
  status/num_fences/name on a live sync file.
- Binder transaction surface: AParcel read/write cluster
  (`binder_parcel.h`) + `AIBinder_transact`/`prepareTransaction` +
  extensions (`getExtension`/`setExtension`) as a follow-up wave; the
  class-side onTransact then serves a real transaction.
- NNAPI execution: `Execution_setInput/setOutput/startCompute` + tensor
  data copies (needs the execution I/O cluster) -- the compute path
  beyond the offline build.
- ICU expansion (only if an engine needs it): normalization
  (`unorm2`) or break iteration (`ubrk`) as a separate declared cluster
  with its own subset policy; collation stays out unless requested.
- On-device suite runs: after G1 (compiler android target) the same
  conformance suite runs on the emulator/device; until then the driver
  under `docs/repro/android-sys-probe/` proves every head functionally.
- `sync_wait` / `sync_file_info_is_signaled`: excluded -- not declared
  by the NDK headers (private libsync surface); revisit only if the
  oracle changes.
