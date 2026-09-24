# xiom.thermo

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** exact integer unit conversions for temperature (Celsius /
> Fahrenheit / Kelvin), pressure (Pa / hPa / bar / atmosphere), energy
> (joule / calorie) and speed (km/h <-> m/s).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (platform dependency only; the library
> module imports nothing). Tests additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.thermo` is a small, dependency-free conversion module built entirely on
64-bit `Int` arithmetic. Every quantity is an integer in a unit spelled out
in the function name, so conversions compose without ever touching a float:

- temperature: `thermo_c_to_f_milli`, `thermo_f_to_c_milli`,
  `thermo_c_to_k_milli`, `thermo_k_to_c_milli`, `thermo_f_to_k_milli`,
  `thermo_k_to_f_milli`, `thermo_above_absolute_zero_k_milli`,
- pressure: `thermo_pa_to_hpa`, `thermo_pa_to_bar_micro`,
  `thermo_pa_to_atm_micro`,
- energy: `thermo_j_to_cal_milli`, `thermo_cal_to_j_milli`,
- speed: `thermo_kmh_to_ms_milli`, `thermo_ms_to_kmh_milli`.

See `SPEC.md` for the exact formulas, the truncation rules and the test plan.

## Units

| Quantity | Unit in the API | Scale example |
|---|---|---|
| Temperature | milli-degree C / F, milli-kelvin | `100000` = 100.000 C; `32000` = 32.000 F; `273150` = 273.150 K |
| Pressure | pascal, hectopascal, micro-bar, micro-atmosphere | `100000` Pa = 1 bar = `1000000` ubar; `101325` Pa = `1000000` uatm |
| Energy | milli-joule, milli-calorie (1 cal = 4.184 J) | `4184000` mJ = 4184 J = `1000000` mcal |
| Speed | milli-km/h, milli-m/s | `36000` mkm/h = 36 km/h = `10000` mm/s |

## API

| Function | Returns | Description |
|---|---|---|
| `thermo_c_to_f_milli(c_milli)` | `Int` | `c*9/5 + 32000`; the division truncates toward zero. |
| `thermo_f_to_c_milli(f_milli)` | `Int` | `(f-32000)*5/9`; the division truncates toward zero. |
| `thermo_c_to_k_milli(c_milli)` | `Int` | `c + 273150` (0 C = 273.15 K); exact. |
| `thermo_k_to_c_milli(k_milli)` | `Int` | `k - 273150`; exact. |
| `thermo_f_to_k_milli(f_milli)` | `Int` | F -> C -> K; one truncating division. |
| `thermo_k_to_f_milli(k_milli)` | `Int` | K -> C -> F; one truncating division. |
| `thermo_above_absolute_zero_k_milli(k_milli)` | `Bool` | `k >= 0`; no clamping is applied by any conversion. |
| `thermo_pa_to_hpa(pa)` | `Int` | `pa / 100`; truncates toward zero. |
| `thermo_pa_to_bar_micro(pa)` | `Int` | `pa * 10` (1 Pa = 10 ubar); exact. |
| `thermo_pa_to_atm_micro(pa)` | `Int` | `pa * 1000000 / 101325`; truncates toward zero. |
| `thermo_j_to_cal_milli(j_milli)` | `Int` | `j_milli * 1000 / 4184`; truncates toward zero. |
| `thermo_cal_to_j_milli(cal_milli)` | `Int` | `cal_milli * 4184 / 1000`; truncates toward zero. |
| `thermo_kmh_to_ms_milli(kmh_milli)` | `Int` | `kmh_milli * 1000 / 3600`; truncates toward zero. |
| `thermo_ms_to_kmh_milli(ms_milli)` | `Int` | `ms_milli * 3600 / 1000`; truncates toward zero. |

## Usage

```xi
use xiom.thermo;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  io.println("100 C = " + convert.int_to_string(thermo_c_to_f_milli(100000)) + " mF");
  io.println("300 K = " + convert.int_to_string(thermo_k_to_c_milli(300000)) + " mC");
  io.println("101325 Pa = " + convert.int_to_string(thermo_pa_to_atm_micro(101325)) + " uatm");
  io.println("36 km/h = " + convert.int_to_string(thermo_kmh_to_ms_milli(36000)) + " mm/s");
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.thermo
```

Expected tail: 24 `[PASS]` lines, `xiom.thermo: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- Integer truncation: every function that divides truncates toward zero
  (never floor, never round-half). Exactness holds only for values that
  divide evenly; see `SPEC.md` section 4 for the two rounding rules and the
  affected inputs.
- `thermo_f_to_k_milli` / `thermo_k_to_f_milli` compose two exact steps with
  one truncating division, so they can deviate by 1 mK (or 1 mF) from
  truncating the single real-valued result (e.g. `0 F -> 255373 mK` here).
- No rounding knob: there is no "round half up" or floating-point variant.
- No compound-unit arithmetic: no derived units (W, N, J/s, ...), no rate or
  scale composition, no unit parsing or formatting, no dimension checking.
- Temperature conversions do not clamp below absolute zero; callers check
  with `thermo_above_absolute_zero_k_milli`.
- One calorie definition only: the thermochemical calorie, 1 cal = 4.184 J
  exactly (no IT calorie, no 15 C calorie).
- `Int` overflow is not checked; inputs are expected to keep products within
  the 64-bit signed range (see `SPEC.md` section 6).

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
