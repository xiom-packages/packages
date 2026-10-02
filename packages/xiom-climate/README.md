# xiom.climate

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-XIOM, integer/fixed-point climate helpers: a zero-dimensional
> energy-balance model, delta-18O paleoclimate reconstruction, CO2 emission
> scenarios, climate-zone classification, and temperature/precipitation trend
> and anomaly analysis.
> **Deps:** `xiom.std` only (`xiom.convert`, `xiom.string.compare`).

## What it is

`xiom.climate` is a dependency-free, FFI-free, floating-point-free climate
toolbox. Every quantity is an integer with a documented scale; every division
is floor division (toward negative infinity); every loop is bounded and
deterministic. It is a compact teaching/analysis core, not a general
circulation model.

- **`climate_model`** -- solar absorption (`floor(1361*(1000-albedo)/1000)`),
  CO2 radiative forcing and equilibrium warming with a standard
  `ECS * log2(C/C0)` response (ECS default 3.00 degC per doubling), and a
  discrete relaxation/simulation loop toward an equilibrium temperature.
- **`paleo`** -- the simplified linear paleotemperature relation
  `T = 16.90 - 4.38*d18O` (both directions, each floor-rounded), sediment age
  from depth and accumulation rate, and a warm/transitional/cold phase code.
- **`scenarios`** -- linear and compound CO2 projections (compound growth in
  basis points per year, floored yearly) plus the warming implied by a
  projected concentration.
- **`zones`** -- a nine-code simplified Koeppen-style classifier from
  annual-mean temperature and annual precipitation, with descriptions and an
  aridity predicate.
- **`trends`** -- floored mean, least-squares linear trend per decade,
  extrapolation, strict threshold counts, and precipitation anomalies in
  permille.

## Units

| Quantity | Unit | Example |
|---|---|---|
| Temperature | centi-degC (0.01 degC) | `1500` = 15.00 degC |
| Precipitation | centi-mm (0.01 mm) | `25000` = 250.00 mm |
| CO2 | ppm | `420` |
| Forcing | milli-W/m^2 | `3710` = 3.710 W/m^2 |
| delta-18O | centi-permille | `100` = 1.00 permille |
| Ratio / anomaly | permille | `200` = 20.0% |
| Scenario growth | milli-ppm/year (linear), bps/year (compound) | `2500` = 2.5 ppm/yr |
| Age | ka (kilo-years) | `100` |

All rounding rules are stated per function in `SPEC.md`; all internal
divisions use floor semantics via `_floor_div`.

## API

All functions are free functions in module `xiom.climate`.

| Function | Returns | Description |
|---|---|---|
| `climate_solar_const_wm2()` | `Int` | Solar constant (1361 W/m^2). |
| `climate_absorbed_wm2(albedo_permille)` | `Result[Int, Str]` | Absorbed solar radiation. |
| `climate_forcing_milli_wm2(co2, base)` | `Result[Int, Str]` | CO2 forcing vs baseline. |
| `climate_equilibrium_warming_centi(co2, base, ecs)` | `Result[Int, Str]` | Warming at a given sensitivity. |
| `climate_relax_step_centi(cur, target, rate)` | `Result[Int, Str]` | One floored relaxation step. |
| `climate_simulate_centi(start, target, rate, steps)` | `Result[Int, Str]` | Iterated relaxation trajectory. |
| `paleo_temp_from_d18o_centi(d)` | `Result[Int, Str]` | Proxy temperature from delta-18O. |
| `paleo_d18o_from_temp_centi(t)` | `Result[Int, Str]` | Inverse (floor-rounded). |
| `paleo_age_ka(depth_cm, rate_mm_per_ka)` | `Result[Int, Str]` | Layer age in ka. |
| `paleo_climate_phase(d)` | `Result[Str, Str]` | `warm interglacial` / `transitional` / `cold glacial`. |
| `scenarios_co2_linear(start, growth, years)` | `Result[Int, Str]` | Linear CO2 projection. |
| `scenarios_co2_compound(start, growth_bps, years)` | `Result[Int, Str]` | Yearly-compounded CO2 projection. |
| `scenarios_warming_centi(start, growth_bps, years, ecs)` | `Result[Int, Str]` | Warming implied by a scenario. |
| `zones_classify(temp_centi, precip_centi_mm)` | `Result[Str, Str]` | Zone code (`Af`..`EF`). |
| `zones_description(code)` | `Result[Str, Str]` | Long zone name. |
| `zones_is_arid(code)` | `Bool` | `true` for `BW`/`BS` only. |
| `trends_mean_centi(values)` | `Result[Int, Str]` | Floored mean of a series. |
| `trends_linear_trend_centi_per_decade(values)` | `Result[Int, Str]` | Least-squares slope per decade. |
| `trends_extrapolate_centi(values, steps)` | `Result[Int, Str]` | Trend extrapolation. |
| `trends_count_above(values, threshold)` | `Result[Int, Str]` | Strict threshold count. |
| `trends_precip_anomaly_permille(observed, normal)` | `Result[Int, Str]` | Floored anomaly vs normal. |

```xi
use xiom.climate;
use xiom.convert;
use xiom.io;

// 420 ppm against a 280 ppm baseline at 3.00 degC per doubling.
match climate_equilibrium_warming_centi(420, 280, 300) {
  Ok(w) => { io.println("warming: " + convert.int_to_string(w) + " centi-degC"); },
  Err(e) => { io.println(e); },
}
```

The manifest package name, the module name and the folder are all
`xiom.climate` / `xiom-climate`, so no name mapping is needed.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom-climate
```

Expected: 24 `[PASS]` lines and
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

Coverage: solar/albedo anchors and envelope errors, CO2 forcing and warming
anchors (doubling, halving, interpolation knots), relaxation and simulation
trajectories, paleotemperature and its inverse, layer age, phase boundaries,
linear/compound scenarios (including the non-positive and overflow guards),
all nine zones and their boundaries, zone descriptions, floored series
statistics, and the exact error strings of every rejected input.

## Limitations

- **Simplified physics.** A zero-dimensional energy balance with a linear
  `log2` response; no carbon cycle, ocean heat uptake, aerosols, feedbacks
  beyond a single sensitivity number, or spatial resolution.
- **Approximate log2.** The response uses a 16-segment piecewise-linear
  integer approximation of `log2` (knots and error bound in `SPEC.md`), not
  the exact logarithm. Warming values are model outputs, not predictions.
- **No floating point.** Sub-centi-degC or sub-permille precision is not
  representable; each function documents its floor rounding.
- **No external data.** No station records, proxy datasets, ice cores or
  reanalysis files; the caller supplies every series. `paleo` is a formula,
  not a calibrated reconstruction pipeline.
- **Seasonality is not an input** to `zones_classify`, so `Cf`/`Cs` reflect
  precipitation totals only.
- **No FFI, no unsafe code, no `Vec[StructType]`, no `Vec[Str]`,
  no `Vec[fn]`** -- XIOM v0.62.2 constraints.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
