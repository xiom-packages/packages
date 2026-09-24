# xiom.subtitle -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.subtitle` (`src/subtitle.xi`). Pure XIOM, no FFI.

## 1. Scope

An in-memory reader/writer for the two dominant plain-text caption formats:

- SRT (SubRip): blank-line separated numbered blocks,
  `HH:MM:SS,mmm --> HH:MM:SS,mmm`, one or more text lines per cue,
  (`srt_parse`, `srt_format`);
- WebVTT: a `WEBVTT` header line, blank-line separated cues with
  `HH:MM:SS.mmm` timestamps, NOTE comment blocks, cue settings after the
  arrow (`vtt_parse`, `vtt_format`);

plus one shared in-memory model and its utilities: cue accessors
(`subtitle_cue_count`, `subtitle_start_ms`, `subtitle_end_ms`,
`subtitle_text`), time shifting with clamping (`subtitle_shift`) and total
duration (`subtitle_total_duration_ms`).

## 2. Non-goals

- Streaming / incremental parsing (whole `Str` in memory only).
- ASS/SSA, MicroDVD, TTML, SAMI, binary caption formats.
- WebVTT cue identifiers, `STYLE`/`REGION` blocks, or writing cue settings.
- Frame-based or SMPTE timecodes (drop-frame, `HH:MM:SS;FF`).
- Styling (bold/italic tags are ordinary text), RTL bidi handling.
- Timestamp ordering/overlap validation, cue merging or splitting.
- Any FFI, file I/O, or registry integration.

## 3. Grammar and semantics

### 3.1 Lines

- `text` is split on LF. A CR immediately before LF is removed, so CRLF
  documents produce the same lines as LF documents. A trailing LF does not
  produce a final empty line.
- A "blank line" is a zero-byte line. A line containing only spaces or tabs
  is text, not a separator.
- A lone CR is not a line ending (it stays inside the line).

### 3.2 Timestamp grammar

```
timestamp = HH ":" MM ":" SS sep mmm
HH        = 2DIGIT          (00..99)
MM, SS    = 2DIGIT          (00..59; values above 59 are errors)
mmm       = 3DIGIT          (000..999)
sep       = "," | "."
```

The timestamp must be exactly 12 bytes. SRT uses `,` and WebVTT uses `.`;
each reader also accepts the other separator leniently. Values convert to
whole milliseconds: `HH*3600000 + MM*60000 + SS*1000 + mmm`.

### 3.3 SRT

```
document = *( blank ) block *( blank block ) *blank
block    = index LF timestamp-line LF text-line *( LF text-line )
index    = 1*DIGIT          (value must equal cue number + 1)
timestamp-line = [SP] timestamp [SP] "-->" [SP] timestamp [SP]
```

Decisions (each one is covered by the conformance suite):

1. **Block separation.** Blocks must be separated by at least one blank
   line. Non-blank lines are consumed into the current cue's text until a
   blank line or end of input, so blocks with no separator merge (the second
   "index" becomes text of the first cue).
2. **Index policy (strict).** The index line must be decimal digits only,
   with value exactly `(number of cues so far) + 1`, i.e. strictly
   sequential `1, 2, 3, ...`. `0`, leading-sign input, non-numeric text, a
   repeated number or a skipped number is `Err("subtitle: bad index")`.
   Leading zeros are accepted when the value matches (`01` = 1).
3. **Timestamp line.** The first `-->` on the line splits it. Both sides are
   trimmed of spaces/tabs; the start side and the whole end side must each
   be exactly one timestamp, otherwise the error is
   `Err("subtitle: bad time")`. A line without `-->` is
   `Err("subtitle: missing arrow")`.
4. **Cue text.** One or more non-blank lines; the cue text is those lines
   joined with LF. A timestamp line directly followed by a blank line or end
   of input is `Err("subtitle: missing cue text")`.
5. **Empty documents.** A document with no cue blocks (empty text or blank
   lines only) is `Err("subtitle: empty input")`.
6. **Writing.** `srt_format` re-numbers cues from 1 in order, writes
   `HH:MM:SS,mmm`, joins lines with LF, separates cue blocks with one blank
   line, and terminates the last text line with LF. An empty `Subtitle`
   formats to `""`.

### 3.4 WebVTT

```
header  = "WEBVTT" [ (SP|TAB) *VCHAR ]
body    = *( blank ) ( note | cue ) *( blank ( note | cue ) ) *blank
note    = "NOTE" [ (SP|TAB) *VCHAR ] LF note-line *( LF note-line )
cue     = timestamp-line LF text-line *( LF text-line )
timestamp-line = [SP] timestamp [SP] "-->" [SP] timestamp [SP settings]
```

Decisions (each one is covered by the conformance suite):

7. **Header.** The first line must be `WEBVTT` exactly, or `WEBVTT`
   followed by a space/tab and a signature suffix. Anything else (including
   an empty document) is `Err("subtitle: missing WEBVTT header")`.
8. **Empty track.** A header with no cues is a valid, empty `Subtitle`.
9. **NOTE blocks.** A line that is `NOTE` alone, or `NOTE` followed by a
   space/tab, starts a comment block; all following lines up to the next
   blank line or EOF are skipped. `ITEM` text is not special.
10. **Cue identifiers.** Not supported: a cue must begin with its timestamp
    line. A non-blank, non-NOTE, non-timestamp line is
    `Err("subtitle: missing arrow")` (non-exhaustive match is a hard error
    in v0.61.3; the parser therefore never uses `match` here).
11. **Cue settings.** Everything after the end timestamp's first
    whitespace-delimited token is ignored on read and never written.
12. **Timestamps.** `HH:MM:SS.mmm`; `,` is also accepted (decision in
    section 3.2). Invalid values are `Err("subtitle: bad time")`.
13. **Writing.** `vtt_format` writes the `WEBVTT` header line, a blank
    separator line when there is at least one cue, then cues without
    indices with `.` timestamps, LF, one blank line between cues and a
    terminating LF after the last text line. An empty `Subtitle` formats to
    `"WEBVTT\n"`.

### 3.5 Shared model

14. **Cue text.** The text lines of one cue are joined with `"\n"` inside
    one `Str`; formatters split them back out verbatim.
15. **Shift.** `subtitle_shift` adds `delta_ms` to every start and end and
    clamps each at 0 (so a fully negative cue becomes `0..0`). Cue count,
    texts and relative order are preserved, and the input track is not
    modified.
16. **Accessors.** `subtitle_start_ms`/`subtitle_end_ms` return `-1` for a
    negative or out-of-range index; `subtitle_text` returns `""` for those.
17. **Duration.** `subtitle_total_duration_ms` is the maximum end time,
    clamped at 0, and 0 for an empty track.
18. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise but never splits or rewrites multi-byte sequences, so
    non-ASCII text round-trips byte-exact.

## 4. API signatures

```xi
pub type Subtitle = { starts: Vec[Int]; ends: Vec[Int]; texts: Vec[Str]; }

pub fn srt_parse(text: Str) -> Result[Subtitle, Str]
pub fn srt_format(s: &Subtitle) -> Str
pub fn vtt_parse(text: Str) -> Result[Subtitle, Str]
pub fn vtt_format(s: &Subtitle) -> Str
pub fn subtitle_shift(s: &Subtitle, delta_ms: Int) -> Subtitle
pub fn subtitle_cue_count(s: &Subtitle) -> Int
pub fn subtitle_start_ms(s: &Subtitle, i: Int) -> Int
pub fn subtitle_end_ms(s: &Subtitle, i: Int) -> Int
pub fn subtitle_text(s: &Subtitle, i: Int) -> Str
pub fn subtitle_total_duration_ms(s: &Subtitle) -> Int
```

Complexity: parsing and formatting are O(n) over the document length;
`subtitle_shift` is O(cues); all other functions are O(1) or O(cues).

## 5. Error catalog

All errors are `Err(message)` with a `"subtitle: "` prefix:

| Message | Raised when |
|---|---|
| `subtitle: empty input` | SRT document with no cue blocks (empty or blank lines only). |
| `subtitle: bad index` | SRT index line missing its digits, zero, or not exactly (cue count + 1). |
| `subtitle: malformed block` | SRT index line present but the timestamp line is missing (end of input). |
| `subtitle: missing arrow` | Timestamp line has no `-->` (SRT and WebVTT). |
| `subtitle: bad time` | A timestamp is not exactly 12 valid `HH:MM:SS[.,]mmm` bytes with minutes/seconds <= 59. |
| `subtitle: missing cue text` | No text line after the timestamp line (SRT and WebVTT). |
| `subtitle: missing WEBVTT header` | WebVTT document whose first line is not `WEBVTT` (optionally suffixed with SP/TAB + text). |

## 6. Test plan

`tests/test_conformance.xi` (module `subtitle_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | SRT two cues | basic block split, exact times (rule 1) |
| t2 | multi-line text | cue text joined with LF (rule 4, 14) |
| t3 | CRLF | CRLF parses like LF (rule 3.1) |
| t4 | exact times | `01:02:03,456` = 3723456 ms; 1 ms cue (rule 3.2) |
| t5 | SRT round trip | parse -> format -> parse equality (rule 6) |
| t6 | SRT format text | re-numbered from 1, LF, blank separator (rule 6) |
| t7 | VTT header + NOTE | NOTE block skipped, two cues (rule 7, 9) |
| t8 | VTT `.` and `,` | exact ms; comma accepted leniently (rule 12) |
| t9 | VTT settings | settings after the arrow ignored (rule 11) |
| t10 | VTT round trip | exact format + parse equality (rule 13) |
| t11 | shift positive | both times move, input unchanged (rule 15) |
| t12 | shift clamp | negative shift clamps at 0 (rule 15) |
| t13 | total duration | max end; 0 for an empty VTT (rule 17) |
| t14 | no arrow | SRT and VTT `missing arrow` (rule 3, 10) |
| t15 | bad times | short ms, minute/second 60+, non-digit, bad separators (rule 4) |
| t16 | index policy | first index 2, non-numeric, 0, and a gap are all `bad index` (rule 2) |
| t17 | structural errors | missing cue text, missing timestamp line, bad VTT header (rules 4, 7) |
| t18 | empty inputs | SRT `""`/blank-only Err; empty VTT valid; format outputs (rules 5, 8, 6, 13) |
| t19 | accessors | fields by index and all out-of-range sentinels (rule 16) |
| t20 | empty track ops | NOTE-only VTT parses empty, shifts empty, formats empty (rules 9, 15) |

Every string comparison in the suite goes through `xiom.string.compare`'s
`str_compare` (BUG 17 discipline), and element reads go through typed
locals (`let s: Str = lines[i];`).

## 7. Compiler / stdlib notes (v0.61.3)

Workarounds carried by this module, in the style of `xiom.wav`:

- **Ok/Err confinement.** `Ok`/`Err` values for `Result[Subtitle, Str]` are
  constructed only in the leaf helpers `_ok_sub`/`_err_sub`, never inline in
  the parsers. The `Subtitle` literal itself is built only by `_make_sub`
  (also used by `subtitle_shift`), mirroring the `_ok_fmt` / builder split
  in `xiom.wav`.
- **Bytes as Int.** Every `string.byte_at` result is converted through
  `_byte(s, pos) -> Int` before comparison, so no `UInt8` constant >= 128
  is ever involved (the `& 0xFF` trap documented in `xiom.wav` and
  `xiom.msgpack`).
- **No Str `==`.** The module never compares `Str` with `==`; the tests use
  `str_compare` and typed locals for every `Vec[Str]` element read.
- **No `Vec[StructType]`.** Cues live in three parallel Vecs
  (`starts`/`ends`/`texts`) inside one `Subtitle`; the type is never
  instantiated as a Vec element.
- **No `match` and no lambdas.** Parsing is `if`/`elif`/`while` only, so no
  non-exhaustive-match or function-vector constructs are reachable.
- **Non-negative decimal formatting** is a local helper (`_int_str`), so the
  module needs no `xiom.convert` import (which pulls the `Int.into` tower
  documented as buggy in `xiom.convert.int`).

## 8. Known limitations

- Both readers are whole-document; there is no streaming API.
- Strict SRT numbering rejects real-world files with stale indices.
- Hours are limited to two digits on read (`00..99`); `srt_format`/
  `vtt_format` print hours above 99 with extra digits, which the parsers
  then reject (output is not round-trip-safe above 99 hours).
- Whitespace-only lines are text; there is no whitespace-tolerant block
  separator.
- WebVTT `STYLE`/`REGION` blocks and cue identifiers are rejected, not
  skipped.
- Cue settings are dropped on read; styled cue payloads are plain text.
- A leading UTF-8 BOM is not stripped (the first line then fails to parse as
  an index or header).
