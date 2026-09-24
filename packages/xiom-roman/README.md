# xiom.roman

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Roman numeral parsing, formatting and canonical validation over
> the standard range 1..3999.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_upper` and
> `xiom.string.str_compare`). Tests additionally use `xiom.test`, `xiom.io`
> and `xiom.string.compare`.

## Scope

`xiom.roman` covers the classical Roman numeral system as used for the values
1..3999:

- **parse** case-insensitive text to an `Int`, rejecting anything that is not
  a canonical spelling (`IIII`, `VX`, `IL`, `XD`, `MMMM`, ...);
- **format** an `Int` to the unique uppercase subtractive form
  (`1994` -> `MCMXCIV`);
- **validate** canonicality: `roman_is_canonical(s)` is true only for the
  exact uppercase canonical spelling;
- expose the range limit (`roman_max() == 3999`).

All functions are free functions, total on the documented domain, and depend
only on `xiom.std`. There is no FFI, no global state and no table allocation:
the formatter walks the fixed symbol ladder documented below.

## API

| Function | Returns | Description |
|---|---|---|
| `roman_parse(s)` | `Result[Int, Str]` | Case-insensitive parse of a canonical numeral; `Ok(1..3999)` or `Err("roman: ...")`. |
| `roman_format(n)` | `Result[Str, Str]` | Uppercase canonical subtractive text for `1..3999`; `Err("roman: out of range")` otherwise. |
| `roman_is_canonical(s)` | `Bool` | True only when `s` is exactly the uppercase canonical form of its value. |
| `roman_max()` | `Int` | The largest representable value, `3999`. |

## Numerals

| Symbol | I | V | X | L | C | D | M |
|---|---|---|---|---|---|---|---|
| Value | 1 | 5 | 10 | 50 | 100 | 500 | 1000 |

Subtractive pairs (the only ones allowed): `IV` 4, `IX` 9, `XL` 40, `XC` 90,
`CD` 400, `CM` 900. Repetition limits: `M` at most 3; `I`, `X` and `C` at
most 3 and only in their own position; `V`, `L` and `D` never repeat.

| Value | Numeral | Value | Numeral |
|---|---|---|---|
| 1 | `I` | 90 | `XC` |
| 4 | `IV` | 400 | `CD` |
| 9 | `IX` | 900 | `CM` |
| 14 | `XIV` | 1994 | `MCMXCIV` |
| 40 | `XL` | 2024 | `MMXXIV` |
| 49 | `XLIX` | 3888 | `MMMDCCCLXXXVIII` |
| 3999 | `MMMCMXCIX` | | |

## Usage

```xi
use xiom.roman;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  match roman_parse("mcmxciv") {
    Ok(v) => { io.println(convert.int_to_string(v)); },   // 1994
    Err(e) => { io.println(e); },
  }
  match roman_format(2024) {
    Ok(s) => { io.println(s); },                          // MMXXIV
    Err(e) => { io.println(e); },
  }
  if roman_is_canonical("MCMXCIV") { io.println("canonical"); }
  io.println(convert.int_to_string(roman_max()));         // 3999
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.roman
```

Expected tail: 16 `[PASS]` lines, `xiom.roman: all tests passed`, then
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Standard range only:** 1..3999. There is no vinculum/overline notation
  for 4000 and above, and no zero (`nulla`).
- **Canonical spelling only:** parsing accepts the canonical form of a value
  (case-insensitively), not arbitrary additive spellings; `IIII`, `VX`, `IL`
  and `XD` are errors rather than alternative readings.
- **ASCII only:** the seven letters `I,V,X,L,C,D,M` in either case; no
  Unicode numeral characters, no combining overlines.
- No `Float64`, no fractions, no clock-face or other non-classical variants.
- `roman_is_canonical` is case-sensitive by design: a lowercase spelling is
  never canonical even when its value is valid.

See `SPEC.md` for the grammar, the validation algorithm and the exact error
catalog. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
