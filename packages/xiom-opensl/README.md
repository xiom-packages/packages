# xiom.opensl

Android legacy-audio bindings for XIOM -- the A6 (OpenSL ES / OpenMAX AL
/ AMidi) tail of the Android SDK100 program.

- Runtime probe for `libOpenSLES.so` + `libOpenMAXAL.so` +
  `libamidi.so` with SKIP semantics (all absent -> `OPENSL_LOAD_ABSENT`;
  partial load or broken exports -> `OPENSL_LOAD_ABI` FAIL).
- **114-symbol export-table ABI check**: OpenSL ES 3 flat exports + 53
  `SL_IID_*` runtime-GUID globals; OpenMAX AL 3 + 41 `XA_IID_*`;
  AMidi 14 functions.  Every `SL_IID_*` slot is also deref-checked for
  a non-null GUID (`sl_iid_null_values`).
- Functional engine head: `sl_engine_lifecycle` runs
  `slCreateEngine` -> non-null ObjectItf -> `Realize(SL_BOOLEAN_FALSE)`
  -> `GetState` -> `Destroy` fully C-side (pointers never cross, B-25),
  plus `slQueryNumSupportedEngineInterfaces` /
  `slQuerySupportedEngineInterfaces` probes.
- AMidi verdict: the r27b oracle (and the API-36 device libraries)
  export exactly the 14 declared functions -- `AMidi_getDeviceInfo` is
  absent, so the device-count attempt records `-1` (JNI-only device
  objects); a future platform exporting it is recorded as `-2`
  (ABI beyond this oracle).  Never silent.
- Verified exclusions: `SPEED_OF_SOUND` is not in the r27b oracle;
  nothing was invented.

```xiom
use xiom.opensl;

let p = opensl_probe();
if p.is_ok {
  let rt: OpenSlRuntime = p.value;
  // rt.sl_missing / rt.xa_missing / rt.amidi_missing == 0 on device
  let rc = sl_engine_lifecycle();          // 0 = realize/destroy clean
  let state = sl_engine_last_state();      // SL_OBJECT_STATE_REALIZED
  let n = amidi_device_count_attempt();    // -1 on the r27b/API-36 oracle
}
```

Run the conformance suite:

```
scripts/port.ps1 -Package xiom.opensl -TimeoutSec 300
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).  On-device evidence driver:
`docs/repro/opensl-probe/`.
