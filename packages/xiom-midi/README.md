# xiom.midi

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** Standard MIDI File structure: header, track chunks,
> variable-length quantities and event counts.
> **Deps:** `xiom.std` only (the library module imports nothing; the tests
> use `xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`).
> No FFI.

## What it is

`xiom.midi` is a pure-XIOM (no FFI) structural reader for Standard MIDI
Files (SMF): it detects the `MThd` magic, reads the header fields (format,
declared track count, signed division), walks the `MTrk` track chunks,
decodes MIDI variable-length quantities (VLQ, at most 4 bytes), counts the
events of a track -- including channel messages with running status, meta
events and sysex events -- and tallies note-on / note-off messages. All
multi-byte integers are big-endian and are read arithmetically. See SPEC.md
for the byte-level layout, the VLQ rules, the event length table and the
full error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `midi_is_file(data)` | `Bool` | True when `data` starts with the 4-byte `MThd` magic. |
| `midi_format(data)` | `Result[Int, Str]` | Header format field: 0, 1 or 2. |
| `midi_track_count(data)` | `Result[Int, Str]` | Header track-count field (0..65535). |
| `midi_division(data)` | `Result[Int, Str]` | Signed division field: positive ticks/quarter, negative SMPTE. |
| `midi_varlen(data, off)` | `Result[(Int, Int), Str]` | VLQ value and next offset; max 4 bytes (0..0x0FFFFFFF). |
| `midi_track_chunks(data)` | `Result[MidiTracks, Str]` | Walks every `MTrk` chunk after the header; count must match. |
| `midi_track_event_count(data, track_index)` | `Result[Int, Str]` | Number of events in one track (running status supported). |
| `midi_note_events(data, track_index)` | `Result[(Int, Int), Str]` | `(note_on_count, note_off_count)`; note-on velocity 0 counts as off. |

`MidiTracks = { offsets: Vec[Int]; lengths: Vec[Int]; }` -- parallel
vectors in file order: `offsets[i]` is the absolute offset of the first
payload byte of chunk `i`, `lengths[i]` its declared payload length.

Errors: `Err("midi: truncated header")`, `Err("midi: bad MThd magic")`,
`Err("midi: bad header length")`, `Err("midi: invalid format")`,
`Err("midi: negative offset")`, `Err("midi: truncated varlen")`,
`Err("midi: overlong varlen")`, `Err("midi: truncated track chunk")`,
`Err("midi: bad track magic")`, `Err("midi: track chunk out of range")`,
`Err("midi: track count mismatch")`, `Err("midi: track index out of range")`,
`Err("midi: truncated event")`, `Err("midi: missing running status")`,
`Err("midi: bad status byte")`, `Err("midi: bad end of track")`
(see SPEC.md).

## Event table

| Status byte | Event | Data after the status byte |
|---|---|---|
| `8n` | Note off | 2 data bytes |
| `9n` | Note on (velocity 0 = note off) | 2 data bytes |
| `An` | Polyphonic key pressure | 2 data bytes |
| `Bn` | Control change | 2 data bytes |
| `Cn` | Program change | 1 data byte |
| `Dn` | Channel pressure | 1 data byte |
| `En` | Pitch bend | 2 data bytes |
| `F0` / `F7` | System exclusive / escape | VLQ length + payload |
| `FF` | Meta (`FF 2F 00` = End of Track) | type byte + VLQ length + payload |
| anything else | rejected | `midi: bad status byte` |

Every event is preceded by a delta-time VLQ. A data byte below `0x80`
reuses the last channel status (running status); meta and sysex events
clear it. Parsing stops after End of Track, which is itself counted.

## Usage

```xi
use xiom.midi;
use xiom.io;
use xiom.convert;

let data = /* Vec[UInt8] with a Standard MIDI File */;
if midi_is_file(&data) {
  io.println("format: " + convert.int_to_string(midi_format(&data).value));
  io.println("tracks: " + convert.int_to_string(midi_track_count(&data).value));
}
let chunks = midi_track_chunks(&data);
let notes = midi_note_events(&data, 0);
if notes.is_ok {
  io.println("on:  " + convert.int_to_string(notes.value.0));
  io.println("off: " + convert.int_to_string(notes.value.1));
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.midi
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Structure and event walking only**: the module never plays audio, does
  not schedule anything and does not convert ticks to time. No tempo maps
  are built from `FF 51` meta events and no SMPTE timing math is done (the
  division field is returned raw as a signed value).
- **No note pairing**: `midi_note_events` only tallies note-on and note-off
  messages per track; it does not match them into notes, tracks channels or
  applies velocity curves.
- **Reduced library**: MIDI events other than the documented set are
  rejected; running status is supported for channel messages only.
- **No writing**: this is a reader; there is no MIDI file builder.
- **In-memory only**: the API works on a `Vec[UInt8]`; RMID/RIFF wrappers
  and streaming are out of scope.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
