# xiom.l10n-unit -- specification

Package `xiom.l10n-unit`, module `xiom.l10n.unit`, version 0.1.0.
All conversion arithmetic is signed 64-bit integer arithmetic on fixed-point
micro-unit values. No floating point is used at any point.

## 1. Scope and non-goals

In scope:

- an embedded table of 82 units in 13 categories (section 2);
- exact rational conversion between units of the same category, including
  affine temperature scales (section 4);
- lookup by symbol and by category+index (section 5);
- parse and format of simple `<number> <symbol>` strings (section 6);
- typed errors with byte offsets for malformed text (section 7).

Out of scope for 0.1.0: locale-aware labels/plurals (a formatter concern, not
a conversion concern), SI-prefix generation beyond the listed symbols,
currency and arbitrary-precision numbers (see `xiom.l10n-currency` and
`xiom.l10n-number`), and value-plus-uncertainty arithmetic.

## 2. Data model

### 2.1 Unit row

```xiom
pub type Unit = {
  category: Int;   // 0..12, see section 2.2
  symbol: Str;     // canonical, case-sensitive ASCII, unique in the table
  name: Str;       // English name, unique in the table
  num: Int;        // rational factor to the category base, base = value*num/den
  den: Int;        // positive, never zero
  offset: Int;     // affine offset in micro-units of this unit (0 outside temperature)
}
```

Invariants (enforced by the table-integrity test):

1. `num > 0`, `den > 0` for every row;
2. `symbol` is non-empty and unique byte-for-byte;
3. `offset == 0` unless `category == 3` (temperature);
4. global index order is category order: length 0..9, mass 10..16,
   time 17..24, temperature 25..27, volume 28..35, area 36..41, speed
   42..45, pressure 46..52, energy 53..59, power 60..63, data 64..73,
   angle 74..77, frequency 78..81.

### 2.2 Categories and bases

| Index | Name | Base | Rows | `num/den` to base |
|-------|------|------|------|-------------------|
| 0 | length | m | 10 | `value_m * num/den` |
| 1 | mass | kg | 7 | `value_kg * num/den` |
| 2 | time | s | 8 | `value_s * num/den` |
| 3 | temperature | K | 3 | affine, section 4.2 |
| 4 | volume | l | 8 | `value_l * num/den` |
| 5 | area | m2 | 6 | `value_m2 * num/den` |
| 6 | speed | m/s | 4 | `value_mps * num/den` |
| 7 | pressure | Pa | 7 | `value_Pa * num/den` |
| 8 | energy | J | 7 | `value_J * num/den` |
| 9 | power | W | 4 | `value_W * num/den` |
| 10 | data | bit | 10 | `value_bit * num/den` |
| 11 | angle | rad | 4 | `value_rad * num/den` |
| 12 | frequency | Hz | 4 | `value_Hz * num/den` |

### 2.3 Values and measurements

A value is `Int` in micro-units: `value_micro = value * 10^6`. Six fraction
digits are the resolution of the model. A parsed measurement is:

```xiom
pub type Measurement = { symbol: Str; value_micro: Int; }
```

## 3. The table

Exactly reduced factors; provenance in section 3.14. `offset` is listed only
where non-zero.

### 3.1 length (base m)

```
m     meter          1/1          mi   mile          201168/125
km    kilometer      1000/1       yd   yard          1143/1250
cm    centimeter     1/100        ft   foot          381/1250
mm    millimeter     1/1000       in   inch          127/5000
um    micrometer     1/1000000    nmi  nautical mile 1852/1
```

### 3.2 mass (base kg)

```
kg  kilogram  1/1          lb  pound   45359237/100000000
g   gram      1/1000       oz  ounce   45359237/1600000000
mg  milligram 1/1000000    st  stone   317514659/50000000
t   tonne     1000/1
```

### 3.3 time (base s)

```
s   second      1/1         min minute 60/1
ms  millisecond 1/1000      h   hour   3600/1
us  microsecond 1/1000000   d   day    86400/1
ns  nanosecond  1/1000000000 wk week   604800/1
```

### 3.4 temperature (base K)

```
K     kelvin             1/1   offset 0
degC  degree Celsius     1/1   offset 273150000
degF  degree Fahrenheit  5/9   offset 459670000
```

### 3.5 volume (base l)

```
l       liter            1/1             pt-US   US pint          473176473/1000000000
ml      milliliter       1/1000          floz-US US fluid ounce   473176473/16000000000
m3      cubic meter      1000/1          gal-UK  imperial gallon  454609/100000
gal-US  US gallon        473176473/125000000
qt-US   US quart         473176473/500000000
```

### 3.6 area (base m2)

```
m2   square meter      1/1            acre acre          316160658/78125
km2  square kilometer  1000000/1      ft2  square foot   145161/1562500
ha   hectare           10000/1        in2  square inch   16129/25000000
```

### 3.7 speed (base m/s)

```
m/s   meter per second     1/1      mph  mile per hour  1397/3125
km/h  kilometer per hour   5/18     kn   knot           463/900
```

### 3.8 pressure (base Pa)

```
Pa   pascal                   1/1               atm  standard atmosphere 101325/1
kPa  kilopascal               1000/1            psi  pound per square inch 8896443230521/1290320000
bar  bar                      100000/1          mmHg millimeter of mercury 26664477483/200000000
mbar millibar                 100/1
```

### 3.9 energy (base J)

```
J    joule                 1/1               BTU  British thermal unit 52752792631/50000000
kJ   kilojoule             1000/1            eV   electronvolt         1/6241509074460762607 (see 8.2)
cal  calorie               523/125
kcal kilocalorie           4184/1
kWh  kilowatt hour         3600000/1
```

### 3.10 power (base W)

```
W   watt        1/1            hp  horsepower  37284993579113511/50000000000000
kW  kilowatt    1000/1         MW  megawatt    1000000/1
```

### 3.11 data (base bit)

```
bit bit      1/1           MB  megabyte  8000000/1        TB  terabyte  8000000000000/1
B   byte     8/1           MiB mebibyte  8388608/1        TiB tebibyte  8796093022208/1
KB  kilobyte 8000/1        GB  gigabyte  8000000000/1
KiB kibibyte 8192/1        GiB gibibyte  8589934592/1
```

### 3.12 angle (base rad)

```
rad   radian   1/1                    grad  gradian  122925461/7825677900
deg   degree   122925461/7043110110   turn  turn     491701844/78256779
```

### 3.13 frequency (base Hz)

```
Hz  hertz      1/1             MHz megahertz 1000000/1
kHz kilohertz  1000/1          GHz gigahertz 1000000000/1
```

### 3.14 Provenance

- SI exact: km, cm, mm, um, m, m3, l, ml, ha, km2, m2, s-prefixes, min, h,
  d, wk, kg-prefixes, t, kPa, bar, mbar, atm, Pa, kJ, kWh, cal (4.184 J
  thermochemical), kcal, W prefixes, data decimal (KB = 1000 B) and binary
  (KiB = 1024 B) chains, frequency prefixes.
- Definitional exact decimals: in = 0.0254 m; ft, yd; mi = 1609.344 m;
  nmi = 1852 m; lb = 0.45359237 kg; oz = lb/16; st = 14 lb; gal-US =
  3.785411784 l; qt-US = gal/4; pt-US = qt/2; floz-US = gal/128;
  gal-UK = 4.54609 l; acre = 4046.8564224 m2; ft2 = ft^2; in2 = in^2;
  mph = mi/h; kn = nmi/h; BTU(IT) = 1055.05585262 J; mmHg = 133.322387415 Pa.
- Derived exact: psi = lbf/in2 with lbf = lb * g0, g0 = 9.80665 m/s2 exactly,
  1 lbf = 4.4482216152605 N; hp = 550 ft*lbf/s.
- Approximations: pi (section 8.1) and eV (section 8.2).

## 4. Conversion math

### 4.1 Linear units

For units of one category with factors `fn/fd` (origin) and `tn/td`
(target), the documented formula is:

```
out = value_micro * fn * td / (fd * tn)
```

evaluated exactly and truncated toward zero at the single division. The
implementation first reduces the cross-ratio `(fn*td)/(fd*tn)` by pairwise
gcd (four pairwise cancellations then a final gcd), producing `rn/rd`, and
computes:

```
out = trunc(value_micro * rn / rd)
```

Reducing before multiplying is mathematically identical (the fraction value
is unchanged) and is what keeps products such as kWh -> J (ratio 3600000,
full factor `4831838208000000000/1342177280`) exact rather than overflowing.

### 4.2 Affine temperature

Temperature rows carry the offset applied in the *source* unit, before the
rational factor:

```
out = trunc((value_micro + from.offset) * rn / rd) - to.offset
```

so for `degC -> K`: `out = (value + 273150000) * 1/1`, and for
`degF -> K`: `out = (value + 459670000) * 5/9`. Anchors, all exact:

| input | path | output |
|-------|------|--------|
| 0 degC | `(0 + 273150000) * 1` | 273150000 micro-K (273.15 K) |
| 100 degC | `(1e8 + 273150000) * 1` | 373150000 micro-K |
| 32 degF | `(32000000 + 459670000) * 5/9` | 0 micro-degC |
| 212 degF | `(212000000 + 459670000) * 5/9` | 100000000 micro-degC |
| -40 degF | `(-4e7 + 459670000) * 5/9` | -40000000 micro-degC |
| -273.15 degC | `(-273150000 + 273150000) * 1` | 0 micro-K |
| -459.67 degF | `(-459670000 + 459670000) * 5/9` | 0 micro-K |

`from == to` with an offset cancels exactly: `(v + o) - o == v`.

### 4.3 Checked arithmetic and overflow

Every step is overflow-checked; a failure returns
`Err("l10n-unit: conversion overflow")`, never a wrapped value:

1. offset addition: `|value + offset| <= Int.MAX`;
2. offset subtraction: `out - to.offset` representable;
3. multiplication: `|a * b| <= Int.MAX` tested before multiplying, with a
   separate `Int.MIN` guard (the magnitude of `Int.MIN` has no positive
   counterpart);
4. when the direct product of the reduced pair does not fit, the exact
   staged identity `trunc((q*rd + r) * rn / rd) = q*rn + trunc(r*rn/rd)`
   (with `q = value/rd`, `r = value%rd`) is used; if that also overflows the
   conversion fails closed.

The conformance suite pins the boundary: `9223372036854775 m -> mm`
succeeds (`9223372036854775000`), `9223372036854776 m -> mm` fails.

## 5. Lookup semantics

- `l10n_unit_by_symbol(symbol)`: byte-for-byte, case-sensitive equality over
  the 82 rows; `""` is `"l10n-unit: bad symbol: "`, a well-formed but absent
  symbol is `"l10n-unit: unknown unit: <symbol>"`. Because `M` is not the
  meter and `MM` is not the millimeter, both are errors.
- `l10n_unit_by_symbol_in_category(category, symbol)`: same, restricted to
  one category; a known symbol from another category yields
  `"l10n-unit: unknown unit in <category-name>: <symbol>"` (e.g. `m` in
  `mass`).
- `l10n_unit_at(index)`: global row 0..81.
- `l10n_unit_at_in_category(category, index)`: within-category row; the
  category start table is section 2.2.
- Every row is reachable by symbol and by both index routes; the integrity
  test checks all three.

## 6. Parse and format

### 6.1 Parse grammar

```
text   := ws* sign? number ws* symbol ws*
sign   := '+' | '-'
number := digits ('.' digits?)? | '.' digits
```

- The integer part may be empty when a fraction is present (`.5`).
- Digits beyond the sixth fraction digit are validated but TRUNCATED:
  `1.0000009 m` is `1000000` micro-m. This is the documented truncation
  rule, not a rounding rule.
- `-0` is 0 (the sign is dropped when the magnitude is zero).
- The symbol is the remaining non-space text; it must equal a table symbol
  byte-for-byte (section 5).

### 6.2 Format rule

`l10n_unit_format(value_micro, symbol)` renders the sign, the integer part,
and up to six fraction digits with trailing zeros trimmed, then one space
and the symbol: `12500000, "km/h"` -> `"12.5 km/h"`; `1, "m"` ->
`"0.000001 m"`; `-500000, "h"` -> `"-0.5 h"`; `0, "m"` -> `"0 m"`.

## 7. Error catalog

All errors are `Err(Str)` with a stable `l10n-unit: ` prefix. Byte offsets
are 0-based byte positions in the input string.

| Message | Trigger |
|---------|---------|
| `l10n-unit: empty input` | `l10n_unit_parse("")` |
| `l10n-unit: no digits at byte <n>` | no digit before the symbol, or whitespace-only input |
| `l10n-unit: unexpected character at byte <n>` | reserved; currently surfaced as `no digits` or `unknown unit` for the same inputs |
| `l10n-unit: multiple decimal separators at byte <n>` | second `.` in the number |
| `l10n-unit: number too large at byte <n>` | integer part does not fit `Int/10^6` |
| `l10n-unit: missing unit at byte <n>` | number present, symbol empty after trimming |
| `l10n-unit: unknown unit: <symbol> at byte <n>` | remainder is not a table symbol |
| `l10n-unit: bad symbol: ` | empty symbol passed to a lookup/format |
| `l10n-unit: unknown unit: <symbol>` | symbol not in the table (lookup/format/convert) |
| `l10n-unit: unknown unit in <category>: <symbol>` | symbol not in the requested category |
| `l10n-unit: category out of range: <n>` | category not in 0..12 |
| `l10n-unit: index out of range: <n>` | row index out of range |
| `l10n-unit: category mismatch: <a> (<ca>) -> <b> (<cb>)` | conversion across categories |
| `l10n-unit: conversion overflow` | checked arithmetic would exceed `Int` |
| `l10n-unit: bad unit row` | invalid row handed to `l10n_unit_convert` |
| `l10n-unit: bad unit factor: <symbol>` | non-positive factor in a row (internal guard) |
| `l10n-unit: bad denominator: <n>` | non-positive denominator in `_mul_div` (internal guard) |
| `l10n-unit: value out of range` | formatting `Int.MIN` (magnitude not representable) |

Note: `unexpected character` is part of the catalog for API stability; the
current grammar consumes any non-digit/non-dot byte as the start of the
symbol tail, so malformed numbers in the number position surface as
`no digits` and malformed tails as `unknown unit`. A future revision may
tighten the number scanner without changing the message set.

## 8. Documented approximations

### 8.1 pi (angle)

`deg`, `grad`, `turn` require pi. The table uses the convergent
`pi ~ 245850922/78256779` (relative error ~1.3e-17). Exact consequences:
`turn -> deg` is exactly 360, `turn -> grad` exactly 400, `grad -> deg`
exactly 0.9, so those conversions are exact; only `rad` bridges carry the
approximation. `180 deg -> rad` is `3141592` micro-rad (pi truncated at the
micro boundary), `90 deg -> rad` is `1570796`.

### 8.2 eV (energy)

`1 eV = 1.602176634e-19 J` exactly equals `1602176634/10^28`; the reduced
form is `801088317/5*10^27`, whose denominator exceeds `Int`. The table
therefore stores the truncated reciprocal `1/6241509074460762607` (the
integer part of `10^28/1602176634`), relative error below `1.6e-19`.
Consequences, both tested:

- `1 eV -> J` truncates to `0` micro-J (the true value is 1.6e-13 micro-J);
- `J -> eV` overflows for ordinary magnitudes (`1 J` would need ~6.24e18
  micro-eV per micro-J, so the ratio's numerator alone overflows for
  `|value| >= 2`);
- converting exactly `6241509074460762607` micro-eV to `J` yields
  `1` micro-J, the boundary where the stored reciprocal is meaningful.

## 9. Verification

`tests/test_conformance.xi` (24 checks, all `[PASS]`) covers: metadata and
counts; index and symbol lookups including case-sensitivity and in-category
errors; row accessors; the required fixtures `mi -> km`, `lb -> kg`,
`gal-US -> l`, `GiB -> B`, `psi -> kPa`; mass/volume/data/pressure/energy/
power/time/speed/area/frequency/angle snapshots; affine temperatures at
0/100 degC, 32/212/-40 degF and both absolute-zero anchors; round trips
(exact where the ratio is exact, <= 9 micro where truncation applies); the
overflow boundary pair; category mismatch and unknown-symbol messages;
parse/format round trips and every byte-offset parse error; and a full table
integrity walk (82 rows, unique symbols, positive factors, positive
denominators, offsets only on temperature). Run it with:

```
& .\scripts\port.ps1 -Package xiom.l10n-unit
```
