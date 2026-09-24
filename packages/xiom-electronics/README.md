# xiom.electronics

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** resistor color codes, the E24 series, voltage dividers and LED
> series resistors.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.electronics` is a small integer-only circuit helper module:

- decode 3/4-band resistor color codes into ohms (`electron_resistor_value`),
- look up single color bands (`electron_color_digit`,
  `electron_color_multiplier`, `electron_resistor_tolerance`),
- snap a value to the E24 (5%) series (`electron_nearest_e24`),
- compute an unloaded voltage divider (`electron_voltage_divider_mv`),
- size an LED series resistor (`electron_led_resistor_ohm`).

No floating point is used anywhere: tolerances are returned in permille and
all divisions use integer semantics (see `SPEC.md` for the exact rounding
rules). The module contains no FFI and imports only `xiom.string.compare`.

## Units

| Quantity | Unit | Where |
|---|---|---|
| Resistance | ohm | `electron_resistor_value`, `electron_nearest_e24`, `electron_led_resistor_ohm`, divider inputs |
| Tolerance | permille (1 permille = 0.1%) | `electron_resistor_tolerance` |
| Voltage | millivolt (mV) | `electron_voltage_divider_mv`, `electron_led_resistor_ohm` |
| Current | microamp (uA) | `electron_led_resistor_ohm` |

## API

| Function | Returns | Description |
|---|---|---|
| `electron_color_digit(color)` | `Option[Int]` | Band digit 0..9; `black`=0 .. `white`=9, `gray` aliases `grey`. `None` for unknown / non-lowercase names. |
| `electron_color_multiplier(color)` | `Option[Int]` | Multiplier band as a power-of-ten exponent 0..9 (same ten digit colors); `gold`/`silver` are `None` (5-band only). |
| `electron_resistor_value(bands)` | `Result[Int, Str]` | Ohms from 3 or 4 bands: `(d1*10 + d2) * 10^multiplier`; the 4th band is tolerance and only validated. |
| `electron_resistor_tolerance(color)` | `Option[Int]` | Tolerance in permille: brown 1% -> 10, red 2% -> 20, gold 5% -> 50, silver 10% -> 100, green 0.5% -> 5. |
| `electron_e24_values()` | `Vec[Int]` | The 24 E24 nominals 10, 11, ..., 91. |
| `electron_nearest_e24(value)` | `Int` | Nearest E24 nominal in the same decade, decade-scaled; ties go to the larger nominal. Values < 10 pass through. |
| `electron_voltage_divider_mv(vin_mv, r1_ohm, r2_ohm)` | `Int` | `vin_mv * r2 / (r1 + r2)`; `0` when `r1 + r2 == 0`. |
| `electron_led_resistor_ohm(supply_mv, forward_mv, current_ua)` | `Result[Int, Str]` | `(supply_mv - forward_mv) * 1000 / current_ua`; error when current <= 0 or supply <= forward. |

## Usage

```xi
use xiom.electronics;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  var bands = Vec[Str].new();
  bands.push("brown");
  bands.push("black");
  bands.push("red");
  let value = electron_resistor_value(&bands);
  match value {
    Ok(ohms) => { io.println("brown-black-red = " + convert.int_to_string(ohms) + " ohm"); },
    Err(msg) => { io.println(msg); },
  }

  let led = electron_led_resistor_ohm(5000, 2000, 20000);
  match led {
    Ok(ohms) => { io.println("LED resistor = " + convert.int_to_string(ohms) + " ohm"); },
    Err(msg) => { io.println(msg); },
  }

  io.println("nearest E24 to 5000 ohm = " + convert.int_to_string(electron_nearest_e24(5000)));
  io.println("divider 9V, 1k/1k = " + convert.int_to_string(electron_voltage_divider_mv(9000, 1000, 1000)) + " mV");
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.electronics
```

Expected tail: 24 `[PASS]` lines, `xiom.electronics: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- 3- and 4-band resistor codes only: the 5-band layout, the gold/silver
  multiplier bands, and temperature-coefficient bands are out of scope.
- Tolerance is modelled for the five common tolerance colors only (no
  "no band" / 20% case).
- Integer units are part of the API contract: ohms, mV, uA and permille.
  There is no float API and no unit conversion (e.g. V or mA inputs).
- `electron_nearest_e24` covers values >= 10 ohm; smaller values (including
  0 and negatives) pass through unchanged.
- `electron_voltage_divider_mv` models an unloaded divider and does not
  account for load current or tolerances.
- Lookups are exact and lowercase; no glyph/colour normalisation.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
