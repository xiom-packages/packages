# xiom.audio-meta

Chiptune and tracker module **metadata** for XIOM: structural parsers for
MIDI SMF, MOD, XM, S3M, IT and NSF, plus a 40-entry chiptune magic registry
with deterministic detection.

Status: `incubating` (implemented, conformance-green with compiler 0.62.2;
not published). Metadata/parse only -- no audio rendering, no sample
decoding, no FFI, no external files.

## Modules

| Module | Source | Public API |
|---|---|---|
| `xiom.audio_meta` | `src/audio_meta.xi` | `midi_parse`, `midi_is_valid`, `mod_parse`, `mod_is_valid` |
| `xiom.audio_meta.trackers` | `src/trackers.xi` | `xm_parse`, `s3m_parse`, `it_parse`, `nsf_parse` and their `*_is_valid` wrappers |
| `xiom.audio_meta.chiptune` | `src/chiptune.xi` | `chiptune_count`, `chiptune_entry`, `chiptune_detect`, `chiptune_detect_id` |

## Formats covered

| Format | Scope of the parser |
|---|---|
| MIDI (SMF) | `MThd` header (format 0/1/2, division incl. SMPTE), `MTrk` chunks, delta-time and length varlen (4-byte cap), channel events with running status, meta events (tempo FF 51, name FF 03, end-of-track FF 2F), sysex events. Aggregate counters only. |
| MOD | ProTracker 31-instrument header, accepted signature subset (4/6/8/16/32 channels), song/restart/order table, computed pattern count, sample and pattern-cell statistics. |
| XM | FastTracker II fixed header (`Extended Module: `, 0x1A marker, version 0x0102..0x0104, header size 276), order table, pattern headers with computed data sizes, instrument block sizes. |
| S3M | Scream Tracker 3 header (0x1A + type 0x10, `SCRM`), order table, instrument/pattern paragraph pointer tables, pattern row geometry. |
| IT | Impulse Tracker `IMPM` header, order table, instrument/sample/pattern pointer tables, pattern row geometry. |
| NSF | 128-byte NES Sound Format header: version, song counts, load/init/play addresses, name/artist/copyright, NTSC/PAL speeds, bank-switch bytes, chip flags, opaque PRG size. |
| Registry | 40 documented magic entries (see `SPEC.md`), first-match detection in index order. |

## Example

```xiom
use xiom.audio_meta;
use xiom.audio_meta.chiptune;

// `data` is a Vec[UInt8] supplied by the caller; this package does no I/O.
let pr = midi_parse(&data);
if pr.is_ok {
  let m = pr.value;
  // m.track_name, m.total_events, m.first_tempo_us, ...
}

let hit = chiptune_detect(&data);   // -1, or a registry index
```

## Design notes

- Pure XIOM, no FFI and no allocations beyond the returned structs and
  vectors; every parser works on in-memory `Vec[UInt8]`.
- Every byte read is bounds-checked and widened to `Int`; varlen reads are
  capped at 4 bytes and every table count is range-checked before any loop,
  so parsing is total and deterministic on hostile inputs.
- Text fields are exposed as printable-ASCII prefixes: extraction stops at
  the first NUL or non-printable byte, so no NUL ever reaches a `Str`.
- Parallel vectors (`order` plus pattern geometry vectors) are pushed in
  lockstep and accessors are guarded; `Vec[Str]` and `Vec[StructType]` are
  not used.
- Error strings are stable and documented in `SPEC.md`; `*_is_valid` is the
  boolean convenience wrapper.

## Build and test

```powershell
.\scripts\port.ps1 -Package xiom-audio-meta -TimeoutSec 60
```

The suite (`tests/test_conformance.xi`, module `audio_meta_tests`) runs 25
deterministic checks with inline synthetic fixtures -- no external files.

## Non-goals

Audio rendering, synthesis, sample/instrument decoding, pattern unpacking,
module playback, file repair/conversion, streaming I/O. See `SPEC.md` for the
exact documented format subsets.
