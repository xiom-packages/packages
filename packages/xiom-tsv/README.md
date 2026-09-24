# xiom.tsv

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** IANA-style tab-separated values with backslash escaping: parse and
> write. Fields are separated by raw TAB bytes, records by LF (a CRLF pair is
> one boundary), and `\\` `\t` `\n` `\r` encode backslash, TAB, LF and CR.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.builder`). Tests additionally use
> `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.tsv` parses tab-separated documents into `Vec[Vec[Str]]` and serializes
them back, following the IANA TSV conventions with the backslash escape subset
described in `SPEC.md`: raw tabs delimit fields, LF terminates records, a
trailing CR is stripped (CRLF input), and a field may contain TAB, LF, CR or a
literal backslash through the `\t`, `\n`, `\r` and `\\` escapes. The module is
dependency-free apart from `xiom.string`/`xiom.string.builder` helpers and
contains no FFI.

## API

| Function | Returns | Description |
|---|---|---|
| `tsv_escape_field(f)` | `Str` | Encodes `\` `TAB` `LF` `CR` as `\\` `\t` `\n` `\r`; other bytes pass through. |
| `tsv_unescape_field(f)` | `Result[Str, Str]` | Inverse; `Err("tsv: invalid escape")` on a malformed backslash sequence. |
| `tsv_parse_line(line)` | `Result[Vec[Str], Str]` | One line split on raw tabs with fields unescaped; one trailing CR stripped; errors like `tsv_unescape_field`. |
| `tsv_parse(text)` | `Vec[Vec[Str]]` | Whole document; LF records, CRLF tolerated, one trailing newline adds no row; empty text yields no rows. Lenient on malformed escapes. |
| `tsv_write_row(fields)` | `Str` | Escapes fields and joins them with a raw TAB. |
| `tsv_write(rows)` | `Str` | Joins encoded rows with LF; no trailing newline. |
| `tsv_is_rectangular(rows)` | `Bool` | True when all rows have the same field count (true for 0/1 rows). |
| `tsv_field_count(rows)` | `Int` | Field count of the first row; `0` when there are no rows. |

## Usage

```xi
use xiom.tsv;
use xiom.io;

fn main() -> Int {
  var rows = tsv_parse("name\tnote\nAda\tloves\ttabs\n");
  io.println(tsv_write(&rows));       // name\tnote
                                      // Ada\tloves\\ttabs
  io.println(tsv_write_row(&rows[0])); // name\tnote
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.tsv
```

Expected tail: 22 `[PASS]` lines, `xiom.tsv: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- IANA escape subset only: `\\`, `\t`, `\n`, `\r` are recognized; any other
  backslash sequence is rejected by `tsv_unescape_field`/`tsv_parse_line` (and
  kept verbatim by the infallible `tsv_parse`). There is no `\uXXXX` decoding.
- UTF-8 byte-oriented: scanning never splits or rewrites multi-byte sequences,
  so non-ASCII text round-trips byte-exact, but there is no Unicode
  normalization or validation.
- No header handling: a first row is ordinary data; no column names, no type
  inference.
- No dialect configuration (delimiter, quote char, comment lines), no
  streaming/incremental API, no BOM stripping, no trailing-space policies.
- The writer emits LF between rows (never CRLF) and no trailing newline.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
