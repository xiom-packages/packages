// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.climate: integer fixed-point climate helpers. Five libs:
// climate_model (solar absorption, CO2 forcing, warming, relaxation),
// paleo (d18O temperature, age, phase), scenarios (CO2 projection and
// warming), zones (nine climate-zone codes), trends (mean, least-squares
// trend, extrapolation, counts, precipitation anomalies). SPEC.md has the
// full behavior.
//
// Units: temperature centi-degC, precipitation centi-mm, CO2 ppm, forcing
// milli-W/m^2, d18O centi-permille, ratios permille, growth milli-ppm/year
// or basis points/year.
//
// Rounding: every division uses _floor_div (floor toward negative
// infinity); _log2_frac_permille has non-negative operands only. The log2
// of the radiative model is a 16-segment piecewise-linear integer
// approximation (knots in SPEC.md).
//
// XIOM v0.62.2: free functions only, no Vec[StructType]/Vec[Str]/Vec[fn],
// no floating point, exhaustive matches, Ok/Err only in leaf helpers,
// bounded loops.

module xiom.climate

use xiom.convert;
use xiom.string.compare;

// --- constants --------------------------------------------------------------

// Solar constant used by the energy-balance model.
const _SOLAR_CONST_WM2: Int = 1361;
// Radiative forcing per CO2 doubling, 3.710 W/m^2 in milli-W/m^2.
const _RF_PER_DOUBLING_MILLI_WM2: Int = 3710;
// Permille scale (1000 = one whole unit).
const _PERMILLE: Int = 1000;
// Basis-point scale (10000 = 100%).
const _BPS: Int = 10000;
// Accepted CO2 range for forcing/warming inputs and scenario start values.
const _CO2_LIMIT_PPM: Int = 1000000;
// Hard cap on compound-scenario CO2 to keep the loop overflow-free.
const _CO2_HARD_LIMIT_PPM: Int = 100000000;
// Maximum loop counts.
const _MAX_STEPS: Int = 10000;
const _SCENARIO_MAX_YEARS: Int = 1000;
const _COMPOUND_MAX_YEARS: Int = 500;
// Growth-rate envelopes for the scenario functions.
const _MAX_LINEAR_GROWTH_MILLI: Int = 100000;
const _MAX_GROWTH_BPS: Int = 100000;
// Series envelopes for the trends functions.
const _MAX_SERIES: Int = 1000;
const _MAX_SERIES_VALUE: Int = 1000000;
// Envelopes for paleo and model inputs.
const _TEMP_LIMIT_CENTI: Int = 100000;
const _D18O_LIMIT_CENTI: Int = 1000;
const _PALEOTEMP_LIMIT_CENTI: Int = 5000;
const _MAX_DEPTH_CM: Int = 1000000000;
const _ZONE_TEMP_MIN_CENTI: Int = -10000;
const _ZONE_TEMP_MAX_CENTI: Int = 6000;
const _MAX_PRECIP_CENTI_MM: Int = 10000000;

// --- Result constructors (leaf helpers; see the module header) --------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --- integer helpers --------------------------------------------------------

// Floor division; callers pass b > 0. Native / truncates toward zero, so
// negative remainders are adjusted down by one.
fn _floor_div(a: Int, b: Int) -> Int {
  var q = a / b;
  let r = a - q * b;
  if r < 0 { q = q - 1; }
  return q;
}

// Ratio a/b in permille, floored, clamped to at least 1 so the logarithm
// never sees zero or a negative input. Callers pass a > 0, b > 0.
fn _ratio_permille(a: Int, b: Int) -> Int {
  let r = _floor_div(a * _PERMILLE, b);
  if r < 1 { return 1; }
  return r;
}

// Piecewise-linear log2 of x in [1000, 2000), in thousandths of a log2 unit
// (1000 -> 0, 1500 -> 585, 2000 -> 1000). The 16-segment knot table is in
// SPEC.md; operands are non-negative so / truncates exactly like floor.
fn _log2_frac_permille(x: Int) -> Int {
  if x < 1062 { return (x - 1000) * 87 / 62; }
  if x < 1125 { return 87 + (x - 1062) * 83 / 63; }
  if x < 1187 { return 170 + (x - 1125) * 78 / 62; }
  if x < 1250 { return 248 + (x - 1187) * 74 / 63; }
  if x < 1312 { return 322 + (x - 1250) * 70 / 62; }
  if x < 1375 { return 392 + (x - 1312) * 67 / 63; }
  if x < 1437 { return 459 + (x - 1375) * 65 / 62; }
  if x < 1500 { return 524 + (x - 1437) * 61 / 63; }
  if x < 1562 { return 585 + (x - 1500) * 59 / 62; }
  if x < 1625 { return 644 + (x - 1562) * 56 / 63; }
  if x < 1687 { return 700 + (x - 1625) * 55 / 62; }
  if x < 1750 { return 755 + (x - 1687) * 52 / 63; }
  if x < 1812 { return 807 + (x - 1750) * 51 / 62; }
  if x < 1875 { return 858 + (x - 1812) * 49 / 63; }
  if x < 1937 { return 907 + (x - 1875) * 47 / 62; }
  return 954 + (x - 1937) * 46 / 63;
}

// log2 of a positive ratio in permille (1000 = 1.0), in thousandths of a
// log2 unit. Range reduction by exact halving/doubling of the integer
// mantissa, then the table above. Bounded: the halving loop halves a
// positive Int, the doubling loop stops at 1000.
fn _log2_permille(ratio_permille: Int) -> Int {
  var x = ratio_permille;
  if x < 1 { x = 1; }
  var k = 0;
  while x >= 2000 {
    x = (x + 1) / 2;
    k = k + 1;
  }
  while x < 1000 {
    x = x * 2;
    k = k - 1;
  }
  return k * _PERMILLE + _log2_frac_permille(x);
}

// Validate a trend series: non-empty, at most _MAX_SERIES values, every
// value within +-_MAX_SERIES_VALUE. Returns Ok(length) or Err(message).
fn _check_series(values: &Vec[Int]) -> Result[Int, Str] {
  let n = values.len();
  if n == 0 {
    return _err_int("climate: empty series");
  }
  if n > _MAX_SERIES {
    return _err_int("climate: series too long: " + convert.int_to_string(n));
  }
  var i = 0;
  while i < n {
    let y: Int = values[i];
    if y < 0 - _MAX_SERIES_VALUE || y > _MAX_SERIES_VALUE {
      return _err_int("climate: series value out of range: " + convert.int_to_string(y));
    }
    i = i + 1;
  }
  return _ok_int(n);
}

// Least-squares slope of values[i] against x = i, in centi-units per decade
// (10 steps). Assumes _check_series passed; the denominator n*Sxx - Sx^2 is
// positive for n >= 2. Floor division, so a negative fractional slope rounds
// away from zero.
fn _trend_per_decade(values: &Vec[Int]) -> Int {
  let n = values.len();
  var sx: Int = 0;
  var sy: Int = 0;
  var sxy: Int = 0;
  var sxx: Int = 0;
  var i = 0;
  while i < n {
    let y: Int = values[i];
    sx = sx + i;
    sy = sy + y;
    sxy = sxy + i * y;
    sxx = sxx + i * i;
    i = i + 1;
  }
  let den = n * sxx - sx * sx;
  let num = n * sxy - sx * sy;
  return _floor_div(10 * num, den);
}

// --- climate_model ----------------------------------------------------------

/// Solar constant of the energy-balance model, in W/m^2 (1361).
pub fn climate_solar_const_wm2() -> Int {
  return _SOLAR_CONST_WM2;
}

/// Absorbed solar radiation for a planetary albedo:
/// absorbed = floor(1361 * (1000 - albedo) / 1000).
/// Params: albedo_permille 0..1000 (0 = black body, 1000 = full mirror).
/// Returns: Ok(W/m^2); Err("climate: albedo out of range: N permille").
pub fn climate_absorbed_wm2(albedo_permille: Int) -> Result[Int, Str] {
  if albedo_permille < 0 || albedo_permille > _PERMILLE {
    return _err_int("climate: albedo out of range: " + convert.int_to_string(albedo_permille) + " permille");
  }
  return _ok_int(_floor_div(_SOLAR_CONST_WM2 * (_PERMILLE - albedo_permille), _PERMILLE));
}

/// CO2 radiative forcing relative to a baseline, in milli-W/m^2:
/// forcing = floor(3710 * log2(co2/base) / 1000) with the module's integer
/// 16-segment log2 (SPEC.md).
/// Params: co2_ppm, base_ppm 1..1000000.
/// Returns: Ok(milli-W/m^2); Err for out-of-range co2 or base.
pub fn climate_forcing_milli_wm2(co2_ppm: Int, base_ppm: Int) -> Result[Int, Str] {
  if co2_ppm < 1 || co2_ppm > _CO2_LIMIT_PPM {
    return _err_int("climate: co2 out of range: " + convert.int_to_string(co2_ppm) + " ppm");
  }
  if base_ppm < 1 || base_ppm > _CO2_LIMIT_PPM {
    return _err_int("climate: base co2 out of range: " + convert.int_to_string(base_ppm) + " ppm");
  }
  let ratio = _ratio_permille(co2_ppm, base_ppm);
  return _ok_int(_floor_div(_RF_PER_DOUBLING_MILLI_WM2 * _log2_permille(ratio), _PERMILLE));
}

/// Equilibrium warming for a CO2 change:
/// warming = floor(ecs_centi * log2(co2/base) / 1000).
/// Params: co2_ppm, base_ppm 1..1000000; ecs_centi 0..100000 (climate
/// sensitivity in centi-degC per CO2 doubling; 300 = 3.00 degC).
/// Returns: Ok(centi-degC); Err for out-of-range co2, base or ecs.
pub fn climate_equilibrium_warming_centi(co2_ppm: Int, base_ppm: Int, ecs_centi: Int) -> Result[Int, Str] {
  if co2_ppm < 1 || co2_ppm > _CO2_LIMIT_PPM {
    return _err_int("climate: co2 out of range: " + convert.int_to_string(co2_ppm) + " ppm");
  }
  if base_ppm < 1 || base_ppm > _CO2_LIMIT_PPM {
    return _err_int("climate: base co2 out of range: " + convert.int_to_string(base_ppm) + " ppm");
  }
  if ecs_centi < 0 || ecs_centi > 100000 {
    return _err_int("climate: ecs out of range: " + convert.int_to_string(ecs_centi) + " centi-celsius");
  }
  let ratio = _ratio_permille(co2_ppm, base_ppm);
  return _ok_int(_floor_div(ecs_centi * _log2_permille(ratio), _PERMILLE));
}

/// One discrete relaxation step toward a target:
/// next = current + floor((target - current) * rate / 1000).
/// Params: current/target +-100000 centi-degC; rate_permille 0..1000
/// (0 = no motion, 1000 = jump to target).
/// Returns: Ok(next); Err for an out-of-range rate or temperature.
pub fn climate_relax_step_centi(current_centi: Int, target_centi: Int, rate_permille: Int) -> Result[Int, Str] {
  if rate_permille < 0 || rate_permille > _PERMILLE {
    return _err_int("climate: relaxation rate out of range: " + convert.int_to_string(rate_permille) + " permille");
  }
  if current_centi < 0 - _TEMP_LIMIT_CENTI || current_centi > _TEMP_LIMIT_CENTI {
    return _err_int("climate: temperature out of range: " + convert.int_to_string(current_centi) + " centi-celsius");
  }
  if target_centi < 0 - _TEMP_LIMIT_CENTI || target_centi > _TEMP_LIMIT_CENTI {
    return _err_int("climate: temperature out of range: " + convert.int_to_string(target_centi) + " centi-celsius");
  }
  return _ok_int(current_centi + _floor_div((target_centi - current_centi) * rate_permille, _PERMILLE));
}

/// Iterate `steps` relaxation steps from start toward target using the same
/// floor rule as climate_relax_step_centi, so the trajectory is exactly the
/// documented integer one (it may asymptote instead of reaching). Params:
/// start/target +-100000 centi-degC; rate 0..1000; steps 0..10000.
pub fn climate_simulate_centi(start_centi: Int, target_centi: Int, rate_permille: Int, steps: Int) -> Result[Int, Str] {
  if steps < 0 || steps > _MAX_STEPS {
    return _err_int("climate: step count out of range: " + convert.int_to_string(steps));
  }
  if rate_permille < 0 || rate_permille > _PERMILLE {
    return _err_int("climate: relaxation rate out of range: " + convert.int_to_string(rate_permille) + " permille");
  }
  if start_centi < 0 - _TEMP_LIMIT_CENTI || start_centi > _TEMP_LIMIT_CENTI {
    return _err_int("climate: temperature out of range: " + convert.int_to_string(start_centi) + " centi-celsius");
  }
  if target_centi < 0 - _TEMP_LIMIT_CENTI || target_centi > _TEMP_LIMIT_CENTI {
    return _err_int("climate: temperature out of range: " + convert.int_to_string(target_centi) + " centi-celsius");
  }
  var t = start_centi;
  var i = 0;
  while i < steps {
    t = t + _floor_div((target_centi - t) * rate_permille, _PERMILLE);
    i = i + 1;
  }
  return _ok_int(t);
}

// --- paleo ------------------------------------------------------------------

/// Proxy temperature from calcite delta-18O (simplified linear relation):
/// T = 16.90 - 4.38*d18O, i.e. temperature_centi = 1690 - floor(438*d/100).
/// Params: d18o_centi_permille -1000..1000 (+-10.00 permille); returns
/// Ok(centi-degC) or Err for an out-of-range d18O.
pub fn paleo_temp_from_d18o_centi(d18o_centi_permille: Int) -> Result[Int, Str] {
  if d18o_centi_permille < 0 - _D18O_LIMIT_CENTI || d18o_centi_permille > _D18O_LIMIT_CENTI {
    return _err_int("climate: d18o out of range: " + convert.int_to_string(d18o_centi_permille) + " centi-permille");
  }
  return _ok_int(1690 - _floor_div(438 * d18o_centi_permille, 100));
}

/// Inverse of paleo_temp_from_d18o_centi with the same floor rule:
/// d = floor((1690 - temp) * 100 / 438). The pair is not an exact
/// round-trip (each side rounds by up to 1 centi-unit; SPEC.md lists pairs).
pub fn paleo_d18o_from_temp_centi(temp_centi: Int) -> Result[Int, Str] {
  if temp_centi < 0 - _PALEOTEMP_LIMIT_CENTI || temp_centi > _PALEOTEMP_LIMIT_CENTI {
    return _err_int("climate: temperature out of range: " + convert.int_to_string(temp_centi) + " centi-celsius");
  }
  return _ok_int(_floor_div((1690 - temp_centi) * 100, 438));
}

/// Age of a sediment layer at a constant accumulation rate:
/// age_ka = floor(depth_cm * 10 / accumulation_mm_per_ka).
/// Params: depth_cm 0..1000000000; accumulation_mm_per_ka >= 1.
/// Returns: Ok(ka); Err for a negative depth or a non-positive rate.
pub fn paleo_age_ka(depth_cm: Int, accumulation_mm_per_ka: Int) -> Result[Int, Str] {
  if depth_cm < 0 || depth_cm > _MAX_DEPTH_CM {
    return _err_int("climate: depth out of range: " + convert.int_to_string(depth_cm) + " cm");
  }
  if accumulation_mm_per_ka < 1 {
    return _err_int("climate: accumulation rate must be positive: " + convert.int_to_string(accumulation_mm_per_ka) + " mm/ka");
  }
  return _ok_int(_floor_div(depth_cm * 10, accumulation_mm_per_ka));
}

/// Three-way paleoclimate phase from delta-18O (centi-permille):
/// d <= -150 -> "warm interglacial"; d >= 150 -> "cold glacial"; otherwise
/// "transitional".
/// Params: d18o_centi_permille -1000..1000.
/// Returns: Ok(phase); Err("climate: d18o out of range: N centi-permille").
pub fn paleo_climate_phase(d18o_centi_permille: Int) -> Result[Str, Str] {
  if d18o_centi_permille < 0 - _D18O_LIMIT_CENTI || d18o_centi_permille > _D18O_LIMIT_CENTI {
    return _err_str("climate: d18o out of range: " + convert.int_to_string(d18o_centi_permille) + " centi-permille");
  }
  if d18o_centi_permille <= -150 { return _ok_str("warm interglacial"); }
  if d18o_centi_permille >= 150 { return _ok_str("cold glacial"); }
  return _ok_str("transitional");
}

// --- scenarios --------------------------------------------------------------

// Validate a scenario start value. Returns Ok(start) when acceptable.
fn _check_scenario_start(start_ppm: Int) -> Result[Int, Str] {
  if start_ppm < 1 || start_ppm > _CO2_LIMIT_PPM {
    return _err_int("climate: co2 start must be positive: " + convert.int_to_string(start_ppm) + " ppm");
  }
  return _ok_int(start_ppm);
}

// Compound a scenario year by year, guarding non-positive and overflowing
// CO2 values. years is assumed validated and 0.._COMPOUND_MAX_YEARS.
fn _co2_compound_checked(start_ppm: Int, growth_bps_per_year: Int, years: Int) -> Result[Int, Str] {
  var v = start_ppm;
  var i = 0;
  while i < years {
    v = v + _floor_div(v * growth_bps_per_year, _BPS);
    if v <= 0 {
      return _err_int("climate: projected co2 non-positive: " + convert.int_to_string(v) + " ppm");
    }
    if v > _CO2_HARD_LIMIT_PPM {
      return _err_int("climate: projected co2 exceeds limit: " + convert.int_to_string(v) + " ppm");
    }
    i = i + 1;
  }
  return _ok_int(v);
}

/// Linear CO2 scenario: start + floor(growth * years / 1000), growth in
/// milli-ppm per year (negative values model mitigation).
/// Params: start_ppm 1..1000000; growth +-100000; years 0..1000.
/// Returns: Ok(ppm); Err for out-of-range inputs or a non-positive
/// projection.
pub fn scenarios_co2_linear(start_ppm: Int, growth_milli_ppm_per_year: Int, years: Int) -> Result[Int, Str] {
  let sr = _check_scenario_start(start_ppm);
  match sr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  }
  if growth_milli_ppm_per_year < 0 - _MAX_LINEAR_GROWTH_MILLI || growth_milli_ppm_per_year > _MAX_LINEAR_GROWTH_MILLI {
    return _err_int("climate: growth rate out of range: " + convert.int_to_string(growth_milli_ppm_per_year) + " milli-ppm/year");
  }
  if years < 0 || years > _SCENARIO_MAX_YEARS {
    return _err_int("climate: year count out of range: " + convert.int_to_string(years));
  }
  let v = start_ppm + _floor_div(growth_milli_ppm_per_year * years, _PERMILLE);
  if v <= 0 {
    return _err_int("climate: projected co2 non-positive: " + convert.int_to_string(v) + " ppm");
  }
  return _ok_int(v);
}

/// Compound CO2 scenario: each year v = v + floor(v * growth_bps / 10000),
/// with growth in basis points per year (100 = 1%/year; -10000 rejected).
/// Runs year by year with floor rounding, so results are reproducible.
/// Params: start_ppm 1..1000000; growth_bps -9999..100000; years 0..500.
pub fn scenarios_co2_compound(start_ppm: Int, growth_bps_per_year: Int, years: Int) -> Result[Int, Str] {
  let sr = _check_scenario_start(start_ppm);
  match sr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  }
  if growth_bps_per_year < 0 - (_BPS - 1) || growth_bps_per_year > _MAX_GROWTH_BPS {
    return _err_int("climate: growth rate out of range: " + convert.int_to_string(growth_bps_per_year) + " bps");
  }
  if years < 0 || years > _COMPOUND_MAX_YEARS {
    return _err_int("climate: year count out of range: " + convert.int_to_string(years));
  }
  return _co2_compound_checked(start_ppm, growth_bps_per_year, years);
}

/// Warming implied by a compound CO2 scenario:
/// warming = floor(ecs_centi * log2(projected/start) / 1000) with the
/// module's integer log2; negative for a shrinking scenario. Params:
/// start_ppm 1..1000000; growth_bps -9999..100000; years 0..500; ecs 0..100000.
pub fn scenarios_warming_centi(start_ppm: Int, growth_bps_per_year: Int, years: Int, ecs_centi: Int) -> Result[Int, Str] {
  let sr = _check_scenario_start(start_ppm);
  match sr {
    Ok(_) => {},
    Err(e) => { return _err_int(e); },
  }
  if growth_bps_per_year < 0 - (_BPS - 1) || growth_bps_per_year > _MAX_GROWTH_BPS {
    return _err_int("climate: growth rate out of range: " + convert.int_to_string(growth_bps_per_year) + " bps");
  }
  if years < 0 || years > _COMPOUND_MAX_YEARS {
    return _err_int("climate: year count out of range: " + convert.int_to_string(years));
  }
  if ecs_centi < 0 || ecs_centi > 100000 {
    return _err_int("climate: ecs out of range: " + convert.int_to_string(ecs_centi) + " centi-celsius");
  }
  let c = _co2_compound_checked(start_ppm, growth_bps_per_year, years);
  var co2_ppm: Int = 0;
  match c {
    Ok(v) => { co2_ppm = v; },
    Err(e) => { return _err_int(e); },
  }
  let ratio = _ratio_permille(co2_ppm, start_ppm);
  return _ok_int(_floor_div(ecs_centi * _log2_permille(ratio), _PERMILLE));
}

// --- zones ------------------------------------------------------------------

// Validate zone inputs (temperature and precipitation envelopes).
fn _check_zone_inputs(temp_centi: Int, precip_centi_mm: Int) -> Result[Int, Str] {
  if temp_centi < _ZONE_TEMP_MIN_CENTI || temp_centi > _ZONE_TEMP_MAX_CENTI {
    return _err_int("climate: temperature out of range: " + convert.int_to_string(temp_centi) + " centi-celsius");
  }
  if precip_centi_mm < 0 || precip_centi_mm > _MAX_PRECIP_CENTI_MM {
    return _err_int("climate: precipitation out of range: " + convert.int_to_string(precip_centi_mm) + " centi-mm");
  }
  return _ok_int(0);
}

/// Climate-zone code from annual-mean temperature and precipitation.
/// Precedence (inclusive on the wetter/warmer side): temp < 0 -> "EF";
/// temp < 1000 -> "ET"; temp >= 1800: precip >= 200000/100000/50000 ->
/// "Af"/"Am"/"Aw", else "BW"; temp < 1800: precip < 25000 -> "BW",
/// < 50000 -> "BS", >= 100000 -> "Cf", else "Cs". Seasonality is not an
/// input, so Cf/Cs name totals only (documented simplification).
/// Params: temp_centi -10000..6000; precip_centi_mm 0..10000000.
/// Returns: Ok(code); Err for out-of-range inputs.
pub fn zones_classify(temp_centi: Int, precip_centi_mm: Int) -> Result[Str, Str] {
  let zr = _check_zone_inputs(temp_centi, precip_centi_mm);
  match zr {
    Ok(_) => {},
    Err(e) => { return _err_str(e); },
  }
  if temp_centi < 0 { return _ok_str("EF"); }
  if temp_centi < 1000 { return _ok_str("ET"); }
  if temp_centi >= 1800 {
    if precip_centi_mm >= 200000 { return _ok_str("Af"); }
    if precip_centi_mm >= 100000 { return _ok_str("Am"); }
    if precip_centi_mm >= 50000 { return _ok_str("Aw"); }
    return _ok_str("BW");
  }
  if precip_centi_mm < 25000 { return _ok_str("BW"); }
  if precip_centi_mm < 50000 { return _ok_str("BS"); }
  if precip_centi_mm >= 100000 { return _ok_str("Cf"); }
  return _ok_str("Cs");
}

/// Long description of a zone code (Af, Am, Aw, BW, BS, Cf, Cs, ET, EF).
/// Returns: Ok(description); Err("climate: unknown zone code: <code>").
pub fn zones_description(code: Str) -> Result[Str, Str] {
  if compare.str_compare(code, "Af") == 0 { return _ok_str("tropical rainforest"); }
  if compare.str_compare(code, "Am") == 0 { return _ok_str("tropical monsoon"); }
  if compare.str_compare(code, "Aw") == 0 { return _ok_str("tropical savanna"); }
  if compare.str_compare(code, "BW") == 0 { return _ok_str("desert"); }
  if compare.str_compare(code, "BS") == 0 { return _ok_str("steppe"); }
  if compare.str_compare(code, "Cf") == 0 { return _ok_str("humid temperate"); }
  if compare.str_compare(code, "Cs") == 0 { return _ok_str("seasonal temperate"); }
  if compare.str_compare(code, "ET") == 0 { return _ok_str("tundra"); }
  if compare.str_compare(code, "EF") == 0 { return _ok_str("polar frost"); }
  return _err_str("climate: unknown zone code: " + code);
}

/// True when a zone code is arid ("BW" or "BS"); false otherwise,
/// including unknown codes.
pub fn zones_is_arid(code: Str) -> Bool {
  if compare.str_compare(code, "BW") == 0 { return true; }
  if compare.str_compare(code, "BS") == 0 { return true; }
  return false;
}

// --- trends -----------------------------------------------------------------

/// Arithmetic mean of a series, floored: floor(sum/length), in series units
/// (centi-degC or centi-mm). [1,2] -> 1, [-1,-2] -> -2.
/// Params: values - non-empty, at most 1000 values within +-1000000.
/// Returns: Ok(mean); Err for empty/oversized/out-of-range series.
pub fn trends_mean_centi(values: &Vec[Int]) -> Result[Int, Str] {
  let checked = _check_series(values);
  var n: Int = 0;
  match checked {
    Ok(v) => { n = v; },
    Err(e) => { return _err_int(e); },
  }
  var sum: Int = 0;
  var i = 0;
  while i < n {
    let y: Int = values[i];
    sum = sum + y;
    i = i + 1;
  }
  return _ok_int(_floor_div(sum, n));
}

/// Least-squares linear trend against year index 0, 1, 2, ..., in series
/// units per decade: slope = floored (n*Sxy - Sx*Sy)/(n*Sxx - Sx*Sx) * 10
/// (Sx=sum(i), Sy=sum(y), Sxy=sum(i*y), Sxx=sum(i*i)). The denominator is
/// positive for n >= 2; a negative fractional slope rounds away from zero
/// (e.g. -0.29 -> -1). Params: values 2..1000 within +-1000000.
pub fn trends_linear_trend_centi_per_decade(values: &Vec[Int]) -> Result[Int, Str] {
  let checked = _check_series(values);
  var n: Int = 0;
  match checked {
    Ok(v) => { n = v; },
    Err(e) => { return _err_int(e); },
  }
  if n < 2 {
    return _err_int("climate: trend requires at least 2 values");
  }
  return _ok_int(_trend_per_decade(values));
}

/// Extrapolate a series `steps` beyond its last value with the floored
/// per-decade trend: projected = last + floor(trend_per_decade * steps / 10).
/// Params: values - as trends_linear_trend_centi_per_decade; steps 0..10000
/// (fractional decade steps are allowed and floor normally).
/// Returns: Ok(projected); Err for an out-of-range step count or a series
/// rejected by the trend checks.
pub fn trends_extrapolate_centi(values: &Vec[Int], steps: Int) -> Result[Int, Str] {
  if steps < 0 || steps > _MAX_STEPS {
    return _err_int("climate: step count out of range: " + convert.int_to_string(steps));
  }
  let tr = trends_linear_trend_centi_per_decade(values);
  var slope: Int = 0;
  match tr {
    Ok(v) => { slope = v; },
    Err(e) => { return _err_int(e); },
  }
  let n = values.len();
  let last: Int = values[n - 1];
  return _ok_int(last + _floor_div(slope * steps, 10));
}

/// Number of values strictly greater than `threshold`.
/// Params: values - non-empty, at most 1000 values within +-1000000.
/// Returns: Ok(count); Err for a series rejected by _check_series.
pub fn trends_count_above(values: &Vec[Int], threshold: Int) -> Result[Int, Str] {
  let checked = _check_series(values);
  var n: Int = 0;
  match checked {
    Ok(v) => { n = v; },
    Err(e) => { return _err_int(e); },
  }
  var count: Int = 0;
  var i = 0;
  while i < n {
    let y: Int = values[i];
    if y > threshold { count = count + 1; }
    i = i + 1;
  }
  return _ok_int(count);
}

/// Precipitation anomaly relative to a normal, in permille:
/// anomaly = floor((observed - normal) * 1000 / normal). 120.00 mm against
/// 100.00 mm is +200; 10.00 mm against 30.00 mm is -667 (floor of -666.6).
/// Params: observed_centi_mm 0..1000000000; normal_centi_mm >= 1.
/// Returns: Ok(permille); Err for a negative observed or non-positive normal.
pub fn trends_precip_anomaly_permille(observed_centi_mm: Int, normal_centi_mm: Int) -> Result[Int, Str] {
  if observed_centi_mm < 0 || observed_centi_mm > _MAX_DEPTH_CM {
    return _err_int("climate: observed precipitation out of range: " + convert.int_to_string(observed_centi_mm) + " centi-mm");
  }
  if normal_centi_mm < 1 {
    return _err_int("climate: normal precipitation must be positive: " + convert.int_to_string(normal_centi_mm) + " centi-mm");
  }
  return _ok_int(_floor_div((observed_centi_mm - normal_centi_mm) * _PERMILLE, normal_centi_mm));
}
