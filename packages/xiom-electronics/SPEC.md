# xiom.electronics -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.electronics` (`src/electronics.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std` only (`xiom.string.compare.str_compare`).

## 1. Scope

Integer-only helpers for common resistor/divider/LED calculations:

- resistor color-band decoding (3 and 4 bands),
- single-band digit/multiplier/tolerance lookup,
- the E24 nominal series and a decade-scaled "nearest nominal" snap,
- unloaded voltage dividers,
- LED series-resistor sizing.

## 2. Non-goals

- Floats: every public value is an `Int`; there is no `Float64` API.
- 5/6-band codes, gold/silver multiplier bands, temperature coefficients.
- Capacitors, amplifiers, logic gates or network analysis (the placeholder
  "libs inventory" is not part of this port).
- Physical modelling beyond the formulas below (power rating, load current,
  temperature drift, E-series beyond E24).
- Any FFI, file I/O, or registry integration.

## 3. Units and conventions

| Quantity | Unit | Notes |
|---|---|---|
| Resistance | ohm | integer |
| Tolerance | permille | 1 permille = 0.1%; `green` = 0.5% = 5 permille |
| Voltage | millivolt (mV) | `electron_voltage_divider_mv`, `electron_led_resistor_ohm` inputs |
| Current | microamp (uA) | `electron_led_resistor_ohm` input |

Color names are lowercase ASCII; lookups are exact (no trimming, no case
folding). `gray` is an alias of `grey` for the digit 8.

## 4. Color tables

Digit band (`electron_color_digit`):

| Color | Digit | | Color | Digit |
|---|---|---|---|---|
| black | 0 | | blue | 6 |
| brown | 1 | | violet | 7 |
| red | 2 | | grey / gray | 8 |
| orange | 3 | | white | 9 |
| yellow | 4 | | *anything else* | `None` |
| green | 5 | | | |

Multiplier band (`electron_color_multiplier`): the same ten digit colors,
interpreted as decade exponents 0..9 (`red` => x100). `gold` (-1) and
`silver` (-2) are accepted by no function as multipliers and return `None`.

Tolerance band (`electron_resistor_tolerance`), returned in permille:

| Color | Standard | Permille |
|---|---|---|
| brown | 1% | 10 |
| red | 2% | 20 |
| gold | 5% | 50 |
| silver | 10% | 100 |
| green | 0.5% | 5 |
| anything else (incl. grey/gray) | -- | `None` |

The tolerance color set is `{brown, red, gold, silver, green}`; it is the set
validated for a 4-band resistor's fourth band. Note `green` is both a digit
color and a tolerance color.

## 5. Formulas

### 5.1 Resistor value (`electron_resistor_value`)

```
3 bands: value = (d1 * 10 + d2) * 10^m
4 bands: value = (d1 * 10 + d2) * 10^m          (band 4 is tolerance, not value)
          bands[3] must be a tolerance color
```

`d1`, `d2` are digit lookups of bands 1-2; `m` is the multiplier lookup of
band 3. Examples: `brown black red` => 1000 ohm; `red violet brown` => 270
ohm; `brown black black` => 10 ohm; `white white white` => 99 * 10^9 ohm
(= 99 Gohm, the maximum).

### 5.2 E24 series (`electron_e24_values`)

The 24 base-decade nominals, ascending, in this exact order:

```
10 11 12 13 15 16 18 20 22 24 27 30 33 36 39 43 47 51 56 62 68 75 82 91
```

### 5.3 Nearest E24 (`electron_nearest_e24`)

For `value >= 10`:

1. find the largest power of ten `scale = 10^k` such that
   `value / scale` (integer division) is in `[10, 100)`;
2. let `mantissa = value / scale`;
3. pick the nominal `n` in the E24 table with the smallest `|n - mantissa|`;
   if two nominals are equidistant (`(a + b)` even, `mantissa` the midpoint)
   the **larger** nominal wins;
4. return `n * scale`.

Because the search stays inside the decade, values above the decade top
clamp to `91 * scale`, e.g. `999` -> `910` and `99999` -> `91000`.

Values `< 10` (including 0 and negative inputs) pass through unchanged: the
integer model covers the decades from 10 ohm up.

Rounding summary: no round-half-up; the tie rule is "half to larger".

### 5.4 Voltage divider (`electron_voltage_divider_mv`)

```
total = r1 + r2
output_mv = 0                    if total == 0
          = vin_mv * r2 / total  otherwise (truncating integer division)
```

Division truncates toward zero for negative operands as well (the expression
is evaluated with normal `Int` semantics; no clamping of inputs).

### 5.5 LED series resistor (`electron_led_resistor_ohm`)

```
error "electronics: current must be positive"        if current_ua <= 0
error "electronics: supply must exceed forward voltage" if supply_mv <= forward_mv
ok((supply_mv - forward_mv) * 1000 / current_ua)     otherwise
```

The factor 1000 converts mV/uA to ohm: `(mV * 1000) / uA = ohm`. The current
check runs first, so a call that violates both constraints reports the
current error. Division truncates toward zero.

## 6. Error catalog

`electron_resistor_value`:

| Condition | Message |
|---|---|
| `bands.len()` not 3 and not 4 | `electronics: resistor bands must be 3 or 4` |
| band 1/2 not a digit color, band 3 not a digit color (gold/silver included), or band 4 (4-band only) not a tolerance color | `electronics: unknown color code` |

`electron_led_resistor_ohm`:

| Condition | Message |
|---|---|
| `current_ua <= 0` | `electronics: current must be positive` |
| `supply_mv <= forward_mv` | `electronics: supply must exceed forward voltage` |

No other public function returns `Err`; `None` from the `Option` lookups is
not an error but a "not a color in this position" answer.

## 7. API signatures

```xi
pub fn electron_color_digit(color: Str) -> Option[Int]
pub fn electron_color_multiplier(color: Str) -> Option[Int]
pub fn electron_resistor_value(bands: &Vec[Str]) -> Result[Int, Str]
pub fn electron_resistor_tolerance(color: Str) -> Option[Int]
pub fn electron_e24_values() -> Vec[Int]
pub fn electron_nearest_e24(value: Int) -> Int
pub fn electron_voltage_divider_mv(vin_mv: Int, r1_ohm: Int, r2_ohm: Int) -> Int
pub fn electron_led_resistor_ohm(supply_mv: Int, forward_mv: Int, current_ua: Int) -> Result[Int, Str]
```

All functions are O(1) (`electron_e24_values` builds 24 entries) and
deterministic; none of them allocate beyond their return value.

## 8. Test plan

`tests/test_conformance.xi` (module `electronics_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | digit codes | all ten colors 0..9 + gray alias |
| t2 | digit rejects | unknown, uppercase, padded, empty |
| t3 | multipliers | ten decades; gold/silver rejected |
| t4 | 3-band values | 1000 / 270 / 10 ohm |
| t5 | 3-band more | 56k, 47k, zero, 68 Gohm |
| t6 | 4-band tolerance ignored | all five tolerance colors give 1000 |
| t7 | 4-band more | first three bands only |
| t8 | unknown color Err | digit, multiplier and tolerance positions |
| t9 | band count Err | 0, 1, 2 and 5 bands |
| t10 | tolerance map | permille 10/20/50/100/5 + non-colors |
| t11 | E24 shape | 24 values, first 10, last 91 |
| t12 | E24 membership | element-wise vs the canonical table |
| t13 | E24 order | strictly ascending |
| t14 | nearest exact | nominals unchanged across decades |
| t15 | nearest between | rounds to the closer nominal |
| t16 | nearest ties | ties resolve to the larger nominal |
| t17 | nearest scaling | decade scaling + decade-top clamp |
| t18 | nearest < 10 | pass-through incl. 0 and negative |
| t19 | divider equal | halves the input (incl. 0 V) |
| t20 | divider extremes | 0 mV and 8999 mV truncation cases |
| t21 | divider zero total | 0 mV, no division by zero |
| t22 | LED known cases | 150/290/130/200/10000 ohm |
| t23 | LED errors | both messages, current checked first |
| t24 | large values | 99 Gohm, 91 Gohm snap, large divider/LED |

Element comparisons route every `Str` through `str_compare` (BUG 17: `==` on
`Str` values read from `Vec[Str]` lowers to a pointer comparison). `Vec[Int]`
element reads use typed `let` bindings. Every test calls the public API; the
`Err` strings are compared exactly.

## 9. Known limitations

- 3/4-band only (no 5/6-band, no gold/silver multipliers, no tempco band).
- Integer truncation everywhere; results are exact only for values that
  divide evenly (documented in section 5).
- Nearest-E24 is defined from 10 ohm up; below that values pass through.
- The divider is unloaded and tolerance-blind.
- No unit conversion, no parsing/formatting of values.

## 10. Compiler / stdlib notes

Built against XIOM v0.61.3. No compiler workarounds were required beyond the
module's discipline:

- `Ok`/`Err` construction lives only in the tiny `_ok_int`/`_err_int` leaf
  helpers (constructing `Result`s inline elsewhere is known to miscompile).
- Color tables are if-chains, not `match` on `Str`; every `match` on
  `Option` has both `Some` and `None` arms (non-exhaustive matches are a
  hard error).
- All `Str` comparisons go through `str_compare`; no `==` on `Str`.
- Integer math only; the test file reads `Vec[Int]` elements with typed
  `let` bindings and never uses `Vec[fn]` dispatch (tests are called
  explicitly from `main`).
