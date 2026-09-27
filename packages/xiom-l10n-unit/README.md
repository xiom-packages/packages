# xiom.l10n-unit

Exact integer unit conversion over an embedded rational-factor table, with
affine temperatures and fixed-point micro-unit values. No floating point is
used anywhere in the conversion path.

- **Package:** `xiom.l10n-unit`
- **Module:** `xiom.l10n.unit` (the compiler rejects `-` in `module`
  declarations, so the module drops the dash)
- **Version:** 0.1.0
- **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
  `xiom.convert`)
- **Verified:** `scripts/port.ps1` green, 24/24 conformance checks

## What this is

A unit-of-measure registry and converter for 82 units in 13 categories,
built so that conversions between exact-ratio units are exact, integer-only,
and reproducible on any machine:

| # | Category | Base | Units |
|---|----------|------|-------|
| 0 | length | m | m, km, cm, mm, um, mi, yd, ft, in, nmi |
| 1 | mass | kg | kg, g, mg, t, lb, oz, st |
| 2 | time | s | s, ms, us, ns, min, h, d, wk |
| 3 | temperature | K | K, degC, degF (affine) |
| 4 | volume | l | l, ml, m3, gal-US, qt-US, pt-US, floz-US, gal-UK |
| 5 | area | m2 | m2, km2, ha, acre, ft2, in2 |
| 6 | speed | m/s | m/s, km/h, mph, kn |
| 7 | pressure | Pa | Pa, kPa, bar, mbar, atm, psi, mmHg |
| 8 | energy | J | J, kJ, cal, kcal, kWh, BTU, eV |
| 9 | power | W | W, kW, MW, hp |
| 10 | data | bit | bit, B, KB, KiB, MB, MiB, GB, GiB, TB, TiB |
| 11 | angle | rad | rad, deg, grad, turn |
| 12 | frequency | Hz | Hz, kHz, MHz, GHz |

## Value model

Values are signed 64-bit integers in **micro-units**: a value of `12500000`
is 12.5 of that unit. Six fraction digits are therefore the resolution
(1e-6 of a unit), and every conversion truncates toward zero (see
`SPEC.md` for the exact rounding points). There are no floats, no
allocations, and no locale dependencies in the library.

## Usage

```xiom
use xiom.l10n.unit;

// 1) Convert by symbol: 12.5 miles to kilometers (micro-unit in, micro-unit out).
match l10n_unit_convert_by_symbol(12500000, "mi", "km") {
  Ok(km) => { /* 20116800 */ },
  Err(e) => { /* "l10n-unit: ..." */ },
}

// 2) Convert row to row (no symbol parsing).
let m = row("mi");     // via l10n_unit_by_symbol
let km = row("km");
let out = l10n_unit_convert(12500000, &m, &km);

// 3) Parse and format simple "<number> <symbol>" strings.
let r = l10n_unit_parse("12.5 km/h");        // Ok(Measurement), truncating to micro
let s = l10n_unit_format(12500000, "km/h");  // Ok("12.5 km/h")

// 4) Temperature is affine: 100 degC -> 212 degF.
let f = l10n_unit_convert_by_symbol(100000000, "degC", "degF"); // Ok(212000000)
```

### Public API

- Table: `l10n_unit_category_count`, `l10n_unit_count`,
  `l10n_unit_count_in_category`, `l10n_unit_category_name`,
  `l10n_unit_at`, `l10n_unit_at_in_category`
- Lookup: `l10n_unit_by_symbol` (case-sensitive), `l10n_unit_by_symbol_in_category`
- Rows: `l10n_unit_category`, `l10n_unit_symbol`, `l10n_unit_name`,
  `l10n_unit_factor_num`, `l10n_unit_factor_den`, `l10n_unit_offset`
- Conversion: `l10n_unit_convert`, `l10n_unit_convert_by_symbol`,
  `l10n_unit_base_micro`, `l10n_unit_is_compatible`
- Text: `l10n_unit_parse`, `l10n_unit_format`, `l10n_unit_parse_to`,
  `l10n_unit_measurement_symbol`, `l10n_unit_measurement_value`

## Honesty notes

- **Truncation, not rounding.** `1 micro-m` converts to `0 km`, `1 lb` is
  `453592 micro-kg` and not `453592.37`, `1 psi` is `6894757 micro-kPa`.
  Every such snapshot is pinned by a test.
- **Overflow is typed, never wrapped.** Conversions whose intermediate
  product exceeds `Int` return
  `Err("l10n-unit: conversion overflow")`. The last representable product
  and the first failing one are both tested.
- **eV.** `1 eV = 1.602176634e-19 J` exactly is `1602176634/10^28`, which is
  not representable as a ratio of 64-bit integers (the reduced denominator
  is `5 * 10^27`). The table stores the truncated reciprocal
  `1/6241509074460762607` (relative error < 1.6e-19). In practice `eV -> J`
  truncates to 0 below ~6.24e18 micro-eV and `J -> eV` overflows for ordinary
  inputs; both behaviors are documented and tested.
- **pi.** `deg`, `grad` and `turn` are defined via pi, which is irrational.
  The table uses the convergent `245850922/78256779` (relative error
  ~1.3e-17). `turn <-> deg <-> grad` ratios are exact (360/400/1).
- **Case-sensitive symbols.** `m` is the meter, `M` is unknown; `min` is the
  minute; `mmHg` is the pressure unit. Lookup is byte-for-byte.
- **Not in scope.** Locale-aware pluralization/labels and SI-prefix parsing
  beyond the listed symbols are out of scope for 0.1.0; the module is a
  conversion engine, not a localized formatter. `xiom.l10n-currency` and
  `xiom.l10n-number` cover money and decimal formatting.

## How it is verified

`tests/test_conformance.xi` builds 24 checks that print `[PASS]`/`[FAIL]`
and exits non-zero on any failure. Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.l10n-unit
```

The suite covers the required fixtures (mi->km, lb->kg, gal->l, GiB->B,
psi->kPa), affine temperatures at 0/100/32/212 and both absolute-zero
anchors, round trips with documented tolerance, overflow boundaries,
category mismatch and unknown-symbol errors, parse/format round trips,
byte-offset parse errors, and a full table-integrity walk (82 rows, unique
symbols, positive factors, non-zero denominators, offsets only on
temperature rows).

## License

MIT OR Apache-2.0
