# xiom.cue

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** CUE sheet parsing and canonical emitting; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Overview

`xiom.cue` is a small, dependency-free codec for CDRWIN/EAC-style CUE sheets.
It parses a whole sheet into one flat element stream, exposes the files,
tracks, indices and text directives through typed accessors, and emits a
canonical CUE document.

The codec covers the structural subset of the format that describes a CD
image layout:

- `CATALOG <13 digits>` (album catalog number, optional quotes),
- `FILE "<name>" <type>` with the type (`WAVE`, `MP3`, `AIFF`, `BINARY`,
  `MOTOROLA`, ...) passed through verbatim,
- `TRACK <nn> <type>` with track numbers 01..99 and types such as `AUDIO`,
  `MODE1/2352`, `MODE2/2352` passed through verbatim,
- `INDEX <nn> <mm:ss:ff>`, `PREGAP <mm:ss:ff>` and `POSTGAP <mm:ss:ff>` with
  frames 00..74 and seconds 00..59,
- `PERFORMER`, `TITLE` and `SONGWRITER` as quoted or bare values at either
  level, with `""` doubling a quote inside a quoted value,
- `ISRC <12 alphanumerics>` (track level),
- `REM ...` lines passed through verbatim.

The parser is strict about shape: keywords are case-sensitive uppercase, track
and index numbers are exactly two digits, and times must occupy the rest of
their line. Structural errors (bad numbers, bad times, positioned keywords,
unterminated quotes, stray text) are `Err("cue: ...")`; a TRACK that never
receives an `INDEX 01` is also an error. It performs no audio-data
verification, no disc-ID math and no burning.

## Install / use

```
xiom pkg install xiom.cue@0.1.0
```

```xi
use xiom.cue;
```

## Quick start

```xi
use xiom.cue;
use xiom.io;

fn main() -> Int {
  let r = cue_parse("FILE \"album.wav\" WAVE\nTRACK 01 AUDIO\nTITLE \"One\"\nINDEX 01 00:00:00\n");
  match r {
    Ok(c) => {
      io.println(cue_file_name(&c, 0));    // album.wav
      io.println(cue_file_type(&c, 0));    // WAVE
      io.println(cue_track_type(&c, 0));   // AUDIO
      io.println(cue_element_text(&c, 2)); // One
      if cue_index_frames(&c, 0) == 0 { io.println("starts at 00:00:00"); }
      io.println(cue_emit(&c));            // canonical CUE text
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API summary

Element kinds (`Int` codes returned by `cue_element_kind`):

| Constant | Value | Element |
|---|---|---|
| `EK_FILE` | 1 | `FILE "name" type` |
| `EK_TRACK` | 2 | `TRACK nn type` |
| `EK_INDEX` | 3 | `INDEX nn mm:ss:ff` |
| `EK_PREGAP` | 4 | `PREGAP mm:ss:ff` |
| `EK_POSTGAP` | 5 | `POSTGAP mm:ss:ff` |
| `EK_PERFORMER` | 6 | `PERFORMER value` |
| `EK_TITLE` | 7 | `TITLE value` |
| `EK_SONGWRITER` | 8 | `SONGWRITER value` |
| `EK_REM` | 9 | `REM body` |
| `EK_ISRC` | 10 | `ISRC code` |
| `EK_CATALOG` | 11 | `CATALOG number` |

Parse / emit:

| Function | Returns | Description |
|---|---|---|
| `cue_parse(text)` | `Result[Cue, Str]` | Parse a whole sheet; LF and CRLF; `Err("cue: ...")` on malformed input. |
| `cue_emit(c)` | `Str` | Canonical emission: LF lines, two-digit numbers, `mm:ss:ff`, track bodies indented; round-trip safe. |

Generic element accessors (out-of-range results in parentheses):

| Function | Returns | Description |
|---|---|---|
| `cue_element_count(c)` | `Int` | Number of elements. |
| `cue_element_kind(c, i)` | `Int` | `EK_*` code (`-1`). |
| `cue_element_kind_count(c, kind)` | `Int` | Number of elements of a kind. |
| `cue_element_num(c, i)` | `Int` | TRACK/INDEX number, 0 otherwise (`-1`). |
| `cue_element_min(c, i)` | `Int` | Minutes of INDEX/PREGAP/POSTGAP (`-1`). |
| `cue_element_sec(c, i)` | `Int` | Seconds of INDEX/PREGAP/POSTGAP (`-1`). |
| `cue_element_frame(c, i)` | `Int` | Frames of INDEX/PREGAP/POSTGAP (`-1`). |
| `cue_element_frames(c, i)` | `Int` | `(mm*60 + ss)*75 + ff` for times, else `-1`. |
| `cue_element_text(c, i)` | `Str` | FILE name, value, code, number or REM body (`""`). |
| `cue_element_text2(c, i)` | `Str` | FILE/TRACK type (`""`). |
| `cue_element_quoted(c, i)` | `Bool` | True when the source value was quoted (`false`). |
| `cue_element_file(c, i)` | `Int` | Owning FILE ordinal (`-1`). |
| `cue_element_track(c, i)` | `Int` | Owning TRACK ordinal, track's own ordinal for TRACK (`-1`). |

Typed accessors -- files:

| Function | Returns | Description |
|---|---|---|
| `cue_file_count(c)` | `Int` | Number of FILE elements. |
| `cue_file_element(c, j)` | `Int` | Element index of file `j` (`-1`). |
| `cue_file_name(c, j)` | `Str` | File name (`""`). |
| `cue_file_type(c, j)` | `Str` | File type, verbatim (`""`). |

Typed accessors -- tracks:

| Function | Returns | Description |
|---|---|---|
| `cue_track_count(c)` | `Int` | Number of TRACK elements. |
| `cue_track_element(c, t)` | `Int` | Element index of track `t` (`-1`). |
| `cue_track_number(c, t)` | `Int` | Track number 1..99 (`-1`). |
| `cue_track_type(c, t)` | `Str` | Track type, verbatim (`""`). |
| `cue_track_file(c, t)` | `Int` | Owning FILE ordinal (`-1`). |
| `cue_track_index_count(c, t)` | `Int` | Number of INDEX elements of track `t` (`0`). |
| `cue_track_index(c, t, j)` | `Int` | Global index ordinal of the `j`-th index of track `t` (`-1`). |
| `cue_track_has_index01(c, t)` | `Bool` | True when track `t` has an INDEX 01 (`false`). |

Typed accessors -- indices:

| Function | Returns | Description |
|---|---|---|
| `cue_index_count(c)` | `Int` | Number of INDEX elements. |
| `cue_index_element(c, k)` | `Int` | Element index of index `k` (`-1`). |
| `cue_index_number(c, k)` | `Int` | Index number 0..99 (`-1`). |
| `cue_index_min(c, k)` | `Int` | Minutes (`-1`). |
| `cue_index_sec(c, k)` | `Int` | Seconds (`-1`). |
| `cue_index_frame(c, k)` | `Int` | Frames (`-1`). |
| `cue_index_frames(c, k)` | `Int` | Total frames from the start of the disc (`-1`). |
| `cue_index_track(c, k)` | `Int` | Owning TRACK ordinal (`-1`). |

## Error model

`cue_parse` is total: it returns `Ok(Cue)` or `Err(msg)` with a `"cue: "`
prefix. The offending line is appended where shown.

| Message | Raised when |
|---|---|
| `cue: NUL byte in input` | The input contains a `0x00` byte. |
| `cue: text outside catalog: <line>` | A non-blank line does not start with a keyword (digits, quotes, `#`, punctuation, ...). |
| `cue: unknown keyword: <token>` | The leading token is not a known uppercase keyword (`FOO`, `TRACKX`, lowercase `track`, ...). |
| `cue: keyword not allowed here: <KW>` | INDEX/PREGAP/POSTGAP/ISRC before any TRACK, or CATALOG after a TRACK. |
| `cue: bad track number: <line>` | TRACK number is not exactly two digits 01..99. |
| `cue: bad track type: <line>` | TRACK type missing, empty or containing whitespace. |
| `cue: bad index number: <line>` | INDEX number is not exactly two digits 00..99. |
| `cue: bad index time: <line>` | INDEX time is not `mm:ss:ff`, or has trailing text. |
| `cue: bad gap time: <line>` | PREGAP/POSTGAP time is not `mm:ss:ff`, or has trailing text. |
| `cue: second out of range: <line>` | The `ss` field is above 59. |
| `cue: frame out of range: <line>` | The `ff` field is above 74. |
| `cue: track <nn> has no INDEX 01` | A TRACK reaches the next TRACK/FILE/EOF without an INDEX 01 (first offender reported). |
| `cue: unterminated quote: <line>` | A quoted value has no closing quote. |
| `cue: trailing text after quote: <line>` | A quoted value is followed by more text on the line. |
| `cue: missing value: <line>` | PERFORMER/TITLE/SONGWRITER carries no value. |
| `cue: bad FILE: <line>` | FILE name is unquoted, the type is missing, empty or contains whitespace/quotes. |
| `cue: bad CATALOG: <line>` | CATALOG is not exactly 13 ASCII digits (quotes allowed). |
| `cue: bad ISRC: <line>` | ISRC is not exactly 12 ASCII alphanumerics (quotes allowed). |

Every accessor and `cue_emit` are total; they never return errors. `cue_emit`
does not validate: a hand-built `Cue` must keep all ten Vecs the same length
and its `Str` fields NUL-free.

## Limitations

- Structural codec only: no audio data, no `.wav`/`.bin` inspection, no
  disc-ID math, no burning, no CDTEXT rendering.
- `CDTEXTFILE` and `FLAGS` are not in the subset; they are
  `Err("cue: unknown keyword: ...")` rather than passed through.
- Keywords are case-sensitive uppercase; `track`, `File` and similar are
  unknown keywords.
- Track/index numbers are strictly two digits, and times strictly `mm:ss:ff`
  ending the line: `TRACK 1`, `INDEX 010` and `INDEX 01 00:00:00 extra` are
  Err.
- Quoted values support exactly one escape: `""` is a literal quote. There
  are no backslash escapes, so Windows paths such as `"C:\Music\a.wav"`
  survive verbatim.
- `CATALOG` must be 13 digits and `ISRC` 12 alphanumerics; other catalogue
  conventions are rejected rather than stored.
- A track without `INDEX 01` is an error (a track numbering sequence is not
  otherwise validated: no uniqueness or ordering checks).
- No file existence checks and no path normalization; file names and types
  are opaque text.
- Whole-document only: no streaming, no editing API, no file I/O.
- Canonical emission normalizes CRLF, blank lines and indentation; a
  single-digit number can never be reproduced because it can never be
  parsed.
- Errors carry the offending line text but no line or column numbers.

See `SPEC.md` for the exact grammar, the position rules, the data-model
invariants, the error catalog, the round-trip rules and the test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
