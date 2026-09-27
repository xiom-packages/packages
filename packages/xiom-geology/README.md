# xiom.geology

**Status:** implemented -- LAS 2.0 (Log ASCII Standard) well-log text parser in
pure XIOM. 26 conformance checks pass (`passed=26 failed=0`).

A dependency-free reader for LAS 2.0 text files: sections `~V`, `~W`, `~C`,
`~P`, `~A` plus opaque `~O`, WRAP YES/NO data, comments, quoted values, and a
fixed-point integer numeric model (scale 1000) with per-cell null flags.

## Scope (honest)

Parses: LF/CRLF lines; `#` comments; case-insensitive section letters and
mnemonics; `MNEM.UNIT VALUE : DESCRIPTION` header rows with dots inside values
and quoted strings; curve rows `NAME.UNIT [API/TYPE] : DESCRIPTION`; wrapped
(`WRAP. YES`) and unwrapped (`WRAP. NO`) data with depth-first rows; the
`NULL` declaration (default -999.25); opaque `~O` preservation; deterministic
`Err` strings carrying a line number and a byte offset.

Does not: write LAS, convert units, interpret the `~O` payload, validate VERS
or STOP against the row count, or accept scientific notation (`1.5E-3` is
rejected as a bad token). See `SPEC.md` for the full grammar, the numeric
model, the error catalog and the list of documented divergences.

## Numeric model

Every numeric value is an `Int` in thousandths (scale 1000:
`45500` = 45.5). Extra fraction digits are truncated toward zero
(`1.2345` -> `1234`, `-1.2345` -> `-1234`). No `Float64` is used anywhere.
Render with `las_scaled_to_string` (`-999250` -> `-999.250`).

A cell is **null** when its token is blank (`""`) or when its scaled value
equals the `NULL` declaration; the raw magnitude is still readable, so always
check the flag (or use `las_cell`).

## Usage

```xiom
use xiom.io;
use xiom.geology;

fn main() -> Int {
  let text = "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~C\nDEPT.M : DEPTH\nGR.GAPI : GR\n~A\n1000.0 45.5\n";
  let r = las_parse(text);
  match r {
    Ok(g) => {
      io.println("curves: " + las_curve_name(&g, 1) + " [" + las_curve_unit(&g, 1) + "]");
      let depth = las_cell(&g, 0, 0);
      let gr = las_cell(&g, 0, 1);
      io.println("depth " + las_scaled_to_string(depth.value) + " gr " + las_scaled_to_string(gr.value));
      if gr.is_null { io.println("gr missing"); } else { io.println("gr valid"); }
    },
    Err(e) => { io.println("las error: " + e); },
  }
  return 0;
}
```

On a bad row this prints e.g.
`las error: geology: invalid numeric token: abc at line 5 offset 42`, where
`geology_error_line` / `geology_error_offset` extract `5` and `42`.

## API

- `las_parse(text: Str) -> Result[LasLog, Str]` -- the only fallible entry point.
- Scalars: `las_version`, `las_wrap`, `las_start_depth`, `las_stop_depth`,
  `las_step`, `las_depth_unit`, `las_null_value`, `las_has_start`,
  `las_has_stop`, `las_has_step`, `las_depth_known`.
- Curves: `las_curve_count`, `las_curve_name`, `las_curve_unit`,
  `las_curve_type`, `las_curve_desc`, `las_curve_index` (case-insensitive).
- Rows: `las_row_count`, `las_cell`, `las_cell_value`, `las_cell_is_null`,
  `las_depth` (strt + row * step), `las_depth_read`, `las_depth_is_expected`,
  `las_row_line`.
- Metadata: `las_well_*` and `las_param_*` counts/rows plus
  `las_well_lookup` / `las_param_lookup` (case-insensitive).
- Opaque: `las_other_count`, `las_other_line`.
- Formatting: `las_value_scale`, `las_scaled_to_string`,
  `geology_error_line`, `geology_error_offset`.

Every accessor is total: out-of-range probes return `""`, `0`, `-1`, or
`LasCell{ value: 0; is_null: true }` instead of trapping.

## Testing

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom.geology
```

The suite builds all fixtures in-test (no data files) and prints one
`[PASS]`/`[FAIL]` line per check.

## License

MIT OR Apache-2.0. Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
