# xiom.ris

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** RIS bibliography text parsing into a flat record/field model,
> plus a canonical emitter and a round-trip guarantee for the documented
> subset.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.ris` parses RIS bibliography records (`TY  - JOUR` ... `ER  -`) into a
flat `RisDoc`: every record's fields in document order, each tag stored as
written and each value trimmed, with continuation lines joined, unknown tags
preserved, blank lines ignored and CRLF/LF normalized. `ris_emit` renders the
document back to canonical RIS that always re-parses, so
`ris_parse(ris_emit(d))` preserves every record, tag and value.

The model is deliberately flat: XIOM v0.61.3 cannot hold a `Vec[StructType]`,
so records are ranges into two shared pools (`field_tags`, `field_values`)
described by parallel `Vec[Int]` vectors rather than a tree of record
structs.

Supported and rejected input is pinned down exactly in `SPEC.md`: the tag
line is `XX  - value` with two tag characters, two spaces, a hyphen and a
space; a line without that prefix continues the previous value (joined with
one space); errors are reported as `Err("ris: ...")` with a 1-based line
number.

## Install / use

The package is not published yet. Once it is:

```
xiom pkg install xiom.ris@0.1.0
```

or depend on it from a package manifest:

```xi
deps: { "xiom.ris": "0.1.0" };
```

Until then, build against this checkout with the repo harness:

```
.\scripts\port.ps1 -Package xiom.ris
```

## Quick start

```xi
use xiom.ris;
use xiom.io;

fn main() -> Int {
  let src = "TY  - JOUR\nAU  - Knuth, Donald E.\nTI  - Literate Programming\nAB  - A short abstract\n   continued here\nER  - \n";
  let r = ris_parse(src);
  match r {
    Ok(d) => {
      io.println(ris_record_count(&d));                 // 1
      io.println(ris_field_count(&d, 0));               // 4
      match ris_get_field(&d, 0, "TI") {
        Some(t) => { io.println(t); },                  // Literate Programming
        None => {},
      }
      io.println(ris_field_value(&d, 0, 3));            // A short abstract continued here
      io.println(ris_emit(&d));                         // canonical RIS text
    },
    Err(e) => { io.println(e); },                       // "ris: ..."
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `ris_parse(text)` | `Result[RisDoc, Str]` | Parse a whole RIS document; `Err("ris: ...")` on the first error in document order. Empty or whitespace-only input is a valid empty document. |
| `ris_record_count(d)` | `Int` | Number of records. |
| `ris_field_count(d, r)` | `Int` | Number of fields in record `r`; `0` when out of range. |
| `ris_field_tag(d, r, j)` | `Str` | Tag of field `j`, as written (case-sensitive); `""` when out of range. |
| `ris_field_value(d, r, j)` | `Str` | Trimmed value of field `j`; `""` when out of range or empty. |
| `ris_get_field(d, r, tag)` | `Option[Str]` | Value of the **first** field with tag `tag` in record `r` (byte-exact, case-sensitive); `None` when absent or the record is out of range. |
| `ris_emit(d)` | `Str` | Canonical RIS text: `<TAG>  - <value>` lines in document order, then `ER  - `; `""` for an empty document. |

Every parsed record has at least one field and its first field is its `TY`
line. Tags other than `ER` may repeat; `ris_get_field` returns the first
occurrence, and indexed access returns every occurrence in order.

## Error model

Every parse failure is `Err(msg)` with `msg` starting `"ris: "`, carrying the
1-based line number and, where useful, a byte snippet of the offending
line:

- `ris: text before first TY at 1: hello`,
- `ris: missing TY at 1: AU`,
- `ris: tag not 2 chars at 1: ABC`,
- `ris: malformed tag line at 1: T!  - x`,
- `ris: missing ER`,
- `ris: missing ER at 2` (a `TY` line inside an open record),
- `ris: duplicate ER at 3`.

Parsing stops at the first error. Accessors never fail: out-of-range indices
yield `0`, `""` or `None`. The full catalog is in `SPEC.md` section 6.

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ris
```

Expected tail: 20 `[PASS]` lines, `xiom.ris: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Strict tag lines.** Only `XX  - value` (two tag characters, two spaces,
  hyphen, space) and the empty-value form `XX  -` are tag lines. One-space or
  tab spacing, `XX -x`, and indented tag lines are continuation text inside a
  record and rejected outside one.
- **Single trailing-line form.** Tag values are trimmed; continuation lines
  are trimmed and joined with one space, so original line breaks and
  indentation are not recoverable.
- **Structural errors are hard errors.** A record that is not closed by `ER`
  before end of input, a second `ER` for one record, and a `TY` inside an
  open record are all errors; the parser never guesses record boundaries.
- **`ER` value ignored.** `ER  - anything` closes the record; the canonical
  emitter writes `ER  - `.
- **No semantics.** Unknown and known non-structural tags are opaque; there
  is no type vocabulary, no author parsing, no citation formatting, no LaTeX
  processing, no sorting, no deduplication and no cross-record linking.
- **Byte-oriented.** `Str` is treated as a UTF-8 byte buffer without
  validation or normalization; CR-only line endings are not supported, and
  CRLF/LF are normalized to LF on emission.
- **No file I/O or streaming.** Documents are complete in-memory `Str`
  values.
- **Canonicalized layout.** `ris_emit` preserves records, tags and values but
  not the original formatting (blank lines, CRLF, continuation layout).
- **Line-level errors.** Errors carry a line number and a byte snippet, not a
  column.

See `SPEC.md` for the exact grammar, decisions, error catalog and test
matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
