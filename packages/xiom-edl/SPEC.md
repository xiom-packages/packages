# xiom.edl -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.edl` (`src/edl.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for a documented subset of the CMX 3600 edit
decision list (EDL):

- `edl_parse` -- document + frame base -> `Result[Edl, Str]`,
- `edl_emit` -- `Edl` -> canonical EDL text,
- line accessors -- `edl_line_*`, `edl_title*`,
- event accessors -- `edl_event_*`,
- timecode helpers -- `edl_event_timecode*`, `edl_timecode_part`,
  `edl_timecode`, `edl_frame_base`,
- public constants -- `LK_*`, `TR_*`, `TC_*`, `TCF_*`, `EDL_FPS_*`.

The codec validates the documented grammar strictly, stores the document as
one flat line stream (twelve parallel Vecs plus the frame base), and
round-trips canonical documents parse -> emit -> parse. It gives no semantics
to reel names, track designators, wipe codes or comment bodies beyond
pass-through.

## 2. Non-goals

- Frame math: no duration computation, no `src_out - src_in` checks, no
  rec-point continuity checks, no timecode addition/subtraction and no
  conversion between frame bases. The only integer encoding offered is the
  lossless packing of one timecode's four components (`edl_timecode_part`
  reverses it).
- Drop-frame and fractional rates: no `;` timecodes, no 23.976/29.97
  pull-down, no pulldown flags, no 2:3 cadence.
- CMX3600 motion effects: no `M`/`D` effect variants beyond the documented
  `D nnn` dissolve, no motion memory, no speed/ freeze codes, no reverse
  codes, no key/wipe parameters beyond the `Wnnn` code itself.
- Other EDL dialects and containers: no AAF, no XML, no FCP XML, no GVG
  `;`-only variants, no `FCM:` / `SPLIT` / `AUD` / `BL` directive handling.
- Media: no reading, verifying or hashing referenced media, no file
  existence checks, no path normalization.
- Reel semantics: `BL` (black) is documented but not special-cased; no
  reel-sorting logic.
- Streaming/incremental parsing (whole `Str` in memory only).
- Editing operations on a parsed document (no add/remove/renumber API).
- Any FFI or registry integration.

## 3. Grammar

```
document = *( blank / title / comment / event )
blank    = (no bytes, or only SP/TAB)
title    = "TITLE" ws+ text
comment  = ( "*" / ";" ) *( char )        ; stored raw, marker included
event    = 3DIGIT ws+ reel ws+ track ws+ trans [ ws+ dur ] ws+ tc x4
ws       = SP | TAB
reel     = 1..8( ALPHA / DIGIT / "_" )    ; "BL" is black (documented)
track    = "V" | "A" | "A2" | "AA" | "B" | "A3" | "A4"
trans    = "C" | "D" | "W" 3DIGIT
dur      = 1..3DIGIT                      ; 1..999 frames
tc       = 2DIGIT ":" 2DIGIT ":" 2DIGIT ":" 2DIGIT
3DIGIT   = value 001..999, strictly increasing across the document
```

### 3.1 Lines and normalization

- `text` is split on LF. One CR immediately before an LF is removed, and one
  trailing CR at the end of an unterminated final line is removed too, so
  CRLF documents produce the same lines as LF documents. A trailing LF does
  not produce a final empty line. A final line without a terminating LF is
  still a line.
- Each line is trimmed of leading/trailing space and tab, so indentation is
  insignificant. A line that is empty after trimming is skipped and is not
  stored.
- The first byte of a non-blank line selects the line type:
  - `*` or `;`: comment;
  - ASCII digit: event;
  - anything else: a `TITLE` line when the first whitespace-delimited token
    compares equal to the uppercase keyword `TITLE`, otherwise
    `edl: unexpected line: <line>`.
- Keywords and tokens are case-sensitive: `title`, `c` and `w001` are not
  recognized. `FCM: NON-DROP FRAME` is not in the subset and is
  `edl: unexpected line: ...`; consumers of real-world EDLs must strip FCM
  lines before parsing.
- Input containing a `0x00` byte is rejected up front with
  `edl: NUL byte in input`, before any slicing, so no NUL can ever reach the
  string builder on emission.

### 3.2 Title and comments

- A `TITLE` line is the keyword `TITLE`, one or more spaces/tabs, and the
  remaining text; the text may not be empty. It is stored without the
  keyword and without the separating whitespace, with internal spacing
  preserved. `TITLE` alone or `TITLE` followed only by whitespace is
  `edl: bad TITLE: <line>`. A title may appear any number of times and
  anywhere in the document; `edl_title` returns the first one.
- A comment line begins with `*` or `;` and is stored as the whole trimmed
  line, marker included, verbatim. Internal spacing is preserved; leading
  and trailing space/tab are not (line trimming, section 3.1).
- Titles and comments occupy slots in the same flat stream as events, so
  document order is preserved exactly and re-emitted in order.

### 3.3 Event fields

An event line is split on runs of space/tab into whitespace-delimited tokens.
The field order is fixed:

| Position | Field | Rule |
|---|---|---|
| 0 | event number | exactly three digits, 001..999 |
| 1 | reel | 1..8 bytes from `A-Z`, `a-z`, `0-9`, `_` |
| 2 | track | one of `V`, `A`, `A2`, `AA`, `B`, `A3`, `A4` |
| 3 | transition | `C`, `D` or `Wnnn` |
| 4 | duration | present only for `D`: 1..3 digits, value 1..999 |
| 5..8 | timecodes | `src-in`, `src-out`, `rec-in`, `rec-out` |

- **Event numbers.** Exactly three digits and a value in 001..999; anything
  else is `edl: bad event number: <line>`. Numbers must be strictly
  increasing in document order; a number less than or equal to the previous
  event's number is `edl: event number out of order: <line>`. Gaps are
  allowed (001, 003, 999). Numbers are stored verbatim and emitted
  zero-padded to three digits; the codec never renumbers.
- **Reels.** 1..8 letters, digits or underscores. `BL` is the conventional
  black leader and is documented, but it receives no special treatment: the
  token is stored and emitted verbatim. Length/charset violations are
  `edl: bad reel: <line>`.
- **Track types.** The accepted designators and their conventional meaning
  are listed below for orientation; the codec stores the token verbatim and
  gives it no further semantics (deck behaviour varies).

  | Token | Conventional meaning |
  |---|---|
  | `V` | video |
  | `A` | audio (single channel / channel 1) |
  | `A2` | audio, second channel |
  | `AA` | audio, both channels |
  | `B` | both video and audio |
  | `A3` | audio, third channel |
  | `A4` | audio, fourth channel |

  Any other token is `edl: unknown track: <line>`.
- **Transitions.**
  - `C` -- cut; it takes no duration. If the token after `C` is not a valid
    timecode (for example a stray duration), the first timecode fails the
    shape check.
  - `D` -- dissolve; the next token is the duration in frames: 1..3 ASCII
    digits with a value in 1..999. Missing is
    `edl: missing dissolve duration: <line>`; malformed or out of range is
    `edl: bad dissolve duration: <line>`. Canonical emission always
    zero-pads to three digits (`D 030`).
  - `W` + three digits -- wipe; the code 001..999 is stored and passed
    through (`edl_event_wipe`). `W000`, `W1`, `W12`, `W1234`, `Wabc` and any
    other non-`C`/`D` token are `edl: bad transition: <line>`. No wipe
    geometry, direction or table is modelled.
- **Token count.** A cut or wipe line has exactly 8 tokens, a dissolve line
  exactly 9. Fewer tokens than the four mandatory fields is
  `edl: missing field: <line>`; fewer than the transition requires (for
  example a dissolve without its duration or without all four timecodes) is
  reported as `edl: missing dissolve duration` or `edl: missing field`
  respectively; more tokens than required is `edl: trailing text: <line>`.
- Fields are validated left to right, so a line with several defects reports
  the first one in field order.

### 3.4 Timecodes

- A timecode is exactly eleven bytes `hh:mm:ss:ff`: two digits, colon, two
  digits, colon, two digits, colon, two digits.
- The document frame base is a parse argument and must be one of `24`, `25`
  or `30` (`EDL_FPS_24`, `EDL_FPS_25`, `EDL_FPS_30`). Any other value is
  `edl: unsupported frame base: <n>`, checked before any line is read and
  independent of the document contents.
- `hh` is 00..99 (exactly two digits, so no further check is possible);
  `mm` and `ss` are 00..59; `ff` must be strictly less than the frame base
  (`23`, `24` and `29` are the maxima for 24/25/30).
- Shape errors, non-digit fields, `mm > 59` and `ss > 59` are
  `edl: bad timecode: <line>`; `ff >= fps` is
  `edl: frame out of range: <line>`.
- **Drop-frame stance.** Drop-frame timecodes use `;` before the frame field
  (for example `01:00:00;00`). This subset is non-drop only: `;` fails the
  colon check and is reported as `edl: bad timecode: <line>`. There is no
  drop-frame conversion, no `.`/`,`/`;` separator acceptance and no
  representation for frame rates other than the three integer bases.
- The codec performs no arithmetic on timecodes: it never compares `src-in`
  with `src-out` and never checks record-point continuity.

## 4. Data model

```xi
pub type Edl = {
  kinds: Vec[Int];      // one LK_* code per stored line
  nums: Vec[Int];       // event number; 0 otherwise
  reels: Vec[Str];      // reel token; "" otherwise
  tracks: Vec[Str];     // track token; "" otherwise
  trans: Vec[Int];      // TR_* code; 0 otherwise
  durs: Vec[Int];       // dissolve frames (1..999); 0 for C/W
  wipes: Vec[Int];      // wipe code (1..999); 0 for C/D
  src_ins: Vec[Int];    // packed timecodes:
  src_outs: Vec[Int];   //   hh*1000000 + mm*10000 + ss*100 + ff
  rec_ins: Vec[Int];    //   (0 for non-event lines)
  rec_outs: Vec[Int];   //
  texts: Vec[Str];      // title text or whole comment line; "" for events
  fps: Int;             // frame base: 24, 25 or 30
}
```

Invariants for a value produced by `edl_parse`:

- all twelve Vecs have length `edl_line_count(e)`, one slot per non-blank
  line, in document order;
- `kinds[i]` is one of `LK_TITLE` (1), `LK_COMMENT` (2) or `LK_EVENT` (3);
- every field Vec is meaningful only for the kind listed above; all other
  slots are 0 or "";
- `num`, `reel`, `track`, `trans` and the four packed timecodes are
  meaningful for `LK_EVENT`; `dur` is meaningful only for `TR_DISSOLVE` and
  `wipe` only for `TR_WIPE`;
- packed timecodes satisfy `hh <= 99`, `mm <= 59`, `ss <= 59`,
  `ff < fps`.

`Vec[StructType]` is not usable in this compiler, so the document is twelve
parallel Vecs instead of a list of line structs. `edl_emit` assumes the same
shape for hand-built values (see section 6).

## 5. Error catalog

All parse failures are `Err(msg)` with an `"edl: "` prefix; `<line>` is the
offending line after trimming, `<n>` is the offending frame base. Fields are
validated left to right and a line with several defects reports the first.

| Message | Trigger |
|---|---|
| `edl: NUL byte in input` | Input contains a `0x00` byte (checked before any slicing). |
| `edl: unsupported frame base: <n>` | The `fps` argument is not 24, 25 or 30. |
| `edl: unexpected line: <line>` | A non-blank line is neither a comment, a `TITLE` line nor an event line (including `FCM:` lines and lowercase keywords). |
| `edl: bad TITLE: <line>` | `TITLE` with no separating whitespace or with empty text. |
| `edl: bad event number: <line>` | Event number is not exactly three digits or is 000. |
| `edl: event number out of order: <line>` | Event number is not strictly greater than the previous event's number. |
| `edl: bad reel: <line>` | Reel is longer than 8 bytes or contains a byte outside `A-Za-z0-9_`. |
| `edl: unknown track: <line>` | Track token is not one of the seven documented designators. |
| `edl: bad transition: <line>` | Transition token is neither `C`, `D` nor `W` + exactly three digits, or the wipe code is 000. |
| `edl: missing dissolve duration: <line>` | A `D` transition is the last token on the line. |
| `edl: bad dissolve duration: <line>` | Dissolve duration is not 1..3 digits with a value in 1..999. |
| `edl: missing field: <line>` | An event line has fewer than four tokens, or fewer tokens than the transition requires. |
| `edl: bad timecode: <line>` | A timecode is not `hh:mm:ss:ff`, has a non-digit field, `mm > 59`, `ss > 59`, or uses the drop-frame `;`. |
| `edl: frame out of range: <line>` | A timecode's `ff` is greater than or equal to the frame base. |
| `edl: trailing text: <line>` | An event line carries more tokens than the transition allows. |

`edl_emit` and all accessors are total: they never return errors. Accessors
return sentinels instead (`-1` for numbers and ordinals, `""` for strings,
`0` for counts) when an index is out of range.

## 6. API contract

```xi
pub type Edl = { ... }                       // section 4

pub fn edl_parse(text: Str, fps: Int) -> Result[Edl, Str]
pub fn edl_emit(e: &Edl) -> Str

pub fn edl_line_count(e: &Edl) -> Int
pub fn edl_line_kind(e: &Edl, i: Int) -> Int
pub fn edl_line_text(e: &Edl, i: Int) -> Str
pub fn edl_title(e: &Edl) -> Str
pub fn edl_title_count(e: &Edl) -> Int
pub fn edl_comment_count(e: &Edl) -> Int
pub fn edl_frame_base(e: &Edl) -> Int

pub fn edl_event_count(e: &Edl) -> Int
pub fn edl_event_line(e: &Edl, i: Int) -> Int
pub fn edl_event_number(e: &Edl, i: Int) -> Int
pub fn edl_event_reel(e: &Edl, i: Int) -> Str
pub fn edl_event_track(e: &Edl, i: Int) -> Str
pub fn edl_event_transition(e: &Edl, i: Int) -> Int
pub fn edl_event_duration(e: &Edl, i: Int) -> Int
pub fn edl_event_wipe(e: &Edl, i: Int) -> Int
pub fn edl_event_timecode_value(e: &Edl, i: Int, which: Int) -> Int
pub fn edl_event_timecode(e: &Edl, i: Int, which: Int) -> Str
pub fn edl_event_src_in(e: &Edl, i: Int) -> Str
pub fn edl_event_src_out(e: &Edl, i: Int) -> Str
pub fn edl_event_rec_in(e: &Edl, i: Int) -> Str
pub fn edl_event_rec_out(e: &Edl, i: Int) -> Str

pub fn edl_timecode_part(value: Int, part: Int) -> Int
pub fn edl_timecode(hh: Int, mm: Int, ss: Int, ff: Int) -> Str
```

Details:

- `edl_parse` accepts LF, CRLF and a missing final newline; it is O(n) over
  the input.
- **Indexing.** `edl_line_*` accessors use stream indices (0-based over all
  stored lines). `edl_event_*` accessors use event ordinals (0-based over
  events only); an event's stream index is `edl_event_line(e, i)`. The two
  differ whenever a comment or title precedes or sits between events.
- **Timecodes.** `edl_event_timecode_value` returns the packed integer
  `hh*1000000 + mm*10000 + ss*100 + ff`; `edl_timecode_part` extracts `hh`,
  `mm`, `ss` or `ff` with the `TCF_*` codes. `edl_event_timecode` and the
  four named accessors return the canonical `hh:mm:ss:ff` text. No
  drop-frame or pulldown adjustment is applied anywhere.
- `edl_event_duration` is 0 for cuts and wipes;
  `edl_event_wipe` is 0 for cuts and dissolves.
- `edl_timecode(hh, mm, ss, ff)` renders four components clamped to two
  digits each (0..99); it performs no validation.
- `edl_emit` writes every stored line in order: `TITLE <text>`, comments
  verbatim, and event lines as
  `NNN reel track trans [dur] tc tc tc tc` with single spaces and LF line
  endings. Event numbers, dissolve durations and wipe codes are zero-padded
  to three digits; timecodes are re-rendered canonically. Every line ends
  with LF, so an empty document emits `""`. For hand-built values:
  - all twelve Vecs should have equal length; slots beyond the shortest Vec
    are ignored, so unequal arrays can only truncate the output;
  - a `Str` field containing NUL is undefined for emission (rejected on
    parse; hand-built values must avoid it);
  - an unknown transition code emits `?` (not re-parseable);
  - a title with empty text emits `TITLE ` (not re-parseable as a title).

## 7. Round-trip rules

For any `e` obtained from `edl_parse`:

- `edl_parse(edl_emit(e), edl_frame_base(e))` yields an `Edl` equal to `e`
  on the whole observable surface: line count and order, line kinds, title
  and comment texts, frame base, and every event's number, reel, track,
  transition, duration, wipe code and four timecodes;
- `edl_emit(edl_parse(edl_emit(e), fps))` is byte-identical to `edl_emit(e)`
  (emission is idempotent);
- no information is lost: reel/track tokens, comment bodies and title texts
  survive verbatim (modulo line trimming).

Normalizations performed by the round trip:

- CRLF, blank-line layout, indentation and whitespace runs between tokens
  collapse to the canonical form: one space between fields, LF line endings;
- the final line always gains an LF;
- event numbers are zero-padded to three digits (they can only be parsed as
  three digits, so this is a no-op for parsed values);
- dissolve durations and wipe codes are zero-padded to three digits
  (`D 30` in the source re-emits as `D 030`);
- timecodes re-render as `hh:mm:ss:ff`.

## 8. Compiler / stdlib notes (v0.61.3)

Workarounds carried by this module, in the style of `xiom.cue`,
`xiom.lexing` and `xiom.ini`:

- **Ok/Err confinement.** `Ok`/`Err` for `Result[Edl, Str]` are constructed
  only in the leaf helpers `_ok_edl`/`_err_edl`; the `Edl` literal itself is
  built only by `_make_edl`.
- **Bytes as Int.** Every `string.byte_at` result goes through
  `_byte(s, pos) -> Int` before comparison, so no `UInt8` constant >= 128 is
  ever involved in a comparison.
- **No Str `==`.** The module never compares `Str` with `==`; token dispatch
  uses `str_compare`, and every `Vec[Str]`/`Vec[Int]` element read binds a
  typed local first.
- **No `Vec[StructType]`.** Twelve parallel Vecs plus the frame base hold
  the line stream.
- **No drift.** Every slot is appended through the `_push_meta`,
  `_push_strs` and `_push_tcs` helpers, which push to all arrays of their
  group, so the twelve Vecs stay index-aligned by construction. `edl_emit`
  additionally clamps its scan to the shortest Vec.
- **No `match` and no lambdas** in the library module; the line loop is
  `if`/`elif`/`while` only. Test functions are called directly from `main`
  (no indexed `Vec[fn]` dispatch).
- **Explicit `&mut`.** Every helper taking `&mut Vec` is called with `&mut`
  from a local.
- **NUL safety.** `sb_to_str` aborts on NUL bytes, so `edl_parse` rejects
  NUL-containing input up front and every emitted Str is parser-produced
  ASCII text or a validated token.

## 9. Test matrix

`tests/test_conformance.xi` (module `edl_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full document | line kinds/order, title, comments, cut/dissolve/wipe, all accessors (3, 4) |
| t2 | CRLF/indentation/blanks/final line | 3.1, canonical emit, unterminated last line |
| t3 | boundaries | 8-char reel, all seven tracks, 1/999 dissolve and wipe, 99:59:59:23, packed values (3.3, 3.4) |
| t4 | bad event numbers | 3.3, 5 |
| t5 | bad reels | 3.3, 5, underscore accepted |
| t6 | unknown tracks | 3.3, 5 |
| t7 | bad transitions | 3.3, 5, `Wnnn` shape |
| t8 | dissolve durations | missing/bad Err, short duration canonicalizes (3.3, 6) |
| t9 | bad timecode shapes | 3.4, 5, drop-frame `;` rejected |
| t10 | frames vs base | 3.4, 5, bases 24/25/30 and unsupported bases |
| t11 | event ordering | 3.3, strict increase, gaps allowed |
| t12 | canonical emission | 6, exact byte layout, padding |
| t13 | round trip | 7, deep equality and idempotence |
| t14 | accessor sentinels | 5, 6 |
| t15 | empty/blank documents | 3.1, 6 |
| t16 | unexpected lines | 3.1, 5, `FCM:` rejected, bad `TITLE` |
| t17 | truncated/trailing tokens | 3.3, 5 |
| t18 | title/comment raw text | 3.2, order preserved |
| t19 | comments anywhere | 3.2, event-to-line mapping |
| t20 | timecode values and parts | 3.4, 4, packing and canonical rendering |
| t21 | 3-digit minimum emit | 6, re-parse |
| t22 | wipe pass-through round trip | 3.3, 7 |

Every Str comparison in the suite goes through `xiom.string.compare`'s
`str_compare` (BUG 17 discipline), element reads bind typed locals first, and
the tests are called directly from `main` (no indexed `Vec[fn]` dispatch).

## 10. Known limitations

- Keywords and field tokens are case-sensitive uppercase (`V`, `A2`, `C`,
  `D`, `W001`, `TITLE`); lowercase forms are errors.
- Real-world EDL headers such as `FCM: NON-DROP FRAME` are outside the
  subset and must be stripped before parsing.
- Drop-frame timecodes and non-integer frame rates are unsupported; `ff`
  must be below one of 24/25/30.
- Wipe codes are exactly `W` + three digits; no wipe parameters or geometry
  are modelled.
- Dissolve durations accept 1..3 digits on input but always emit as three
  digits; the codec computes no durations.
- `BL` is documented as black but is not special-cased anywhere.
- Event numbers must be strictly increasing; duplicate or decreasing
  numbers are rejected, and gaps are preserved (not renumbered).
- No `M`/effect codes, no motion memory, no speed/reverse/key parameters, no
  AAF/XML, no media or filesystem access.
- Whole-document only; no streaming, no editing API, no file I/O.
- Blank-line layout, CRLF and column alignment are not preserved on emit.
- Errors carry the offending line text but no line/column numbers.
