# xiom.metadata

> **Status:** `incubating` -- conformance-tested (28/28); not yet published on the XIOM registry.
> **Scope:** ordered metadata blocks (section, key, value) with
> ASCII-case-insensitive dotted keys, duplicate-key policies, scoping and
> nesting, merge with precedence and provenance, block diff, canonical
> serialization and parse round-trip, and a pinned validation/error catalog.
> In-memory `Str` only: no file I/O, no FFI, no environment.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.str_trim`, `xiom.string.byte_at`,
> `xiom.string.builder.sb_to_str`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.metadata` is a deterministic model for tag/metadata documents: an
ordered list of `(section, key, value)` entries where the section path gives
the block a key lives in (the empty path is the root scope and dotted paths
nest, e.g. `server.tls.mode`). It is the shared data model behind the
media-tag readers in this repository (EXIF, ID3, Vorbis comments, APE, MP4,
Matroska), written as pure XIOM.

Entry identity is the ASCII-case-folded `(section, key)` pair: `Host`,
`host` and `HOST` are the same key, while values stay byte-exact and
case-sensitive. Every construction path takes an explicit duplicate policy:

| Policy | `md_dup_*()` | Behavior |
|---|---|---|
| first | `0` | An existing pair keeps its first value and its position. |
| last | `1` | An existing pair takes the new value in place (position kept). |
| error | `2` | An assignment to an existing pair fails with `metadata: duplicate key: ...`. |

The canonical text form is insertion order, one `section.key = value` line
per entry, LF separated with no trailing LF; `md_serialize_sorted` emits the
same lines ordered by folded section then folded key. `md_parse` reads the
same shape (first `=` splits, the last dot in the left side splits section
from key), skips blank lines and full-line `#`/`;` comments, accepts CRLF and
trims keys and values. Every parsed line is validated, and every valid block
round-trips byte-exact.

## API

| Function | Returns | Description |
|---|---|---|
| `md_new()` | `MetaBlock` | Empty block. |
| `md_len(b)` | `Int` | Number of entries. |
| `md_entry_section(b, i)` | `Str` | Section path of entry `i` (`""` = root). |
| `md_entry_key(b, i)` | `Str` | Key of entry `i`. |
| `md_entry_value(b, i)` | `Str` | Value of entry `i`. |
| `md_entry_origin(b, i)` | `Int` | Provenance code of entry `i` (`-1` out of range). |
| `md_index(b, s, k)` | `Int` | Index of the folded pair, or `-1`. |
| `md_has(b, s, k)` | `Bool` | True when the folded pair exists. |
| `md_get(b, s, k)` | `Option[Str]` | Value of the folded pair, or `None`. |
| `md_origin(b, s, k)` | `Option[Int]` | Provenance of the folded pair, or `None`. |
| `md_set(b, s, k, v, policy)` | `Result[MetaBlock, Str]` | Apply one assignment under a duplicate policy (pure). |
| `md_append(b, s, k, v)` | `MetaBlock` | Unchecked append; the only way to build duplicates. |
| `md_scoped(b, prefix)` | `MetaBlock` | Re-parent the block under `prefix` (identity for `""`). |
| `md_subblock(b, path)` | `MetaBlock` | Extract the exact section level, re-rooted to `""`. |
| `md_merge(base, over)` | `MetaBlock` | Over-wins merge per folded pair with provenance. |
| `md_serialize(b)` | `Str` | Canonical text in insertion order. |
| `md_serialize_sorted(b)` | `Str` | Canonical text sorted by folded section/key. |
| `md_parse(text, policy)` | `Result[MetaBlock, Str]` | Parse and validate text; duplicate policy applies. |
| `md_diff(left, right)` | `MetaDiff` | Added/removed/changed report (section-aware identity). |
| `md_diff_len(d, kind)` | `Int` | Count for `md_kind_added/removed/changed`. |
| `md_diff_section/key/value(d, kind, i)` | `Str` | Entry fields (changed value = old value). |
| `md_diff_new_value(d, i)` | `Str` | New value aligned with changed entry `i`. |
| `md_diff_render(d)` | `Str` | `+`/`-`/`~` one-line-per-entry report. |
| `md_key_valid(k)` / `md_section_valid(s)` / `md_value_valid(v)` | `Bool` | Lexical rules. |
| `md_validate_code/message(s, k, v)` | `Int` / `Str` | Catalog code and pinned message. |
| `md_validate(b)` | `Str` | First failure in insertion order, else `""`. |
| `md_first_duplicate(b)` | `Int` | Index of the later duplicate entry, or `-1`. |
| `md_dup_*()` / `md_origin_*()` / `md_kind_*()` / `md_val_*()` | `Int`/`Str` | Explicit enum-by-code accessors and names. |

## Usage

```xi
use xiom.metadata;
use xiom.io;

fn build(text: Str) -> MetaBlock {
  match md_parse(text, md_dup_last()) {
    Ok(b) => { return b; },
    Err(_) => { return md_new(); },
  }
  return md_new();
}

fn main() -> Int {
  let base = build("debug = 0\nserver.host = localhost\n");
  let over = build("SERVER.HOST = example.org\nname = app\n");
  let merged = md_merge(&base, &over);
  io.println(md_serialize(&merged));
  // debug = 0
  // server.host = example.org
  // name = app
  match md_origin(&merged, "server", "host") {
    Some(o) => { io.println(md_origin_name(o)); },  // override
    None => {},
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.metadata -TimeoutSec 60
```

Expected tail: 28 `[PASS]` lines, `xiom.metadata: all tests passed`, then
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

## Limitations

- No interpolation, no include/import, no type coercion: values are byte
  runs stored verbatim.
- Comments are not preserved on parse; serialization never writes comments.
- A key is one dot-free segment; nesting comes from the dotted section path
  (`a.b` is a two-level path, not a key with a dot).
- `md_set` and `md_append` store arguments verbatim (no validation); call
  `md_validate` or use `md_parse`, which validates every line.
- `md_merge` records provenance for that merge only; folding two merges does
  not stack an older origin.
- Diff values are compared byte-exact and case-sensitive; key lookup is
  case-insensitive.
- Blocks are small by design; lookups, merge and diff are linear scans, and
  parse is O(lines x entries).

See `SPEC.md` for the normative block, merge, diff, serialization,
validation and error rules.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
