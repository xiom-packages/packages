# xiom.cue -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.cue` (`src/cue.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for the structural subset of CDRWIN/EAC CUE
sheets:

- `cue_parse` -- document -> `Result[Cue, Str]`,
- `cue_emit` -- `Cue` -> canonical CUE text,
- generic element accessors -- `cue_element_*`,
- typed accessors -- `cue_file_*`, `cue_track_*`, `cue_index_*`,
- element-kind constants -- `EK_FILE` ... `EK_CATALOG`.

The codec validates the documented grammar strictly, stores the sheet as one
flat element stream, and round-trips canonical documents parse -> emit ->
parse. It gives no semantics to file types, track types or `REM` bodies
beyond pass-through.

## 2. Non-goals

- Audio data: no reading, verifying or hashing of the referenced image, no
  `.wav`/`.bin` parsing.
- Disc-ID math, TOC/CRC computation, cue-point rendering or burning.
- File existence checks or filesystem access of any kind; no file I/O.
- `CDTEXTFILE` / `FLAGS` support, CD-TEXT rendering, or any keyword outside
  the subset in section 3.
- ISO/UPC validation beyond "13 ASCII digits" for `CATALOG` and "12 ASCII
  alphanumerics" for `ISRC`; no checksum or country-code validation.
- Track-number sequence validation (uniqueness, contiguity, ordering).
- Semantics of `PREGAP`/`POSTGAP` or `INDEX 00`/`01` placement.
- Float/Float64 times; times are integer `mm:ss:ff` with 75 frames per
  second.
- Streaming/incremental parsing (whole `Str` in memory only).
- Editing operations on a parsed sheet (no add/remove/mutate API).
- Any FFI or registry integration.

## 3. Grammar

```
document   = *( blank / line )
blank      = (no bytes, or only space/tab)
line       = ws* directive ws* 
ws         = SP | TAB
directive  = "CATALOG" SP value13
           / "FILE" SP quoted SP type
           / "TRACK" SP nn SP type
           / "INDEX" SP nn SP time
           / "PREGAP" SP time
           / "POSTGAP" SP time
           / "PERFORMER" SP textvalue
           / "TITLE" SP textvalue
           / "SONGWRITER" SP textvalue
           / "ISRC" SP value12
           / "REM" [ SP rembody ]
nn         = 2DIGIT                      ; track 01..99, index 00..99
time       = 2DIGIT ":" 2DIGIT ":" 2DIGIT
quoted     = '"' *( char / '""' ) '"'    ; "" is a literal quote
textvalue  = quoted / 1*( char except SP/TAB )   ; trailing space/tab trimmed
type       = 1*( char except SP/TAB )    ; no whitespace, no quote
value13    = quoted / 13DIGIT
value12    = quoted / 12( ALPHA / DIGIT )
rembody    = *( char )                   ; verbatim after line trimming
```

### 3.1 Lines

- `text` is split on LF. One CR immediately before an LF is removed, and one
  trailing CR at the end of an unterminated final line is removed too, so
  CRLF documents produce the same lines as LF documents. A trailing LF does
  not produce a final empty line. A lone CR elsewhere stays inside the line.
- Each line is trimmed of leading/trailing space and tab, so indentation is
  insignificant. A line that is empty after trimming is skipped.
- A final line without a terminating LF is still a line.
- The first byte of a non-blank line must be an ASCII letter or `_`; any
  other byte is `cue: text outside catalog: <line>`.
- The leading token is the longest run of ASCII letters, digits and `_`. It
  is looked up case-sensitively: no match is
  `cue: unknown keyword: <token>`.
- For every keyword except `REM`, at least one space/tab must separate the
  keyword from its value; otherwise the keyword's own shape error is raised
  (`missing value` for the text directives, `bad FILE`/`bad CATALOG`/
  `bad ISRC`/`bad track number`/`bad index number`/`bad gap time`
  respectively).

### 3.2 Quoted values

- A quoted value opens with `"` and ends at the first `"` that is not
  followed by another `"`.
- Inside, `""` denotes one literal `"`. There are no other escapes:
  backslashes are ordinary bytes, so Windows paths survive verbatim.
- The value after the closing quote must be empty (only the keyword's
  remaining fields, if any); otherwise
  `cue: trailing text after quote: <line>`.
- An unclosed quote is `cue: unterminated quote: <line>`.

### 3.3 File, track, index

- `FILE` names are always quoted. The type is a single non-empty token with
  no whitespace and no `"`, passed through verbatim (`WAVE`, `MP3`, `AIFF`,
  `BINARY`, `MOTOROLA`, ...). Missing/unquoted name or missing/malformed
  type is `cue: bad FILE: <line>`.
- `TRACK` numbers are exactly two digits in 01..99. Violations (one digit,
  `00`, three digits, non-digits) are `cue: bad track number: <line>`. The
  type is a single non-empty token with no whitespace, passed through
  verbatim (`AUDIO`, `MODE1/2352`, `MODE2/2352`, ...); otherwise
  `cue: bad track type: <line>`.
- `INDEX` numbers are exactly two digits in 00..99; otherwise
  `cue: bad index number: <line>`.
- `time` is exactly eight bytes `mm:ss:ff` and must occupy the rest of the
  line. `mm` is 00..99 (two digits, so no further check), `ss` is 00..59 and
  `ff` is 00..74. Wrong shape or trailing text on an INDEX line is
  `cue: bad index time: <line>`, on a PREGAP/POSTGAP line
  `cue: bad gap time: <line>`. `ss > 59` is
  `cue: second out of range: <line>`; `ff > 74` is
  `cue: frame out of range: <line>`.
- `ISRC` is 12 ASCII alphanumerics (quoted or bare); anything else is
  `cue: bad ISRC: <line>`.
- `CATALOG` is 13 ASCII digits (quoted or bare); anything else is
  `cue: bad CATALOG: <line>`.

### 3.4 Position rules

A TRACK starts a track body; a FILE ends the current body and starts a new
file group; EOF ends the last body. The current track is therefore the most
recent TRACK after the most recent FILE.

| Keyword | Allowed |
|---|---|
| `CATALOG` | Only when there is no current track. |
| `FILE` | Always; ends the current track body (multi-file sheets). |
| `TRACK` | Always; starts a new track body. |
| `INDEX`, `PREGAP`, `POSTGAP`, `ISRC` | Only when there is a current track. |
| `PERFORMER`, `TITLE`, `SONGWRITER`, `REM` | Always; they attach to the current track when there is one. |

A known keyword used where the table says no is
`cue: keyword not allowed here: <KEYWORD>`.

### 3.5 Missing INDEX 01 (documented decision)

Every TRACK must receive at least one `INDEX` whose number is 1 before the
body ends (next TRACK, next FILE or EOF). The first offending track in
document order makes the whole parse fail with
`cue: track <nn> has no INDEX 01`, `<nn>` being its two-digit track number.
This mirrors the burn requirement of the format and is deliberately strict;
`cue_track_has_index01` exists for hand-built values only.

## 4. Data model

```xi
pub type Cue = {
  kinds: Vec[Int];     // one EK_* code per element
  nums: Vec[Int];      // TRACK/INDEX number; 0 otherwise
  mins: Vec[Int];      // INDEX/PREGAP/POSTGAP minutes; 0 otherwise
  secs: Vec[Int];      // INDEX/PREGAP/POSTGAP seconds; 0 otherwise
  frames: Vec[Int];    // INDEX/PREGAP/POSTGAP frames; 0 otherwise
  texts: Vec[Str];     // FILE name, value, ISRC/CATALOG value, REM body
  texts2: Vec[Str];    // FILE type, TRACK type
  quoted: Vec[Int];    // 1 when texts[i] was quoted in the source
  files: Vec[Int];     // owning FILE ordinal, -1 when none
  tracks: Vec[Int];    // owning TRACK ordinal, -1 when outside a track
}
```

Invariants for a value produced by `cue_parse`:

- all ten Vecs have length `cue_element_count(c)`;
- `kinds[i]` is one of the eleven `EK_*` codes;
- `files[0]` is -1 until the first `FILE`; each FILE element carries its own
  (new) ordinal; a TRACK carries the ordinal of the latest FILE, or -1
  before the first FILE;
- a TRACK element carries its own `tracks` ordinal; elements before the first
  TRACK and elements after a FILE (until the next TRACK) carry -1;
- `quoted[i]` is 1 only for a text directive whose value was quoted
  (`FILE`, `PERFORMER`, `TITLE`, `SONGWRITER`, `ISRC`, `CATALOG`);
- `nums`/`mins`/`secs`/`frames`/`texts`/`texts2` are meaningful only for the
  kinds listed in the module header; all other slots are 0 or "".

`Vec[StructType]` is not usable in this compiler, so the sheet is ten
parallel Vecs instead of a list of element structs. `cue_emit` assumes the
same shape for hand-built values; unequal lengths or NUL bytes in a `Str`
field are undefined for emission and must be avoided by callers.

## 5. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"cue: "`:

| Message | Trigger |
|---|---|
| `cue: NUL byte in input` | Input contains a `0x00` byte (checked before any slicing). |
| `cue: text outside catalog: <line>` | First byte of a non-blank line is not a letter or `_`. |
| `cue: unknown keyword: <token>` | Leading token is not a known uppercase keyword. |
| `cue: keyword not allowed here: <KEYWORD>` | Position-rule violation (section 3.4). |
| `cue: bad track number: <line>` | TRACK number not exactly 2 digits 01..99. |
| `cue: bad track type: <line>` | TRACK type missing/empty/with whitespace. |
| `cue: bad index number: <line>` | INDEX number not exactly 2 digits 00..99. |
| `cue: bad index time: <line>` | INDEX time not `mm:ss:ff` or with trailing text. |
| `cue: bad gap time: <line>` | PREGAP/POSTGAP time not `mm:ss:ff` or with trailing text. |
| `cue: second out of range: <line>` | `ss > 59`. |
| `cue: frame out of range: <line>` | `ff > 74`. |
| `cue: track <nn> has no INDEX 01` | Section 3.5, first offending track. |
| `cue: unterminated quote: <line>` | Quoted value with no closing quote. |
| `cue: trailing text after quote: <line>` | Quoted value followed by more text. |
| `cue: missing value: <line>` | PERFORMER/TITLE/SONGWRITER with no value (or no separating whitespace). |
| `cue: bad FILE: <line>` | Unquoted name, missing/empty type, whitespace or quote in the type. |
| `cue: bad CATALOG: <line>` | Not exactly 13 digits. |
| `cue: bad ISRC: <line>` | Not exactly 12 alphanumerics. |

`cue_emit` and all accessors are total: they never return errors. Accessors
return sentinels instead (`-1` for numbers and ordinals, `""` for strings,
`0` for counts, `false` for booleans) when an index is out of range.

## 6. API contract

```xi
pub type Cue = { ... }                       // section 4

pub fn cue_parse(text: Str) -> Result[Cue, Str]
pub fn cue_emit(c: &Cue) -> Str

pub fn cue_element_count(c: &Cue) -> Int
pub fn cue_element_kind(c: &Cue, i: Int) -> Int
pub fn cue_element_kind_count(c: &Cue, kind: Int) -> Int
pub fn cue_element_num(c: &Cue, i: Int) -> Int
pub fn cue_element_min(c: &Cue, i: Int) -> Int
pub fn cue_element_sec(c: &Cue, i: Int) -> Int
pub fn cue_element_frame(c: &Cue, i: Int) -> Int
pub fn cue_element_frames(c: &Cue, i: Int) -> Int
pub fn cue_element_text(c: &Cue, i: Int) -> Str
pub fn cue_element_text2(c: &Cue, i: Int) -> Str
pub fn cue_element_quoted(c: &Cue, i: Int) -> Bool
pub fn cue_element_file(c: &Cue, i: Int) -> Int
pub fn cue_element_track(c: &Cue, i: Int) -> Int

pub fn cue_file_count(c: &Cue) -> Int
pub fn cue_file_element(c: &Cue, j: Int) -> Int
pub fn cue_file_name(c: &Cue, j: Int) -> Str
pub fn cue_file_type(c: &Cue, j: Int) -> Str

pub fn cue_track_count(c: &Cue) -> Int
pub fn cue_track_element(c: &Cue, t: Int) -> Int
pub fn cue_track_number(c: &Cue, t: Int) -> Int
pub fn cue_track_type(c: &Cue, t: Int) -> Str
pub fn cue_track_file(c: &Cue, t: Int) -> Int
pub fn cue_track_index_count(c: &Cue, t: Int) -> Int
pub fn cue_track_index(c: &Cue, t: Int, j: Int) -> Int
pub fn cue_track_has_index01(c: &Cue, t: Int) -> Bool

pub fn cue_index_count(c: &Cue) -> Int
pub fn cue_index_element(c: &Cue, k: Int) -> Int
pub fn cue_index_number(c: &Cue, k: Int) -> Int
pub fn cue_index_min(c: &Cue, k: Int) -> Int
pub fn cue_index_sec(c: &Cue, k: Int) -> Int
pub fn cue_index_frame(c: &Cue, k: Int) -> Int
pub fn cue_index_frames(c: &Cue, k: Int) -> Int
pub fn cue_index_track(c: &Cue, k: Int) -> Int
```

Details:

- `cue_parse` accepts LF, CRLF and a missing final newline; it is O(n) over
  the input.
- `cue_element_frames`/`cue_index_frames` return `(mm*60 + ss)*75 + ff` for
  time elements and `-1` otherwise. The maximum for a parsed sheet is
  `99:59:74` = 449999 frames; the arithmetic is exact integer math.
- `cue_track_index(c, t, j)` returns a global index ordinal for use with the
  `cue_index_*` family, not an element index; use `cue_index_element` to get
  the element index.
- `cue_emit` writes top-level lines at column 0 and track-body lines (every
  element after a TRACK until the next FILE) indented by two spaces. Track
  and index numbers are zero-padded to two digits; times are `mm:ss:ff` with
  each component clamped to two digits. Every line ends with LF, so an empty
  sheet emits `""`. An unknown kind code is skipped. The `quoted` flags are
  reproduced exactly (`""` doubling on write), so parsed bare and quoted
  values re-emit in their original style.

## 7. Round-trip rules

For any `c` obtained from `cue_parse`:

- `cue_parse(cue_emit(c))` yields a `Cue` equal to `c` on the whole
  observable surface: element count and order, kind, numeric fields, minute/
  second/frame fields, both texts, quoting flag, and the owning file/track
  ordinals;
- `cue_emit(cue_parse(cue_emit(c)))` is byte-identical to `cue_emit(c)`
  (emission is idempotent);
- no information is lost: unknown-free text values, `REM` bodies, file
  names/types, track types, index numbers and times all survive verbatim.

Normalizations performed by the round trip:

- CRLF, blank-line layout and leading/trailing space or tab collapse to the
  canonical LF form with two-space track-body indentation;
- a `REM` body keeps internal spacing but loses leading/trailing space/tab;
- quoting style is preserved, not normalized: `TITLE x` stays bare and
  `TITLE "x"` stays quoted.

## 8. Test matrix

`tests/test_conformance.xi` (module `cue_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full sheet | element kinds/order, files, tracks, indices, ordinals, quoting (3, 4) |
| t2 | CRLF / indentation / blanks | 3.1 |
| t3 | bare and quoted values | 3.2, empty quoted title |
| t4 | doubled quotes, backslashes | 3.2, canonical quoting on emit |
| t5 | boundaries | track 99, index 00, time 99:59:74, frame totals (3.3) |
| t6 | bad track numbers | 3.3, 5 |
| t7 | bad index numbers | 3.3, 5 |
| t8 | bad time shapes | 3.3, 5 |
| t9 | second/frame ranges | 3.3, 5 |
| t10 | missing INDEX 01 | 3.5, exact message |
| t11 | quote errors | 3.2, 5 |
| t12 | keyword/stray-text errors | 3.1, 3.4, 5 |
| t13 | bad FILE | 3.3, 5 |
| t14 | bad CATALOG/ISRC, bare forms | 3.3, 5 |
| t15 | canonical emit | 6, exact byte layout |
| t16 | round trip | 7, deep equality and idempotence |
| t17 | multi-FILE association | 3.4, 4 |
| t18 | accessor sentinels | 5, 6 |
| t19 | REM pass-through | 3, 6 |
| t20 | empty documents | 3.1, 6 |
| t21 | gaps and formatting | 3.3, 6, two-digit padding |
| t22 | quoted CATALOG/ISRC | 3.2, 6, quoting flags |

Every Str comparison in the suite goes through `xiom.string.compare`'s
`str_compare` (BUG 17 discipline), element reads bind typed locals first, and
the tests are called directly from `main` (no indexed `Vec[fn]` dispatch).

## 9. Compiler / stdlib notes (v0.61.3)

Workarounds carried by this module, in the style of `xiom.ini`,
`xiom.m3u` and `xiom.vtt`:

- **Ok/Err confinement.** `Ok`/`Err` for `Result[Cue, Str]` are constructed
  only in the leaf helpers `_ok_cue`/`_err_cue`; the `Cue` literal itself is
  built only by `_make_cue`.
- **Bytes as Int.** Every `string.byte_at` result goes through
  `_byte(s, pos) -> Int` before comparison, so no `UInt8` constant >= 128 is
  ever compared.
- **No Str `==`.** The module never compares `Str` with `==`; keyword
  dispatch uses `str_compare`, and every `Vec[Str]`/`Vec[Int]` element read
  binds a typed local first.
- **No `Vec[StructType]`.** Ten parallel Vecs hold the element stream.
- **No `match` and no lambdas** in the library module; the line loop is
  `if`/`elif`/`while` only. Test functions are called directly from `main`.
- **Explicit `&mut`.** Every helper taking `&mut Vec[UInt8]` is called with
  `&mut out` from a local builder; builder parameters forward the reference
  directly.
- **NUL safety.** `sb_to_str` aborts on NUL bytes, so `cue_parse` rejects
  NUL-containing input up front and every emitted Str is parser-produced
  ASCII/digit text or a validated quoted value.

## 10. Known limitations

- Strict two-digit track/index numbers and `mm:ss:ff` times: single-digit
  and three-digit forms are Err, so canonical emission can never reproduce
  them.
- The time must occupy the rest of the line; trailing comments after a time
  are Err.
- `CDTEXTFILE` and `FLAGS` are outside the subset and are unknown keywords.
- Keywords are case-sensitive uppercase.
- Quoted values have exactly one escape rule (`""`); there are no `\n`,
  `\xNN` or other escapes.
- `CATALOG` (13 digits) and `ISRC` (12 alphanumerics) are length/charset
  checked only; no checksums, no country/registrant validation.
- A track without `INDEX 01` is rejected; track numbers are not checked for
  uniqueness or order.
- No audio/image verification, no disc-ID math, no burning; file names are
  not checked against the filesystem.
- Whole-document only; no streaming, no editing API, no file I/O.
- Blank-line layout, CRLF and indentation are not preserved on emit.
- Errors carry the offending line text but no line/column numbers.
