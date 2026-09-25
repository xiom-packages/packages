# xiom.gedcom

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** GEDCOM 5.5.1 line codec: line grammar `level [xref] tag [value]`,
> nesting validation, parents, pointers, CONT/CONC joining and canonical
> emission; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_push_int`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.gedcom` parses a GEDCOM 5.5.1 transmission into a flat `Gedcom` (five
parallel vectors: levels, xref ids, tags, verbatim values and computed parent
indices), exposes per-line accessors, subtree ranges and a first-tag lookup,
classifies pointer values with a documented predicate, joins CONT/CONC
continuation children back into one text, and emits the canonical
single-space, LF-terminated form.

It intentionally does **not** validate GEDCOM records semantically (no
HEAD/INDI/FAM rules, no required tags, no pointer-target resolution), does not
convert charsets (UTF-8 bytes pass through), and does not implement GEDCOM 7
differences -- see Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `gedcom_parse(text)` | `Result[Gedcom, Str]` | Parse a whole document; `Err("gedcom: ...")` on the first malformed line. |
| `gedcom_line_count(g)` | `Int` | Number of stored lines. |
| `gedcom_level(g, i)` | `Int` | Level of line `i`; `-1` out of range. |
| `gedcom_xref(g, i)` | `Option[Str]` | Xref id incl. `@`s; `None` when absent/out of range. |
| `gedcom_tag(g, i)` | `Str` | Tag of line `i`; `""` out of range. |
| `gedcom_value(g, i)` | `Str` | Verbatim value; `""` when absent/out of range. |
| `gedcom_parent(g, i)` | `Int` | Nearest level-1 ancestor; `-1` for level 0/out of range. |
| `gedcom_first_tag(g, tag)` | `Option[Int]` | First line with that byte-equal tag; case-sensitive. |
| `gedcom_subtree_end(g, i)` | `Int` | Exclusive end of the subtree of `i`. |
| `gedcom_is_pointer(v)` | `Bool` | True when `v` is syntactically `@id@` with id `[A-Za-z0-9_]`. |
| `gedcom_join_text(g, i)` | `Str` | `values[i]` plus direct CONT (LF + value) / CONC (value) children. |
| `gedcom_emit(g)` | `Str` | Canonical `level [xref] tag [value]` lines, single spaces, LF. |

## Usage

```xi
use xiom.gedcom;
use xiom.io;

fn main() -> Int {
  let text = "0 HEAD\n1 SOUR APP\n0 @I1@ INDI\n1 NAME Ada /Lovelace/\n0 TRLR\n";
  let r = gedcom_parse(text);
  match r {
    Ok(g) => {
      match gedcom_first_tag(&g, "INDI") {
        Some(ind) => {
          let id = gedcom_xref(&g, ind);       // Some("@I1@")
          io.println(gedcom_tag(&g, ind));     // INDI
          io.println(gedcom_emit(&g));         // canonical text
        },
        None => {},
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.gedcom
```

Expected tail: 23 `[PASS]` lines, `xiom.gedcom: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Line codec only**: no semantic record validation (HEAD/INDI/FAM grammar,
  required tags, pointer targets, date/place interpretation), no duplicate
  xref or cross-reference checks.
- **No charset work**: UTF-8 bytes pass through untouched; no BOM stripping,
  no ANSEL/UNICODE conversions.
- **GEDCOM 5.5.1 subset**: no GEDCOM 7 rules (no `@<...>@` escape pointers,
  no `UTF-8` difference handling).
- Zero-length lines are parsed as record separators and dropped; whitespace-
  only lines are `Err`.
- Non-canonical separators collapse on emit; a lone CR is not a line
  terminator (it becomes part of the line/value).
- Errors carry the offending line text but no line/column numbers.
- A `Gedcom` built by hand (not via `gedcom_parse`) is not validated; a value
  containing LF does not round-trip.

See `SPEC.md` for the full grammar, nesting and join rules, the error catalog
and the test plan. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
