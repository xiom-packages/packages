# xiom.srt

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a strict, in-memory SubRip (SRT) subtitle codec: index lines,
> timing lines with trailing-settings pass-through, flat payload-line
> storage, millisecond accessors, and a canonical emitter.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.byte_at`, `xiom.string.str_contains` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.srt` parses a SubRip (SRT) document held in memory as an `Str` into a
flat `Srt` track and serializes it back canonically. It validates the
documented subset strictly, keeps payload bytes exact, and round-trips
canonical documents `parse -> format -> parse`.

What it handles:

- blank-line separated cue blocks;
- an integer index line (positive decimal digits; the value is kept and the
  canonical emitter renumbers cues from 1);
- the timing line `hh:mm:ss,mmm --> hh:mm:ss,mmm` (a `.` separator is also
  accepted on read), including tight arrows (`00:00:01,000-->00:00:02,000`);
- trailing settings after the end timestamp, passed through verbatim;
- one or more payload lines per cue, preserved in order and stored flat as
  `[payload_starts[i], payload_ends[i])` ranges into one shared line buffer;
- CRLF and LF documents (both parse to the same track; output is LF).

It intentionally does **not** render captions, sanitize HTML tags, convert
encodings, or read SSA/ASS -- see Limitations and `SPEC.md` for the exact
grammar and decisions.

## Install / use

```
xiom pkg install xiom.srt@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Quick start:

```xi
use xiom.srt;
use xiom.io;

fn main() -> Int {
  let doc = "1\n00:00:01,000 --> 00:00:02,500 X1:10 X2:200\nHello\nWorld\n";
  let r = srt_parse(doc);
  if !r.is_ok {
    io.println(r.error);
    return 1;
  }
  let s = r.value;
  io.println(srt_cue_text(&s, 0));                  // Hello (LF) World
  io.println(srt_cue_line(&s, 0, 1));               // World
  io.println(srt_format_timestamp(3723456));        // 01:02:03,456
  io.println(srt_cue_settings(&s, 0));              // X1:10 X2:200
  io.println(srt_format(&s));                       // canonical document
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `srt_parse(text)` | `Result[Srt, Str]` | Parse a whole SRT document (LF/CRLF). |
| `srt_format(s)` | `Str` | Canonical serialization: renumbered indices, `,` timestamps, LF, one blank line between cues. |
| `srt_parse_timestamp(t)` | `Result[Int, Str]` | Parse one `HH:MM:SS,mmm` timestamp to milliseconds. |
| `srt_format_timestamp(ms)` | `Str` | Canonical timestamp text for `ms` (negative clamps to zero). |
| `srt_cue_count(s)` | `Int` | Number of cues. |
| `srt_cue_index(s, i)` | `Int` | Index as read from the document; `-1` out of range. |
| `srt_cue_start_ms(s, i)` | `Int` | Cue start in milliseconds; `-1` out of range. |
| `srt_cue_end_ms(s, i)` | `Int` | Cue end in milliseconds; `-1` out of range. |
| `srt_cue_settings(s, i)` | `Str` | Verbatim trailing settings; `""` when absent or out of range. |
| `srt_cue_line_count(s, i)` | `Int` | Payload lines of cue `i`; `0` out of range. |
| `srt_cue_line(s, i, j)` | `Str` | Payload line `j` of cue `i`, verbatim; `""` out of range. |
| `srt_cue_text(s, i)` | `Str` | Payload lines joined with `"\n"`; `""` out of range. |

## Timestamp rules

Accepted form (byte-exact, no surrounding whitespace):

```
hh:mm:ss,mmm     hours exactly two digits 00..99, minutes/seconds 00..59,
                 milliseconds exactly three digits 000..999
```

A `.` separator is accepted leniently on read; the canonical emitter always
writes `,`. Whole milliseconds are `hh*3600000 + mm*60000 + ss*1000 + mmm`.
Minutes or seconds above 59 are a range error distinct from a shape error.
A cue whose end is before its start is rejected (equal times are allowed).

## Error model

All failures are `Err(message)` with an `"srt: "` prefix and no line numbers:

| Message | Raised when |
|---|---|
| `srt: empty input` | The document has no cue blocks (empty or blank lines only). |
| `srt: missing index` | A block starts with a timing line instead of an index line. |
| `srt: bad index` | The block-start line is neither a timing line nor a positive decimal index (e.g. `0`, `abc`, `1a`). |
| `srt: missing timing line` | An index line is the last line, or is followed by a blank line. |
| `srt: stray text` | After a valid index line, the next line has no `-->`. |
| `srt: bad timestamp shape` | A timestamp is not exactly 12 `HH:MM:SS[.,]mmm` bytes with three millisecond digits. |
| `srt: timestamp out of range` | Minutes or seconds exceed 59. |
| `srt: end before start` | Both timestamps parse and the end is earlier than the start. |
| `srt: cue without payload` | A timing line is followed by a blank line or end of input. |

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.srt
```

Expected tail: 21 `[PASS]` lines, `xiom.srt: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Whole document only**: no streaming, no incremental parsing.
- **No rendering or interpretation**: settings and tags are opaque bytes; no
  HTML sanitization, no styling semantics.
- **Strict timestamps**: hours are exactly two digits on read and the
  millisecond field exactly three digits; a comma is canonical (a dot is
  accepted leniently). Times at or above 100 hours format fine but fail to
  parse (so they do not round-trip).
- **Index policy**: parse accepts any positive decimal index, including
  duplicates, gaps and leading zeros; the recorded value is available via
  `srt_cue_index`, and `srt_format` always renumbers cues sequentially from
  1. Sequentiality is not enforced.
- **Blank lines are structural**: a blank line always ends a cue, so a
  payload cannot contain one; whitespace-only lines are payload text, not
  separators.
- **Payload is mandatory**: a cue without at least one payload line is an
  error, and `srt_format` of a hand-built cue with an empty payload range
  produces a document that will not re-parse.
- **No BOM handling**: a leading UTF-8 BOM makes the first index line fail.
- **No ordering/overlap validation**: cues may overlap or be out of order.
- Errors carry no line/column numbers.

See `SPEC.md` for the full grammar, decisions, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
