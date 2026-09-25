# xiom.gcode

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** parse a documented subset of RS-274-style G-code into a flat
> command/parameter stream: optional `Nnn` line numbers, letter+number words,
> `;` and `( ... )` comments, `*hh` XOR checksums, case-insensitive letters,
> whitespace tolerance; plus canonical emission, a scaled-integer accessor and
> a deterministic error catalog.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_upper`, `xiom.math.bit_xor` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test`,
> `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.gcode` turns controller text such as

```
N10 G1 X10.5 Y-3 ; lead-in
N11 G1 X20.0
M3 S1000*0C
```

into plain values: a command stream with line numbers and parameter words,
each number exposed both verbatim (`"10.5"`) and as a signed scaled integer
plus a scale (`105`, scale `1`). It can also emit a parsed line back in a
canonical form. Parsing is byte-oriented and stateless: every function
rescans its input, so there is no parser object to allocate, retain or
invalidate. All arithmetic is 64-bit integer math; there is no floating
point, no I/O and no global state.

This is a **codec**, not a controller: `G1` is just a word. No motion or modal
semantics, no arcs, no machine state, no file I/O.

## API

| Function | Returns | Description |
|---|---|---|
| `gcode_parse_line(text)` | `Result[GcodeLine, Str]` | Parse one physical line; blank lines yield `Ok` with `blank = true`. |
| `gcode_parse(text)` | `Result[GcodeProgram, Str]` | Parse LF-separated text; blank lines are skipped; errors carry the 1-based physical line number. |
| `gcode_emit(line)` | `Str` | Canonical line text (uppercase letters, normalized numbers); `""` for blank lines. |
| `gcode_line_is_blank(line)` | `Bool` | The blank flag. |
| `gcode_line_number(line)` | `Int` | `N` value, or `-1` when absent/blank. |
| `gcode_command_letter(line)` | `Str` | Uppercase command letter (`""` when blank). |
| `gcode_command_text(line)` | `Str` | Verbatim command number text. |
| `gcode_command_value(line)` | `Int` | Scaled command value. |
| `gcode_command_scale(line)` | `Int` | Command fraction digit count (0-18). |
| `gcode_param_count(line)` | `Int` | Number of parameter words. |
| `gcode_param_letter(line, j)` | `Str` | Uppercase parameter letter; `""` when out of range. |
| `gcode_param_text(line, j)` | `Str` | Verbatim parameter number text; `""` when out of range. |
| `gcode_param_value(line, j)` | `Int` | Scaled parameter value; `0` when out of range. |
| `gcode_param_scale(line, j)` | `Int` | Parameter fraction digit count; `0` when out of range. |
| `gcode_micro(value, scale)` | `Result[Int, Str]` | Convert a scaled value to millionths (1e-6 units), truncating extra digits. |
| `gcode_command_count(program)` | `Int` | Number of parsed (non-blank) lines. |
| `gcode_program_param_count(program)` | `Int` | Total parameter words across all commands. |
| `gcode_program_line(program, i)` | `GcodeLine` | Rebuild command `i` as a line value. |

Scaling contract: a number's numeric magnitude is `value / 10^scale`. For
example `X10.5` yields `value = 105, scale = 1`, `X.050` yields
`value = 50, scale = 3`, and `X5.` yields `value = 5, scale = 0`. The
verbatim text is preserved on the side (`.text` accessors). The exact
grammar, checksum rule and error catalog are in `SPEC.md`.

## Usage

```xi
use xiom.gcode;
use xiom.io; use xiom.convert;

fn main() -> Int {
  let r = gcode_parse("N10 G1 X10.5 Y-3 ; lead-in\nN11 G1 X20.0\n");
  if !r.is_ok {
    io.println(r.error);      // e.g. "gcode: line 2: bad number: Y"
    return 1;
  }
  let p: GcodeProgram = r.value;
  var i = 0;
  while i < gcode_command_count(&p) {
    let l = gcode_program_line(&p, i);
    io.println(gcode_emit(&l));   // N10 G1 X10.5 Y-3
    i = i + 1;
  }
  return 0;
}
```

## Error model

Every parse error is a deterministic `Str` starting with `gcode: `.
`gcode_parse_line` reports line-local details; `gcode_parse` wraps them as
`gcode: line <n>: <detail>` with the 1-based physical line number (blank and
comment-only lines included). Details: `bad line number`,
`bad number: <word>`, `number too large: <word>`,
`too many fraction digits: <word>`, `bad checksum`,
`checksum mismatch: <hh>`, `unterminated paren comment`,
`trailing garbage`, `unexpected character at <pos>`, `missing command`.
`gcode_micro` reports `gcode: bad scale` and `gcode: value out of range`.
Blank lines are not errors: they are documented as skipped by `gcode_parse`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.gcode
```

Expected tail: 23 `[PASS]` lines, `xiom.gcode: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No motion semantics:** `G0`/`G1`/`M3`/`T1` are opaque words. There is no
  modal state, no coordinate interpretation, no arc interpolation and no
  validation of which letters are valid commands.
- **Positional command rule:** the first word after the optional line number
  is always the command; a line without one is a `missing command` error.
  Only the first word can be the line number; later `N` words are ordinary
  parameters.
- **Comments and checksums are not retained:** the model has no comment text
  and `gcode_emit` never emits a checksum, so a parsed line round-trips
  structurally but not byte-for-byte when it had comments or a suffix.
- **ASCII only:** the scanner is byte-wise; multi-byte UTF-8 is never decoded
  and never accepted as a digit or letter.
- **No nesting or escapes:** the first `)` closes a paren comment, and there
  is no way to put `)` inside one.
- **Documented number limits:** magnitude must fit the signed 64-bit range
  and scale is capped at 18 fraction digits; extra digits are errors, not
  rounded or truncated. `gcode_micro` truncates toward zero.
- **LF-separated lines only:** `gcode_parse` splits on LF and tolerates a CR
  before it; a lone CR does not start a new line (it is whitespace).

See `SPEC.md` for the exact grammar, checksum rule, scaling contract, error
catalog and test matrix. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
