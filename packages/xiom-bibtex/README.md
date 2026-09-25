# xiom.bibtex

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** BibTeX `.bib` parsing into a flat document model, plus a
> canonical emitter and a round-trip guarantee for the documented subset.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`, `xiom.string.str_lower`,
> `xiom.string.str_starts_with` and
> `xiom.string.compare.str_eq_ignore_case`). Tests additionally use
> `xiom.test` and `xiom.io`.

## What it is

`xiom.bibtex` parses BibTeX bibliography text into a flat `BibDoc`: entries
(`@article{key, author = {A. Uthor}, year = 2020}`), `@string` macros with
case-insensitive reference expansion, and `@comment` / `@preamble`
pass-through. Values may be brace-delimited (nested braces preserved),
quote-delimited (`\"` escapes preserved verbatim) or nonnegative numbers.
`bib_emit` renders the document back to canonical BibTeX that always
re-parses, so `bib_parse(bib_emit(d))` preserves every entry, field, macro,
preamble and comment.

The model is deliberately flat: XIOM v0.61.3 cannot hold a
`Vec[StructType]`, so entries and fields live in parallel vectors with
per-entry field slices. See `SPEC.md` for the exact grammar, decisions and
error catalog.

## Install / use

The package is not published yet. Once it is:

```
xiom pkg install xiom.bibtex@0.1.0
```

or depend on it from a package manifest:

```xi
deps: { "xiom.bibtex": "0.1.0" };
```

Until then, build against this checkout with the repo harness:

```
.\scripts\port.ps1 -Package xiom.bibtex
```

## Quick start

```xi
use xiom.bibtex;
use xiom.io;

fn main() -> Int {
  let src = "@string{ieee = \"IEEE Trans. Inf. Theory\"}\n@article{knuth1984,\n  author = {Knuth, Donald E.},\n  journal = ieee,\n  year = 1984\n}\n";
  let r = bib_parse(src);
  match r {
    Ok(d) => {
      io.println(bib_entry_count(&d));                 // 1
      io.println(bib_entry_key(&d, 0));                // knuth1984
      let i = bib_find_entry(&d, "KNUTH1984");         // case-insensitive: 0
      match bib_get_field(&d, i, "author") {
        Some(a) => { io.println(a); },                 // Knuth, Donald E.
        None => {},
      }
      io.println(bib_field_value(&d, 0, 1));           // IEEE Trans. Inf. Theory
      io.println(bib_emit(&d));                        // canonical .bib text
    },
    Err(e) => { io.println(e); },                      // "bibtex: ..."
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `bib_parse(text)` | `Result[BibDoc, Str]` | Parse a whole `.bib` document; `Err("bibtex: ...")` on malformed input, duplicates or unsupported constructs. |
| `bib_entry_count(d)` | `Int` | Number of entries. |
| `bib_entry_type(d, i)` | `Str` | Lowercased type of entry `i` (`"article"`); `""` when out of range. |
| `bib_entry_key(d, i)` | `Str` | Citation key as written; `""` when out of range. |
| `bib_find_entry(d, key)` | `Int` | Entry index for `key` (case-insensitive, BibTeX-style); `-1` when absent. |
| `bib_field_count(d, i)` | `Int` | Number of fields on entry `i`; `0` when out of range. |
| `bib_field_name(d, i, j)` | `Str` | Lowercased name of field `j`; `""` when out of range. |
| `bib_field_value(d, i, j)` | `Str` | Expanded value of field `j`; `""` when out of range. |
| `bib_get_field(d, i, name)` | `Option[Str]` | Value of field `name` on entry `i` (case-insensitive); `None` when absent. |
| `bib_macro_count(d)` | `Int` | Number of `@string` macros. |
| `bib_macro_name(d, k)` | `Str` | Lowercased macro name; `""` when out of range. |
| `bib_macro_value(d, k)` | `Str` | Expanded macro value; `""` when out of range. |
| `bib_get_macro(d, name)` | `Option[Str]` | Macro value by name (case-insensitive); `None` when undefined. |
| `bib_preamble_count(d)` | `Int` | Number of `@preamble` blocks. |
| `bib_preamble(d, i)` | `Str` | Expanded preamble value; `""` when out of range. |
| `bib_comment_count(d)` | `Int` | Number of `@comment` blocks. |
| `bib_comment(d, i)` | `Str` | Trimmed `@comment` body; `""` when out of range. |
| `bib_emit(d)` | `Str` | Canonical BibTeX text; `""` for an empty document. |

## Error model

Every parse failure is `Err(msg)` with `msg` starting `"bibtex: "`. Errors
name the offending entry key, field name, macro name or token snippet, for
example:

- `bibtex: missing key in entry`,
- `bibtex: expected '{' after entry type`,
- `bibtex: missing '=' after field name: title`,
- `bibtex: unterminated value`, `bibtex: unterminated quote`,
  `bibtex: unbalanced braces in value`,
- `bibtex: duplicate key: A`, `bibtex: duplicate field: X`,
  `bibtex: duplicate macro: S`,
- `bibtex: undefined macro: nope`,
- `bibtex: text outside entries: hello`.

The full catalog is in `SPEC.md` section 6. Accessors never fail: absent
entries/fields/macros yield `""`, `0`, `-1`, or `None`.

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom.bibtex
```

Expected tail: 24 `[PASS]` lines, `xiom.bibtex: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No LaTeX processing.** Braces, backslashes and `\"` are preserved
  byte-for-byte; no macro expansion, accent handling or escaping is applied.
  A quoted value must keep its braces balanced (an unbalanced `}` inside
  quotes is an error), so values are always re-emittable inside braces.
- **No `#` concatenation.** `field = "a" # "b"` is
  `Err("bibtex: unsupported concatenation")`.
- **No parenthesis entries.** `@type(...)` is rejected; use `@type{...}`.
- **No built-in month macros.** Only user `@string` definitions expand, and
  they must appear before their first use (document order).
- **`@comment` bodies** must have balanced braces and are trimmed; `@comment`
  without braces is not supported.
- **Text outside entries** must be whitespace: `%` comments and other junk
  are errors.
- **No citation styles, sorting, `.bib` merging, file I/O or streaming.**
- Entry order is preserved, but `bib_emit` stores macros/preamble/comments
  in their pools and emits them before entries; the interleaving of the
  original file is not preserved (semantics are).
- Numbers are stored as their digit text; leading zeros are kept, and a
  number directly followed by a letter is a parse error.

See `SPEC.md` for the exact grammar and decisions. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
