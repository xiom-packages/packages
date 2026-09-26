# xiom.mp4

> **Status:** `incubating` -- implemented and green on the local harness
> (33 conformance checks), NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) ISO BMFF / MP4 (ISO/IEC 14496-12) box
> parser: the recursive box tree, `ftyp` brands, `mvhd`/`tkhd`/`mdhd`/`hdlr`
> metadata, `stsd` sample-entry fourccs and visual dimensions, `elst`/`stco`/
> `co64`/`stsz` table counts, plus fragmented (`moof`) and moov-at-end
> detection. Parse-only: no media decoding, no sample-table expansion, no
> writing.
> **Deps:** `xiom.std` only (the library imports `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare`; the tests add `xiom.test`
> and `xiom.io`).

## What it is

`xiom.mp4` walks an in-memory `.mp4` byte buffer and returns an `Mp4File`
index. Every box at every depth is recorded in file order (fourcc, offset,
size, header size, depth, parent, uuid user type), and a documented set of
metadata boxes is decoded on the way:

- `ftyp` -- major brand, minor version and the compatible-brand list;
- `mvhd` -- version, timescale, duration (32-bit v0 / 64-bit v1);
- `tkhd` -- track id, duration, presentation width/height as whole pixels
  (16.16 fixed point rounded to nearest);
- `mdhd` -- timescale, duration and the packed ISO-639-2/T language;
- `hdlr` -- handler type (`vide`, `soun`, `text`, ...);
- `stsd` -- sample-entry fourccs plus width/height for visual entries
  (`avc1`, `hvc1`, `mp4a`, ... entry list is opaque beyond the fourcc);
- `elst` -- entry count; `stco`/`co64` -- chunk-offset entry count;
  `stsz` -- sample count and uniform sample size.

Three layouts that trip naive parsers are handled explicitly:

- **64-bit sizes**: `size == 1` reads the 64-bit `largesize` that follows
  the type (16-byte header);
- **`size == 0`**: the box runs to the end of the enclosing context (the
  file at top level);
- **`uuid` boxes**: the 16 user-type bytes are rendered as 32 lowercase hex
  digits (never as a raw string, which a `0x00` byte would truncate).

Container boxes whose children are walked are exactly `moov`, `trak`,
`mdia`, `minf`, `stbl`, `dinf` and `edts`; the walk is depth-limited to 32
levels. Fragmented files are detected by top-level `moof` presence, and
moov-at-end layouts by comparing the first `moov` and `mdat` offsets.

Malformed input is rejected with a deterministic `Err(Str)` message -- see
[SPEC.md](SPEC.md) for the full byte layout, the validation order and the
error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `mp4_parse(buffer)` | `Result[Mp4File, Str]` | Parse the whole buffer; Err on malformation. |
| `mp4_total_len(f)` | `Int` | Input buffer length. |
| `mp4_box_count(f)` | `Int` | Number of boxes recorded (all depths). |
| `mp4_box_type(f, i)` | `Result[Str, Str]` | Fourcc of box `i`. |
| `mp4_box_offset/size/header_size/depth/parent(f, i)` | `Int` | Box framing; `-1` when out of range. |
| `mp4_box_uuid(f, i)` | `Result[Str, Str]` | 32 hex digits for uuid boxes. |
| `mp4_box_is_container(f, i)` | `Bool` | Children were walked. |
| `mp4_find_box(f, t)` | `Int` | First box of type `t`, or `-1`. |
| `mp4_tree_text(f)` | `Str` | Indented depth-first listing. |
| `mp4_ftyp_count/major/minor/brand_count/brand` | mixed | ftyp fields. |
| `mp4_has_ftyp(f)` | `Bool` | ftyp at offset 0. |
| `mp4_mvhd_count/version/timescale/duration` | mixed | Movie header fields. |
| `mp4_tkhd_count/version/track_id/duration/width/height` | mixed | Track header fields (width/height in pixels). |
| `mp4_mdhd_count/version/timescale/duration/language` | mixed | Media header fields. |
| `mp4_hdlr_count/handler` | mixed | Handler type fourcc. |
| `mp4_stsd_count/entry_count`, `mp4_sample_entry_count/fourcc/width/height/stsd` | mixed | Sample descriptions. |
| `mp4_elst_count/version/entry_count` | mixed | Edit lists. |
| `mp4_chunk_offset_table_count/kind/count` | mixed | `stco`/`co64` counts (kind 0/1). |
| `mp4_stsz_count/sample_count/uniform_size` | mixed | Sample sizes. |
| `mp4_moov_count/moof_count/mdat_count` | `Int` | Top-level occurrence counts. |
| `mp4_is_fragmented/has_mdat/is_moov_at_end` | `Bool` | Layout detection. |

Int accessors return `-1` for out-of-range indices; the `Result` accessors
return `Err` with `mp4: ... index out of range` (or `mp4: box is not uuid`).

## Usage

```xi
use xiom.io;
use xiom.convert.int;
use xiom.mp4;

fn main() -> Int {
  // `data` holds a whole .mp4 file read from disk (xiom.os.file/io).
  var data = Vec[UInt8].new();
  // ... fill `data` ... (tests build buffers in memory instead)

  let r = mp4_parse(&data);
  if !r.is_ok {
    io.println("parse failed: " + r.error);
    return 1;
  }
  let f = r.value;

  io.println(mp4_tree_text(&f));            // indented box listing
  io.println("boxes: " + int.int_to_string(mp4_box_count(&f)));

  let mr = mp4_ftyp_major(&f, 0);
  if mr.is_ok {
    io.println("major brand: " + mr.value);
  }
  if mp4_mvhd_count(&f) > 0 {
    io.println("timescale: " + int.int_to_string(mp4_mvhd_timescale(&f, 0)));
    io.println("duration:  " + int.int_to_string(mp4_mvhd_duration(&f, 0)));
  }
  if mp4_is_fragmented(&f) {
    io.println("fragmented file");
  }
  return 0;
}
```

## Tests

```
xiom --run tests/test_conformance.xi      # or: .\scripts\port.ps1 -Package xiom.mp4
```

Expected: 33 `[PASS]` lines, then `xiom.mp4: all tests passed`, exit 0. All
fixtures are synthetic byte buffers built inside the test file; no external
data files are used.

## Limits (honest scope)

- No media decoding and no validation of `mdat` payload bytes; only box
  framing is checked.
- Sample tables are counted, not expanded: no per-chunk/per-sample lists, no
  composition time math.
- Only the seven container types above are descended into; a `moof`'s
  `traf` children are not walked (presence is detected at top level).
- Only the listed metadata boxes are interpreted; unknown boxes are
  recorded as opaque spans.
- The walk is strict: data after the last complete box, non-printable
  fourccs and malformed payloads of decoded boxes are errors, not warnings.
- 64-bit fields with the sign bit set are rejected (they cannot fit a XIOM
  `Int`).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
