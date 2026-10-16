# xiom.mediandk on-device probe (A7 core media head)

On-device evidence for the `libmediandk.so` runtime bridge: links the
package bridge (`../../src/mediandk_bridge.c`) into a small driver built
for `x86_64-linux-android26` and runs it on the API-36 emulator
(`Medium_Phone_API_36.0`), proving:

1. **276/276 declared export symbols resolve** (133 functions + 143 key
   data symbols; ABSENT -> SKIP / ABI -> FAIL classification unchanged).
2. **AMediaFormat roundtrips are exact** -- Int32, Float32, String,
   Buffer (4 bytes, byte-exact) and `toString` carries every entry.
3. **The audio/opus decoder-create probe verdict** (PRESENT on the
   API-36 emulator; a null decoder would be recorded as a typed,
   NON-FATAL outcome).
4. **143/143 key-string constants are exact** against the runtime
   `dlsym` values (fidelity table generated from `mediandk.xi` by
   `gen-keys-expected.ps1`; without it the driver runs in DUMP mode and
   prints every `KEY <symbol>=<value>` line for transcription).

## Run

```powershell
# emulator already running, or start headless:
# C:\Android\sdk\emulator\emulator.exe -avd Medium_Phone_API_36.0 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect
pwsh build-probe.ps1              # regen keys_expected.h + build + push + run
pwsh build-probe.ps1 -SkipExpected  # DUMP mode (no fidelity table)
```

`build-probe.ps1` picks the NDK clang
(`C:\Android\sdk\ndk\27.1.12297006\...\bin\clang.exe`) and pushes to
`/data/local/tmp/xiom-spike/mediandk_probe`.

## Recorded run (2026-10-16, API-36 x86_64 emulator, fidelity mode)

```
== xiom.mediandk on-device driver (A7 core media head) ==
load rc=0 error=<clean>
export_count=276 missing_exports=0
keys: color-format=color-format width=width mime=mime frame-rate=frame-rate csd-0=csd-0
format: new ok handle=129230621008016
format: int32 color-format get=21 (want 21)
format: int32 width get=640 (want 640)
format: string mime get=audio/opus (want audio/opus)
format: float frame-rate found=1 get=2.500000 (want 2.500000)
format: buffer csd-0 size=4 bytes=12345678 (want 4 / 12345678)
format: toString=color-format: int32(21), width: int32(640), mime: string(audio/opus), frame-rate: float(2.500000), csd-0: data}
format: delete rc=0
codec: audio/opus decoder create -> handle=129225520694704 delete rc=0 VERDICT=PRESENT
keys: declared=143
keys: fidelity checked=143 mismatches=0
RESULT: PASS
```

DUMP-mode bootstrap run (same session, the source of the transcribed
constants): identical output up to `keys: declared=143`, then 143
`KEY <symbol>=<value>` lines (see `mediandk.xi` for the transcribed
values).

## Files

- `mediandk_harness.c` -- the driver (bridge contract at the top).
- `build-probe.ps1` -- regen keys table + build + push + run.
- `gen-keys-expected.ps1` -- extracts the 143 key constants from
  `../../mediandk.xi` into `keys_expected.h` (fails loudly unless exactly
  143 are found).
- `keys_expected.h` -- generated fidelity table (committed for the
  recorded evidence).

Prerequisite: NDK r27b at `C:\Android\sdk\ndk\27.1.12297006` and
`adb` at `C:\Android\sdk\platform-tools\adb.exe` (both verified on this
box; the toolchain is shared Unity/UE5/Flutter -- READ-ONLY, no
sdkmanager installs).
