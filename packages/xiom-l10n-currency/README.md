# xiom.l10n-currency

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.2` on the XIOM registry.
> **Scope:** embedded ISO 4217 currency table (165 codes), lookups by alpha /
> numeric / name / symbol, and exact integer minor-unit amount parsing,
> formatting and half-up rounding.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`).

## What it is

`xiom.l10n-currency` carries money as an exact integer count of minor units --
never a float -- and resolves the currency metadata from an embedded table:

- **Table.** 165 rows from the ISO 4217 "List One" published 2026-09-17,
  each with alpha code, zero-padded 3-digit numeric code, minor-unit exponent
  (0/2/3/4), English name and a best-effort prefix symbol for majors. The
  cut-off excludes the 13 active codes whose minor units are `N.A.` (XAU,
  XAG, XPT, XPD, XDR, XBA, XBB, XBC, XBD, XSU, XUA, XTS, XXX): they have no
  minor-unit semantics, so parse/format cannot be defined for them. Every
  excluded code fails with `unknown currency` (see SPEC.md).
- **Lookups.** `l10n_currency_by_alpha` (case-insensitive), `by_numeric`
  (zero-padded 3-digit match), `by_name` (English ISO name, ASCII
  case-insensitive), `by_symbol`, plus `is_valid`, `at`/`count` for
  iteration, and the `alpha` <-> `numeric` cross-check helper.
- **Amounts.** `Money` is `{ alpha; minor; exponent }`; a USD 12.34 amount is
  `minor = 1234`. `l10n_currency_parse_amount` reads localized text with an
  explicit decimal and grouping separator, an optional leading symbol or
  alpha code, sign handling, and rejects fraction digits beyond the
  currency's exponent. `l10n_currency_format_amount` renders minor units
  back with a grouping separator, symbol or code, leading-minus or
  parenthesized negatives, and exponent-aware zero padding.
- **Rounding.** `l10n_currency_round_half_up` rescales extra-precision
  amounts to fewer fraction digits, with halves away from zero for both
  signs (explicit sign handling; truncating division is never trusted).
  `l10n_currency_round_to_currency` is the per-currency convenience.

Everything is deterministic and locale-free: a "locale" is the caller's
`(group_sep, decimal_sep)` pair, not a database row.

## Install / use

```
xiom pkg install xiom.l10n-currency@0.1.0
```

Note on names: the package manifest name is `xiom.l10n-currency`, but the
importable module is `xiom.l10n.currency` (compiler v0.61.3 rejects `-` in
`module` declarations, error[P001]).

```xi
use xiom.l10n.currency;
use xiom.io;

match l10n_currency_by_alpha("usd") {
  Ok(c) => {
    let cur = c;
    io.println(cur.name);                       // "US Dollar"
    io.println(cur.numeric);                    // "840"
    match l10n_currency_parse_amount("$1,234.56", &cur, ".", ",") {
      Ok(m) => {
        io.println(l10n_currency_money_minor(&m));   // 123456
        match l10n_currency_format_amount(&m, ",", ".", true, false) {
          Ok(s) => { io.println(s); },               // "$1,234.56"
          Err(e) => { io.println(e); },
        }
      },
      Err(e) => { io.println(e); },             // "l10n-currency: ... at byte N"
    }
  },
  Err(e) => { io.println(e); },
}
```

Other one-liners:

```xi
// de-DE style round-trip: "1.234,56" in, "1.234,56" out
l10n_currency_parse_amount_code("1.234,56", "eur", ",", ".");     // Ok(minor=123456)
// lookups
l10n_currency_by_numeric("392");            // Ok(Yen, exponent 0)
l10n_currency_by_name("Indian Rupee");      // Ok(INR)
l10n_currency_by_symbol("₩");               // Ok(KRW)
l10n_currency_cross_check("USD", "840");    // true
// extra precision down to minor units
l10n_currency_round_half_up(123456, 4, 2);  // 1235  (12.3456 -> 12.35)
l10n_currency_round_half_up(-25, 1, 0);     // -3    (halves away from zero)
```

## API

All functions are free functions in module `xiom.l10n.currency`:

| Function | Returns | Description |
|---|---|---|
| `l10n_currency_count()` | `Int` | Number of embedded rows (165). |
| `l10n_currency_at(index)` | `Result[Currency, Str]` | Row by index `0..count-1`; out-of-range is an error. |
| `l10n_currency_by_alpha(code)` | `Result[Currency, Str]` | Case-insensitive alpha lookup; malformed vs unknown errors. |
| `l10n_currency_by_numeric(code)` | `Result[Currency, Str]` | Exact zero-padded 3-digit numeric lookup. |
| `l10n_currency_by_name(name)` | `Result[Currency, Str]` | English ISO name, ASCII case-insensitive. |
| `l10n_currency_by_symbol(symbol)` | `Result[Currency, Str]` | Prefix symbol; table symbols are unique. |
| `l10n_currency_is_valid(code)` | `Bool` | `true` iff `by_alpha` accepts `code`. |
| `l10n_currency_cross_check(alpha, numeric)` | `Bool` | `true` iff the alpha row's numeric is exactly `numeric`. |
| `l10n_currency_parse_amount(text, cur, decimal_sep, group_sep)` | `Result[Money, Str]` | Exact integer parse; errors carry byte offsets. |
| `l10n_currency_parse_amount_code(text, alpha, decimal_sep, group_sep)` | `Result[Money, Str]` | Same, resolving the currency by alpha first. |
| `l10n_currency_format_amount(m, group_sep, decimal_sep, use_symbol, paren_negative)` | `Result[Str, Str]` | Render an amount; unknown `m.alpha` is an error. |
| `l10n_currency_money_alpha(m)` / `_minor(m)` / `_exponent(m)` | `Str` / `Int` / `Int` | Accessors on a parsed amount. |
| `l10n_currency_round_half_up(scaled, from_decimals, to_decimals)` | `Int` | Half-away-from-zero rescale to fewer digits. |
| `l10n_currency_round_to_currency(scaled, from_decimals, cur)` | `Result[Int, Str]` | Rescale to `cur.exponent`; refuses scale-up. |

```xi
pub type Currency = { alpha: Str; numeric: Str; exponent: Int; name: Str; symbol: Str; }
pub type Money    = { alpha: Str; minor: Int; exponent: Int; }
```

## Error model

Lookups are strict: `l10n-currency: bad currency code: <code>` (not three
ASCII letters), `l10n-currency: unknown currency: <code>` (well formed, not
in the table), `l10n-currency: bad numeric code: <code>`,
`l10n-currency: unknown numeric code: <code>`,
`l10n-currency: unknown currency name: <name>`,
`l10n-currency: bad symbol: <symbol>`,
`l10n-currency: unknown currency symbol: <symbol>`,
`l10n-currency: index out of range: <index>`.

Every positional parse error carries the byte offset of the failing byte:
`unexpected character at byte N`, `multiple decimal separators at byte N`,
`too many decimals at byte N`, `no digits at byte N`,
`number too large at byte N` (late magnitude problems report the end of the
input). The empty input is `l10n-currency: empty input`. The full catalog is
in SPEC.md.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.l10n-currency
```

Expected: 24 `[PASS]` lines and
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

Coverage: exponent classes 0/2/3/4 (17/139/7/2 rows asserted), every lookup
key including case variants and malformed/unknown errors, the table-integrity
sweep (unique alpha/numeric/symbol, 3-character widths, exponent classes,
ascending order, row counts), symbol/code prefixes, `,`/`.`/space grouping
pairs, negative and `-0`/`+` signs, parse errors with exact offsets, overflow
at both the digit scan and the scale-up step, format styles (code, symbol,
fallback, minus, parentheses, zero padding), half-up rounding including
negative edges, 19-digit drops, carries, and parse -> format round-trips.

## Limitations

- **Snapshot table.** The rows are the 2026-09-17 ISO list; later
  amendments are not picked up automatically.
- **Documented cut-off.** The 13 `N.A.` codes are `unknown currency` here
  (see the list above); so are historical codes and unofficial codes.
- **Prefix symbols only.** `symbol` is a common prefix symbol for majors
  (`$`, `€`, `£`, `¥`, `₹`, ...) and `""` otherwise; suffix symbols (`kr`,
  `zł`, `Ft`) are deliberately not stored, and formatting always places the
  symbol before the digits.
- **No locale database or CLDR.** Separators, symbol/code choice, minus vs
  parentheses and grouping are caller-supplied parameters.
- **No national cash-rounding rules.** `round_half_up` is the only rounding
  policy; cash rounding to 0.05 etc. is out of scope.
- **Financial funds codes are included, not authoritative rates.** CLF,
  UYW, BOV, COU, MXV, USN, UYI, XAD, CHE, CHW are ISO codes with exponents;
  the table says nothing about their current rate or tradability.
- **No arbitrary-precision money.** `minor` is a signed 64-bit `Int`;
  parsing refuses magnitudes that would overflow.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
