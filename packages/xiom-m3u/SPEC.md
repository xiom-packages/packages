# xiom.m3u -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.m3u` (`src/m3u.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory reader/writer for the M3U/M3U8 playlist format:

- `m3u_parse` -- document -> `Result[Playlist, Str]`,
- `m3u_emit` -- `Playlist` -> canonical extended-M3U text,
- entry accessors -- `m3u_entry_count`, `m3u_has_header`,
  `m3u_duration_seconds`, `m3u_title`, `m3u_path`,
- tag accessors -- `m3u_tag_count`, `m3u_tag`, `m3u_entry_tag_count`,
  `m3u_entry_tag`, `m3u_trailing_tag_count`, `m3u_trailing_tag`.

The codec covers the line grammar shared by plain M3U (path lines only) and
extended M3U (optional `#EXTM3U` header, `#EXTINF` entries, arbitrary `#`
tag/comment lines). It does not interpret HLS semantics.

## 2. Non-goals

- HLS playback or semantics: no segment assembly, no `#EXT-X-*` meaning, no
  duration/targetduration validation, no playlist-type logic.
- File existence checks or filesystem access of any kind; no file I/O.
- URL validation beyond "the path line is non-empty"; no normalization of
  relative/absolute paths, no percent-decoding.
- Float/`Float64` durations; fractional `#EXTINF` values are rejected.
- M3U8 UTF-8 BOM stripping, XML/PLSPLUS variants, ASX, WPL.
- Streaming/incremental parsing (whole `Str` in memory only).
- Editing operations on a parsed playlist (no add/remove/mutate API).
- Any FFI or registry integration.

## 3. Line grammar

```
document = *blank [ "#EXTM3U" LF ] *( blank / tag / extinf / path )
blank    = (no bytes)
tag      = "#" *( byte except LF )            ; preserved verbatim
extinf   = "#EXTINF:" seconds "," title
seconds  = 1*18DIGIT                          ; non-negative integer
title    = *( byte except LF )                ; verbatim, may be empty
path     = 1*( byte except LF )               ; verbatim, never starts "#"
```

### 3.1 Lines

- `text` is split on LF. A CR immediately before an LF is removed and one
  trailing CR at the end of an unterminated final line is removed too, so
  CRLF documents produce the same lines as LF documents and no line ever
  ends with CR. A trailing LF does not produce a final empty line. A lone CR
  elsewhere stays inside the line.
- A line is blank iff it is zero bytes long. A line containing only spaces
  or tabs is **not** blank: it is a path and is stored verbatim.
- A final line without a terminating LF is still a line.

### 3.2 Classification

Each non-blank line is classified by its first byte:

1. First byte `#`:
   - if it is the first non-blank line of the document and the line is
     exactly `#EXTM3U`, it is the header (`has_header = true`);
   - else if it starts with `#EXTINF:` it is an entry header (section 3.3);
   - else if it starts with `#EXTINF` (but not `#EXTINF:`) it is an error
     (section 5);
   - else it is a raw tag/comment line, preserved verbatim.
2. Any other byte: the line is a path, stored verbatim.

Tags are stored in document order. Every stored tag becomes a *preceding
tag* of the next entry created, and tags after the last entry are *trailing
tags*. Blank lines are skipped and do not affect attachment.

### 3.3 `#EXTINF` grammar

- The line must start with the exact bytes `#EXTINF:`.
- The seconds field runs to the first `,` and must be 1..18 ASCII digits
  `0`..`9`: no sign, no decimal point, no whitespace anywhere. Leading
  zeros are accepted (`007` = 7 seconds). A field of 19 or more digits is an
  error (the 18-digit cap guarantees the accumulated value fits `Int`).
- A missing comma, or a line that starts with `#EXTINF` but not with
  `#EXTINF:`, is `m3u: bad #EXTINF: <line>`.
- An empty or non-digit seconds field is
  `m3u: bad duration in #EXTINF: <line>`. This includes negative (`-1`,
  common for streams), floating point (`9.009`), signed (`+5`) and
  whitespace-padded (`1 2`) values.
- The title is the verbatim remainder after the first comma; it may be
  empty and may itself contain commas.
- An `#EXTINF` line must be followed by a path line before the next
  `#EXTINF` or the end of input. Blank lines, tags and comments may occur in
  between; they do not satisfy the requirement. Otherwise the error is
  `m3u: missing path after #EXTINF`.

### 3.4 Header and path-before-header rule (documented decision)

The `#EXTM3U` header is optional, and it is recognized only on the first
non-blank line (blank lines before it are allowed). Consequently:

- A path line before a later `#EXTM3U` is accepted. The document is then a
  plain M3U (`has_header = false`) and the late `#EXTM3U` line is preserved
  as an ordinary raw tag attached to the entry that follows it.
- A second `#EXTM3U` after the first is likewise an ordinary raw tag.
- An `#EXTM3U` line is never an error; there is no "misplaced header" case.

`#EXTM3U` must match byte-exactly: a trailing space or a leading UTF-8 BOM
makes it an ordinary tag.

## 4. Data model

```xi
pub type Playlist = {
  has_header: Bool;    // input began with a #EXTM3U first non-blank line
  durations: Vec[Int]; // per entry: seconds, -1 = no #EXTINF
  titles: Vec[Str];    // per entry: #EXTINF title, "" when none
  paths: Vec[Str];     // per entry: path line, verbatim
  tag_starts: Vec[Int];// per entry: first index into tags
  tag_ends: Vec[Int];  // per entry: exclusive end index into tags
  tags: Vec[Str];      // all raw tag/comment lines in document order
}
```

Invariants for a value produced by `m3u_parse`:

- the five per-entry Vecs all have length `m3u_entry_count(p)`;
- `0 <= tag_starts[i] <= tag_ends[i] <= tags.len()`;
- the ranges tile the `tags` prefix: `tag_starts[0] == 0` and
  `tag_starts[i] == tag_ends[i - 1]`;
- `durations[i] == -1` iff entry `i` had no `#EXTINF`; otherwise
  `durations[i] >= 0` (negative durations are unrepresentable after parse,
  so `-1` is an unambiguous sentinel);
- tags at indices `>= tag_ends[last]` are trailing tags; when there are no
  entries, every tag is trailing.

`Vec[StructType]` is not usable in this compiler, so entries are five
parallel Vecs plus per-entry tag ranges instead of a list of entry structs.

## 5. Error catalog

All parse failures are `Err(msg)` where `msg` starts with `"m3u: "` and,
where shown, ends with the offending raw line:

| Message | Trigger |
|---|---|
| `m3u: bad #EXTINF: <line>` | `#EXTINF` with no colon, `#EXTINF5,x`, `#EXTINF:5` (no comma), `#EXTINF:5 title` |
| `m3u: bad duration in #EXTINF: <line>` | `#EXTINF:,x` (empty), `#EXTINF:-1,x`, `#EXTINF:1.5,x`, `#EXTINF:abc,x`, `#EXTINF:1 2,x`, 19+ digits |
| `m3u: missing path after #EXTINF` | `#EXTINF` followed by EOF or by another `#EXTINF` before any path line |

`m3u_emit` and all accessors are total: they never return errors. Accessors
return sentinels instead (`-1` for durations, `""` for strings, `0` for
counts) when an index is out of range.

## 6. API contract

```xi
pub type Playlist = {
  has_header: Bool;
  durations: Vec[Int]; titles: Vec[Str]; paths: Vec[Str];
  tag_starts: Vec[Int]; tag_ends: Vec[Int]; tags: Vec[Str];
}

pub fn m3u_parse(text: Str) -> Result[Playlist, Str]
pub fn m3u_emit(p: &Playlist) -> Str
pub fn m3u_entry_count(p: &Playlist) -> Int
pub fn m3u_has_header(p: &Playlist) -> Bool
pub fn m3u_duration_seconds(p: &Playlist, i: Int) -> Int
pub fn m3u_title(p: &Playlist, i: Int) -> Str
pub fn m3u_path(p: &Playlist, i: Int) -> Str
pub fn m3u_tag_count(p: &Playlist) -> Int
pub fn m3u_tag(p: &Playlist, j: Int) -> Str
pub fn m3u_entry_tag_count(p: &Playlist, i: Int) -> Int
pub fn m3u_entry_tag(p: &Playlist, i: Int, j: Int) -> Str
pub fn m3u_trailing_tag_count(p: &Playlist) -> Int
pub fn m3u_trailing_tag(p: &Playlist, j: Int) -> Str
```

Details:

- `m3u_parse` accepts LF, CRLF and a missing final newline; it is O(n) over
  the input.
- `m3u_path`/`m3u_title`/`m3u_entry_tag`/`m3u_tag`/`m3u_trailing_tag`
  return `""` for any negative or out-of-range index.
- `m3u_duration_seconds` returns `-1` both for an entry without `#EXTINF`
  and for an out-of-range index.
- `m3u_emit` always writes the `#EXTM3U` header first. For each entry it
  writes the preceding tags in stored order, then `#EXTINF:<seconds>,<title>`
  when the duration is `>= 0`, then the path. Trailing tags follow the last
  path. Every line ends with LF, so output always ends with LF and an empty
  playlist emits `"#EXTM3U\n"`. A negative duration (possible only in a
  hand-built `Playlist`) is treated as "no `#EXTINF`" and skipped.
  `m3u_emit` is O(total output length).

## 7. Round-trip rules

For any `p` obtained from `m3u_parse`, `m3u_parse(m3u_emit(p))` yields a
playlist equal to `p` on the whole observable surface: entry count,
`has_header`, each duration/title/path, each entry's tag list, total tag
count and trailing tag list. The emitted text is byte-identical to
`m3u_emit` of the reparsed playlist (emission is idempotent).

Normalizations performed by the round trip:

- CRLF and blank-line layout collapse to canonical LF lines;
- a headerless (plain) playlist gains the `#EXTM3U` header, so
  `has_header` is `true` after reparse;
- `#EXTINF:007,...` re-emits as `#EXTINF:7,...`.

No other information is lost: unknown tags, comments and their positions,
titles (including commas and empty titles) and paths survive verbatim.

## 8. Test matrix

`tests/test_conformance.xi` (module `m3u_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | extended playlist | header, two entries, duration/title/path accessors (3.2, 3.3) |
| t2 | plain M3U | no header, `-1` durations, empty titles (3.2, 3.4) |
| t3 | CRLF | CRLF parses like LF (3.1) |
| t4 | missing final LF | final line is a line; CR stripped (3.1) |
| t5 | blank lines | blanks ignored anywhere, including between `#EXTINF` and path; whitespace-only line is a path (3.1, 3.3) |
| t6 | HLS tags | `#EXT-X-VERSION`/`TARGETDURATION` preceding, `ENDLIST` trailing (3.2) |
| t7 | tag attachment | per-entry ranges; tag between `#EXTINF` and path (3.2) |
| t8 | zero duration | `#EXTINF:0,` and empty title (3.3) |
| t9 | leading zeros | `007` = 7 (3.3) |
| t10 | comma in title | first comma splits, rest is title (3.3) |
| t11 | missing path | EOF, next `#EXTINF`, tag then EOF (3.3, 5) |
| t12 | bad shape | no colon, `#EXTINF5`, no comma (3.3, 5) |
| t13 | bad duration | empty, negative, float, alpha, spaced (3.3, 5) |
| t14 | digit range | 18 digits accepted, 30 digits Err (3.3) |
| t15 | path before header | accepted; late `#EXTM3U` is a raw tag (3.4) |
| t16 | canonical emit | CRLF + blanks normalize to exact LF layout (6) |
| t17 | round trip | deep equality after parse -> emit -> parse (7) |
| t18 | header normalization | headerless input emits the header (7) |
| t19 | empty documents | `""`, blank-only, header-only, comment-only (3.2, 6) |
| t20 | accessor sentinels | all out-of-range results (6) |

Every Str comparison in the suite goes through `xiom.string.compare`'s
`str_compare` (BUG 17 discipline), and element reads bind typed locals
first.

## 9. Compiler / stdlib notes (v0.61.3)

Workarounds carried by this module, in the style of `xiom.ini` and
`xiom.subtitle`:

- **Ok/Err confinement.** `Ok`/`Err` for `Result[Playlist, Str]` are
  constructed only in the leaf helpers `_ok_playlist`/`_err_playlist`; the
  `Playlist` literal itself is built only by `_make_playlist`.
- **Bytes as Int.** Every `string.byte_at` result goes through
  `_byte(s, pos) -> Int` before comparison, so no `UInt8` constant >= 128 is
  ever compared.
- **No Str `==`.** The module never compares `Str` with `==`; the tests use
  `str_compare`, and every `Vec[Str]`/`Vec[Int]` element read binds a typed
  local first.
- **No `Vec[StructType]`.** Entries live in five parallel Vecs plus the
  `tags` store with per-entry ranges.
- **No `match` and no lambdas** in the library module; parsing is
  `if`/`elif`/`while` only. Test functions are called directly from `main`
  (no indexed `Vec[fn]` dispatch).
- **Explicit `&mut`.** Every `xiom.string.builder` call site passes
  `&mut out` explicitly.
- **Bounded seconds parsing.** The 18-digit cap keeps the digit
  accumulation exact without a big-integer dependency.

## 10. Known limitations

- Integer seconds only: fractional `#EXTINF` values (common in HLS) are
  rejected; values longer than 18 digits are rejected.
- `#EXTINF:-1,...` (live-stream sentinel) is rejected; there is no
  "unknown duration" duration value other than "no `#EXTINF` at all".
- Strict `#EXTINF` prefix: any line starting with `#EXTINF` that is not
  `#EXTINF:<digits>,<title>` is an error, so a vendor comment such as
  `#EXTINFO` cannot be stored.
- Path lines cannot start with `#`; there is no escaping mechanism, so such
  a path is parsed as a tag.
- Titles and paths cannot end with CR (line-end CR is stripped).
- No HLS semantics, no `#EXT-X-*` validation, no segment assembly, no file
  existence checks, no URL validation beyond non-empty.
- Whole-document only; no streaming, no editing API, no file I/O.
- Blank-line layout and CRLF byte layout are not preserved on emit.
- A leading UTF-8 BOM is not stripped; a BOM-prefixed `#EXTM3U` is treated
  as an ordinary tag.
- Errors carry the offending line text but no line/column numbers.
