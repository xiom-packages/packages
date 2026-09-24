# xiom.id3

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** read-only ID3v2 tag inspection: version, declared size, and
> text information frames (TIT2/TPE1/TALB/TXXX/...).
> **Deps:** `xiom.std` only (`xiom.string.builder`, `xiom.string.compare`;
> tests add `xiom.test`, `xiom.io` and `xiom.string`). No FFI.

## What it is

`xiom.id3` inspects a complete in-memory ID3v2 tag: the 10-byte header plus
its frames. It answers "is there a tag?", "which major version?", "how large
is the tag?" and collects text frames into the index-aligned
`Id3Tags{ ids, texts }` structure, with `id3_title` / `id3_artist` /
`id3_album` convenience accessors for TIT2 / TPE1 / TALB. Frames are walked
with the v2.3 frame size layout (plain big-endian) or the v2.4 layout
(syncsafe) depending on the header's major version. All reads are arithmetic
and byte-exact (latin1 and UTF-8 payloads are copied verbatim); no FFI, no
allocation tricks. See SPEC.md for the byte-level layout, size encodings,
encoding table and the full error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `id3_has_tag(data)` | `Bool` | True when "ID3" (73 68 51) is at offset 0. |
| `id3_version(data)` | `Result[Int, Str]` | Major version byte (3, 4, and others; returned as stored). |
| `id3_tag_size(data)` | `Result[Int, Str]` | Syncsafe 28-bit size field + the 10 header bytes. |
| `id3_text_frames(data)` | `Result[Id3Tags, Str]` | Walk frames and collect text frames as `ids`/`texts`. |
| `id3_frame(tags, id)` | `Option[Str]` | First text frame with that id; `None` when absent. |
| `id3_frame_count(tags)` | `Int` | Number of collected text frames. |
| `id3_title(data)` | `Result[Str, Str]` | TIT2 convenience; `Ok("")` when absent. |
| `id3_artist(data)` | `Result[Str, Str]` | TPE1 convenience; `Ok("")` when absent. |
| `id3_album(data)` | `Result[Str, Str]` | TALB convenience; `Ok("")` when absent. |

`Id3Tags = { ids: Vec[Str]; texts: Vec[Str]; }` with `texts[i]` the payload
of frame `ids[i]`. Only text frames (id starts with `'T'`) are collected;
non-text frames (APIC, COMM, ...) are skipped and the walk continues.

Errors: `Err("id3: truncated header")`, `Err("id3: bad magic")`,
`Err("id3: tag size beyond buffer")`, `Err("id3: frame size beyond tag")`
(see SPEC.md).

## Frame format

All frames in a v2.3/v2.4 tag:

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | Frame id | ASCII, e.g. `TIT2`; text frames start with `'T'` (0x54). |
| 4 | 4 | Frame size | v2.3: plain big-endian u32. v2.4: syncsafe 28-bit (7 bits/byte). |
| 8 | 2 | Flags | Ignored by this module. |
| 10 | size | Payload | Text frame: one encoding byte, then the text bytes. |

Tag header (10 bytes): `"ID3"`, major version, revision (ignored), flags
(ignored), then the syncsafe 28-bit size of everything after the header.
`id3_tag_size` returns that size **+ 10**; trailing bytes (audio data) are
ignored.

Encodings decoded by `id3_text_frames`:

| Byte | Meaning | Behavior |
|---|---|---|
| 0 | ISO-8859-1 (latin1) | Bytes copied verbatim (byte-exact). |
| 3 | UTF-8 | Bytes copied verbatim (byte-exact). |
| other | UTF-16 variants, reserved | Frame id recorded, text `""`. |

## Usage

```xi
use xiom.id3;
use xiom.io;

let tag = ...; // whole tag (or tag + audio) as Vec[UInt8]
if id3_has_tag(&tag) {
  match id3_title(&tag) {
    Ok(title) => { io.println("title: " + title); },
    Err(e) => { io.println("error: " + e); },
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.id3
```

Expected: the section-4 namespace check passes, 21 `[PASS]` lines, and a
final `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **ID3v2.3 / ID3v2.4 text frames only**: the frame walk uses the v2.3
  (plain big-endian) size layout unless the major version is 4 (syncsafe).
  Other majors are returned by `id3_version` but their frame layouts are
  not otherwise supported.
- **No ID3v1**: only ID3v2 tags at offset 0 are inspected; the trailing
  128-byte ID3v1 block is not read.
- **No unsynchronisation**: the header/frame unsynchronisation scheme is
  not reversed; unsynchronised tags are parsed as stored and will usually
  report a size/bounds error.
- **No images or binary frames**: APIC/PRIV/COMM/etc. are skipped by the
  collector (they are neither decoded nor returned).
- **No extended header / footer handling**: the extended header (v2.3/2.4
  flag) and the v2.4 footer are not skipped; frames after them are misread
  as frames (usually a bounds error).
- **Text encodings 1/2 (UTF-16 with/without BOM) are not decoded**; such
  frames are recorded with an empty text.
- **Read-only**: nothing is written, rebuilt or re-encoded; latin1 text is
  not transcoded to UTF-8.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
