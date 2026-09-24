# xiom.fixed

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** fixed-width text table parsing and writing by column widths.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.str_trim`, `xiom.string.lines` and `xiom.string.byte_at`).
> Tests additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.fixed` reads and writes the fixed-width ("column") text used by legacy
data exports, bank files, log reports and mainframe-style dumps: every column
occupies a known number of bytes, so a line is sliced at the cumulative column
widths. The module works on in-memory `Str` documents and containers
(`Vec[Int]` widths, `Vec[Vec[Str]]` rows), contains no FFI, and pins every
rule in `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `fixed_total_width(widths)` | `Int` | Sum of the non-negative widths (negative and zero widths add nothing). |
| `fixed_column_count(widths)` | `Int` | `widths.len()`: the number of fields in every parsed or written row. |
| `fixed_parse(text, widths)` | `Vec[Vec[Str]]` | Slice each line at the cumulative widths; fields are raw (untrimmed). A short line yields `""` for the missing fields; a width `<= 0` yields `""` and consumes no input. |
| `fixed_parse_trimmed(text, widths)` | `Vec[Vec[Str]]` | Same as `fixed_parse`, with `str_trim` applied to every field. |
| `fixed_write(rows, widths, pad)` | `Str` | Left-align each cell into its width, padding with the first byte of `pad` (space when `pad` is empty); longer cells are truncated; missing cells are empty; rows joined with LF, no trailing newline. |
| `fixed_field(rows, r, c)` | `Option[Str]` | Cell lookup; `None` when the row or column is out of range. |

Lines end at LF or CRLF; a single trailing terminator adds no row; empty text
has no rows; a blank line is one row of empty fields. All widths are **byte**
widths (see Limitations).

## Usage

```xi
use xiom.fixed;
use xiom.io;

fn main() -> Int {
  var widths = Vec[Int].new();
  widths.push(4);   // name
  widths.push(3);   // age
  var rows = fixed_parse_trimmed("Ada 36\nBob 7\n", &widths);
  var name = fixed_field(&rows, 1, 0);
  match name {
    Some(v) => { io.println(v); },   // Bob
    None => {},
  }
  io.println(fixed_write(&rows, &widths, ""));  // "Ada 36 "
                                                // "Bob 7  "
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.fixed
```

Expected tail: 18 `[PASS]` lines, `xiom.fixed: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Byte widths.** Column widths are byte counts, not character counts: a
  multi-byte UTF-8 character occupies several columns and a write can split a
  multi-byte sequence when it truncates. The module is intended for ASCII
  fixed-width data.
- **ASCII padding.** `fixed_write` pads with the first byte of `pad` only;
  multi-byte pad text degenerates to its first byte.
- **No escaping.** A field containing LF cannot round-trip: writing embeds it
  verbatim and parsing treats it as a line boundary. Cells are written
  verbatim apart from truncation and padding.
- **LF-only output.** The writer joins rows with LF and emits no trailing
  terminator; the reader accepts LF and CRLF (a bare CR is data).
- **No typed conversion.** Values stay `Str`; numbers, dates and booleans are
  not decoded.
- **No alignment modes.** Columns are left-aligned only (no right/center
  alignment, borders or header handling).
- **Concatenation cost.** Every function builds its result by `Str`
  concatenation; the module targets table-sized documents, not bulk ETL.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
