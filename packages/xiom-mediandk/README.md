# xiom.mediandk

Android NDK media bindings for XIOM -- the **A7 core media head** of the
Android SDK100 program.

- Runtime probe for `libmediandk.so` with SKIP semantics (absent
  runtime -> `MEDIANDK_LOAD_ABSENT`; broken exports ->
  `MEDIANDK_LOAD_ABI` FAIL).
- Declared export set of the NDK r27b media headers bound +
  ABI-checked: **276 symbols** (AMediaCodec / AMediaFormat +
  AMEDIAFORMAT_KEY_* keys / AMediaExtractor / AMediaMuxer /
  AMediaDataSource / AMediaDrm / AMediaCrypto).
- Functional `AMediaFormat` head: new/delete, set/get Int32, Float32,
  String, Buffer, toString -- exact roundtrips (on-device verified).
- Functional codec probe: `codec_create_decoder("audio/opus")` +
  `codec_delete` (a missing decoder is a typed, non-fatal outcome).
- Constants cluster: all `AMEDIA_*` error codes, codec flags / info /
  crypto modes, extractor/muxer/DRM clusters, and the 143 key strings
  (resolved from the runtime, re-verified on-device).

```xiom
use xiom.mediandk;

let p = mediandk_probe();
if p.is_ok {
  let f = format_new().value;
  format_set_int32(&f, AMEDIAFORMAT_KEY_WIDTH, 640);
  format_set_string(&f, AMEDIAFORMAT_KEY_MIME, "audio/opus");
  let w = format_get_int32(&f, AMEDIAFORMAT_KEY_WIDTH);
  ...
}
```

Run the conformance suite:

```
scripts/port.ps1 -Package xiom.mediandk
```

On-device evidence (API-36 x86_64 emulator; 276/276 exports, format
roundtrips exact, 143/143 key constants, audio/opus decoder PRESENT):
`docs/repro/mediandk-probe/`.

Program context: `docs/ANDROID-SDK100.md` (coverage ledger, slice A7)
and `docs/prep/android-wave.md` (wave brief).
