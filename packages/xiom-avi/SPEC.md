# xiom.avi -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.avi`, version `0.1.0`).
Module: `src/avi.xi` (`module xiom.avi`).
Depends on `xiom.std` (`xiom.string`).

## Scope

A pure-XIOM (no FFI) reader for the RIFF/AVI container skeleton:

- `avi_is_file` validates the 12-byte `RIFF` + size + `AVI ` signature;
- `avi_riff_size` returns the stored RIFF ChunkSize field;
- `avi_find_chunk` walks the top-level chunk list (4-byte id, LE u32 size,
  payload, 2-byte word alignment) and returns a payload offset;
- `avi_parse_avih` locates the `avih` main-header chunk at the top level or
  inside the first `LIST hdrl` and returns an `AviInfo`;
- `avi_duration_ms` / `avi_fps_permille` derive time metadata from an
  `AviInfo`.

## Non-goals

- Stream headers (`strh`, `strf`, `strn`, `indx`), `idx1`/OpenDML indexes,
  `movi` payload extraction, interleaving, demuxing or muxing.
- Codec/format identification, video/audio frame decoding.
- `RIFF-AVIX` (OpenDML AVI 2.0) extensions, `RIFF-WAVE` reuse.
- Editing, building or rewriting AVI files (this package is read-only).
- Streaming over files/sockets; the API works on in-memory `Vec[UInt8]`.
- Payloads above 4 GiB (all sizes are 32-bit fields).

## Container layout

Offsets are decimal and absolute unless stated; all multi-byte integers are
little-endian.

### File header (12 bytes)

| Offset | Size | Field | Value / rule |
|---|---|---|---|
| 0 | 4 | ChunkID | ASCII `"RIFF"` (`52 49 46 46`). |
| 4 | 4 | ChunkSize | u32; `len - 8` for well-formed files. Stored value returned by `avi_riff_size`; never cross-checked. |
| 8 | 4 | FormType | ASCII `"AVI "` (`41 56 49 20`). |
| 12 | ... | Chunk list | Top-level chunks. |

### Chunk

| Offset | Size | Field | Value / rule |
|---|---|---|---|
| +0 | 4 | ChunkID | Four ASCII bytes. |
| +4 | 4 | ChunkSize | Unsigned LE u32 payload length. |
| +8 | `size` | Payload | `size` bytes. |
| +8 + size | `size % 2` | Pad | One zero-ish byte when `size` is odd, so the next header is word-aligned. |

A `LIST` chunk's payload starts with a 4-byte list type (`"hdrl"`,
`"movi"`, ...) that is included in the LIST `ChunkSize`. The chunk walk
treats LIST chunks like any other payload at the top level (skipped as a
whole); only `avi_parse_avih` enters the first one.

### Worked example -- minimal file with avih and JUNK

````
offset  bytes                     meaning
0       52 49 46 46               "RIFF"
4       50 00 00 00               size = 80 (total 88 - 8)
8       41 56 49 20               "AVI "
12      61 76 69 68               "avih"
16      38 00 00 00               size = 56
20      40 9c 00 00 ...          10 u32 fields (56 bytes)
76      4a 55 4e 4b               "JUNK"
80      04 00 00 00               size = 4
84      ...                       4-byte payload
````

`avi_find_chunk(&data, "avih", 12)` returns `Ok(20)`;
`avi_find_chunk(&data, "JUNK", 12)` returns `Ok(84)`;
`avi_riff_size(&data)` returns `Ok(80)`.

### avih payload (56 bytes)

Ten little-endian u32 fields. The port field map is fixed by the brief:

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

> **Field map:** the avih offsets follow the historical `AVIMAINHEADER`:
> `dwStreams` is read at payload offset 24 and offsets 40..55 are reserved
> and ignored. (An earlier port brief listed offset 40; the mapping was
> corrected to the standard before first integration and the tests pin the
> historical layout: streams 2 at offset 24, sentinel 7 at offset 40.)

## API signatures

All functions are free functions in module `xiom.avi`:

```xi
pub type AviInfo = {
  micro_sec_per_frame: Int;
  total_frames: Int;
  width: Int;
  height: Int;
  streams: Int;
}

pub fn avi_is_file(data: &Vec[UInt8]) -> Bool
pub fn avi_riff_size(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn avi_find_chunk(data: &Vec[UInt8], id: Str, start: Int) -> Result[Int, Str]
pub fn avi_parse_avih(data: &Vec[UInt8]) -> Result[AviInfo, Str]
pub fn avi_duration_ms(info: &AviInfo) -> Int
pub fn avi_fps_permille(info: &AviInfo) -> Int
```

## Semantics

`avi_is_file(data)`
: `true` iff `len >= 12` and bytes 0..4 are `"RIFF"` and bytes 8..12 are
  `"AVI "`. The size field at 4..8 is not read or checked.

`avi_riff_size(data)`
: Validates in this order: `len >= 12`; `"RIFF"`; `"AVI "`; then returns
  the unsigned LE u32 at offset 4 verbatim.

`avi_find_chunk(data, id, start)`
: Validates the file header and arguments in this order: `len >= 12`;
  `"RIFF"`; `"AVI "`; `id.len() == 4`; `12 <= start <= len`. Then walks
  chunks from `start`: at each header it reads the payload size; if
  `pos + 8 + size > len` it fails with "chunk out of range"; if the four
  bytes at `pos` equal `id`, it returns `pos + 8` (payload offset);
  otherwise `pos += 8 + size + (size % 2)`. A tail with fewer than 8 bytes
  left fails with "chunk truncated"; running past the end without a match
  fails with "chunk not found". A matched chunk returns only its payload
  offset; the payload content is not validated. LIST payloads are skipped
  as opaque bytes.

`avi_parse_avih(data)`
: Validates the file header as above. Then:
  1. `_scan` for a top-level `"avih"`; if found, parse its payload.
  2. otherwise `_scan` for the first top-level `"LIST"`; if none, or if
     its first four payload bytes are not `"hdrl"`, report "avih not
     found".
  3. otherwise `_scan_range` for `"avih"` inside the LIST payload, bounded
     by the LIST chunk size (which was validated to fit the buffer).
  4. parse the payload: if `off + 56 > len`, report "truncated avih";
     otherwise return the five exposed fields.
: Errors encountered while walking (out-of-range payload, partial tail
  header) are propagated; if the second search finds no avih, the result is
  "avih not found".

`avi_duration_ms(info)`
: `info.total_frames * info.micro_sec_per_frame / 1000`, integer division
  truncated towards zero. Values are used as given (no validation).

`avi_fps_permille(info)`
: `0` when `micro_sec_per_frame <= 0`; otherwise
  `(1000000000 + micro_sec_per_frame / 2) / micro_sec_per_frame`, i.e.
  1e9 / micro rounded to the nearest whole permille. Example: 40000 ->
  25000 (25.000 fps); 33367 -> 29970 (29.970 fps, rounded from 29.9696).

## Error string catalog

| Condition | Error text |
|---|---|
| `data.len() < 12` (any reader) | `avi: truncated header` |
| Bytes 0..4 are not `"RIFF"` | `avi: bad RIFF magic` |
| Bytes 8..12 are not `"AVI "` | `avi: bad AVI magic` |
| `id.len() != 4` in `avi_find_chunk` | `avi: bad chunk id` |
| `start < 12` or `start > data.len()` | `avi: bad start offset` |
| A declared chunk payload does not fit before the end | `avi: chunk out of range` |
| Fewer than 8 bytes remain at the tail of the walk | `avi: chunk truncated` |
| No chunk with the requested id in the walk | `avi: chunk not found` |
| avih chunk payload shorter than 56 bytes | `avi: truncated avih` |
| No avih at the top level and none inside the first `LIST hdrl` | `avi: avih not found` |

Error order is fixed by the validation order in `Semantics`; the first
failure wins. `avi_parse_avih` never returns "chunk not found": a missing
avih is always "avih not found".

## Complexity

| Operation | Complexity |
|---|---|
| `avi_is_file` | O(1) |
| `avi_riff_size` | O(1) |
| `avi_find_chunk` | O(number of top-level chunks) |
| `avi_parse_avih` | O(number of top-level chunks + chunks inside the first hdrl) |
| `avi_duration_ms` / `avi_fps_permille` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module avi_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are assembled byte by byte with
`push_text`/`push_le32`/`push_chunk`, independent of the module's own
writers. Coverage:

1. `avi_is_file` true for the 88-byte minimal fixture (avih + JUNK);
2. `avi_is_file` false for empty / 11 bytes / junk / bad RIFF / bad form,
   true for a wrong size field (not cross-checked);
3. `avi_riff_size` = 80 for the fixture, = 4 for a header-only 12-byte
   buffer, and returns a corrupted field (0) verbatim while parsing still
   succeeds;
4. `avi_riff_size` errors: truncated header, bad RIFF magic, bad AVI magic;
5. `avi_find_chunk` payload offsets: avih 20, JUNK 84;
6. `avi_find_chunk` not found; 3- and 5-byte ids; start 11 and len+1; start
   == len is "chunk not found";
7. odd-sized (3-byte) chunk word alignment: next header at 24, avih payload
   at 32;
8. `avi_parse_avih` fields: micro 40000, frames 300, 640x480, streams 2
   (fixture stores streams 2 at offset 24 and a reserved sentinel 7 at
   offset 40, which must be ignored);
9. `avi_duration_ms`: 12000 ms, truncation (999 us -> 0), exact 1 ms;
10. `avi_fps_permille`: 25000, 0 for micro 0 and negative, rounding
    33367 -> 29970, 500000 -> 2000;
11. avih inside `LIST hdrl`: top-level `avi_find_chunk` is "chunk not
    found", `LIST` payload at 20, `avi_parse_avih` returns the fields;
12. LIST `movi` and no-avih fixtures -> "avi: avih not found";
13. 40-byte avih payload -> "avi: truncated avih" (find still succeeds);
14. declared payload beyond the buffer -> "avi: chunk out of range";
15. trailing 4-byte partial header -> "avi: chunk truncated";
16. `avi_parse_avih` header error catalog (empty, 11 bytes, bad magics);
17. empty input rejected by every reader;
18. end-to-end with JUNK before and LIST movi after avih: offsets 20 / 34 /
    98, fields, duration 12000 ms, fps 25000.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.avi
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- The `streams` field follows the historical `dwStreams` offset 24; the
  reserved words at 40..55 are ignored.
- The RIFF size field is never validated; a truncated or over-long chunk
  list is detected by the walk itself, not by the size field.
- Only the first top-level `LIST` is entered by `avi_parse_avih`, and only
  when its type is `hdrl`; nested LISTs and later LISTs are ignored.
- A missing padding byte after the final odd payload is tolerated; interior
  alignment is assumed correct.
- Chunk ids are compared byte-exactly; case is significant.
- All sizes are 32-bit; no OpenDML/AVIX 64-bit extensions.
- No stream/frame decode, no index, no write support.
- No thread safety; plain value types only.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_err_info`/`_ok_info` (constructing Results
  directly in other functions miscompiles in this compiler).
- The chunk walker `_scan_range` returns plain Int codes (-1/-2/-3) so no
  Result value crosses its internal branches; public functions map the
  codes through the leaf helpers.
- Every byte read is widened with `(data[pos] as Int) & 0xFF`; little-endian
  reads are arithmetic and never use shifts on values with bit 31 set.
- `AviInfo` crosses function boundaries only by reference (`&AviInfo`) and
  is constructed inside `_ok_info` alone.
- The tests compare error strings with `compare.str_compare` (BUG 17:
  `==` between Str values read from a `Vec` lowers to a pointer compare).
- The module declares no `extern "C"` blocks (no FFI).
