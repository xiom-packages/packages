# xiom.lrc

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** LRC synced-lyrics parsing and canonical emitting; in-memory `Str`
> only, no audio, no rendering, no encoding conversion.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.compare.str_compare`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Overview

`xiom.lrc` is a small codec for the LRC synced-lyrics text format. It parses
a whole document into a flat `Lyrics` value -- the five documented metadata
tags, the signed millisecond offset, and index-aligned entry arrays -- and
emits a canonical LRC document.

The covered subset is deliberately narrow and fully specified in `SPEC.md`:

- metadata tags `[ti:...]`, `[ar:...]`, `[al:...]`, `[by:...]` and
  `[offset:...]` with a signed integer millisecond offset;
- timestamp fields `[mm:ss.xx]` (centiseconds) and `[mm:ss.xxx]`
  (milliseconds), with minutes and seconds `00..59`;
- several timestamp fields on one line (`[00:01.00][00:05.00]Chorus`), each
  producing one entry in field order;
- the text after the last timestamp is kept verbatim (it may be empty);
- blank lines are skipped, and plain untimed lines are skipped by documented
  design;
- LF and CRLF line endings, including a missing final newline.

The parser is strict: malformed timestamps, bad offsets, bracket tags without
a colon, unclosed brackets and unrecognized tag names are rejected with
deterministic `Err("lrc: ...")` messages rather than silently repaired.

## Install / use

```
xiom pkg install xiom.lrc@0.1.0
```

```xi
use xiom.lrc;
```

## Quick start

```xi
use xiom.lrc;
use xiom.io;

fn main() -> Int {
  let text = "[ti:Blue Hour]\n[ar:The XIOMs]\n[offset:+250]\n[00:12.34]First line\n[00:15.00][00:18.50]Chorus\n";
  let r = lrc_parse(text);
  if r.is_ok {
    let l = r.value;
    io.println(lrc_title(&l));                 // Blue Hour
    io.println(lrc_artist(&l));                // The XIOMs
    io.println(lrc_offset_ms(&l));             // 250
    io.println(lrc_entry_count(&l));           // 3
    io.println(lrc_text(&l, 1));               // Chorus
    if lrc_adjusted_time_ms(&l, 0) == 12590 {  // 12340 + 250
      io.println("adjusted");
    }
    io.println(lrc_emit(&l));                  // canonical LRC
  } else {
    io.println(r.error);                       // "lrc: <reason>"
  }
  return 0;
}
```

## API summary

| Function | Returns | Description |
|---|---|---|
| `lrc_parse(text)` | `Result[Lyrics, Str]` | Parse a whole LRC document; LF/CRLF; `Err("lrc: ...")` on malformed input. |
| `lrc_emit(l)` | `Str` | Canonical emission: `ti`, `ar`, `al`, `by`, `offset`, then entries in stored order; LF-terminated lines. |
| `lrc_entry_count(l)` | `Int` | Number of timed entries. |
| `lrc_time_ms(l, i)` | `Int` | Raw entry time in milliseconds; `-1` out of range. |
| `lrc_adjusted_time_ms(l, i)` | `Int` | Entry time plus the offset, clamped at 0; `-1` out of range. |
| `lrc_text(l, i)` | `Str` | Entry text (verbatim, may be `""`); `""` out of range. |
| `lrc_title(l)` | `Str` | `[ti:...]` value; `""` when absent. |
| `lrc_artist(l)` | `Str` | `[ar:...]` value; `""` when absent. |
| `lrc_album(l)` | `Str` | `[al:...]` value; `""` when absent. |
| `lrc_by(l)` | `Str` | `[by:...]` value; `""` when absent. |
| `lrc_offset_ms(l)` | `Int` | Signed `[offset:...]` value; `0` when absent. |

## Canonical emission

`lrc_emit` writes, in order:

1. `[ti:...]`, `[ar:...]`, `[al:...]`, `[by:...]` for non-empty values only;
2. `[offset:...]` only when the offset is non-zero, always with an explicit
   sign (`+` or `-`);
3. every entry in stored (source) order, as `[mm:ss.xx]text`, or
   `[mm:ss.xxx]text` when the millisecond remainder is not a whole number of
   centiseconds.

Every line is LF-terminated. A document with no metadata and no entries
emits `""`. Entries are never sorted by time; a line with several timestamps
keeps field order. For any `Lyrics` obtained from `lrc_parse`,
`lrc_parse(lrc_emit(l))` reproduces the same metadata, offset and entries,
and emission is idempotent.

## Error model

`lrc_parse` is total: it returns `Ok(Lyrics)` or `Err(msg)` with an `"lrc: "`
prefix. The messages are:

| Message | Raised when |
|---|---|
| `lrc: unclosed bracket` | A line starting with `[` has no `]` (checked before classification). |
| `lrc: bad timestamp shape` | A digit-first field is not exactly `mm:ss.xx` / `mm:ss.xxx` (wrong digit counts, wrong separators, non-digits). |
| `lrc: time out of range` | A structurally valid timestamp has minutes or seconds above 59. |
| `lrc: bad fraction length` | A structurally valid timestamp has a fraction other than 2 or 3 digits. |
| `lrc: tag missing colon` | A non-timestamp bracket field has no `:`. |
| `lrc: bad offset value` | `[offset:...]` is not an optional `+`/`-` followed by 1..18 digits. |
| `lrc: unknown tag: [<field>]` | A tag name is not `ti`, `ar`, `al`, `by` or `offset`. |

## Limitations

- Only the five documented tags are recognized; real-world extras such as
  `[length:03:12]`, `[re:...]` or `[ve:...]` are `Err("lrc: unknown tag: ...")`
  rather than preserved or skipped.
- Timestamps must be `mm:ss.xx` / `mm:ss.xxx` with two-digit minutes and
  seconds in `00..59`; a track longer than 59:59.999 cannot be parsed, and a
  hand-built `Lyrics` with a longer time emits minutes that the parser then
  rejects.
- Plain untimed lines (anything not starting with `[`) are skipped, so
  section markers such as `[Chorus]` are rejected as tags without a colon and
  free text is dropped.
- The text after the last timestamp is verbatim: no trimming, no karaoke
  word-timing tags, no ruby/translation variants.
- Encoding passes through byte-for-byte; a UTF-8 BOM is not stripped (it
  makes the first line untimed).
- Offsets are stored, not applied: use `lrc_adjusted_time_ms` to read
  offset-applied times.
- Whole-document only: no streaming and no editing API; no file I/O, no
  audio, no rendering.

See `SPEC.md` for the exact grammar, the data-model invariants, the error
catalog, the round-trip rules and the test matrix. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
