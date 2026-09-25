# xiom.sbv -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.sbv` (`src/sbv.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for YouTube SBV subtitles:

- `sbv_parse` -- document -> `Result[Sbv, Str]`;
- `sbv_format` -- canonical serialization (unpadded-hour `.` timestamps, no
  comma whitespace, LF);
- `sbv_parse_timestamp` / `sbv_format_timestamp` -- the timestamp grammar on
  its own;
- accessors for cue count, start/end/duration milliseconds and the
  payload-line range (`sbv_cue_line_count`, `sbv_cue_line`, `sbv_cue_text`).

The codec keeps payload bytes exact, validates the documented subset
strictly, and round-trips canonical documents `parse -> format -> parse`.

## 2. Non-goals

- Rendering captions; no layout, no text shaping, no font handling.
- HTML/tag sanitization: markup such as `<i>` is ordinary payload text and
  passes through unchanged.
- Style tags (`{\an8}`, `<font>`): opaque payload bytes, never validated.
- Conversion to SRT or any other subtitle format; the sibling `xiom.srt`
  covers SubRip, `xiom.vtt` covers WebVTT.
- Encoding conversion: `Str` is treated as a UTF-8 byte buffer and never
  re-encoded; no BOM stripping.
- SSA/ASS, MicroDVD, TTML, SAMI and binary caption formats.
- Frame-based or SMPTE timecodes (drop-frame, `HH:MM:SS;FF`).
- Cue ordering, overlap detection, merging, splitting, seeking, or
  per-track duration computation.
- Streaming/incremental parsing.
- Any FFI, file I/O, or registry integration.

## 3. Data model

```xi
pub type Sbv = {
  starts: Vec[Int];          // cue start, milliseconds
  ends: Vec[Int];            // cue end, milliseconds
  payload_starts: Vec[Int];  // per-cue range start into `lines`
  payload_ends: Vec[Int];    // per-cue range end (exclusive) into `lines`
  lines: Vec[Str];           // shared payload-line store
}
```

Invariants of a parsed value:

- `starts`, `ends`, `payload_starts` and `payload_ends` all have the same
  length (the cue count).
- For cue `i`: `0 <= payload_starts[i] < payload_ends[i] <= lines.len()`;
  its payload lines are `lines[payload_starts[i] .. payload_ends[i])` and the
  range is non-empty.
- Payload ranges follow document order and do not overlap:
  `payload_ends[i] <= payload_starts[i + 1]`.
- `ends[i] >= starts[i]` (equal times are allowed).

`Vec[StructType]` is unsupported in this compiler, so cues are deliberately
flat: parallel homogeneous vectors plus payload-line ranges into one shared
line buffer. There is no `Vec[Cue]`. Hand-built `Sbv` values with drifted
vector lengths cannot cause out-of-range reads: every accessor and
`sbv_format` clamp against the actual lengths (section 7).

## 4. Document grammar

```
document  = *blank block *( blank block ) *blank
block     = timing LF payload *( LF payload )
timing    = [SP|TAB]* timestamp [SP|TAB]* "," [SP|TAB]* timestamp [SP|TAB]*
payload   = ( SP | TAB | VCHAR )*        ; non-blank line
```

```
blank     = ""                            ; exactly zero bytes
timestamp = h ":" MM ":" SS "." mmm
h         = 1*2DIGIT                      ; 0..99
MM, SS    = 2DIGIT                        ; 00..59 (above 59 is an error)
mmm       = 3DIGIT                        ; exactly three digits, 000..999
```

SBV has no index line, no settings field and no `-->` arrow: cue blocks are
recognized by their timing line alone.

## 5. Parsing decisions (each is covered by the conformance suite)

1. **Physical lines.** `text` is split on LF. A CR immediately before LF is
   removed, so CRLF documents produce the same lines as LF documents. A
   trailing LF does not produce a final empty line. A lone CR is not a line
   ending and stays inside its line.
2. **Blank lines.** A blank line is a zero-byte line. A line holding only
   spaces or tabs is payload text, not a separator. Any number of consecutive
   blank lines may separate blocks; leading and trailing blanks are ignored
   and stray blanks are never an error.
3. **Blocks.** A block is a timing line followed by one or more payload
   lines. There is no index line; payloads are consumed greedily up to the
   next blank line, so a payload line may itself look like a timing line
   (rule 11).
4. **Timing line split.** The *first* comma on the line splits it. The
   segment before and the segment after it are each trimmed of spaces/tabs
   (this also trims spaces/tabs at the start and end of the line) and each
   must be exactly one timestamp. A second comma, or any other content after
   the end timestamp, is a bad shape -- SBV has no settings field.
5. **Missing comma.** A non-blank block-start line that contains a `:` byte
   but no comma is a timing-line attempt whose separator is missing:
   `Err("sbv: missing comma")` (examples: `0:00:01.000 0:00:02.000`,
   `0:00:01.000-0:00:02.000`).
6. **Misplaced payload text.** A non-blank block-start line with neither a
   comma nor a `:` is payload text where a timing line belongs. Before any
   cue has been parsed it is `Err("sbv: text before first cue")`; after at
   least one cue it is `Err("sbv: payload before timing")`.
7. **Timestamps.** See section 6. The start is validated first (shape, then
   range), then the end, then `end < start` is
   `Err("sbv: end before start")`; equal start and end is allowed. Errors
   carry no position information.
8. **Payload.** Every line after the timing line up to the next blank line
   or end of input is a payload line, stored verbatim. At least one payload
   line is required: a timing line directly followed by a blank line or end
   of input is `Err("sbv: cue without payload")`. A blank line always ends
   the block, so a payload cannot contain a blank line.
9. **Empty document.** A document with no cue blocks (empty input or blank
   lines only) is `Err("sbv: empty input")`.
10. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites or splits multi-byte sequences, so
    non-ASCII payload bytes round-trip exactly. A leading UTF-8 BOM is not
    stripped and makes the first timing line fail.
11. **Greedy payload.** A non-blank line after a timing line is always
    payload text, even when it parses as a timing line. Two cues must
    therefore be separated by a blank line; a "timing line" inside a payload
    is preserved byte-for-byte and re-emitted as text.

## 6. Timestamp grammar

```
timestamp = h ":" MM ":" SS "." mmm
h         = 1*2DIGIT (0..99)      ; single-digit hours are allowed
MM, SS    = 2DIGIT (00..59)
mmm       = 3DIGIT (000..999)
```

- The dot separator is required; a comma or any other byte is a bad shape.
- The hour field is one or two digits: `0:00:01.000` and `00:00:01.000`
  both parse, and both convert to the same milliseconds. Three-digit hours
  (`000:00:01.000`) are a bad shape.
- Minutes and seconds are exactly two digits: `0:0:01.000` and `0:00:1.000`
  are bad shapes, not shorthand.
- The millisecond field is exactly three digits; `.00`, `.0000` and `,000`
  are bad shapes.
- Minutes or seconds above 59 are an out-of-range component
  (`sbv: timestamp out of range`), not a shape error.
- The timestamp is 11 or 12 bytes and `sbv_parse_timestamp` allows no
  surrounding whitespace (inside a timing line the segments are trimmed by
  rule 4).
- Values convert to whole milliseconds:
  `h*3600000 + MM*60000 + SS*1000 + mmm`.
- Canonical output always uses an unpadded hour field, `h:MM:SS.mmm`. Hours
  at or above 100 print with more than two digits (`100:00:00.000`) and are
  accepted by `sbv_format_timestamp` but rejected by `sbv_parse_timestamp`
  (documented, not round-trip safe).

## 7. Canonical output

`sbv_format` emits, for a cue count `n`:

1. the timing line `h:MM:SS.mmm,h:MM:SS.mmm` with unpadded hours, two
   zero-padded minute/second digits, three millisecond digits and no
   whitespace around the comma;
2. each payload line verbatim, LF-terminated;
3. exactly one blank line between cue blocks; the document ends with LF
   after the last payload line.

An empty track formats to `""`. Consequences: CRLF input is normalized to
LF; stray blank lines collapse; two-digit hours become single-digit below
10; whitespace around the comma disappears. Inputs that are already
canonical round-trip byte-exactly.

Defensive clamping: `sbv_format` computes the cue count as the minimum length
of the vectors it reads and clamps every payload range into `[0,
lines.len()]`; a hand-built `Sbv` with drifted vectors therefore emits at
most the consistent prefix instead of reading out of bounds. Note that a cue
emitted with an empty payload range cannot be re-parsed (rule 8); parsed
values always satisfy the payload invariant.

## 8. API signatures

```xi
pub type Sbv = { ... }                                   ; see section 3

pub fn sbv_parse(text: Str) -> Result[Sbv, Str]
pub fn sbv_format(s: &Sbv) -> Str
pub fn sbv_parse_timestamp(t: Str) -> Result[Int, Str]
pub fn sbv_format_timestamp(ms: Int) -> Str
pub fn sbv_cue_count(s: &Sbv) -> Int
pub fn sbv_cue_start_ms(s: &Sbv, i: Int) -> Int
pub fn sbv_cue_end_ms(s: &Sbv, i: Int) -> Int
pub fn sbv_cue_duration_ms(s: &Sbv, i: Int) -> Int
pub fn sbv_cue_line_count(s: &Sbv, i: Int) -> Int
pub fn sbv_cue_line(s: &Sbv, i: Int, j: Int) -> Str
pub fn sbv_cue_text(s: &Sbv, i: Int) -> Str
```

Accessor sentinels: `sbv_cue_start_ms`, `sbv_cue_end_ms` and
`sbv_cue_duration_ms` return `-1` for a negative or out-of-range index;
`sbv_cue_line` and `sbv_cue_text` return `""`; `sbv_cue_line_count` returns
`0`. Out-of-range line indices `j` also yield `""`.
`sbv_cue_duration_ms` is `end - start`; parsed cues always have a
non-negative duration, and a hand-built track with `end < start` returns the
computed negative difference.

Complexity: `sbv_parse` and `sbv_format` are O(input or payload size);
timestamp helpers are O(1); all accessors are O(1) except `sbv_cue_text`,
which is O(lines of the cue).

## 9. Error catalog

All failures are `Err(msg)` where `msg` starts with `"sbv: "` and carries no
line/column number:

| Message | Trigger |
|---|---|
| `sbv: empty input` | No cue blocks (empty document or blank lines only). |
| `sbv: missing comma` | A non-blank block-start line contains a `:` but no comma (a timing-line attempt missing its separator). |
| `sbv: text before first cue` | The first non-blank line of the document contains neither a comma nor a `:` (payload text where the first timing line belongs). |
| `sbv: payload before timing` | After at least one cue, a non-blank block-start line contains neither a comma nor a `:` (payload text where a timing line belongs). |
| `sbv: bad timestamp shape` | A timestamp is not exactly `h:mm:ss.mmm` with a 1..2-digit hour field, exactly two minute and second digits and exactly three millisecond digits; includes wrong separators, a missing half, a second comma and any content after the end timestamp. |
| `sbv: timestamp out of range` | Minutes or seconds exceed 59. |
| `sbv: end before start` | Both timestamps parse and the end is earlier than the start. |
| `sbv: cue without payload` | The timing line is followed by a blank line or end of input. |

Validation order inside a block: comma presence, missing-comma vs
misplaced-text classification, start timestamp shape, start timestamp range,
end timestamp shape, end timestamp range, end-before-start,
cue-without-payload. The first failure encountered is returned.

## 10. Test plan

`tests/test_conformance.xi` (module `sbv_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | two cues | block split, exact times, payload (rules 3, 7) |
| t2 | multi-line payload | line order, `sbv_cue_line`, LF-joined text (rule 8) |
| t3 | CRLF | CRLF and LF parse identically; output is LF (rule 1) |
| t4 | timestamps | 0, 1 ms, 3723456 ms, 99:59:59.999; format, clamp, 100 h (section 6) |
| t5 | timestamp errors | digit counts, separators, hour width, whitespace, empty, range (section 6) |
| t6 | end vs start | end < start Err; equal times allowed; duration 0 (rule 7) |
| t7 | comma whitespace | spaces/tabs around the comma and line edges accepted; canonical output has none (rules 4, 7) |
| t8 | comma policy | comma required; extra content after the end timestamp is a shape error (rules 4, 5) |
| t9 | cue without payload | timing line at EOF; timing line followed by blank (rule 8) |
| t10 | payload before timing | colon-less text at a later block start (rule 6) |
| t11 | text before first cue | colon-less text before any cue, after leading blanks (rule 6) |
| t12 | empty input | `""`, LF-only and CRLF-only documents (rule 9) |
| t13 | canonical output | CRLF + two-digit hours + comma spaces + extra blanks + trailing tab normalized exactly (section 7) |
| t14 | round trip | canonical doc parse -> format -> parse -> format, byte-exact (section 7) |
| t15 | accessor sentinels | every accessor at negative and high indices (section 8) |
| t16 | UTF-8 + whitespace-only line | multi-byte bytes exact; `"   "` is payload text (rules 2, 8, 10) |
| t17 | greedy payload | a timing-like payload line stays text and round-trips (rule 11) |
| t18 | boundaries | 0:00:00.000, 1 ms and 99:59:59.999 exact (section 6) |
| t19 | drifted vectors | hand-built `Sbv` with an out-of-bounds payload range is clamped (section 7) |
| t20 | duration | end - start; zero-duration cue; out-of-range sentinel (section 8) |

Every string comparison in the suite goes through
`xiom.string.compare.str_compare` (BUG 17 discipline) and every element read
goes through a typed local.

## 11. Compiler / stdlib notes (v0.61.3)

- **Flat storage.** No `Vec[StructType]`: cues live in parallel vectors and
  reference payload lines by range into one shared buffer.
- **Ok/Err confinement.** Results are constructed only in the leaf helpers
  `_ok_sbv`, `_err_sbv`, `_ok_int`, `_err_int`; the `Sbv` literal itself is
  built only by `_make_sbv`.
- **Bytes as Int.** Every `xiom.string.byte_at` read goes through
  `_byte(s, pos) -> Int`, which masks with `& 0xFF`, so no `UInt8` constant
  >= 128 is involved in a comparison and no widened byte can be negative.
- **No Str `==`.** String equality uses
  `xiom.string.compare.str_compare`; Vec element reads are bound to typed
  locals before use.
- **Trim helper.** `_trim_from` exists so a Str read from a `Vec[Str]`
  element is never trimmed with an explicit `s.len()` call at the call site
  (the sibling `xiom.vtt` workaround).
- **No `match`, no lambdas, no `Vec[fn]`.** Parsing is `if`/`else`/`while`
  only; the test suite calls `t1()` ... `t20()` directly.
- **No conversion imports.** Non-negative decimal formatting is local
  (`_int_str`, `_pad2`, `_pad3`).
- **Drift guards.** `sbv_format`, `sbv_cue_count` and the range accessors
  clamp/min against the actual vector lengths.

## 12. Known limitations

- Whole-document, in-memory only: no streaming API.
- Strict timestamps on read: hours are one or two digits and the millisecond
  field exactly three digits; a comma separator is rejected; times at or
  above 100 hours fail to re-parse.
- A blank line always ends a block, so payloads cannot contain blank lines;
  whitespace-only lines are text.
- Payload is greedy: a timing-like line inside a payload is text, so two
  cues must be separated by a blank line.
- At least one payload line per cue is required; a timing line without
  payload is an error rather than an empty cue.
- No settings field: any content after the end timestamp is a shape error.
- No HTML/tag sanitization: styled payloads are plain text.
- No cue ordering, overlap or per-track duration checks.
- A leading UTF-8 BOM is not stripped.
- Errors carry no line/column numbers.
