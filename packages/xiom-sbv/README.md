# xiom.sbv

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a strict, in-memory YouTube SBV subtitle codec: comma timing
> lines with unpadded-hour `.` timestamps, flat payload-line storage,
> millisecond accessors, and a canonical emitter.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.byte_at` and `xiom.string.compare.str_compare`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.sbv` parses a YouTube SBV (SubViewer) document held in memory as an
`Str` into a flat `Sbv` track and serializes it back canonically. It
validates the documented subset strictly, keeps payload bytes exact, and
round-trips canonical documents `parse -> format -> parse`.

What it handles:

- blank-line separated cue blocks with no index line: a timing line
  `h:mm:ss.mmm,h:mm:ss.mmm` followed by one or more payload lines;
- the SBV digit policy: the hour field is one or two digits, minutes and
  seconds exactly two digits, milliseconds exactly three (`0:00:01.000`,
  `00:00:01.000`, `99:59:59.999`);
- optional spaces/tabs around the comma and at both ends of the timing line,
  accepted on read and never written by the canonical emitter;
- payload lines preserved in order and stored flat as
  `[payload_starts[i], payload_ends[i])` ranges into one shared line buffer;
- CRLF and LF documents (both parse to the same track; output is LF).

It intentionally does **not** render captions, sanitize HTML tags, interpret
style tags, convert to SRT (the sibling `xiom.srt` covers SubRip), or read
SSA/ASS -- see Limitations and `SPEC.md` for the exact grammar and
decisions.

## Install / use

```
xiom pkg install xiom.sbv@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Quick start:

```xi
use xiom.sbv;
use xiom.io;

fn main() -> Int {
  let doc = "0:00:01.000,0:00:02.500\nHello\nWorld\n\n0:00:03.000,0:00:04.000\nSecond\n";
  let r = sbv_parse(doc);
  if !r.is_ok {
    io.println(r.error);
    return 1;
  }
  let s = r.value;
  io.println(sbv_cue_text(&s, 0));            // Hello (LF) World
  io.println(sbv_cue_line(&s, 0, 1));         // World
  io.println(sbv_cue_duration_ms(&s, 0));     // 1500
  io.println(sbv_format_timestamp(3723456));  // 1:02:03.456
  io.println(sbv_format(&s));                 // canonical document
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `sbv_parse(text)` | `Result[Sbv, Str]` | Parse a whole SBV document (LF/CRLF). |
| `sbv_format(s)` | `Str` | Canonical serialization: unpadded-hour timestamps, no comma whitespace, LF, one blank line between cues. |
| `sbv_parse_timestamp(t)` | `Result[Int, Str]` | Parse one `h:mm:ss.mmm` timestamp to milliseconds. |
| `sbv_format_timestamp(ms)` | `Str` | Canonical timestamp text for `ms` (negative clamps to zero). |
| `sbv_cue_count(s)` | `Int` | Number of cues. |
| `sbv_cue_start_ms(s, i)` | `Int` | Cue start in milliseconds; `-1` out of range. |
| `sbv_cue_end_ms(s, i)` | `Int` | Cue end in milliseconds; `-1` out of range. |
| `sbv_cue_duration_ms(s, i)` | `Int` | `end - start` in milliseconds; `-1` out of range. |
| `sbv_cue_line_count(s, i)` | `Int` | Payload lines of cue `i`; `0` out of range. |
| `sbv_cue_line(s, i, j)` | `Str` | Payload line `j` of cue `i`, verbatim; `""` out of range. |
| `sbv_cue_text(s, i)` | `Str` | Payload lines joined with `"\n"`; `""` out of range. |

## Timestamp rules

Accepted form (no surrounding whitespace inside `sbv_parse_timestamp`):

```
h:mm:ss.mmm      hours 1 or 2 digits 0..99, minutes/seconds exactly two
                 digits 00..59, milliseconds exactly three digits 000..999
```

The canonical emitter writes the hour field without leading zeros
(`0:00:01.000`), so `00:00:01.000` normalizes to `0:00:01.000`. Whole
milliseconds are `h*3600000 + mm*60000 + ss*1000 + mmm`. Minutes or seconds
above 59 are a range error distinct from a shape error. A cue whose end is
before its start is rejected (equal times are allowed). Hours at or above
100 format with more than two digits but fail to parse, so they do not
round-trip.

## Error model

All failures are `Err(message)` with an `"sbv: "` prefix and no line numbers:

| Message | Raised when |
|---|---|
| `sbv: empty input` | The document has no cue blocks (empty or blank lines only). |
| `sbv: missing comma` | A non-blank block-start line has a `:` but no comma (e.g. `0:00:01.000 0:00:02.000`). |
| `sbv: text before first cue` | The first non-blank line has neither a comma nor a `:` (text where the first timing line belongs). |
| `sbv: payload before timing` | After a cue, a block-start line has neither a comma nor a `:` (payload text where a timing line belongs). |
| `sbv: bad timestamp shape` | A timestamp is not exactly `h:mm:ss.mmm` (wrong digit counts or separators), or content follows the end timestamp. |
| `sbv: timestamp out of range` | Minutes or seconds exceed 59. |
| `sbv: end before start` | Both timestamps parse and the end is earlier than the start. |
| `sbv: cue without payload` | A timing line is followed by a blank line or end of input. |

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.sbv
```

Expected tail: 20 `[PASS]` lines, `xiom.sbv: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Whole document only**: no streaming, no incremental parsing.
- **No rendering or interpretation**: tags and style markup are opaque
  bytes; no HTML sanitization, no styling semantics.
- **Strict timestamps**: hours are one or two digits on read, minutes and
  seconds exactly two, milliseconds exactly three; the separator is a dot.
  A timing line carries no settings: anything after the end timestamp is a
  shape error.
- **Blank lines are structural**: a blank line always ends a cue, so a
  payload cannot contain one; whitespace-only lines are payload text, not
  separators.
- **Greedy payload**: a payload line that looks like a timing line stays
  text, so two cues must be separated by a blank line.
- **Payload is mandatory**: a cue without at least one payload line is an
  error, and `sbv_format` of a hand-built cue with an empty payload range
  produces a document that will not re-parse.
- **No BOM handling**: a leading UTF-8 BOM makes the first timing line fail.
- **No ordering/overlap validation**: cues may overlap or be out of order;
  no per-track duration helper.
- Errors carry no line/column numbers.

See `SPEC.md` for the full grammar, decisions, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
