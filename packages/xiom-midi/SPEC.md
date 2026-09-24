# xiom.midi -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.midi`, version `0.1.0`).
Module: `src/midi.xi` (`module xiom.midi`).
Depends on `xiom.std` (the library module imports nothing; the tests use
`xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) structural reader for Standard MIDI Files (SMF):

- `midi_is_file` detects the `MThd` magic;
- `midi_format`, `midi_track_count` and `midi_division` read the header
  fields;
- `midi_varlen` decodes one MIDI variable-length quantity;
- `midi_track_chunks` walks the `MTrk` chunks after the header and returns
  their offsets and lengths;
- `midi_track_event_count` counts the events of one track, decoding channel
  messages (with running status), meta events and sysex events;
- `midi_note_events` tallies note-on / note-off messages per track.

## Non-goals

- Playback, synthesis, scheduling, audio output.
- Tempo maps: `FF 51` meta events are walked by length but their contents
  are not interpreted and ticks are never converted to time.
- SMPTE timing math: the division field is returned raw, signed; no
  frames-per-second conversion.
- Note pairing, chord detection, channel separation, velocity curves.
- Writing MIDI files, RMID/RIFF wrappers, file I/O and streaming.
- Running status for non-channel (system) messages.

## Byte layout

### Header chunk (14 bytes)

All multi-byte fields are **big-endian**. Offsets are decimal.

| Offset | Size | Field | Value / rule |
|---|---|---|---|
| 0 | 4 | Chunk tag | ASCII `"MThd"` (`4D 54 68 64`). |
| 4 | 4 | Chunk length | u32 = 6; any other value is `midi: bad header length`. |
| 8 | 2 | Format | u16: 0, 1 or 2; anything else is `midi: invalid format`. |
| 10 | 2 | Track count | u16: number of `MTrk` chunks that must follow. |
| 12 | 2 | Division | signed i16 (see below). |

The division field is returned signed:

- `1..32767`: ticks per quarter note (metrical time).
- negative (high bit set): SMPTE time -- the high byte is a negative
  frames-per-second code (`-24`, `-25`, `-29`, `-30`) and the low byte is
  ticks per frame. The whole 16-bit value is returned (e.g. `0xE728` ->
  `-6360`, `0x8000` -> `-32768`); it is not decomposed further.

### Track chunks

At most `track_count` chunks are expected after the header; the walk
requires all of them to be present and no extras. Each chunk is:

| Offset | Size | Field | Value / rule |
|---|---|---|---|
| 0 | 4 | Chunk tag | ASCII `"MTrk"` (`4D 54 72 6B`). |
| 4 | 4 | Chunk length | u32 big-endian payload length. |
| 8 | `length` | Payload | Event stream; must fit inside the buffer. |

`MidiTracks.offsets[i]` is the absolute offset of the first payload byte
(chunk offset + 8); `MidiTracks.lengths[i]` is the declared payload length.

### Worked example -- the test fixture

Format 0, one track, division 480 (ticks per quarter note):

```
4D 54 68 64 00 00 00 06 00 00 00 01 01 E0     MThd, 6, format 0, 1 track, division 480
4D 54 72 6B 00 00 00 0D                       MTrk, payload length 13
00 90 3C 40                                    delta 0,  note-on  C4 velocity 64
83 60 80 3C 40                                 delta 480, note-off C4 velocity 64
00 FF 2F 00                                    delta 0,  End of Track
```

The track payload starts at absolute offset 22 and is 13 bytes long, so the
whole file is 35 bytes: 3 events, 1 note-on, 1 note-off.

## VLQ rules

MIDI variable-length quantities (used for delta times and payload lengths):

- At most **4 bytes**; the value range is `0..0x0FFFFFFF` (268435455).
- The most-significant 7-bit group comes first.
- Bit 7 of each byte is the continuation flag: set on every byte but the
  last.
- Non-minimal encodings (leading `0x80` groups) are accepted; readers are
  lenient here, matching common MIDI implementations.
- `midi_varlen` returns `(value, next_offset)` where `next_offset` points
  just past the last consumed byte.

| Bytes | Value |
|---|---|
| `00` | 0 |
| `40` | 64 |
| `7F` | 127 |
| `81 00` | 128 |
| `83 60` | 480 |
| `A6 8E 65` | 624485 |
| `FF FF FF 7F` | 268435455 (0x0FFFFFFF) |

## Event length table

Event stream of one track: repeated `delta-time VLQ + event`. The event
starts with a status byte `>= 0x80`; a byte `< 0x80` is a data byte and
reuses the last channel status (running status). Meta and sysex events
clear running status.

| First byte | Kind | Encoding |
|---|---|---|
| `80..8F` | Note off | 2 data bytes |
| `90..9F` | Note on (velocity 0 = note off) | 2 data bytes |
| `A0..AF` | Polyphonic key pressure | 2 data bytes |
| `B0..BF` | Control change | 2 data bytes |
| `C0..CF` | Program change | 1 data byte |
| `D0..DF` | Channel pressure | 1 data byte |
| `E0..EF` | Pitch bend | 2 data bytes |
| `F0` | System exclusive | VLQ length + payload |
| `F7` | Escape / continuation sysex | VLQ length + payload |
| `FF` | Meta | type byte + VLQ length + payload |
| `F1..F6`, `F8..FE` | rejected | `midi: bad status byte` |

End of Track is the meta event `FF 2F 00` (type 47, length 0). It is
parsed and **counted as an event**, then the walk stops: bytes after it
inside the chunk are not inspected. A track without End of Track is
counted up to its declared end. `FF 2F` with a non-zero length is
`midi: bad end of track`.

## API signatures

All functions are free functions in module `xiom.midi`:

```xi
pub type MidiTracks = { offsets: Vec[Int]; lengths: Vec[Int]; }

pub fn midi_is_file(data: &Vec[UInt8]) -> Bool
pub fn midi_format(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn midi_track_count(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn midi_division(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn midi_varlen(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str]
pub fn midi_track_chunks(data: &Vec[UInt8]) -> Result[MidiTracks, Str]
pub fn midi_track_event_count(data: &Vec[UInt8], track_index: Int) -> Result[Int, Str]
pub fn midi_note_events(data: &Vec[UInt8], track_index: Int) -> Result[(Int, Int), Str]
```

## Semantics

`midi_is_file(data)`
: `true` iff `data` starts with the 4-byte tag `4D 54 68 64`; a bare
  4-byte prefix returns true and trailing bytes are ignored. `false` for
  fewer than 4 bytes.

`midi_format(data)` / `midi_track_count(data)` / `midi_division(data)`
: Validate the 14-byte header (length, magic, length field = 6), then read
  the u16 at offset 8 / 10 / 12. `midi_format` additionally rejects values
  above 2 with `midi: invalid format`. Header errors are the same catalog
  for all three.

`midi_varlen(data, off)`
: Decodes one VLQ starting at `off`. Errors: `midi: negative offset` for
  `off < 0`, `midi: truncated varlen` when the encoding runs past the end,
  `midi: overlong varlen` when four bytes all carry the continuation flag.

`midi_track_chunks(data)`
: Validates the header, then walks from offset 14. Every chunk must start
  with `"MTrk"`, have at least 8 bytes available for the tag + length, and
  its declared length must fit inside the buffer. The walked count must
  equal the header track count. Zero-length chunks and zero declared
  tracks are valid.

`midi_track_event_count(data, track_index)`
: Runs the chunk walk, validates `0 <= track_index < count`, and walks the
  events of that track with the length table above. Returns the number of
  events (End of Track included). Errors: the header/chunk catalog plus
  `midi: track index out of range` and `midi: truncated event` for any
  delta, status or payload read that would cross the track end;
  `midi: missing running status` for a data byte with no prior channel
  status; `midi: bad status byte` for system bytes other than `F0`, `F7`,
  `FF`.

`midi_note_events(data, track_index)`
: Same walk, returning `(note_on_count, note_off_count)`:
  `8n` is a note-off; `9n` with velocity 1..127 is a note-on; `9n` with
  velocity 0 is a note-off. Other channel events are walked but not
  tallied. Parsing stops at End of Track exactly as for the event count.

## Error string catalog

| Condition | Error text |
|---|---|
| Fewer than 14 bytes for the header | `midi: truncated header` |
| Bytes 0..4 are not `"MThd"` | `midi: bad MThd magic` |
| Header length field != 6 | `midi: bad header length` |
| Format field > 2 | `midi: invalid format` |
| `midi_varlen` offset < 0 | `midi: negative offset` |
| VLQ starts at `off` but crosses the end of `data` | `midi: truncated varlen` |
| Four VLQ bytes all continue | `midi: overlong varlen` |
| Fewer than 8 bytes remain where a chunk header is expected | `midi: truncated track chunk` |
| Chunk tag is not `"MTrk"` | `midi: bad track magic` |
| Declared chunk length extends past the end of `data` | `midi: track chunk out of range` |
| Walked chunk count != header track count | `midi: track count mismatch` |
| `track_index` outside `0..count-1` | `midi: track index out of range` |
| Event read would cross the track end | `midi: truncated event` |
| Data byte before any channel status | `midi: missing running status` |
| System byte other than `F0`/`F7`/`FF` | `midi: bad status byte` |
| `FF 2F` meta with a non-zero length | `midi: bad end of track` |

## Complexity

| Operation | Complexity |
|---|---|
| `midi_is_file` / `midi_format` / `midi_track_count` / `midi_division` | O(1) |
| `midi_varlen` | O(1) (at most 4 bytes) |
| `midi_track_chunks` | O(number of chunks + file length) |
| `midi_track_event_count` / `midi_note_events` | O(track payload bytes) + the chunk walk |

## Test plan

`tests/test_conformance.xi` (`module midi_tests`, 24 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). All fixtures are built in-test with byte
pushes. Coverage:

1. `midi_is_file`: full file and bare magic true; bad magic, empty and
   3-byte input false;
2. `midi_format` 0/1/2, `midi: invalid format` for 3;
3. `midi_track_count` 0/1/2/255;
4. `midi_division` 480, 32767, SMPTE `0xE728` = -6360, `0x8000` = -32768;
5. header catalog on all accessors: truncated (0 and 13 bytes), bad magic,
   bad header length;
6. VLQ single-byte 0 and 127, and a non-zero start offset;
7. VLQ 128, 255, 16383 and 624485;
8. VLQ four-byte maximum 268435455;
9. VLQ errors: negative offset, truncation (1/2/3 bytes and past the
   end), overlong (4 continuation bytes and a 5-byte stream);
10. chunk walk on the 35-byte fixture: offset 22, length 13;
11. chunk walk on a two-track file: offsets 22/38, lengths 8/7;
12. zero declared tracks -> empty vectors; zero-length chunk accepted and
    counted as 0 events;
13. chunk errors: truncated chunk header, bad track magic, out-of-range
    length, count mismatch (2 declared / 1 present, 1 declared / 0
    present);
14. basic track: 3 events, notes (1, 1);
15. running status: reused `0x90` with velocity 0 -> note-off, notes (1, 1);
16. meta (tempo) + `F0`/`F7` sysex + End of Track -> 4 events, notes (0, 0);
17. End of Track stops the walk (trailing note not counted); a missing End
    of Track counts to the declared end;
18. truncated events: short channel data, delta at the track end, short
    sysex payload, short meta payload;
19. missing running status: data byte with no prior status, and after a
    meta event;
20. bad status bytes `F1` and `F8`;
21. `FF 2F` with non-zero length -> `midi: bad end of track`;
22. `track_index` out of range: 1 and -1 on a one-track file, 2 on a
    two-track file, for both readers;
23. format 1 two-track file: per-track event counts and note tallies;
24. note tally: 1 note-on, 2 note-offs (`8n` plus `9n` velocity 0).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.midi
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Structure-only: no playback, no tick-to-time conversion, no tempo map
  interpretation, no SMPTE math, no note pairing.
- The 14-byte canonical `MThd` layout only: a header length other than 6
  is rejected, and every byte after it must be a well-formed `MTrk` chunk.
- Meta events are validated by length but their contents are not decoded.
- The division field is returned raw and signed; negative values are SMPTE
  encodings that this module does not decompose.
- Running status applies to channel messages only and is cleared by meta
  and sysex events.
- Events are not decoded into typed records, and `Vec[UInt8]` values are
  the only input; no streaming or file I/O.
- Not thread-safe; plain value types only.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_pair`/`_err_pair`/`_ok_tracks`/`_err_tracks`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- Every raw byte widens through `(x as Int) & 0xFF`; a bare `as Int` on a
  UInt8 carrying bit patterns above bit 30 miscompiles (the wasm/msgpack
  precedent).
- All big-endian reads are arithmetic (multiplication/addition), no byte
  swaps and no FFI.
- `_walk_events` returns `Result[(Int, Int), Str]` for both public readers
  but delegates all construction to the leaf helpers.
- Vec reads are bound to typed locals (`let off: Int = tracks.offsets[i]`)
  before comparison or arithmetic.
- The module declares no `extern "C"` blocks (no FFI).
