# xiom.mediandk -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md` (slice A7); wave brief:
`docs/prep/android-wave.md`.

## 0.1.0 -- A7 core media head (current)

- [x] Runtime probe (`libmediandk.so`) with ABSENT/ABI classification +
  export-set verification (276 symbols: 133 functions + 143 key data
  symbols) -- 0 missing on-device (API-36 x86_64 emulator).
- [x] Constants cluster: `AMEDIA_*` error codes; codec buffer/config
  flags + info codes + crypto modes; extractor seek/sample enums; muxer
  output/append enums; DRM event/key/status enums + property strings;
  143 key strings (runtime-resolved + on-device re-verified).
- [x] Functional AMediaFormat head (int32/float/string/buffer/toString;
  exact roundtrips on-device; bridge-owned slots, no pointer crossing).
- [x] Functional codec probe: `audio/opus` decoder create + delete
  (typed non-fatal outcome; PRESENT on the API-36 emulator).
- [x] Suite: constants + deterministic SKIP path + live path (SKIP leg
  green on Windows).
- [x] On-device driver + evidence: `docs/repro/mediandk-probe/`.

## Next

- Extractor/Muxer/DataSource functional heads: need real media assets
  (a tiny generated container in the repro dir) -- run sample read /
  muxer write roundtrips on-device.
- DRM functional head: `AMediaDrm_isCryptoSchemeSupported` probe +
  property reads (provisioning needs a device profile; keep non-fatal).
- A7 image remainder: `NdkImage.h` / `NdkImageReader.h` (AImage_*,
  AImageReader_*) as the follow-up head or a sibling package.
- Live XIOM suite on the emulator: after G1 (compiler android target)
  the same conformance suite runs on-device; until then the C driver
  carries the evidence.
- Platform declaration: `android-arm64` / `android-x86_64` tokens are
  declared in STATUS.json (first Android users, pending G3 token
  acceptance in the packages pipeline).
- Publish: gated on the naming decision + G1, per the program ledger.
