# xiom.srt -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.srt` (`src/srt.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for SubRip (SRT) subtitles:

- `srt_parse` -- document -> `Result[Srt, Str]`;
- `srt_format` -- canonical serialization (indices renumbered, comma
  timestamps, LF);
- `srt_parse_timestamp` / `srt_format_timestamp` -- the timestamp grammar on
  its own;
- accessors for cue count, index, start/end milliseconds, trailing settings
  and the payload-line range (`srt_cue_line_count`, `srt_cue_line`,
  `srt_cue_text`).

The codec keeps payload bytes exact, validates the documented subset
strictly, and round-trips canonical documents `parse -> format -> parse`.

## 2. Non-goals

- Rendering captions; no layout, no text shaping, no font handling.
- HTML/tag sanitization: markup such as `<i>` is ordinary payload text and
  passes through unchanged.
- Encoding conversion: `Str` is treated as a UTF-8 byte buffer and never
  re-encoded; no BOM stripping.
- SSA/ASS, WebVTT, MicroDVD, TTML, SAMI and binary caption formats.
- Frame-based or SMPTE timecodes (drop-frame, `HH:MM:SS;FF`).
- Cue settings semantics: the text after the end timestamp is passed through
  verbatim and never validated, applied or rewritten.
- Cue ordering, overlap detection, merging, splitting, seeking, or duration
  computation.
- Reading indices that are not positive decimal integers; enforcing index
  sequentiality or uniqueness.
- Streaming/incremental parsing.
- Any FFI, file I/O, or registry integration.

## 3. Data model

```xi
pub type Srt = {
  indexes: Vec[Int];         // index value read from the document
  starts: Vec[Int];          // cue start, milliseconds
  ends: Vec[Int];            // cue end, milliseconds
  settings: Vec[Str];        // verbatim settings text, "" when absent
  payload_starts: Vec[Int];  // per-cue range start into `lines`
  payload_ends: Vec[Int];    // per-cue range end (exclusive) into `lines`
  lines: Vec[Str];           // shared payload-line store
}
```

Invariants of a parsed value:

- `indexes`, `starts`, `ends`, `settings`, `payload_starts` and `payload_ends`
  all have the same length (the cue count).
- For cue `i`: `0 <= payload_starts[i] < payload_ends[i] <= lines.len()`;
  its payload lines are `lines[payload_starts[i] .. payload_ends[i])` and the
  range is non-empty.
- Payload ranges follow document order and do not overlap:
  `payload_ends[i] <= payload_starts[i + 1]`.

`Vec[StructType]` is unsupported in this compiler, so cues are deliberately
flat: parallel homogeneous vectors plus payload-line ranges into one shared
line buffer. There is no `Vec[Cue]`. Hand-built `Srt` values with drifted
vector lengths cannot cause out-of-range reads: every accessor and
`srt_format` clamp against the actual lengths (section 7).

## 4. Document grammar

```
document  = *blank block *( blank block ) *blank
block     = index LF timing LF payload *( LF payload )
index     = 1*DIGIT                      ; value >= 1
timing    = [SP|TAB] timestamp [SP|TAB] "-->" [SP|TAB] timestamp [SP|TAB settings]
payload   = ( SP | TAB | VCHAR )*        ; non-blank line
```

```
blank     = ""                            ; exactly zero bytes
timestamp = HH ":" MM ":" SS sep mmm
HH        = 2DIGIT                        ; 00..99
MM, SS    = 2DIGIT                        ; 00..59 (above 59 is an error)
mmm       = 3DIGIT                        ; exactly three digits, 000..999
sep       = "," | "."                     ; "," is canonical; "." accepted
```

## 5. Parsing decisions (each is covered by the conformance suite)

1. **Physical lines.** `text` is split on LF. A CR immediately before LF is
   removed, so CRLF documents produce the same lines as LF documents. A
   trailing LF does not produce a final empty line. A lone CR is not a line
   ending and stays inside its line.
2. **Blank lines.** A blank line is a zero-byte line. A line holding only
   spaces or tabs is payload text, not a separator. Any number of
   consecutive blank lines may separate blocks; leading and trailing blanks
   are ignored and stray blanks are never an error.
3. **Blocks.** A block is an index line, a timing line and one or more
   payload lines, in that order.
4. **Index policy (lenient parse, canonical emit).** The index line must
   consist of one or more ASCII digits with a value `>= 1`; leading zeros
   are accepted and the numeric value is what is stored (`007` is 7).
   Index values need not be sequential or unique: gaps, repeats and
   out-of-order indices parse successfully and are available via
   `srt_cue_index`. `srt_format` always renumbers cues `1..n`.
5. **Missing index.** A block whose first line contains the byte sequence
   `-->` is a timing line where the index belongs:
   `Err("srt: missing index")`.
6. **Bad index.** A block whose first line contains no `-->` and is not a
   positive decimal integer (empty is impossible there; examples: `0`,
   `abc`, `1a`, `+1`, `-1`, ` 1`) is `Err("srt: bad index")`.
7. **Missing timing line.** An index line that is the last line of the
   document, or that is directly followed by a blank line, is
   `Err("srt: missing timing line")`.
8. **Stray text.** After a valid index line, the next non-blank line must
   contain `-->`. A non-blank line without it is `Err("srt: stray text")`.
   (Text at a block start is instead a bad index, per rule 6.)
9. **Timing line.** The first `-->` on the line splits it. The text before
   the arrow is trimmed of spaces/tabs and must be exactly one timestamp;
   after the arrow, spaces/tabs are skipped, the next token (up to a
   space/tab or the end of line) must be exactly one timestamp, and the
   remainder of the line with surrounding spaces/tabs trimmed is the
   settings text, stored verbatim (interior spacing preserved, may be
   empty). Zero or more spaces/tabs are accepted around the arrow, so
   `00:00:01,000-->00:00:02,000` parses.
10. **Timestamps.** See section 6. The start is validated first (shape, then
    range), then the end, then `end < start` is
    `Err("srt: end before start")`; equal start and end is allowed. Errors
    carry no position information.
11. **Payload.** Every line after the timing line up to the next blank line
    or end of input is a payload line, stored verbatim. At least one payload
    line is required: a timing line directly followed by a blank line or end
    of input is `Err("srt: cue without payload")`. A blank line always ends
    the block, so a payload cannot contain a blank line.
12. **Empty document.** A document with no cue blocks (empty input or blank
    lines only) is `Err("srt: empty input")`.
13. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites or splits multi-byte sequences, so
    non-ASCII payload and settings bytes round-trip exactly. A leading
    UTF-8 BOM is not stripped and makes the first index line fail.

## 6. Timestamp grammar

```
timestamp = HH ":" MM ":" SS sep mmm
HH        = 2DIGIT (00..99)
MM, SS    = 2DIGIT (00..59)
mmm       = 3DIGIT (000..999)
sep       = "," | "."          ; "," canonical; "." accepted on read
```

- The separator must be `,` or `.`; any other byte is a bad shape.
- The timestamp is exactly 12 bytes; no surrounding whitespace is allowed by
  `srt_parse_timestamp` (inside a timing line the timestamps are trimmed by
  rule 9).
- Hours are exactly two digits; a one-digit hour (`0:00:01,000`) is a bad
  shape. Three-digit hours are not accepted on read.
- The millisecond field is exactly three digits; `,00`, `,0000` and `;000`
  are bad shapes.
- Minutes or seconds above 59 are an out-of-range component
  (`srt: timestamp out of range`), not a shape error.
- Values convert to whole milliseconds:
  `HH*3600000 + MM*60000 + SS*1000 + mmm`.
- Canonical output is always `HH:MM:SS,mmm`, zero-padded. Hours at or above
  100 print with more than two digits (`100:00:00,000`) and are accepted by
  `srt_format_timestamp` but rejected by `srt_parse_timestamp` (documented,
  not round-trip safe).

## 7. Canonical output

`srt_format` emits, for a cue count `n`:

1. cues numbered `1..n` in order (any stored index values are ignored);
2. `HH:MM:SS,mmm --> HH:MM:SS,mmm` with canonical zero-padded comma
   timestamps;
3. one space followed by the stored settings text when it is non-empty
   (whitespace-only settings are treated as empty);
4. each payload line verbatim, LF-terminated;
5. exactly one blank line between cue blocks; the document ends with LF
   after the last payload line.

An empty track formats to `""`. Consequences: CRLF input is normalized to
LF; stray blank lines collapse; dot separators become commas; non-sequential
indices become `1..n`. Inputs that are already canonical round-trip
byte-exactly.

Defensive clamping: `srt_format` computes the cue count as the minimum length
of the vectors it reads and clamps every payload range into `[0,
lines.len()]`; a hand-built `Srt` with drifted vectors therefore emits at
most the consistent prefix instead of reading out of bounds. Note that a cue
emitted with an empty payload range cannot be re-parsed (rule 11); parsed
values always satisfy the payload invariant.

## 8. API signatures

```xi
pub type Srt = { ... }                                   ; see section 3

pub fn srt_parse(text: Str) -> Result[Srt, Str]
pub fn srt_format(s: &Srt) -> Str
pub fn srt_parse_timestamp(t: Str) -> Result[Int, Str]
pub fn srt_format_timestamp(ms: Int) -> Str
pub fn srt_cue_count(s: &Srt) -> Int
pub fn srt_cue_index(s: &Srt, i: Int) -> Int
pub fn srt_cue_start_ms(s: &Srt, i: Int) -> Int
pub fn srt_cue_end_ms(s: &Srt, i: Int) -> Int
pub fn srt_cue_settings(s: &Srt, i: Int) -> Str
pub fn srt_cue_line_count(s: &Srt, i: Int) -> Int
pub fn srt_cue_line(s: &Srt, i: Int, j: Int) -> Str
pub fn srt_cue_text(s: &Srt, i: Int) -> Str
```

Accessor sentinels: `srt_cue_index`, `srt_cue_start_ms` and `srt_cue_end_ms`
return `-1` for a negative or out-of-range index; `srt_cue_settings`,
`srt_cue_line` and `srt_cue_text` return `""`; `srt_cue_line_count` returns
`0`. Out-of-range line indices `j` also yield `""`.

Complexity: `srt_parse` and `srt_format` are O(input or payload size);
timestamp helpers are O(1); all accessors are O(1) except `srt_cue_text`,
which is O(lines of the cue).

## 9. Error catalog

All failures are `Err(msg)` where `msg` starts with `"srt: "` and carries no
line/column number:

| Message | Trigger |
|---|---|
| `srt: empty input` | No cue blocks (empty document or blank lines only). |
| `srt: missing index` | A block starts with a line containing `-->`. |
| `srt: bad index` | The block-start line has no `-->` and is not a positive decimal integer (including `0`, non-digits and digit-plus-junk). |
| `srt: missing timing line` | The index line is the last line or is followed by a blank line. |
| `srt: stray text` | After a valid index line, the next non-blank line contains no `-->`. |
| `srt: bad timestamp shape` | A timestamp is not exactly 12 bytes of `HH:MM:SS[.,]mmm` (wrong length, bad separators or digits, wrong millisecond digit count). |
| `srt: timestamp out of range` | Minutes or seconds exceed 59. |
| `srt: end before start` | Both timestamps parse and the end is earlier than the start. |
| `srt: cue without payload` | The timing line is followed by a blank line or end of input. |

Validation order inside a block: missing/bad index, missing timing line,
stray text, start timestamp shape, start timestamp range, end timestamp
shape, end timestamp range, end-before-start, cue-without-payload. The first
failure encountered is returned.

## 10. Test plan

`tests/test_conformance.xi` (module `srt_tests`) runs 21 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | two cues | block split, index accessor, exact times, payload (rules 3, 4, 9) |
| t2 | multi-line payload | line order, `srt_cue_line`, LF-joined text (rule 11) |
| t3 | CRLF | CRLF and LF parse identically; output is LF (rule 1) |
| t4 | timestamps | 0, 1 ms, 3723456 ms, 99:59:59,999; format, clamp (section 6) |
| t5 | timestamp errors | ms digit count, `;` separator, short hour, empty, range; dot accepted (rule 10, section 6) |
| t6 | end vs start | end < start Err; equal times allowed (rule 10) |
| t7 | settings | trailing settings verbatim; canonical placement (rule 9, section 7) |
| t8 | missing index | timing-line-first block, with and without leading blanks (rule 5) |
| t9 | bad index | `0`, `abc`, `1a` (rule 6) |
| t10 | stray text | text where the timing line belongs; block-level text is a bad index (rules 6, 8) |
| t11 | missing timing line | index at EOF; index followed by blank (rule 7) |
| t12 | cue without payload | timing line at EOF; timing line followed by blank (rule 11) |
| t13 | empty input | `""`, LF-only and CRLF-only documents (rule 12) |
| t14 | index renumbering | indices 7, 3, 007 accepted; output 1, 2, 3; re-parse (rule 4, section 7) |
| t15 | canonical output | CRLF + dot + extra blanks + tight arrow normalized exactly (section 7) |
| t16 | round trip | canonical doc parse -> format -> parse -> format, byte-exact (section 7) |
| t17 | accessor sentinels | every accessor at negative and high indices (section 8) |
| t18 | UTF-8 + whitespace-only line | multi-byte bytes exact; `"   "` is payload text (rules 2, 11, 13) |
| t19 | arrow whitespace | tight arrow parses; empty settings stay empty (rule 9) |
| t20 | boundaries | 00:00:00,000, 1 ms and 99:59:59,999 exact; canonical output (section 6) |
| t21 | drifted vectors | hand-built `Srt` with an out-of-bounds payload range is clamped (section 7) |

Every string comparison in the suite goes through
`xiom.string.compare.str_compare` (BUG 17 discipline) and every element read
goes through a typed local.

## 11. Compiler / stdlib notes (v0.61.3)

- **Flat storage.** No `Vec[StructType]`: cues live in parallel vectors and
  reference payload lines by range into one shared buffer.
- **Ok/Err confinement.** Results are constructed only in the leaf helpers
  `_ok_srt`, `_err_srt`, `_ok_int`, `_err_int`; the `Srt` literal itself is
  built only by `_make_srt`.
- **Bytes as Int.** Every `xiom.string.byte_at` read goes through
  `_byte(s, pos) -> Int`, which masks with `& 0xFF`, so no `UInt8` constant
  >= 128 is involved in a comparison and no widened byte can be negative.
- **No Str `==`.** String equality uses
  `xiom.string.compare.str_compare`; Vec element reads (including the `Int`
  entries of `indexes` and the range vectors) are bound to typed locals
  before use.
- **Trim helper.** `_trim_from` exists so a Str read from a `Vec[Str]`
  element is never trimmed with an explicit `s.len()` call at the call site
  (the sibling `xiom.vtt` workaround).
- **No `match`, no lambdas, no `Vec[fn]`.** Parsing is `if`/`elif`/`while`
  only; the test suite calls `t1()` ... `t20()` directly.
- **No conversion imports.** Non-negative decimal formatting is local
  (`_int_str`, `_pad2`, `_pad3`).
- **Drift guards.** `srt_format`, `srt_cue_count` and the range accessors
  clamp/min against the actual vector lengths.

## 12. Known limitations

- Whole-document, in-memory only: no streaming API.
- Strict timestamps on read: exactly two hour digits and exactly three
  millisecond digits; a dot is accepted but a comma is canonical; times at
  or above 100 hours fail to re-parse.
- A blank line always ends a block, so payloads cannot contain blank lines;
  whitespace-only lines are text.
- At least one payload line per cue is required; an index without a timing
  line, or a timing line without payload, is an error rather than an empty
  cue.
- Index sequentiality is not enforced on read; the emitter renumbers, so the
  stored index values are informational and do not survive formatting.
- Trailing settings are preserved verbatim but never trimmed beyond the
  surrounding spaces/tabs, validated or interpreted; interior spacing is
  kept.
- No HTML/tag sanitization: styled payloads are plain text.
- No cue ordering, overlap or duration checks.
- A leading UTF-8 BOM is not stripped.
- Errors carry no line/column numbers.
