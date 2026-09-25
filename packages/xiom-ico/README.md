# xiom.ico

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (16/16); NOT published yet.
> **Scope:** Pure-XIOM ICO/CUR container codec for a documented subset: 6-byte ICONDIR header parse, 16-byte ICONDIRENTRY decode, resource-slice accessors, structural validation, and a canonical builder that recomputes the image count and every resource offset.
> **Deps:** `xiom.std` only (the library module imports nothing). No FFI in v0.1.

## What it is

`xiom.ico` reads and writes the container structure shared by Windows icon
files (`.ico`, resource type 1) and cursor files (`.cur`, resource type 2).
It is not a pixel decoder: every image resource -- a PNG stream, a DIB, or a
legacy bitmap/cursor bitmap -- passes through byte-for-byte, and no palette
entry, alpha channel, hotspot pixel or DPI field is interpreted. That makes
it the right building block for validators, converters, resource extractors
and downstream decoders that want a hardened front end.

The container is deliberately small:

```
ICONDIR        6 bytes     reserved (0), type (1 or 2), image count
ICONDIRENTRY  16 bytes     one per image (width, height, colors, planes/
                           hotspot, bits/hotspot, resource size, offset)
resources      n bytes     one opaque payload per entry
```

Dimensions are stored in a single byte, so 256 pixels is encoded as the
sentinel 0. Both directions are handled: `ico_entry` reads the sentinel back
as 256 and the builder encodes a requested 256 as 0. Cursor entries reuse the
planes and bit-count words for hotspot X and hotspot Y; `IcoEntry.planes` and
`IcoEntry.bits` carry those values for CUR containers.

## API

| Function | Returns | Description |
|---|---|---|
| `ico_parse_header(data)` | `Result[IcoInfo, Str]` | Validate the 6-byte header and the declared directory size. |
| `ico_parse(data)` | `Result[IcoInfo, Str]` | Full-buffer parse: header plus every entry and resource span. |
| `ico_entry(data, i)` | `Result[IcoEntry, Str]` | Decode directory entry `i` (0-as-256 decoded). |
| `ico_image_data(data, i)` | `Result[Vec[UInt8], Str]` | Copy the payload of entry `i` verbatim. |
| `ico_is_ico(data)` | `Bool` | True when the header validates with type 1. |
| `ico_is_cur(data)` | `Bool` | True when the header validates with type 2. |
| `ico_dir_bytes(count)` | `Int` | `6 + 16 * count`. |
| `ico_builder_new(kind)` | `Result[IcoBuilder, Str]` | Empty builder for `ICO_TYPE_ICON` or `ICO_TYPE_CURSOR`. |
| `ico_builder_add(b, image, width, height, color_count, planes, bit_count)` | `Result[Int, Str]` | Append one icon; returns the new count. |
| `ico_builder_add_cursor(b, image, width, height, color_count, hotspot_x, hotspot_y)` | `Result[Int, Str]` | Append one cursor image; returns the new count. |
| `ico_builder_count(b)` | `Int` | Images appended so far. |
| `ico_builder_kind(b)` | `Int` | Builder resource type. |
| `ico_builder_emit(b)` | `Result[Vec[UInt8], Str]` | Emit the canonical container; count and offsets are recomputed. |

Constants: `ICO_TYPE_ICON` (1), `ICO_TYPE_CURSOR` (2),
`ICO_DIR_HEADER_BYTES` (6), `ICO_DIR_ENTRY_BYTES` (16).

## Install / use

```
xiom pkg install xiom.ico@0.1.0     # consumer
```

Then import the module from any XIOM source file with `use xiom.ico;`. The
library pulls in nothing but `xiom.std` as a platform dependency.

## Quick start

```xiom
use xiom.ico;

// Parse an existing container (bytes from disk, network, ...).
let parsed = ico_parse(bytes);
match parsed {
  Ok(info) => {
    // info.kind is 1 (ICO) or 2 (CUR); info.count is 1..65535.
    let e = ico_entry(bytes, 0);
    match e {
      Ok(entry) => {
        // entry.width / entry.height are 1..256 (0 on disk means 256).
        // entry.planes is color planes for ICO, hotspot X for CUR.
        // entry.bits is bits per pixel for ICO, hotspot Y for CUR.
        let payload = ico_image_data(bytes, 0);   // opaque bytes
      },
      Err(err) => { /* ico:-prefixed message, see SPEC.md */ },
    }
  },
  Err(err) => { /* handle */ },
}

// Build a two-image ICO from literal payload bytes.
let png16 = Vec[UInt8].new();
png16.push(0x89 as UInt8);    // the payload is opaque to xiom.ico
let png256 = Vec[UInt8].new();
png256.push(0x89 as UInt8);
match ico_builder_new(1) {
  Ok(b) => {
    let a = ico_builder_add(&mut b, png16, 16, 16, 0, 1, 32);
    let c = ico_builder_add(&mut b, png256, 256, 256, 0, 1, 32);
    if a.is_ok && c.is_ok {
      let file = ico_builder_emit(b);   // count, offsets, sentinels handled
    }
  },
  Err(err) => { /* handle */ },
}
```

## Error model

Every fallible function returns `Result[..., Str]` with deterministic
messages prefixed `ico: `. Header and entry failures are distinct:
truncation, non-zero reserved words, unknown resource type, zero image
count, a directory that does not fit, an empty resource, a resource size that
exceeds the buffer, a resource that overlaps the directory, and a resource
that overruns the buffer each have their own message. The builder validates
every field before appending, so a rejected `ico_builder_add` leaves the
builder byte-for-byte unchanged, and `ico_builder_emit` re-validates the
public builder fields so tampered state cannot produce a malformed file. The
full catalog is in SPEC.md.

## Testing

From the repo root:

```
.\scripts\port.ps1 -Package xiom.ico
```

16 conformance checks cover the directory-size table, hand-built 2-image ICO
and 1-image CUR fixtures, entry field decode including the 0-as-256 sentinel,
payload slices, `ico_is_ico` / `ico_is_cur`, builder creation and field-range
boundaries, the 65535-image count cap, canonical emit with recomputed
offsets, a three-image build-then-parse round-trip, the 256 sentinel in both
directions, and every error path (header, entry, index range, tampered
builder).

## Limitations

- No payload decoding: PNG/BMP/DIB bytes, palettes, alpha and DPI fields stay
  opaque. This module never renders, scales or converts an image.
- No icon-theme (`index.theme`) or thumbnail-cache handling; only the
  ICONDIR container itself.
- Resources may share bytes with each other (that is accepted), and bytes
  after the last resource are ignored; only resources that overlap the
  directory are rejected.
- Cursor hotspot coordinates are range-checked to their 16-bit field but not
  against the image dimensions.
- The whole file is held in memory; there is no streaming API.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
