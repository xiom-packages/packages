# xiom.android -- ROADMAP

Android SDK100 program: `docs/ANDROID-SDK100.md`; wave brief:
`docs/prep/android-wave.md`.

## 0.1.0 -- A1 window-core head

- [x] Runtime probe (libandroid.so + libnativewindow.so) with
  ABSENT/ABI classification + export-set verification (27 exports).
- [x] Functional AHardwareBuffer head (allocate/describe/lock pixel
  roundtrip/release).
- [x] Suite: constants + deterministic SKIP path + live path.

## 0.2.0 -- A5 assets-storage head

- [x] Export set extended 27 -> 53 (asset_manager 17 + storage_manager
  6 + sharedmem 3); ABI-checked on-device (0 missing).
- [x] Functional ASharedMemory head (create/size/setProt/map probe/
  close); on-device roundtrip exact (0x11223344).
- [x] Suite: asset-mode + PROT constants; SHM functional block.

## 0.3.0 -- A2 lifecycle-glue head

- [x] Export set 53 -> 117 (looper 9 + native_activity 5 +
  configuration 50); `setScreenRound` documented as a platform-unexported
  header prototype (device + stub verified).
- [x] Functional ALooper head (`xiom.android.lifecycle`): prepare /
  forThread / wake / addFd (NULL-callback ident + direct-handoff
  callback) / removeFd / pollOnce / pollAll with C-side out params +
  probe pipe helpers; on-device pipe + callback + pollOnce proof.
- [x] Functional AConfiguration head (`xiom.android.configuration`):
  new/delete/copy/diff/match/isBetterThan + 19 get/set pairs +
  language/country + getScreenRound; on-device roundtrip + diff mask.
- [x] native_app_glue documented (source ships in the NDK; not
  vendored) + import-closure proof (`docs/repro/check-glue-closure.ps1`).
- [x] Suite: A2 constants + unloaded-runtime explicit errors +
  export-count guard + live looper/config blocks.

## 0.4.0 -- A3 input + A4 sensors heads (current)

- [x] Export set 117 -> 209 (input.h 60 of 63 names -- 3 JNI
  constructors -> A11; sensor.h 32); on-device 209/209 resolved (0
  missing) in both a shell process and an app process.
- [x] Constant tables generated from the NDK r27b headers and
  `_Static_assert`-gated at probe build: input.h 161 + keycodes.h 317
  + sensor.h 60 = 538 values (+ the nanf("") sentinel as a
  bit-pattern runtime check).
- [x] Functional A3 head (`xiom.android.input`): queue attach (callback
  + ident) / detach / hasEvents / getEvent / preDispatch / finish +
  the full AKeyEvent (8) and AMotionEvent (42) accessor families;
  binary32-bits float path (B-12).
- [x] Functional A4 head (`xiom.android.sensors`): manager
  getInstance(+ForPackage) / sensor list + dynamic list enumeration /
  default sensor (Ex) / create+destroy event queue / register / enable
  / disable / setEventRate / hasEvents / getEvents into bridge-owned
  slots / direct-channel trio / ASensor metadata family.
- [x] On-device LIVE (A4): 18 sensors enumerated + described;
  ident-queue `registerSensor` -> `getEvents` event with exact f32
  x/y/z; callback-queue variant fires (ALOOPER_POLL_CALLBACK).
- [x] On-device LIVE (A3): C-only NativeActivity app probe (hasCode=
  false APK) -- framework-delivered queue; detach rc=0 + attach rc=0
  twice; AKEYCODE_A/B decoded through the accessors; getEvent/
  preDispatch/finish contract honored.  Touch injection documented
  blocked for the probe window (dispatcher InputWindowInfo frame 0x0);
  the 42 AMotionEvent_* exports are ABI-checked.
- [x] Suite: A3/A4 constant clusters + null-handle explicit-error
  checks + export-count guard 209 + live sensor block (event-queue
  roundtrip on the device's looper).
- [x] native_app_glue closure: the six `AInputQueue_*`/`AInputEvent_*`
  imports now classify as covered (glue's A3 prediction fulfilled).

## Next

- Live window ops: ANativeWindow lock/geometry flows once a Surface is
  reachable (A11 JNI seam or a spawned app context).
- Live activity ops: ANativeActivity_* wrappers once a real activity
  instance is reachable (A11/G1).
- On-device suite runs: after G1 (compiler android target) the same
  conformance suite runs on the emulator/device; until then the
  on-device driver under `docs/repro/` proves the bridge functionally.
- Platform declaration: `platforms` + `runtime_deps` are declared in
  STATUS.json (android-arm64 / android-x86_64 tokens, G3 filed).
