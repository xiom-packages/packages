# SPEC: xiom.miniaudio -- miniaudio bindings (vendored single header)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.miniaudio` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | miniaudio -- https://github.com/mackron/miniaudio |
| Upstream version pinned | tag **0.11.25** |
| Upstream license | Unlicense (public domain) OR MIT-0, at your option (`vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (miniaudio resolves platform backends itself) |
| Compiler pin | v0.64.1 |

## 2. Vendored path (G2 pin)

The single-header library is vendored **verbatim** into `vendor/` and
compiled via `src/miniaudio_all.c` (`MINIAUDIO_IMPLEMENTATION` plus the
`extern "C"` probe bridge) with `--c-source`; no system audio library at link
time, no runtime DLL of ours (the OS backends miniaudio loads are the
platform's).

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/miniaudio.h` (tag 0.11.25) | 4,108,168 | `AC7AF4DE748B7E26B777F37E01CEE313A308A7296A3EB080E2906B320CC55C89` |
| `vendor/LICENSE` | 2,597 | `457F1B500E0ADF6BC059EDDDFA78A2F62012E7C3BB43476C20E0BD23B25BA0EB` |

### Provenance

| Artifact | Value |
|----------|-------|
| Header URL | https://raw.githubusercontent.com/mackron/miniaudio/0.11.25/miniaudio.h |
| License URL | https://raw.githubusercontent.com/mackron/miniaudio/0.11.25/LICENSE |
| Upstream repo | https://github.com/mackron/miniaudio (tag `0.11.25`) |

`.gitattributes` pins `vendor/** -text`. Re-pin: fetch the new tag's header +
LICENSE, recompute hashes, update the table and version rows, re-run
`scripts/port.ps1 -Package xiom.miniaudio` (x2).

## 3. Design and safe boundary (G5)

`miniaudio.xi` is the only module with `extern "C"`; wrappers:
`ma_version_packed`, `ma_context_probe` (context init + device enumeration),
`ma_decode_probe` (in-memory WAV decode with sample spot-checks), plus
`MaContextInfo` / `MaWavInfo` and format constants. Out-params use
XIOM-owned 4-byte slots read little-endian; local `int_to_str` for error
text (the stdlib convert must not be called inside confined blocks -- see
the lane findings).

Compile-unit probe details: the embedded WAV is 8 kHz mono s16, 16 frames of
a precomputed sine (no libm dependency); the decode asserts 16 frames read,
zero frames at EOS (`MA_AT_END` accepted), and spot-checked samples.

## 4. Test matrix (recorded 2026-10-09, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored header (always compiled in) | `scripts/port.ps1 -Package xiom.miniaudio` | **PASS 4/4 x2** -- version 0.11.25, context playback=9/capture=4, WAV decode 16 frames / 1 channel / 8000 Hz / s16 |

There is no library-absence SKIP path (the library is vendored). A host
without an audio service reports the context check as SKIP with the
miniaudio result code.

## 5. Scope

Pilot: version, device enumeration and in-memory WAV decoding. Playback
engines, mixing, capture, encoding and file I/O are Phase 2
(`ROADMAP.md`). The pre-pilot files referenced a bridge and a miniaudio
header that were never vendored; they are preserved in git history.
