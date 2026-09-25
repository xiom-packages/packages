# xiom.m3u

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** M3U/M3U8 playlist parsing and canonical emitting; in-memory
> `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_push_int`,
> `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Overview

`xiom.m3u` is a small, dependency-free codec for the M3U/M3U8 playlist
format as used for local playlists and HLS media playlists. It parses a whole
document into a flat `Playlist` value, exposes the entries and their raw tag
lines through accessors, and emits a canonical extended-M3U document.

The codec covers the shared line grammar of plain M3U and extended M3U:

- an optional `#EXTM3U` header (recognized as the first non-blank line),
- `#EXTINF:<seconds>,<title>` lines with whole-second, non-negative integer
  durations (float durations are rejected by design),
- path lines stored verbatim (relative or absolute; no file existence checks
  and no URL validation beyond being non-empty),
- every other `#` line -- `#EXT-X-...` HLS tags and plain comments -- is
  preserved verbatim as a raw tag line,
- blank lines ignored, CRLF normalized to LF, and a final line without a
  newline accepted.

It performs no HLS playback or semantic interpretation: `#EXT-X-STREAM-INF`,
`#EXT-X-KEY`, `#EXT-X-BYTERANGE` and friends are opaque text that survives a
round trip unchanged.

## Install / use

```
xiom pkg install xiom.m3u@0.1.0
```

```xi
use xiom.m3u;
```

## Quick start

```xi
use xiom.m3u;
use xiom.io;

fn main() -> Int {
  let r = m3u_parse("#EXTM3U\n#EXTINF:212,Example Song\ntracks/example.mp3\n");
  match r {
    Ok(p) => {
      io.println(m3u_path(&p, 0));    // tracks/example.mp3
      io.println(m3u_title(&p, 0));   // Example Song
      if m3u_duration_seconds(&p, 0) == 212 { io.println("212 s"); }
      io.println(m3u_emit(&p));       // canonical extended M3U
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API summary

| Function | Returns | Description |
|---|---|---|
| `m3u_parse(text)` | `Result[Playlist, Str]` | Parse a whole M3U/M3U8 document; LF and CRLF; `Err("m3u: ...")` on malformed input. |
| `m3u_emit(p)` | `Str` | Canonical emission: always starts with `#EXTM3U`, LF-terminated lines; round-trip safe. |
| `m3u_entry_count(p)` | `Int` | Number of entries (path lines). |
| `m3u_has_header(p)` | `Bool` | True when the input started with `#EXTM3U`. |
| `m3u_duration_seconds(p, i)` | `Int` | Whole-second `#EXTINF` duration; `-1` when absent or out of range. |
| `m3u_title(p, i)` | `Str` | `#EXTINF` title (verbatim, may be `""`); `""` out of range. |
| `m3u_path(p, i)` | `Str` | Path of the entry (verbatim); `""` out of range. |
| `m3u_tag_count(p)` | `Int` | Total stored raw tag/comment lines. |
| `m3u_tag(p, j)` | `Str` | Raw tag/comment line `j` in document order; `""` out of range. |
| `m3u_entry_tag_count(p, i)` | `Int` | Raw tag lines directly preceding entry `i`; `0` out of range. |
| `m3u_entry_tag(p, i, j)` | `Str` | `j`-th preceding tag of entry `i`; `""` out of range. |
| `m3u_trailing_tag_count(p)` | `Int` | Tag lines after the last entry (for example `#EXT-X-ENDLIST`). |
| `m3u_trailing_tag(p, j)` | `Str` | `j`-th trailing tag; `""` out of range. |

## Error model

`m3u_parse` is total: it returns `Ok(Playlist)` or `Err(msg)` with a
`"m3u: "` prefix. There are exactly three error messages:

| Message | Raised when |
|---|---|
| `m3u: bad #EXTINF: <line>` | A line starting with `#EXTINF` is not `#EXTINF:<digits>,<title>` (missing colon or comma). |
| `m3u: bad duration in #EXTINF: <line>` | The seconds field is empty, negative, floating point, non-numeric, whitespace-padded, or longer than 18 digits. |
| `m3u: missing path after #EXTINF` | The input ends, or another `#EXTINF` starts, before the pending entry's path line. |

Everything else is accepted by documented design: a missing header, a path
line before a later `#EXTM3U` (the late header is then an ordinary raw tag),
blank lines anywhere, unknown tags, and whitespace-only lines (which are
paths, stored verbatim).

## Limitations

- No HLS semantics: tags are opaque text, `#EXTINF` durations are not
  validated against `#EXT-X-TARGETDURATION`, and segments are not assembled.
- Integer seconds only: `#EXTINF:9.009,...` (common in HLS) is
  `Err("m3u: bad duration in #EXTINF: ...")`; coarser whole-second playlists
  round-trip, float-timestamped ones do not. Values above 18 digits are
  rejected as out of range.
- A path line can never start with `#` and a path/title can never end with
  CR; M3U has no escaping for those cases.
- No file existence checks, no URL validation beyond a non-empty path, no
  normalization of relative paths.
- Parsing is whole-document; there is no streaming API.
- Comment ordering relative to entries is preserved, but blank-line layout
  and CRLF byte layout are not.
- A leading UTF-8 BOM is not stripped, so a BOM-prefixed `#EXTM3U` becomes a
  raw tag and `m3u_has_header` is false.

See `SPEC.md` for the exact line grammar, the data-model invariants, the
error catalog, the round-trip rules and the test matrix. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
