# xiom.csv

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** CSV parsing and writing with RFC 4180-style quoting and escaping.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.str_slice`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## Scope

`xiom.csv` parses comma-separated values into `Vec[Vec[Str]]` and serializes
them back, with the RFC 4180 quoting subset described in `SPEC.md`:
double-quoted fields, doubled quotes as literals, commas and CR/LF inside
quotes, LF/CRLF line endings, and a single trailing newline that does not
create an extra empty record. The module is dependency-free apart from
`xiom.string` helpers and contains no FFI.

## API

| Function | Returns | Description |
|---|---|---|
| `csv_parse_line(text)` | `Vec[Str]` | One record without embedded terminators; RFC 4180 quoting. Empty text yields one empty field; extra records are ignored. |
| `csv_parse(text)` | `Vec[Vec[Str]]` | Whole document; LF, CR and CRLF terminate records; quoted fields may contain newlines; empty text yields no records. |
| `csv_needs_quoting(field)` | `Bool` | True when the field contains `,` `"` LF CR, or starts/ends with a space. |
| `csv_write_row(fields)` | `Str` | Quotes and escapes fields only when needed; joins with commas. |
| `csv_write(rows)` | `Str` | Joins encoded rows with LF; no trailing newline. |
| `csv_is_rectangular(rows)` | `Bool` | True when all rows have the same field count (true for 0/1 rows). |
| `csv_get(rows, r, c)` | `Option[Str]` | Cell lookup; `None` when the row or column is out of range. |
| `csv_field_count(rows)` | `Int` | Field count of the first row; `0` when there are no rows. |

## Usage

```xi
use xiom.csv;
use xiom.io;

fn main() -> Int {
  var rows = csv_parse("name,note\nAda,\"loves, math\"\n");
  var note = csv_get(&rows, 1, 1);
  match note {
    Some(v) => { io.println(v); },   // loves, math
    None => {},
  }
  io.println(csv_write(&rows));      // name,note
                                     // Ada,"loves, math"
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.csv
```

Expected tail: 20 `[PASS]` lines, `xiom.csv: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- RFC 4180 subset: comma is the only delimiter and `"` the only quote
  character; there is no configurable dialect.
- No streaming/incremental API: `csv_parse` consumes a whole `Str` in memory,
  and `csv_parse`/`csv_parse_line` cannot report errors (they return containers,
  not `Result`), so an unterminated quoted field is closed leniently at EOF.
- The writer emits LF terminators (not CRLF); the reader accepts LF, CR and
  CRLF.
- A blank line parses as one record with a single empty field; a single
  trailing newline adds no record.
- No typed conversion (numbers/dates stay `Str`), no headers handling, no
  comment lines, no escape character beyond `""`.
- No BOM stripping; a leading UTF-8 BOM is treated as field content.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
