# xiom.thermo -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.thermo` (`src/thermo.xi`). Pure XIOM, no FFI, no imports.
Dependencies: `xiom.std` only (tests use `xiom.test` and `xiom.io`).

## 1. Scope

Exact integer unit conversions in four families:

- temperature: Celsius <-> Fahrenheit <-> Kelvin, and an absolute-zero check,
- pressure: pascal -> hectopascal / micro-bar / micro-atmosphere,
- energy: milli-joule <-> milli-calorie,
- speed: milli-km/h <-> milli-m/s.

Every value is an `Int`; the unit is encoded in the function name. The module
is deterministic, allocation-free, and free of error paths: every function is
total over `Int`.

## 2. Non-goals

- Floats: there is no `Float64` API and no rounding-mode knob.
- Derived/compound units (W, N, J/s, torque, flow rates), dimensional
  analysis, unit parsing or pretty-printing.
- Temperature clamping: conversions below absolute zero are computed
  arithmetically; `thermo_above_absolute_zero_k_milli` only reports.
- Other calorie definitions (IT calorie, 15 C calorie) and other pressure
  references (technical atmosphere, torr).
- Any FFI, file I/O, or registry integration.

## 3. Units and conventions

| Quantity | Unit | Conversion anchor |
|---|---|---|
| Temperature | milli-degree C, milli-degree F, milli-kelvin | 0 C = 273.15 K; F = C*9/5 + 32 |
| Pressure | pascal, hectopascal, micro-bar, micro-atmosphere | 1 hPa = 100 Pa; 1 Pa = 10 ubar; 1 atm = 101325 Pa |
| Energy | milli-joule, milli-calorie | 1 cal = 4.184 J exactly (thermochemical) |
| Speed | milli-km/h, milli-m/s | 1 km/h = 1000/3600 m/s |

The `_milli` suffix means the value is 1000x the named unit (so `1` = 0.001 C,
`32000` = 32.000 F, `4184000` mJ = 4184 J). Pressure uses explicit
`hpa`/`bar_micro`/`atm_micro` suffixes instead.

## 4. Rounding rules

All divisions are XIOM `Int` divisions and **truncate toward zero** (never
floor, never round-half). Two rules capture every function:

1. **Single truncating division.** The expression in section 5 is evaluated
   with products first, then one division truncated toward zero, then the
   remaining exact (additive) terms. This applies to `thermo_c_to_f_milli`,
   `thermo_f_to_c_milli`, `thermo_pa_to_hpa`, `thermo_pa_to_atm_micro`,
   `thermo_j_to_cal_milli`, `thermo_cal_to_j_milli`,
   `thermo_kmh_to_ms_milli`, `thermo_ms_to_kmh_milli`.
2. **Exact (no division).** `thermo_c_to_k_milli`, `thermo_k_to_c_milli` and
   `thermo_pa_to_bar_micro` add, subtract or multiply only and are exact for
   every input that fits `Int`.

Composition caveat: `thermo_f_to_k_milli` and `thermo_k_to_f_milli` are
defined as F -> C -> K and K -> C -> F, i.e. they apply rule 1 once (the F<->C
leg) and are then exact (the C<->K leg). Because the offset is applied after
the truncating division, the result can differ by 1 milli-unit from truncating
the single real-valued formula:

- `thermo_f_to_k_milli(0)` = `-160000/9 + 273150` = `-17777 + 273150` =
  `255373` mK, while 0 F is 255.372... K and a single truncation would give
  `255372` mK.
- `thermo_c_to_f_milli(-1)` = `-9/5 + 32000` = `31999` mF, while -0.001 C is
  31.9982 F.

The pinned conformance values follow these rules, not float rounding.

## 5. Formulas

### 5.1 Temperature

| Function | Formula |
|---|---|
| `thermo_c_to_f_milli(c)` | `c * 9 / 5 + 32000` |
| `thermo_f_to_c_milli(f)` | `(f - 32000) * 5 / 9` |
| `thermo_c_to_k_milli(c)` | `c + 273150` |
| `thermo_k_to_c_milli(k)` | `k - 273150` |
| `thermo_f_to_k_milli(f)` | `thermo_c_to_k_milli(thermo_f_to_c_milli(f))` |
| `thermo_k_to_f_milli(k)` | `thermo_c_to_f_milli(thermo_k_to_c_milli(k))` |
| `thermo_above_absolute_zero_k_milli(k)` | `k >= 0` |

Examples: `100000 -> 212000`; `32000 -> 0`; `-40000 -> -40000` (the -40 tie);
`0 -> 273150`; `300000 -> 26850`.

### 5.2 Pressure

| Function | Formula |
|---|---|
| `thermo_pa_to_hpa(pa)` | `pa / 100` |
| `thermo_pa_to_bar_micro(pa)` | `pa * 10` |
| `thermo_pa_to_atm_micro(pa)` | `pa * 1000000 / 101325` |

Examples: `101325 -> 1013` hPa; `101325 -> 1013250` ubar;
`101325 -> 1000000` uatm exactly; `1 -> 9` uatm.

### 5.3 Energy

| Function | Formula |
|---|---|
| `thermo_j_to_cal_milli(j)` | `j * 1000 / 4184` |
| `thermo_cal_to_j_milli(c)` | `c * 4184 / 1000` |

Examples: `4184000 -> 1000000` mcal; `1000 -> 239` mcal (1 J = 239.005 mcal
truncated); `1000000 -> 239005` mcal (1000 J); `1000 -> 4184` mJ.

### 5.4 Speed

| Function | Formula |
|---|---|
| `thermo_kmh_to_ms_milli(v)` | `v * 1000 / 3600` |
| `thermo_ms_to_kmh_milli(v)` | `v * 3600 / 1000` |

Examples: `36000 -> 10000` mm/s (36 km/h = 10 m/s); `10000 -> 2777` mm/s
(10 km/h); `1000 -> 3600` mkm/h (1 m/s); `1 -> 3` mkm/h (1 mm/s).

## 6. Range and overflow

Inputs are 64-bit signed `Int`. The widest intermediate is
`pa * 1000000` in `thermo_pa_to_atm_micro`, exact while
`|pa| <= 9.22e12`; every other product is at least 1000x narrower. Values
listed in the large-value test (section 8, t23) stay far inside the range.
Overflow behaviour for extreme inputs is undefined by this spec and not
tested.

## 7. API signatures

```xi
pub fn thermo_c_to_f_milli(c_milli: Int) -> Int
pub fn thermo_f_to_c_milli(f_milli: Int) -> Int
pub fn thermo_c_to_k_milli(c_milli: Int) -> Int
pub fn thermo_k_to_c_milli(k_milli: Int) -> Int
pub fn thermo_f_to_k_milli(f_milli: Int) -> Int
pub fn thermo_k_to_f_milli(k_milli: Int) -> Int
pub fn thermo_above_absolute_zero_k_milli(k_milli: Int) -> Bool
pub fn thermo_pa_to_hpa(pa: Int) -> Int
pub fn thermo_pa_to_bar_micro(pa: Int) -> Int
pub fn thermo_pa_to_atm_micro(pa: Int) -> Int
pub fn thermo_j_to_cal_milli(j_milli: Int) -> Int
pub fn thermo_cal_to_j_milli(cal_milli: Int) -> Int
pub fn thermo_kmh_to_ms_milli(kmh_milli: Int) -> Int
pub fn thermo_ms_to_kmh_milli(ms_milli: Int) -> Int
```

All functions are O(1), total, and import nothing.

## 8. Test plan

`tests/test_conformance.xi` (module `thermo_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | C->F known | 100 C, 0 C, 37 C, -40 C |
| t2 | C->F more | -100 C, 5 C, 1 C |
| t3 | C->F truncation | division truncates toward zero before +32000 (1/-1/2/-2 mC) |
| t4 | F->C known | 212 F, 32 F, 98.6 F |
| t5 | F->C truncation | both signs, `31999 -> 0`, 0 F -> -17777 mC |
| t6 | C<->K exact | 0 C=273.15 K, 100 C, 300 K=26.85 C, -273.15 C |
| t7 | K->C pinned | 300 K = 26850 mC (26.85 C), sub-zero exact |
| t8 | F->K | 32 F, 212 F, -40 F, 0 F -> 255373 mK (composition rule) |
| t9 | K->F | 273.15 K, 373.15 K, 0 K = -459.67 F, -40 tie |
| t10 | F<->K round-trips | exact for 8 pinned temperatures in both directions |
| t11 | Pa->hPa | 101325 Pa = 1013 hPa; toward-zero truncation incl. 0 |
| t12 | Pa->hPa negative | -150 -> -1, -99 -> 0, -101325 -> -1013 |
| t13 | Pa->ubar exact | 100000 Pa = 1 bar = 1000000 ubar; 1 Pa = 10 ubar; negative exact |
| t14 | Pa->uatm exact | 101325 Pa = 1000000 uatm; 10 atm; negative exact |
| t15 | Pa->uatm truncation | 1 Pa = 9 uatm; 200000 Pa = 1973846 uatm; -1 Pa = -9 uatm |
| t16 | J->mcal exact | 4184 J = 1000000 mcal; both signs |
| t17 | J->mcal truncation | 1 J = 239 mcal; 1000 J = 239005 mcal; both signs; 1 mJ -> 0 |
| t18 | mcal->J | 1 cal = 4184 mJ; 1 mcal = 4 mJ; lossy round-trip 999996 mJ |
| t19 | km/h->m/s known | 36 km/h = 10 m/s; 72 km/h; 3.6 km/h |
| t20 | km/h->m/s truncation | 10 km/h = 2777 mm/s; both signs; 1 mkm/h -> 0 |
| t21 | m/s->km/h | 1 m/s = 3600 mkm/h; 10 m/s = 36 km/h; 1 mm/s = 3 mkm/h |
| t22 | absolute zero | k >= 0 true, all negative k false, no clamping implied |
| t23 | large values | 10^9 mC, 10^12 mK, 10^9 Pa, 10^9 mcal, 10^6 mm/s stay exact |
| t24 | zero points | every scale's zero maps exactly (32 F, 273.15 K, 0, ...) |

Every expected value is an exact integer result of section 5; no assertion
uses tolerance. The test file reads no `Vec`, builds no `Str`, and dispatches
no `Vec[fn]`; each test is called explicitly from `main`.

## 9. Known limitations

- Truncation toward zero is the only rounding; the composition caveat of
  section 4 applies to the F<->K pair.
- No unit registry, parsing or formatting; callers keep track of units.
- No overflow checking for inputs beyond section 6.
- No below-absolute-zero clamping; the check function is advisory.

## 10. Compiler / stdlib notes

Built against XIOM v0.61.3. No workarounds beyond the repo's standard
discipline: free functions only (no methods), no lambdas, no `Vec[Struct]`,
no `Result`/`Option` (every function is total), no `match` inside the module,
`module` without a trailing semicolon, `use` lines with one, and the
copyright + SPDX header on every `.xi` file.
