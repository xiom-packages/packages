# SPEC: xiom.portaudio -- PortAudio bindings (dynamic loader)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.portaudio` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | PortAudio -- https://www.portaudio.com/ / https://github.com/PortAudio/portaudio |
| Upstream version pinned | v19.7.0 (builds from Audacity / DaVinci Resolve samples) |
| Upstream license | MIT; nothing vendored -- constants declared locally |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `portaudio_x64.dll`) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + entry-point set + struct layout

**Soname (runtime contract):** `portaudio_x64.dll` (official x64 build name).
Resolved at runtime via `xiom.ffi.dl`; no import library, no headers, nothing
vendored. (MSYS2's `libportaudio-2.dll` variant is a Phase 2 consideration.)

**Resolved entry points** (8): `Pa_GetVersion`, `Pa_GetVersionText`,
`Pa_Initialize`, `Pa_Terminate`, `Pa_GetDeviceCount`,
`Pa_GetDefaultOutputDevice`, `Pa_GetDefaultInputDevice`,
`Pa_GetDeviceInfo`.

**ABI details pinned:** `Pa_GetVersion` int is packed major/minor/sub
(1246976 = 0x130700 = 19.7.0); `PaDeviceInfo` layout prefix =
`int structVersion` at 0 (4 bytes + 4 padding), `const char* name` at
offset 8 (the probe reads the name pointer there and copies the C string).
Sample formats re-exported: `FORMAT_FLOAT32=1`, `INT32=2`, `INT24=4`,
`INT16=8`, `INT8=16`, `UINT8=32`, `CUSTOM=0x10000`.

**Local runtime samples used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| `Audacity\portaudio_x64.dll` (used for the recorded present-path runs) | 221,696 bytes, SHA256 `370E0FD6A9793EDBD0D0FA7F2CC7CDAA4EED86D3A747D765CAFC1DDB0E5968EF` |
| `DaVinci Resolve\portaudio_x64.dll` (secondary sample) | 102,400 bytes, SHA256 `12E0C6AE447F5C72F4EABD8CAFD6A036AEB33FAD392973FE46BEDF17A628D3AB` |
| Runtime report | version text `PortAudio V19.7.0-devel, revision unknown` (int 1246976); 52 devices; default output `Speakers (Realtek(R) Audio)`; default input `Microphone (Razer USB Sound Card...)` |

### Re-pin procedure

1. Re-verify the entry-point names/struct offsets against the PortAudio
   headers before touching the module.
2. Update the sample table and version rows in `README.md`/`AUDIT.md` in one
   commit.
3. Re-run `scripts/port.ps1 -Package xiom.portaudio` in both configurations
   (absent -> SKIP; DLL on PATH -> probe) and record the matrix.

## 3. Design and safe boundary (G5)

`portaudio.xi` is the only module with `unsafe`: a `PaLibrary` loader struct
plus wrappers (`pa_load(_named)`, `pa_close`, `pa_probe(_named/_default)`).
The probe initializes PortAudio, reports version/device count/default device
names (name pointer read at `PaDeviceInfo` offset 8 via
`xiom.ffi.ptr_read_u64_le`), then terminates.

Classification: `PA_LOAD_ABSENT` -> SKIP; `PA_LOAD_ABI` -> FAIL;
`PA_PROBE_FAILED` (initialize failed -- serviceless host) -> SKIP-class in
the suite. Bridge locals use the `f_` prefix (compiler finding B-10) and
`int_to_str` is local (no stdlib convert inside the confined block).

## 4. Test matrix (recorded 2026-10-09, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| PortAudio absent (CI shape; default PATH) | `scripts/port.ps1 -Package xiom.portaudio` | **PASS 2/2 x2** -- deterministic SKIP classification + `probe: SKIP` (code 126) |
| PortAudio present (Audacity 19.7.0 on PATH) | same | **PASS 5/5 x2** -- version text/int, 52 devices, default output/input names |
| Streams/formats/callbacks | Phase 2 (needs the stream API) | not exercised |

## 5. Scope

Pilot: library identification, device enumeration and default-device names.
Streams (`Pa_OpenStream`/`Pa_StartStream`), callbacks and host-API info are
Phase 2 (`ROADMAP.md`). The pre-pilot module declared static externs; it is
preserved in git history.
