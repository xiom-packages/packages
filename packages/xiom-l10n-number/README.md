# xiom.l10n.number

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Locale-style integer and decimal formatting, rounding and parsing
> on a scaled-integer model.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.convert.int_to_string`). Tests additionally
> use `xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`.

## Scope

A locale here is exactly a `(group_sep, decimal_sep)` pair: the caller passes
the separators (`","`/`"."`, `"."`/`","`, `" "`/`","`, ...), so there is no
locale database and no global state.

The number model is a **scaled integer**: `scaled` with `decimals` fraction
digits denotes the value `scaled / 10^decimals`. `12345` with `decimals=2` is
`123.45`; there is no `Float64` anywhere in the module, so every operation is
exact and reproducible. The module covers:

- grouping integers in threes (`1000` -> `1,000`, negatives and the 64-bit
  minimum included);
- fixed-decimal formatting with zero padding (`5`, 3 -> `0.005`), never
  rounding behind the caller's back;
- rescaling with round-half-away-from-zero (`12355`, 2 -> 0 digits -> `124`);
- parsing localized text back to a scaled integer, ignoring `,` `_` and space
  grouping and rejecting malformed input with a stable `Err("l10n: ...")`
  catalog;
- permille rendering as a percent-like number (`12345` -> `1234.5`).

## API

| Function | Returns | Description |
|---|---|---|
| `l10n_int_format(value, group_sep)` | `Str` | Sign (when negative) plus digits in groups of three separated by `group_sep`; empty `group_sep` disables grouping. `0` -> `"0"`; exact for `Int::MIN`. |
| `l10n_decimal_format(scaled, decimals, group_sep, decimal_sep)` | `Str` | `scaled`'s last `decimals` digits as the zero-padded fraction, grouped integer part, sign emitted once. `decimals <= 0` is plain integer formatting; no rounding or carry. |
| `l10n_decimal_round(scaled, from_decimals, to_decimals)` | `Int` | Rescale to a smaller fraction-digit count, rounding halves away from zero; `to_decimals >= from_decimals` returns `scaled` unchanged; both counts clamp to `>= 0`. |
| `l10n_decimal_parse(text, decimal_sep, decimals)` | `Result[Int, Str]` | Parse optional sign, ASCII digits, one optional `decimal_sep` and ignored `,`/`_`/space groups; shorter fractions right-pad with zeros. `Err("l10n: ...")` on too many fraction digits or malformed text. |
| `l10n_permille_format(permille, decimals, group_sep, decimal_sep)` | `Str` | `permille / 10` with exactly `decimals` fraction digits; `decimals = 0` rounds half away from zero to whole percent; never overflows. |

`l10n_int_format` and `l10n_decimal_format` never fail. The full error catalog
and the exact rounding algorithm are in `SPEC.md`.

## Usage

```xi
use xiom.l10n.number;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  io.println(l10n_int_format(1234567, ","));                       // 1,234,567
  io.println(l10n_decimal_format(12345, 2, ".", ","));             // 123,45
  io.println(convert.int_to_string(l10n_decimal_round(12355, 2, 0))); // 124
  io.println(l10n_permille_format(-12345, 1, ",", "."));           // -1,234.5
  match l10n_decimal_parse("1_234.50", ".", 2) {
    Ok(v) => { io.println(convert.int_to_string(v)); },             // 123450
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.l10n.number
```

Expected tail: 30 `[PASS]` lines, `xiom.l10n.number: all tests passed`, then
`port: PASS (passed=30 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Scaled-integer model:** values are `Int` scaled by a power of ten; no
  floating point, no decimals larger than 18 digits of integer magnitude, and
  the parser accepts only magnitudes up to `2^63 - 1` (`-2^63` is rejected as
  `l10n: number too large` because the magnitude is accumulated positively).
- **ASCII only:** input digits must be ASCII; the ignored grouping set is
  exactly `,`, `_` and space. Non-ASCII bytes in `text` are parse errors.
  Output separators may be any string.
- **No locale databases:** no CLDR, no currency or percent symbols, no Indian
  2-2-3 grouping, no bidi/Arabic digits, no plural rules -- the caller owns the
  locale pair.
- Grouping repeats every three digits indefinitely; no space-before-percent,
  no significant-digit or scientific notation, no exponent parsing.
- `l10n_decimal_format` never rounds: `123.456` with 2 decimals must be
  rounded explicitly with `l10n_decimal_round` first (this is deliberate).
- Compiler note: `Ok`/`Err` are constructed only in the leaf helpers
  `_parse_ok`/`_parse_err` (v0.61.3 miscompiles inline `Result` construction in
  struct-returning functions); `Str` equality in the tests always goes through
  `xiom.string.compare.str_compare` (BUG 17 family).

See `SPEC.md` for the exact semantics, rounding rules, error catalog and test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
