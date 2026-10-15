# xiom.aaudio -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.

## 0.1.0 -- A6 AAudio head (current)

- [x] Runtime probe (libaaudio.so) with ABSENT/ABI classification +
  export-set verification (67 AAUDIO_API exports; compile-time guard).
- [x] Constants/types transcription: direction/format/result family/
  stream states/sharing/performance/usage/content-type/spatialization/
  input presets/capture policy/session id/callback result/channel masks.
- [x] Functional builder lifecycle (create/delete device-free) + full
  builder setter surface + top-level C callbacks (direct handoff).
- [x] Stream head: open attempt + request start/pause/stop/flush +
  read/write (bridge-side scratch) + waitForStateChange/getState +
  xrun/frames-per-burst/timestamp queries + close.
- [x] Suite: constants + deterministic SKIP path + live path (SKIPs on
  Windows; binds live on Android).
- [x] On-device evidence driver under `docs/repro/`: constants vs the
  NDK header, export set (0 missing), builder lifecycle, honest
  open-attempt verdict (recorded on the API-36 x86_64 emulator).

## Next

- On-device suite runs: after G1 (compiler android emission target) the
  same conformance suite runs on the emulator/device; until then the
  `docs/repro/` driver proves the bridge functionally.
- A6 tails (W2d): `amidi/AMidi.h` (libamidi) and OpenSL ES (`SLES/*`,
  libOpenSLES, interface-query wrapper rather than a flat export map).
- Platform declaration: `windows-x64`/`android-arm64`/`android-x86_64`
  + `runtime_deps: [libaaudio.so]` already recorded in STATUS.json (G3
  token adoption).
