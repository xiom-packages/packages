# xiom.vtt -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.vtt` (`src/vtt.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for WebVTT (W3C "Web Video Text Tracks") text:

- `vtt_parse` -- document -> `Result[Vtt, Str]`;
- `vtt_format` -- canonical serialization;
- accessors for signature, header metadata, cues (identifier, start/end,
  settings, payload lines) and raw NOTE/STYLE/REGION blocks;
- `vtt_timestamp_parse` / `vtt_timestamp_format` -- the timestamp grammar on
  its own;
- `vtt_new` / `vtt_cue_add` -- building a track cue by cue.

The codec preserves the document structure (including block order), keeps
payload bytes exact, validates the documented subset strictly, and
round-trips canonical documents `parse -> format -> parse`.

## 2. Non-goals

- Rendering captions; no layout, no text shaping, no font handling.
- HTML/CSS parsing: cue payload markup and STYLE block content are opaque
  bytes; `::cue` rules are not interpreted.
- Cue settings semantics: settings are passed through verbatim and never
  validated, applied or rewritten (no alignment, position, size, line or
  region semantics).
- Region/voice semantics: `REGION` blocks and `<v ...>` voice spans are raw
  text.
- STYLE/REGION placement rules from the W3C grammar (count, position,
  uniqueness, header-only restriction) are not enforced.
- Streaming/incremental parsing; encoding conversion; BOM stripping.
- Cue ordering, overlap detection, merging, splitting, seeking, or
  duration computation.
- Comma (`","`) timestamp separators: rejected (the codec is strict about
  the documented WebVTT form).
- Any FFI, file I/O, or registry integration.

## 3. Data model

```xi
pub type Vtt = {
  signature: Str;        // full signature line, verbatim
  headers: Vec[Str];     // header metadata lines, document order
  order: Vec[Int];       // 0 = cue entry, 1 = raw block, document order
  starts: Vec[Int];      // cue start, milliseconds
  ends: Vec[Int];        // cue end, milliseconds
  ids: Vec[Str];         // cue identifier, "" when absent
  settings: Vec[Str];    // verbatim settings text, "" when absent
  payload_starts: Vec[Int];  // per-cue range start into `lines`
  payload_ends: Vec[Int];    // per-cue range end (exclusive) into `lines`
  lines: Vec[Str];       // shared payload-line store
  raw_texts: Vec[Str];   // NOTE/STYLE/REGION text, lines joined with "\n"
  raw_kinds: Vec[Str];   // "NOTE" | "STYLE" | "REGION", aligned with raw_texts
}
```

Invariants:

- `starts`, `ends`, `ids`, `settings`, `payload_starts` and `payload_ends`
  all have the same length (the cue count).
- For cue `i`: `0 <= payload_starts[i] <= payload_ends[i] <= lines.len()`;
  its payload lines are `lines[payload_starts[i] .. payload_ends[i])`.
- `raw_texts` and `raw_kinds` have the same length (the raw-block count);
  `order` has one entry per cue or raw block, so the number of `0` entries
  equals the cue count and the number of `1` entries the raw-block count.
- `payload_starts`/`payload_ends` are non-decreasing and payload ranges do
  not overlap.

`Vec[StructType]` is unsupported in this compiler, so cues are deliberately
flat: parallel homogeneous vectors plus payload-line ranges into one shared
line buffer. There is no `Vec[Cue]`.

## 4. Document grammar

```
document  = signature LF [ header ] *( blank block ) *blank
signature = "WEBVTT" [ ( SP | TAB ) *VCHAR ]
header    = line *( LF line )                 ; up to the first blank line
block     = raw | cue
raw       = ( "NOTE" | "STYLE" | "REGION" ) [ ( SP | TAB ) text ]
            *( LF line )
cue       = [ id LF ] timing LF *( payload LF )
```

## 5. Parsing decisions (each is covered by the conformance suite)

1. **Physical lines.** `Str` is split on LF. A CR immediately before an LF
   is removed, so CRLF documents produce the same lines as LF documents. A
   trailing LF does not produce a final empty line. A lone CR is not a line
   ending and stays inside its line (other than the CR-before-LF case).
2. **Blank lines.** A blank line is a zero-byte line. A line holding only
   spaces or tabs is text, not a separator. Any number of consecutive blank
   lines may separate blocks (leading and trailing blanks are ignored);
   stray blanks are never an error.
3. **Signature.** The first line must be exactly `WEBVTT`, or `WEBVTT`
   followed by a space or tab and optional trailing text. Matching is
   case-sensitive (`webvtt` is invalid) and no other separator is accepted
   (`WEBVTT-captions` is invalid). The whole line is stored in `signature`
   and re-emitted verbatim. Empty input -> `vtt: missing signature`.
4. **Header metadata.** Everything between the signature line and the first
   blank line is header metadata, kept verbatim and in order. When the
   document has no blank line after the signature, every remaining line is
   metadata and the track is empty (documented decision). Metadata is never
   re-parsed as blocks, even when a line contains `-->`.
5. **Blocks.** After the header metadata, the body is blank-line separated
   blocks. A block is a maximal run of non-blank lines.
6. **Raw blocks.** A block whose first line is `NOTE`, `STYLE` or `REGION`
   (exactly, or followed by a space/tab) is raw: every line up to the block
   end is preserved, joined with LF in `raw_texts`, and its keyword is
   stored in `raw_kinds`. `NOTE`/`STYLE`/`REGION` matching is case-sensitive
   and the rest of the first line is not interpreted. Keyword-looking lines
   later in a block are ordinary content.
7. **Cue blocks.** Any other block is a cue. The first line containing the
   byte sequence `-->` must be the block's first line (no identifier) or
   second line (the first line is the cue identifier, stored verbatim); if
   it is later, the cue is `Err("vtt: payload before timing")`; if no line
   contains `-->`, the cue is `Err("vtt: cue without timing")`. The arrow
   search runs before timestamp validation, so a block such as `foo --> bar`
   is a shape error, not a missing-timing error.
8. **Timing line.** The text before the first `-->` is trimmed of spaces and
   tabs and must be exactly one timestamp. After the arrow, spaces/tabs are
   skipped, the next token (up to a space/tab or the end of line) must be
   exactly one timestamp, and the remainder of the line with surrounding
   spaces/tabs trimmed is the settings text, stored verbatim (interior
   spacing preserved, may be empty). Zero or more spaces/tabs are accepted
   around the arrow.
9. **Timestamps.** See section 6. The start is validated first: shape, then
   range; then the end: shape, then range; finally `end < start` is
   `Err("vtt: end before start")`. Equal start and end is allowed. Errors
   carry no position information.
10. **Payload.** Every line after the timing line up to the block end is a
    payload line, verbatim. Zero payload lines is valid (an empty cue); a
    blank line always ends the block, so payloads cannot contain blank
    lines. Payload lines are stored once in `lines` and referenced by the
    cue's range.
11. **Empty track.** A document with only a signature line (and optional
    header metadata) is valid, with zero cues and zero raw blocks.
12. **Encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
    byte-wise and never rewrites or splits multi-byte sequences, so non-ASCII
    payload and metadata bytes round-trip exactly. A leading UTF-8 BOM is
    not stripped and makes the signature check fail.

## 6. Timestamp grammar

```
timestamp = hh ":" mm ":" ss "." mmm      ; long form
          | mm ":" ss "." mmm             ; hours omitted, hh = 00
hh        = 2DIGIT (00..99)
mm, ss    = 2DIGIT (00..59)
mmm       = 3DIGIT (000..999)
```

- The separator must be `"."`; `","` is rejected as a bad shape.
- The long form is exactly 12 bytes, the short form exactly 9.
- Hours are exactly two digits; a one-digit hour (`0:00:01.000`) is a bad
  shape. There is no three-digit hour form on input.
- Minutes or seconds above 59 are an out-of-range component, not a shape
  error.
- Values convert to whole milliseconds: `hh*3600000 + mm*60000 + ss*1000 +
  mmm` (the short form contributes no hours).
- No surrounding whitespace is allowed by `vtt_timestamp_parse`; inside a
  timing line the timestamps are trimmed by the timing-line rule.
- Canonical output is always the long form, zero-padded, e.g.
  `01:02:03.456`. Hours at or above 100 print with more than two digits
  (`100:00:00.000`) and are accepted by `vtt_timestamp_format` but rejected
  by `vtt_timestamp_parse` (documented, not round-trip safe).

## 7. Formatting (canonical output)

`vtt_format` emits:

1. the stored signature line followed by LF;
2. every header metadata line followed by LF;
3. one blank line when `order` is non-empty;
4. the blocks in `order`, separated by exactly one blank line, each line
   terminated with LF:
   - cue: optional identifier line (verbatim, when non-empty), then
     `HH:MM:SS.mmm --> HH:MM:SS.mmm` (canonical timestamps), then settings
     preceded by one space when non-empty, then every payload line;
   - raw block: the stored text.

Consequences: CRLF input is normalized to LF; stray blank lines collapse to
one; comments and STYLE/REGION blocks keep their document position; an empty
track serializes to `"WEBVTT\n"` for the default signature. Inputs that are
already canonical round-trip byte-exactly.

## 8. API signatures

```xi
pub type Vtt = { ... }                                   ; see section 3

pub fn vtt_parse(text: Str) -> Result[Vtt, Str]
pub fn vtt_format(v: &Vtt) -> Str
pub fn vtt_timestamp_parse(t: Str) -> Result[Int, Str]
pub fn vtt_timestamp_format(ms: Int) -> Str
pub fn vtt_signature(v: &Vtt) -> Str
pub fn vtt_header_count(v: &Vtt) -> Int
pub fn vtt_header(v: &Vtt, i: Int) -> Str
pub fn vtt_cue_count(v: &Vtt) -> Int
pub fn vtt_cue_id(v: &Vtt, i: Int) -> Str
pub fn vtt_cue_start_ms(v: &Vtt, i: Int) -> Int
pub fn vtt_cue_end_ms(v: &Vtt, i: Int) -> Int
pub fn vtt_cue_settings(v: &Vtt, i: Int) -> Str
pub fn vtt_cue_line_count(v: &Vtt, i: Int) -> Int
pub fn vtt_cue_line(v: &Vtt, i: Int, j: Int) -> Str
pub fn vtt_cue_text(v: &Vtt, i: Int) -> Str
pub fn vtt_block_count(v: &Vtt) -> Int
pub fn vtt_block_text(v: &Vtt, i: Int) -> Str
pub fn vtt_block_kind(v: &Vtt, i: Int) -> Str
pub fn vtt_new() -> Vtt
pub fn vtt_cue_add(v: &Vtt, id: Str, start_ms: Int, end_ms: Int, settings: Str, text: Str) -> Result[Vtt, Str]
```

Accessor sentinels: `vtt_header`, `vtt_cue_id`, `vtt_cue_settings`,
`vtt_cue_line`, `vtt_cue_text`, `vtt_block_text` and `vtt_block_kind` return
`""` for a negative or out-of-range index; `vtt_cue_start_ms` and
`vtt_cue_end_ms` return `-1`; `vtt_cue_line_count` returns `0`.

Builder semantics:

- `vtt_new()` returns an empty track with signature `"WEBVTT"`.
- `vtt_cue_add` returns a copy of the input with one cue appended after
  every existing cue and raw block (`order` gains a `0`). The input track is
  not modified.
- `id` and `settings` are stored verbatim; `text` is split on LF into
  payload lines (a CR immediately before an LF is dropped, and a trailing LF
  does not add an empty line).
- Validation order and errors: negative `start_ms` or `end_ms` ->
  `vtt: negative time`; `end_ms < start_ms` -> `vtt: end before start`;
  `id` containing `-->` or LF -> `vtt: bad cue identifier`; `settings`
  containing LF -> `vtt: bad settings`; a zero-length payload line ->
  `vtt: blank payload line`. An empty `text` appends a cue with no payload
  lines, which is valid.

Complexity: `vtt_parse`, `vtt_format` and `vtt_cue_add` are O(input or cue
size); all accessors are O(1).

## 9. Error catalog

Parse failures are `Err(msg)` where `msg` starts with `"vtt: "` and carries
no line/column number:

| Message | Trigger |
|---|---|
| `vtt: missing signature` | Empty input, or the first line is not a valid `WEBVTT` signature line. |
| `vtt: cue without timing` | A non-raw block whose lines contain no `-->`. |
| `vtt: payload before timing` | The first `-->` line is the third or later line of its block. |
| `vtt: bad timestamp shape` | A timestamp matches neither accepted form (length, separators, digits). |
| `vtt: timestamp out of range` | Minutes or seconds exceed 59. |
| `vtt: end before start` | Both timestamps parse and the end is earlier than the start. |

Builder failures:

| Message | Trigger |
|---|---|
| `vtt: negative time` | `start_ms < 0` or `end_ms < 0`. |
| `vtt: end before start` | `end_ms < start_ms`. |
| `vtt: bad cue identifier` | `id` contains `-->` or LF. |
| `vtt: bad settings` | `settings` contains LF. |
| `vtt: blank payload line` | `text` contains a zero-length line. |

## 10. Test plan

`tests/test_conformance.xi` (module `vtt_tests`) runs 23 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | signature-only track | header metadata kept; format re-emits it; 0 cues |
| t2 | signature trailing text | `WEBVTT - ...` kept verbatim; cue parses; exact round-trip |
| t3 | identifier + multi-line payload | id, exact ms, line/text accessors; exact round-trip |
| t4 | settings + arrow whitespace | settings passed through; tabs/spaces around arrow tolerated; canonical output |
| t5 | timestamp parse values | long/short forms; 0, 1 ms, 99:59:59.999 |
| t6 | timestamp errors | shape vs range distinction; comma, short hour, bad digits, empty |
| t7 | end vs start | end < start Err; equal times allowed |
| t8 | missing signature | empty, `WEBVTTX`, lowercase, bad separator, cue-first |
| t9 | cue structure | no arrow; `NOTEish` is not a comment; two lines before timing; blank splits payload |
| t10 | timing-line errors | comma, end out of range, short start, missing end token |
| t11 | NOTE blocks | raw text + kind preserved; bare `NOTE`; exact round-trip |
| t12 | STYLE/REGION blocks | kinds and text; interleaved with cues; exact round-trip |
| t13 | stray blanks + CRLF | blanks skipped; CRLF normalizes to LF |
| t14 | empty payload cue | zero payload lines valid; exact round-trip |
| t15 | canonical formatting | `0`, `3723456`, `62345`, `359999999`, clamp, 100 h |
| t16 | full document round-trip | signature + headers + 3 raw blocks + 3 cues, exact |
| t17 | cue builder | `vtt_new`, two `vtt_cue_add` calls, exact output, input unchanged, parse-back |
| t18 | builder errors | negative, end-before-start, bad id/settings, blank payload line |
| t19 | accessor sentinels | every accessor at negative and high indices |
| t20 | UTF-8 payload | multi-byte bytes round-trip exactly |
| t21 | empty tracks | `vtt_new`, `WEBVTT`, `WEBVTT\n`, `WEBVTT \n` |
| t22 | no blank line | every line after the signature is header metadata |
| t23 | settings edge cases | whitespace-only trailing settings; tight `-->`; empty settings |

Every string comparison in the suite goes through
`xiom.string.compare.str_compare` (BUG 17 discipline) and every element read
goes through a typed local.

## 11. Compiler / stdlib notes (v0.61.3)

- **Flat storage.** No `Vec[StructType]`: cues live in parallel vectors and
  reference payload lines by range into one shared buffer.
- **Ok/Err confinement.** Results are constructed only in the leaf helpers
  `_ok_vtt`, `_err_vtt`, `_ok_int`, `_err_int`; the `Vtt` literal itself is
  built only by `_make_vtt`.
- **Bytes as Int.** Every `xiom.string.byte_at` read goes through
  `_byte(s, pos) -> Int`, so no `UInt8` constant >= 128 is involved in a
  comparison.
- **No Str `==`.** String equality uses
  `xiom.string.compare.str_compare` (BUG 17); Vec element reads are bound to
  typed locals before use, including the `Int` entries of `order` and the
  index vectors.
- **No `match`, no lambdas, no `Vec[fn]`.** Parsing is `if`/`elif`/`while`
  only; the test suite calls `t1()` ... `t23()` directly.
- **No conversion imports.** Non-negative decimal formatting is local
  (`_int_str`, `_pad2`, `_pad3`).

## 12. Known limitations

- Whole-document, in-memory only: no streaming API.
- Strict timestamps: exactly two hour digits, `.` separator only; a comma is
  rejected, and times at or above 100 hours fail to re-parse.
- A blank line always ends a block, so payloads cannot contain blank lines
  and the builder rejects them.
- Whitespace-only lines are text, not block separators.
- Cue identifiers and settings are preserved verbatim but never trimmed,
  validated or interpreted; identifier whitespace is part of the identifier.
- Raw blocks are opaque and may appear anywhere; W3C placement rules for
  STYLE/REGION are not enforced.
- The builder cannot add header metadata or custom signature lines; use a
  parsed document as the base if either is needed.
- A leading UTF-8 BOM is not stripped.
- Errors carry no line/column numbers.
