# xiom.avi

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** RIFF/AVI container structure: top-level chunk walking and the
> main AVI header (`avih`). Header structure only -- no stream or frame
> decoding.
> **Deps:** `xiom.std` only (`xiom.string`; tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare`). Pure XIOM, no FFI.
> **Compiler:** v0.61.3 (pinned).

## What it is

`xiom.avi` reads the RIFF container skeleton of an AVI file. It checks the
12-byte `RIFF` + size + `AVI ` signature, returns the stored RIFF size,
walks top-level chunks with word alignment, and parses the main AVI header
(`avih` chunk) -- locating it at the top level or inside the first
`LIST hdrl` -- into the five metadata fields this package exposes. All
multi-byte fields are little-endian and are read arithmetically. There is no
demuxing, muxing, index handling or frame decoding; see SPEC.md for the
exact layout, semantics and error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `avi_is_file(data)` | `Bool` | True when the buffer is >= 12 bytes and starts with `RIFF` + size + `AVI `; the size field is not cross-checked. |
| `avi_riff_size(data)` | `Result[Int, Str]` | Unsigned LE u32 RIFF ChunkSize field at offset 4; Err on truncated header / bad magics. |
| `avi_find_chunk(data, id, start)` | `Result[Int, Str]` | Absolute payload offset (chunk header + 8) of the first **top-level** chunk with the 4-byte `id`, walking from `start`; odd payloads are word-aligned; LIST chunks are skipped, not entered. |
| `avi_parse_avih(data)` | `Result[AviInfo, Str]` | Finds `avih` at the top level, else inside the first top-level `LIST hdrl`; reads the 56-byte payload into `AviInfo`. |
| `avi_duration_ms(info)` | `Int` | `total_frames * micro_sec_per_frame / 1000`, truncated to whole milliseconds. |
| `avi_fps_permille(info)` | `Int` | Frames per second in thousandths: `(1000000000 + micro / 2) / micro` (rounded); 0 when `micro_sec_per_frame <= 0`. |

```xi
pub type AviInfo = {
  micro_sec_per_frame: Int;   // avih payload + 0
  total_frames: Int;          // avih payload + 16
  width: Int;                 // avih payload + 32
  height: Int;                // avih payload + 36
  streams: Int;               // avih payload + 24 (dwStreams)
}
```

Errors: `Err("avi: truncated header")`, `Err("avi: bad RIFF magic")`,
`Err("avi: bad AVI magic")`, `Err("avi: bad chunk id")`,
`Err("avi: bad start offset")`, `Err("avi: chunk out of range")`,
`Err("avi: chunk truncated")`, `Err("avi: chunk not found")`,
`Err("avi: truncated avih")`, `Err("avi: avih not found")` (see SPEC.md).

## RIFF/AVI layout

All multi-byte fields are little-endian; offsets are relative unless stated.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | `RIFF` magic | ASCII `52 49 46 46`. |
| 4 | 4 | ChunkSize | u32 = `len - 8` for well-formed files; returned as-is, never cross-checked. |
| 8 | 4 | Form type | ASCII `AVI ` (`41 56 49 20`). |
| 12 | ... | Chunks | Top-level chunk list. |

| Chunk offset | Size | Field | Rule |
|---|---|---|---|
| +0 | 4 | Chunk id | Four ASCII bytes, e.g. `avih`, `LIST`, `JUNK`. |
| +4 | 4 | Payload size | Unsigned LE u32. |
| +8 | size | Payload | `size` bytes. |
| +8 + size | `size % 2` | Pad | One byte when `size` is odd (word alignment). |

`LIST` payloads begin with a 4-byte list type (`hdrl`, `movi`, ...); the
list type bytes are part of the LIST payload size.

### avih payload field map (56 bytes)

| Payload offset | Field | Exposed as |
|---|---|---|
| 0 | dwMicroSecPerFrame | `micro_sec_per_frame` |
| 4 | dwMaxBytesPerSec | -- |
| 8 | dwPaddingGranularity | -- |
| 12 | dwFlags | -- |
| 16 | dwTotalFrames | `total_frames` |
| 20 | dwInitialFrames | -- |
| 24 | dwStreams | `streams` |
| 28 | dwSuggestedBufferSize | -- |
| 32 | dwWidth | `width` |
| 36 | dwHeight | `height` |
| 40, 44, 48, 52 | reserved[0..3] | -- |

> **Field map note:** the avih offsets follow the historical
> `AVIMAINHEADER`: `dwStreams` is read at offset 24; offsets 40..55 are
> reserved and ignored. See SPEC.md.

## Usage

```xi
use xiom.avi;
use xiom.io;
use xiom.convert;

let data: Vec[UInt8] = read_avi_file();      // caller-provided buffer
if avi_is_file(&data) {
  match avi_parse_avih(&data) {
    Ok(info) => {
      io.println("frames: " + convert.int_to_string(info.total_frames));
      io.println("size:   " + convert.int_to_string(info.width) + "x" + convert.int_to_string(info.height));
      io.println("ms:     " + convert.int_to_string(avi_duration_ms(&info)));
      io.println("fps x1k:" + convert.int_to_string(avi_fps_permille(&info)));
    },
    Err(e) => { io.println("error: " + e); },
  }
}
let size = avi_find_chunk(&data, "movi", 12); // Err("avi: chunk not found") when absent
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.avi
```

Expected: namespace check OK, 18 `[PASS]` lines, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Header structure only**: chunks are located and `avih` is parsed; no
  stream headers (`strh`/`strf`), no `idx1` index, no frame/sample data, no
  demux/mux, no codec handling.
- **Top-level walking**: `avi_find_chunk` never enters LIST chunks. Only
  `avi_parse_avih` performs a second search, and only inside the *first*
  top-level `LIST`, and only when its list type is `hdrl`; subsequent
  LISTs and nested LISTs are not searched.
- **`streams` at payload offset 24** (`dwStreams`, the historical layout);
  reserved words 40..55 are ignored.
- **The RIFF size field is never cross-checked**: a wrong size is returned
  verbatim by `avi_riff_size` and does not make `avi_is_file` false.
- A missing final padding byte after an odd payload is tolerated; chunk
  ids and sizes are otherwise trusted structurally.
- All sizes are 32-bit fields; files above 4 GiB are out of scope.
- Plain value types, no thread safety.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
