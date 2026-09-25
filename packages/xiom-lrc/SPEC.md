# xiom.lrc -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.lrc` (`src/lrc.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for a documented subset of the LRC synced-lyrics
format:

- `lrc_parse` -- document -> `Result[Lyrics, Str]`,
- `lrc_emit` -- `Lyrics` -> canonical LRC text,
- entry accessors -- `lrc_entry_count`, `lrc_time_ms`,
  `lrc_adjusted_time_ms`, `lrc_text`,
- metadata accessors -- `lrc_title`, `lrc_artist`, `lrc_album`, `lrc_by`,
  `lrc_offset_ms`.

The subset covers the five common metadata tags, centisecond and millisecond
timestamps, several timestamps per line, verbatim entry text and signed
millisecond offsets. It performs no audio, no rendering and no encoding
conversion; bytes pass through unchanged.

## 2. Non-goals

- Audio playback, lyric rendering, karaoke word-level timing or scrolling.
- Encoding conversion of any kind (including UTF-8 BOM stripping, UTF-16
  input or line-ending conversion beyond dropping CR before LF).
- Enhanced LRC / A2 extensions (word timing inside `<...>`), multiple
  languages on one line, ruby or translation tags.
- Filesystem access; streaming or incremental parsing (whole `Str` in
  memory only).
- Sorting entries by time, overlap detection, de-duplication or merging.
- Editing operations on a parsed document (no add/remove/mutate API).
- Any FFI or registry integration.

## 3. Grammar and semantics

```
document = *( blank / tagline / timeline / untimed )
blank    = (no bytes)
untimed  = non-blank line whose first byte is not "["
tagline  = "[" tag "]" *any
tag      = name ":" value
name     = "ti" | "ar" | "al" | "by" | "offset"
value    = *( any byte except "]" )        ; for offset: [ "+" | "-" ] 1*18DIGIT
timeline = timestamp *( "[" timestamp "]" ) text
timestamp= 2DIGIT ":" 2DIGIT "." frac
frac     = 2DIGIT | 3DIGIT                 ; centis | millis
text     = *( any byte except LF )         ; verbatim, may be empty
```

### 3.1 Lines

- `text` is split on LF. A CR immediately before an LF is removed, and one
  trailing CR at the end of an unterminated final line is removed too, so
  CRLF documents produce the same lines as LF documents and no line ever
  ends with CR. A trailing LF does not produce a final empty line. A lone CR
  elsewhere stays inside the line.
- A line is blank iff it is zero bytes long. Blank lines are skipped.
- A non-blank line whose first byte is not `[` is *untimed*: it is skipped
  (section 3.5).
- A final line without a terminating LF is still a line.
- A leading UTF-8 BOM is not stripped: the first line is then untimed and is
  skipped.

### 3.2 Bracket fields

A line whose first byte is `[` is scanned as one or more bracket fields:

1. The field body runs from the byte after `[` to the first `]` on the line.
   If there is no `]`, the error is `lrc: unclosed bracket`; this check runs
   before any field classification, so a truncated tag line and a truncated
   timestamp line share that error.
2. A field body whose first byte is an ASCII digit (`0`..`9`) must be a
   timestamp (section 3.3).
3. Any other field body is a metadata tag (section 3.4).

The first field decides the line kind. On a tag line, bytes after the
closing `]` are ignored (documented normalization). On a timestamp line,
every subsequent `[...]` field must also be a timestamp; the entries are
appended in field order and the remainder after the last `]` is the entry
text, verbatim and possibly empty (no trimming).

Examples:

| Line | Result |
|---|---|
| `[00:12.34]Hello` | one entry at 12340 ms, text `Hello` |
| `[00:12.340]Hello` | one entry at 12340 ms, text `Hello` |
| `[00:01.00][00:05.00]Chorus` | two entries (1000, 5000), both text `Chorus` |
| `[00:01.00]` | one entry at 1000 ms, empty text |
| `[ti:Title]` | title `Title`, no entry |
| `[ti:Title] junk` | title `Title`; ` junk` ignored |
| `Hello` | untimed, skipped |
| `[Chorus]` | `Err("lrc: tag missing colon")` |

### 3.3 Timestamp grammar

```
timestamp = 2DIGIT ":" 2DIGIT "." frac
2DIGIT    = exactly two ASCII digits (no more, no fewer)
frac      = 2DIGIT          ; centiseconds, value * 10 milliseconds
          | 3DIGIT          ; milliseconds
```

Checks are performed in this fixed order, so the error for an invalid field
is deterministic:

1. **Shape**: exactly two digits, `:`, two digits, `.`, then at least one
   digit, and nothing else. Anything else (including a fraction containing a
   non-digit, a missing dot, a one-digit minute, an hour field or extra
   bytes) is `Err("lrc: bad timestamp shape")`.
2. **Range**: minutes and seconds must be `00..59`;
   otherwise `Err("lrc: time out of range")`.
3. **Fraction length**: the digit run after the dot must be exactly 2 or 3
   digits; otherwise `Err("lrc: bad fraction length")` (a fraction of one
   digit fails here only after the shape checks; a fraction with a non-digit
   fails as shape).

The millisecond value is `mm * 60000 + ss * 1000 + frac`, where `frac` is
scaled by 10 for a two-digit fraction. Zero is representable
(`[00:00.00]`), and the largest parseable time is `[59:59.999]` = 3599999 ms.

### 3.4 Metadata tags

- A tag field body is `name:value`; the name is everything before the first
  `:` and the value the remainder after it (the value may contain `:` and be
  empty). The name must match exactly one of `ti`, `ar`, `al`, `by`,
  `offset` -- no case folding, no whitespace, no prefixes.
- A body with no `:` is `Err("lrc: tag missing colon")`.
- A body with a colon but an unrecognized name is
  `Err("lrc: unknown tag: [<body>]")`.
- `ti` sets the title, `ar` the artist, `al` the album and `by` the
  writer/attribution. Empty values are valid and read back as `""`.
- `offset` takes an optional `+` or `-` followed by 1..18 ASCII digits, no
  whitespace and no other bytes. Leading zeros are accepted
  (`[offset:+0005]` = 5). Anything else is `Err("lrc: bad offset value")`.
  The 18-digit cap keeps the accumulated value inside `Int` range.
- Tags may appear before, between or after timestamp lines. A repeated tag
  overwrites the earlier value: the last occurrence wins.
- A tag line's text after the closing `]` is ignored, and the tag applies to
  the whole document, not to the next entry.

### 3.5 Untimed lines

A non-blank line that does not start with `[` is skipped and is not
represented in the model or in `lrc_emit` output. This is a documented
decision: LRC files carry plain headers or notes that have no timed
representation, and refusing the whole document would be worse than dropping
them. Whitespace-only lines are untimed and skipped too (they are not blank,
but they are dropped by the same rule). Lines that merely contain `[` later
are untimed as well, since only the first byte is inspected.

## 4. Data model

```xi
pub type Lyrics = {
  title: Str;        // [ti:...], "" when absent
  artist: Str;       // [ar:...], "" when absent
  album: Str;        // [al:...], "" when absent
  by_text: Str;      // [by:...], "" when absent
  offset_ms: Int;    // [offset:...] in milliseconds, 0 when absent
  times: Vec[Int];   // per entry: raw time in milliseconds
  texts: Vec[Str];   // per entry: text after the last timestamp
}
```

Invariants for a value produced by `lrc_parse`:

- `times.len() == texts.len()` (the entry count);
- every time is in `0..3599999`;
- entries are in source order -- not sorted by time -- and a line with `k`
  timestamp fields contributes `k` consecutive entries with the same text;
- `offset_ms` is stored raw; it is never applied to `times`.

`Vec[StructType]` is not usable in this compiler, so entries are two
parallel Vecs rather than a list of entry structs.

## 5. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"lrc: "`:

| Message | Trigger |
|---|---|
| `lrc: unclosed bracket` | A line starting with `[` where a field has no closing `]`: `[00:12.34`, `[ti:Title`, `[00:01.00][00:02.00`. |
| `lrc: bad timestamp shape` | Digit-first field not exactly `mm:ss.xx` / `mm:ss.xxx`: `[00:1.50]`, `[0:01.50]`, `[00-01.50]`, `[00:01,50]`, `[00:01.5a]`, `[00:12]`. |
| `lrc: time out of range` | Structurally valid timestamp with `mm > 59` or `ss > 59`: `[60:00.00]`, `[00:60.00]`, `[99:99.99]`. |
| `lrc: bad fraction length` | Structurally valid timestamp with a 1-, 4-, 5-, ...-digit fraction: `[00:12.1]`, `[00:12.1234]`. |
| `lrc: tag missing colon` | Non-timestamp field with no `:`: `[ti]`, `[Chorus]`, `[]`. |
| `lrc: bad offset value` | `[offset:...]` value that is not optional sign + 1..18 digits: `[offset:]`, `[offset:abc]`, `[offset:1.5]`, `[offset:--5]`, `[offset:+]`, `[offset: 5]`, 19+ digits. |
| `lrc: unknown tag: [<field>]` | Tag name outside `ti`/`ar`/`al`/`by`/`offset`: `[re:some]`, `[length:03:12]`, `[:x]`. |

`lrc_emit` and all accessors are total: they never return errors. Accessors
return sentinels instead of failing: `-1` for an out-of-range time and `""`
for an out-of-range string.

## 6. API contract

```xi
pub type Lyrics = {
  title: Str; artist: Str; album: Str; by_text: Str; offset_ms: Int;
  times: Vec[Int]; texts: Vec[Str];
}

pub fn lrc_parse(text: Str) -> Result[Lyrics, Str]
pub fn lrc_emit(l: &Lyrics) -> Str
pub fn lrc_entry_count(l: &Lyrics) -> Int
pub fn lrc_time_ms(l: &Lyrics, i: Int) -> Int
pub fn lrc_adjusted_time_ms(l: &Lyrics, i: Int) -> Int
pub fn lrc_text(l: &Lyrics, i: Int) -> Str
pub fn lrc_title(l: &Lyrics) -> Str
pub fn lrc_artist(l: &Lyrics) -> Str
pub fn lrc_album(l: &Lyrics) -> Str
pub fn lrc_by(l: &Lyrics) -> Str
pub fn lrc_offset_ms(l: &Lyrics) -> Int
```

Details:

- `lrc_parse` accepts LF, CRLF and a missing final newline; it is O(n) over
  the input. An empty document, a blank-only document and an untimed-only
  document are all valid and yield an empty `Lyrics`.
- `lrc_time_ms` and `lrc_text` return `-1` / `""` for any negative or
  out-of-range index. `lrc_adjusted_time_ms` computes
  `max(0, time + offset)` and returns `-1` out of range.
- `lrc_entry_count` is `0` for an empty document.
- Metadata accessors return the stored string (possibly `""`); they have no
  out-of-range case.
- `lrc_emit` is O(total output length).

## 7. Canonical emission and round-trip rules

`lrc_emit(l)` writes:

1. `[ti:<title>]`, `[ar:<artist>]`, `[al:<album>]`, `[by:<by_text>]`, for
   each non-empty value, in that fixed order;
2. `[offset:<signed>]` only when `offset_ms != 0`, always with an explicit
   `+` or `-` (for example `[offset:+250]`, `[offset:-100]`);
3. one line per entry, in stored source order: `[mm:ss.xx]<text>`, or
   `[mm:ss.xxx]<text>` when `ms % 10 != 0`, so the exact millisecond value
   survives; milliseconds are zero-padded, minutes and seconds print with at
   least two digits. A negative time (possible only in a hand-built
   `Lyrics`) clamps to zero.

Every emitted line ends with LF, so a non-empty result always ends with LF,
and an empty document emits `""`.

For any `l` obtained from `lrc_parse`:

- `lrc_parse(lrc_emit(l))` yields a `Lyrics` equal to `l` on the whole
  observable surface: the four string tags, the offset, the entry count and
  every entry time and text;
- `lrc_emit(lrc_parse(lrc_emit(l)).value)` is byte-identical to
  `lrc_emit(l)` (emission is idempotent).

Normalizations performed by the round trip:

- CRLF, blank-line layout and a missing final LF collapse to canonical LF
  lines;
- `[00:01.500]` and `[00:01.50]` both emit as `[00:01.50]`;
- an absent or zero offset is not emitted; non-zero offsets gain an explicit
  sign;
- untimed lines are dropped; tag-line bytes after `]` are dropped.

No other information is lost within the supported subset: entry order,
verbatim texts (including empty or whitespace-padded ones) and tag values
survive.

## 8. Test matrix

`tests/test_conformance.xi` (module `lrc_tests`) runs 21 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | metadata + entries | all five tags, multi-timestamp line, exact times (3.2, 3.4) |
| t2 | centis/millis | 2-digit and 3-digit fractions, 0 and 59:59.999 boundaries (3.3) |
| t3 | multi-timestamp order | three fields keep source order, never sorted (3.2, 4) |
| t4 | verbatim text | leading/trailing spaces kept, empty text, tag after entry (3.2) |
| t5 | canonical emit | fixed metadata order, signed offset, entry order, exact bytes (7) |
| t6 | round trip | CRLF input, parse -> emit -> parse equality and idempotence (7) |
| t7 | CRLF / final LF | CRLF and unterminated final line (3.1) |
| t8 | untimed skipped | plain, whitespace-only and bracket-later lines dropped (3.5) |
| t9 | bad shape | six malformed timestamp shapes (3.3, 5) |
| t10 | out of range | `mm`/`ss` above 59 (3.3, 5) |
| t11 | fraction length | 1- and 4-/5-digit fractions (3.3, 5) |
| t12 | offset values | seven bad forms and `+`/`-`/`0`/unsigned good forms (3.4, 5) |
| t13 | missing colon | `[ti]`, `[Chorus]`, `[]` (3.4, 5) |
| t14 | unclosed bracket | truncated tag and timestamp lines (3.2, 5) |
| t15 | unknown tag | `[re:...]`, `[length:...]`, empty name (3.4, 5) |
| t16 | offset semantics | raw vs adjusted times, clamping at 0, sentinels (6) |
| t17 | accessors | values and out-of-range sentinels (6) |
| t18 | empty documents | `""`, blank-only, untimed-only, metadata-only (3.1, 3.5, 6) |
| t19 | duplicate tags | last occurrence wins; tags after entries (3.4) |
| t20 | emit normalization | `.500` -> `.50`, `.234` kept, zero offset dropped (7) |
| t21 | emit edge cases | hand-built negative time clamps at 0; 60 minutes emit `[60:00.00]`, which reparse rejects (7, 10) |

Every string comparison in the suite goes through
`xiom.string.compare.str_compare` (BUG 17 discipline), and element reads bind
typed locals first. Test functions are called directly from `main`; there is
no indexed `Vec[fn]` dispatch.

## 9. Compiler / stdlib notes (v0.61.3)

Workarounds carried by this module, in the style of `xiom.subtitle` and
`xiom.m3u`:

- **Ok/Err confinement.** `Ok`/`Err` for `Result[Lyrics, Str]` are
  constructed only in the leaf helpers `_ok_lyrics`/`_err_lyrics`; the
  `Lyrics` literal itself is built only by `_make_lyrics`.
- **Bytes as Int.** Every `string.byte_at` result goes through
  `_byte(s, pos) -> Int` before comparison, so no `UInt8` constant >= 128 is
  ever compared.
- **No Str `==`.** The module never compares `Str` with `==`; tag names go
  through `str_compare`, and every `Vec[Str]`/`Vec[Int]` element read binds a
  typed local first.
- **No `Vec[StructType]`.** Entries live in two parallel Vecs
  (`times`/`texts`) inside one `Lyrics`; the type is never instantiated as a
  Vec element.
- **No `match` and no lambdas.** Parsing is `if`/`elif`/`while` only, and the
  tests call each check function directly.
- **Sentinel-returning timestamp parser.** `_ts_ms` returns `-1`/`-2`/`-3`
  codes for shape/range/fraction errors so the caller can map them to the
  catalog messages without constructing results deep in the scan.
- **Bounded offset parsing.** The 18-digit cap keeps the digit accumulation
  exact without a big-integer dependency.
- **Non-negative decimal formatting** is a local helper (`_int_str`), so the
  module needs no `xiom.convert` import.

## 10. Known limitations

- Only the five documented tags; `[length:...]`, `[re:...]`, `[ve:...]`,
  `[#:...]` and friends are errors, not preserved tags.
- Two-digit minutes and seconds in `00..59` only: tracks longer than
  59:59.999 cannot be parsed. A hand-built `Lyrics` above that range emits
  minutes with extra digits, which the parser rejects (output is not
  round-trip-safe above 59:59.999).
- `]` cannot appear inside a tag value or a timestamp field, since the first
  `]` closes the field; metadata values are truncated there and the rest of
  the line is ignored on a tag line.
- Untimed lines are dropped, and `[Chorus]`-style section markers are
  rejected as tags without a colon.
- Entry text is verbatim: no trimming and no enhanced-LRC word timings.
- Offsets are stored, not applied; `lrc_adjusted_time_ms` clamps at 0.
- Whole-document only: no streaming, no editing API, no file I/O.
- A leading UTF-8 BOM is not stripped and makes the first line untimed.
- Errors carry the offending field text only for unknown tags; other errors
  carry no line or column numbers.
