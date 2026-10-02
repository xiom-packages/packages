# xiom.climate -- Specification

Version: 0.1.0 (incubating, conformance-tested 24/24, not published).
Module: `xiom.climate` (`src/climate.xi`, 596 lines). Pure XIOM: no FFI, no
floating point, no I/O, no unsafe code.

## 1. Scope

Integer/fixed-point climate helpers in five libs:

- `climate_model` -- zero-dimensional energy-balance model: solar
  absorption, CO2 radiative forcing, equilibrium warming, and a discrete
  relaxation/simulation loop toward equilibrium;
- `paleo` -- delta-18O proxy temperature (both directions), sediment age
  from depth and accumulation rate, and a three-way climate-phase code;
- `scenarios` -- linear and compound CO2 emission-scenario projection and
  the warming implied by a projected concentration;
- `zones` -- nine-code annual temperature/precipitation climate-zone
  classification, zone descriptions, and an aridity predicate;
- `trends` -- floored mean, least-squares linear trend per decade,
  extrapolation, strict threshold counts, and precipitation anomalies.

Every entry point is a free function; the only imports are
`xiom.convert.int_to_string` (error-message rendering) and
`xiom.string.compare.str_compare` (zone-code comparison) from `xiom.std`.

## 2. Non-goals

- No general circulation model, no radiative-transfer spectra, no
  carbon cycle, no ocean/ice dynamics, no aerosols, no clouds, no spatial
  grid, no seasonality, no weather.
- No floating point anywhere (no `Vec[Float64]`, no scalar `Float64`):
  every quantity is an integer with a fixed documented scale, and every
  division is floor division.
- No external data files, station records, proxy databases, ice cores or
  reanalysis products; the caller supplies every series.
- No structs for datasets, no `Vec[StructType]`, no `Vec[Str]`,
  no `Vec[fn]` dispatch, no methods, no lambdas (XIOM v0.62.2 limits).
- No uncertainty propagation, no error bars, no statistical significance
  testing (the trends lib is descriptive, not inferential).

## 3. Units, data model and rounding

### 3.1 Units

| Quantity | Unit | Reference value |
|---|---|---|
| Temperature | centi-degrees Celsius (`centi-degC`, 1 = 0.01 degC) | `1500` = 15.00 degC |
| Precipitation | centi-millimetres (`centi-mm`, 1 = 0.01 mm) | `25000` = 250.00 mm |
| CO2 | parts per million (ppm) | `420` |
| Radiative forcing | milli-W/m^2 (1 = 0.001 W/m^2) | `3710` = 3.710 W/m^2 |
| delta-18O | centi-permille (1 = 0.01 permille) | `100` = 1.00 permille |
| Ratios, anomalies | permille (1 = 0.1%) | `200` = 20.0% |
| Linear scenario growth | milli-ppm per year | `2500` = 2.5 ppm/year |
| Compound scenario growth | basis points per year (100 = 1%) | `100` = 1%/year |
| Sediment depth | centimetres | `500` |
| Accumulation rate | millimetres per kilo-year | `50` |
| Age | kilo-years (ka) | `100` |
| Climate sensitivity | centi-degC per CO2 doubling | `300` = 3.00 degC |

### 3.2 Data model

The module is scalar-only: all inputs are `Int` or `Str`, all outputs are
`Int`, `Bool`, `Str`, `Result[Int, Str]` or `Result[Str, Str]`. Series
inputs are `&Vec[Int]` and are never stored; no struct type is defined and
no parallel Vecs exist to drift. `Ok`/`Err` are constructed only in the
`_ok_int` / `_err_int` / `_ok_str` / `_err_str` leaf helpers.

### 3.3 Rounding

Every division uses `_floor_div` (floor toward negative infinity), so a
negative non-exact quotient rounds down, not toward zero. The only
division with guaranteed non-negative operands is inside
`_log2_frac_permille`, where truncation and floor coincide. Rounding is
documented per function below; the tests pin negative cases explicitly
(e.g. `trends_mean_centi([-1,-2]) = -2`, `trends_linear_trend_...([0,0,1,0,0,0]) = -1`,
`scenarios_warming_centi(280,-1000,10,300) = -474`).

## 4. climate_model

Constants: solar constant `1361 W/m^2`; forcing per CO2 doubling
`3710 milli-W/m^2` (3.710 W/m^2); `_PERMILLE = 1000`.

### 4.1 Solar absorption

```
absorbed_wm2 = floor(1361 * (1000 - albedo_permille) / 1000)
```

Anchors: albedo 300 -> 952, albedo 290 -> 966, albedo 0 -> 1361,
albedo 1000 -> 0. Albedo is validated to `0..1000`.

### 4.2 CO2 forcing and equilibrium warming

```
ratio_permille = floor(co2 * 1000 / base), clamped to >= 1
l              = log2_permille(ratio_permille)      // 1000 * log2, approx.
forcing_milli  = floor(3710 * l / 1000)             // milli-W/m^2
warming_centi  = floor(ecs_centi * l / 1000)        // centi-degC
```

`ecs_centi` is the equilibrium climate sensitivity in centi-degC per
doubling; the standard 3.00 degC/doubling is `300`. Pinned anchors:
doubling (560 vs 280) -> `+300`; quadrupling -> `+600`; halving -> `-300`;
no change -> `0`; 420/280 -> `+175`; 400/280 -> `+154`; 700/280 -> `+396`;
240/280 -> `-67`.

### 4.3 Integer log2 approximation (16 segments)

`ratio_permille` (1000 = 1.0) is range-reduced: while `x >= 2000` do
`x = (x + 1) / 2; k = k + 1`; while `x < 1000` do `x = x * 2; k = k - 1`.
The mantissa `x` in `[1000, 2000)` is mapped through 16 linear segments;
the result is `k * 1000 + frac(x)`. Knots (`m` -> thousandths of log2,
each the rounded true value):

| m | 1000 | 1062 | 1125 | 1187 | 1250 | 1312 | 1375 | 1437 |
|---|---|---|---|---|---|---|---|---|
| y | 0 | 87 | 170 | 248 | 322 | 392 | 459 | 524 |

| m | 1500 | 1562 | 1625 | 1687 | 1750 | 1812 | 1875 | 1937 | 2000 |
|---|---|---|---|---|---|---|---|---|---|
| y | 585 | 644 | 700 | 755 | 807 | 858 | 907 | 954 | 1000 |

`log2` is concave, so each chord under-estimates; together with knot
rounding and integer range reduction the approximation error is below
5 thousandths of a log2 unit (at ECS 300 that is under 0.02 degC of
warming). The suite pins the exact integer outputs, not the real
logarithm.

### 4.4 Relaxation and simulation

```
relax_step(current, target, rate) = current + floor((target-current)*rate/1000)
simulate(start, target, rate, steps) = relax_step applied steps times
```

`rate_permille 0..1000` (0 = no motion, 1000 = jump to target). The
trajectory is exactly the floored integer sequence and may asymptote
rather than reach the target. Pinned: `(0,300,100)` -> 30;
`(300,0,500)` -> 150; simulate `(0,300,100,5)` -> 121;
simulate `(300,0,500,2)` -> 75. Temperatures are limited to
`+-100000 centi-degC`; steps to `0..10000`.

## 5. paleo

### 5.1 Paleotemperature (simplified linear relation)

```
T_centi = 1690 - floor(438 * d / 100)          // d = d18O in centi-permille
d       = floor((1690 - T_centi) * 100 / 438)  // inverse
```

with the slope 4.38 degC per permille and intercept 16.90 degC. The two
directions are each floor-rounded and are not exact round-trips:
`1690 -> 0`, `100 -> 1252`, `-100 -> 2128`, `50 -> 1471`,
`-51 -> 1914` (floor of -223.38 is -224), `1500 -> 43 -> 1502`,
`3000 -> -300 -> 3004`. `d` is limited to `+-1000 centi-permille`;
the inverse temperature to `+-5000 centi-degC`.

### 5.2 Layer age

```
age_ka = floor(depth_cm * 10 / accumulation_mm_per_ka)
```

Pinned: `(500,50) -> 100`, `(123,40) -> 30`, `(0,50) -> 0`. Depth is
limited to `0..1000000000 cm`; the accumulation rate must be `>= 1`.

### 5.3 Phase classification

`d <= -150` -> `"warm interglacial"`; `d >= 150` -> `"cold glacial"`;
otherwise `"transitional"`. Both thresholds are inclusive (pinned at
-151/-150/-149, 149/150/151).

## 6. scenarios

### 6.1 Linear

```
co2 = start + floor(growth_milli_ppm_per_year * years / 1000)
```

Growth may be negative; the projection must stay positive.
Pinned: `(280,2500,10) -> 305`, `(280,-1000,10) -> 270`,
`(280,1234,3) -> 283`, `(100,-60000,2)` -> Err (projected -20 ppm).

### 6.2 Compound

Year by year: `v = v + floor(v * growth_bps / 10000)`, repeated `years`
times, with a per-step guard: the projection must stay `<= 100000000 ppm`
(overflow guard) and `> 0`. Pinned: `(280,100,10) -> 300`
(1%/year); `(500,10000,1) -> 1000` (+100% in one year);
`(1000,-100,1) -> 990`; `(1000000,100000,500)` -> Err at 121000000 ppm.
Envelopes: start `1..1000000`; growth `-9999..100000` bps; years `0..500`.

### 6.3 Scenario warming

Project the compound concentration, then apply the climate_model warming
with `ratio = floor(projected * 1000 / start)`:
`warming = floor(ecs_centi * log2_permille(ratio) / 1000)`. Pinned:
`(280,100,10,300) -> 29`; `(280,0,10,300) -> 0`;
`(280,-1000,10,300) -> -474` (floored negative); ecs `0..100000`.

## 7. zones

Input validation: temperature `-10000..6000 centi-degC`, precipitation
`0..10000000 centi-mm`. Classification precedence (boundaries inclusive on
the wetter/warmer side):

| Condition | Code | Description |
|---|---|---|
| temp < 0 | `EF` | polar frost |
| temp < 1000 | `ET` | tundra |
| temp >= 1800, precip >= 200000 | `Af` | tropical rainforest |
| temp >= 1800, precip >= 100000 | `Am` | tropical monsoon |
| temp >= 1800, precip >= 50000 | `Aw` | tropical savanna |
| temp >= 1800, else | `BW` | desert |
| temp < 1800, precip < 25000 | `BW` | desert |
| temp < 1800, precip < 50000 | `BS` | steppe |
| temp < 1800, precip >= 100000 | `Cf` | humid temperate |
| temp < 1800, else | `Cs` | seasonal temperate |

Pinned boundary pairs: `1799/1800` at 30000 and 99999 precipitation,
`199999/200000`, `49999/50000`, `99999/100000`, and the polar cut at
`-1/0`. `zones_description` maps each of the nine codes to its long name
and rejects anything else; `zones_is_arid` is true exactly for `BW` and
`BS`. Seasonality is not an input, so `Cf`/`Cs` name precipitation totals
only -- a documented simplification, not a full Koeppen map.

## 8. trends

Series validation (`_check_series`): non-empty, at most 1000 values, every
value within `+-1000000` in series units.

### 8.1 Mean

`mean = floor(sum / n)`. Pinned: `[100,200,300] -> 200`, `[1,2] -> 1`,
`[-1,-2] -> -2`.

### 8.2 Least-squares slope per decade

```
Sx = sum(i), Sy = sum(y), Sxy = sum(i*y), Sxx = sum(i*i)   (x_i = i)
slope_per_decade = floor(10 * (n*Sxy - Sx*Sy) / (n*Sxx - Sx*Sx))
```

The denominator is positive for `n >= 2` (n < 2 is an error). Pinned:
`[100,110,120] -> 100`, `[300,200,100] -> -1000`,
`[100,120,90,130] -> 60`, `[0,0,1,0,0,0] -> -1` (floor of -0.286),
`[0,0,0,0,0,1] -> 1`.

### 8.3 Extrapolation

`projected = last + floor(slope_per_decade * steps / 10)`, `steps 0..10000`
(fractional decade steps floor normally). Pinned:
`[100,110,120], steps 5 -> 170`; steps 3 -> 150; steps 0 -> 120.

### 8.4 Threshold count

Number of values strictly greater than `threshold` (no values out of range
are added). Pinned: `[100,200,150] > 150 -> 1`; `[1,5,3,5] > 4 -> 2`.

### 8.5 Precipitation anomaly

`anomaly_permille = floor((observed - normal) * 1000 / normal)`. Pinned:
`(120000,100000) -> 200`; `(80000,100000) -> -200`;
`(1000,3000) -> -667` (floor of -666.6); `(0,100000) -> -1000`.
Observed is validated `0..1000000000`; normal must be `>= 1`.

## 9. API signatures

```xi
pub fn climate_solar_const_wm2() -> Int
pub fn climate_absorbed_wm2(albedo_permille: Int) -> Result[Int, Str]
pub fn climate_forcing_milli_wm2(co2_ppm: Int, base_ppm: Int) -> Result[Int, Str]
pub fn climate_equilibrium_warming_centi(co2_ppm: Int, base_ppm: Int, ecs_centi: Int) -> Result[Int, Str]
pub fn climate_relax_step_centi(current_centi: Int, target_centi: Int, rate_permille: Int) -> Result[Int, Str]
pub fn climate_simulate_centi(start_centi: Int, target_centi: Int, rate_permille: Int, steps: Int) -> Result[Int, Str]
pub fn paleo_temp_from_d18o_centi(d18o_centi_permille: Int) -> Result[Int, Str]
pub fn paleo_d18o_from_temp_centi(temp_centi: Int) -> Result[Int, Str]
pub fn paleo_age_ka(depth_cm: Int, accumulation_mm_per_ka: Int) -> Result[Int, Str]
pub fn paleo_climate_phase(d18o_centi_permille: Int) -> Result[Str, Str]
pub fn scenarios_co2_linear(start_ppm: Int, growth_milli_ppm_per_year: Int, years: Int) -> Result[Int, Str]
pub fn scenarios_co2_compound(start_ppm: Int, growth_bps_per_year: Int, years: Int) -> Result[Int, Str]
pub fn scenarios_warming_centi(start_ppm: Int, growth_bps_per_year: Int, years: Int, ecs_centi: Int) -> Result[Int, Str]
pub fn zones_classify(temp_centi: Int, precip_centi_mm: Int) -> Result[Str, Str]
pub fn zones_description(code: Str) -> Result[Str, Str]
pub fn zones_is_arid(code: Str) -> Bool
pub fn trends_mean_centi(values: &Vec[Int]) -> Result[Int, Str]
pub fn trends_linear_trend_centi_per_decade(values: &Vec[Int]) -> Result[Int, Str]
pub fn trends_extrapolate_centi(values: &Vec[Int], steps: Int) -> Result[Int, Str]
pub fn trends_count_above(values: &Vec[Int], threshold: Int) -> Result[Int, Str]
pub fn trends_precip_anomaly_permille(observed_centi_mm: Int, normal_centi_mm: Int) -> Result[Int, Str]
```

Complexity: every function is O(1) except `climate_simulate_centi`
(O(steps), steps <= 10000), the two compound scenarios and
`scenarios_warming_centi` (O(years), years <= 500), and the trends
functions (O(n), n <= 1000).

## 10. Error catalog

Every `Err` message starts with `"climate: "` and carries the offending
value (or code) verbatim:

| Trigger | Channel(s) | Message |
|---|---|---|
| albedo outside 0..1000 | absorbed | `climate: albedo out of range: N permille` |
| co2 outside 1..1000000 | forcing, warming | `climate: co2 out of range: N ppm` |
| base outside 1..1000000 | forcing, warming | `climate: base co2 out of range: N ppm` |
| ecs outside 0..100000 (or negative) | warming, scenario warming | `climate: ecs out of range: N centi-celsius` |
| rate outside 0..1000 | relax, simulate | `climate: relaxation rate out of range: N permille` |
| temperature outside +-100000 | relax, simulate | `climate: temperature out of range: N centi-celsius` |
| steps outside 0..10000 | simulate, extrapolate | `climate: step count out of range: N` |
| d18O outside +-1000 | paleo temperature, phase | `climate: d18o out of range: N centi-permille` |
| paleotemperature outside +-5000 | paleo inverse | `climate: temperature out of range: N centi-celsius` |
| depth negative or > 1000000000 | age | `climate: depth out of range: N cm` |
| accumulation rate < 1 | age | `climate: accumulation rate must be positive: N mm/ka` |
| scenario start < 1 or > 1000000 | all scenarios | `climate: co2 start must be positive: N ppm` |
| linear growth outside +-100000 | linear | `climate: growth rate out of range: N milli-ppm/year` |
| compound growth <= -10000 or > 100000 | compound, scenario warming | `climate: growth rate out of range: N bps` |
| years outside 0..1000 (linear) / 0..500 (compound) | scenarios | `climate: year count out of range: N` |
| projection <= 0 | scenarios | `climate: projected co2 non-positive: N ppm` |
| projection > 100000000 | scenarios | `climate: projected co2 exceeds limit: N ppm` |
| zone temperature outside -10000..6000 | zones | `climate: temperature out of range: N centi-celsius` |
| zone precipitation outside 0..10000000 | zones | `climate: precipitation out of range: N centi-mm` |
| unknown zone code | description | `climate: unknown zone code: <code>` |
| empty series | trends | `climate: empty series` |
| series longer than 1000 | trends | `climate: series too long: N` |
| series value outside +-1000000 | trends | `climate: series value out of range: N` |
| fewer than 2 values | trend, extrapolate | `climate: trend requires at least 2 values` |
| observed precipitation < 0 or > 1000000000 | anomaly | `climate: observed precipitation out of range: N centi-mm` |
| normal precipitation < 1 | anomaly | `climate: normal precipitation must be positive: N centi-mm` |

The suite pins the exact text of representative errors from every group.

## 11. Test plan

`tests/test_conformance.xi` (module `climate_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check; `main` returns the
failure count (0 = green) and prints one `[PASS]`/`[FAIL]` line per check.
No external files, no floating point, no `Vec[fn]` dispatch; every check is
deterministic.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | solar and albedo anchors | 1361; 300->952, 290->966, 0->1361, 1000->0 |
| t2 | albedo envelope | -1 and 1001 rejected with exact message |
| t3 | warming doubling/halving | 560/280->300, 1120/280->600, 140/280->-300, 280/280->0 |
| t4 | log2 interpolation | 420/280->175, 400/280->154, 700/280->396, 240/280->-67 |
| t5 | forcing anchors | 3710, 2170, 1906, 0, -3710 milli-W/m^2 |
| t6 | forcing/warming errors | co2/base/ecs envelopes with exact messages |
| t7 | relax step | 30, 150, 100, 0; rate and temperature errors |
| t8 | simulate trajectories | (0,300,100,5)->121; (300,0,500,2)->75; zero steps |
| t9 | simulate envelopes | steps -1/10001 and bad rate rejected |
| t10 | paleotemperature | 1690, 1252, 2128, 1471, 1914, 814 |
| t11 | paleotemperature envelope | +-1001 centi-permille rejected |
| t12 | inverse and asymmetry | 43, -300, 1502, 3004; temp 5001 rejected |
| t13 | layer age | 100, 30, 0; depth/rate errors |
| t14 | phase boundaries | -151..151 across both inclusive thresholds |
| t15 | linear scenario | 305, 270, 283; non-positive projection error |
| t16 | linear envelopes | start, years, growth messages |
| t17 | compound scenario | 300, 280, 990, 1000 |
| t18 | compound guards | full-decay growth, 501 years, 121000000 ppm overflow |
| t19 | scenario warming | 29, 0, 0, -474; ecs error |
| t20 | zone classification | all nine branches and boundary pairs 1799/1800, 49999/50000, 99999/100000, 199999/200000 |
| t21 | zone metadata | descriptions for all codes, unknown-code error, aridity predicate |
| t22 | trend mean | 200, 1 (floor), -2 (floor), empty error |
| t23 | least-squares slope | 100, -1000, 60, -1, 1; short series and value-envelope errors |
| t24 | extrapolate/count/anomaly | 170/150/120; strict counts; 200, -200, -667, -1000; envelope errors |

## 12. Provenance of expected values

Anchors that are conventional: 1361 W/m^2 solar constant; 3.71 W/m^2 per
CO2 doubling; 3.00 degC per doubling (ECS); 16.90 degC intercept and
4.38 degC/permille slope of the linear paleotemperature relation. Every
other expected value in the suite (interpolation outputs, floored negative
quotients, scenario trajectories, boundary classifications) was derived by
hand from the formulas in this document and `src/climate.xi` with floor
semantics, then checked against the implementation via the conformance
suite; the tests pin this package's algorithms, not an external dataset.
The log2 table knots are the correctly rounded values of `1000*log2(m)`.

## 13. Compiler / stdlib notes

No unsafe code and no FFI. The module follows the same v0.62.2 idioms as
`xiom.astronomy` and `xiom.geography`:

- free functions only; no methods, lambdas, generics or function tables;
- `Ok`/`Err` only inside the four leaf helpers, never in the public bodies;
- every `match` on a `Result` has both arms (exhaustive matches);
- `Str` comparisons go through `xiom.string.compare.str_compare`, notably
  in `zones_description` / `zones_is_arid`;
- `Vec[Int]` element reads bind a typed local first
  (`let y: Int = values[i];`);
- `&Vec[Int]` parameters are passed with an explicit `&` at every call
  site in the tests;
- all loops are bounded: log2 halving/doubling by the value's magnitude
  (or the ±1e9 permille clamp), simulation by `steps <= 10000`, compound
  scenarios by `years <= 500`, series scans by `n <= 1000`.

## 14. Known limitations

- The log2 approximation introduces up to 5 thousandths of a log2 unit of
  error in the radiative model; sensitivity results are model outputs, not
  scientific predictions.
- Paleotemperature is a linear approximation of the proxy relation; it
  ignores the quadratic term, salinity, ice volume and species effects,
  and its inverse is not an exact round-trip.
- Zone classification uses annual means only: no seasonality, no
  continentality, no elevation, no temperature-of-coldest-month input.
- Trends are ordinary least squares on the index `0..n-1`; no confidence
  intervals, no autocorrelation correction, no missing-data handling, no
  monthly aggregation.
- Scenario projections are pure extrapolations with no carbon-cycle
  feedbacks.
- Sub-unit precision below the documented scale (0.01 degC, 0.01 mm,
  0.01 permille) is not representable.
