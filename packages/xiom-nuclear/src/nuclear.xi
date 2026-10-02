// XIOM -- xiom.nuclear: deterministic integer/fixed-point nuclear physics
//   decay (half-life, activity, remaining atoms), fission and fusion Q-values
//   and energy release, isotope data + nuclear notation, cross-section lookup,
//   and radiation dose/attenuation estimates.
// Port task: replace the xiom.nuclear placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Unit and rounding conventions (full details in SPEC.md):
//   * fractions are permille (1000 = 1.0); *_x1e4 names are scaled by 1e4;
//   * energies and mass excesses are keV (Int); half-lives are seconds and
//     one Julian year is 31557600 s; ln(2) = 693147 x 1e-6;
//   * sample mass is nanograms (ng), molar mass g/mol; Avogadro's number is
//     stored divided by 1e15 as 602214076 (N_A = 6.02214076e23 /mol);
//   * cross-sections are millibarns (1 b = 1e-24 cm2); macroscopic
//     cross-sections are 1e-6 /cm from densities in 1e21 /cm3;
//   * dose is microgray (uGy); 1 MeV = 1.602176634e-13 J = 160.2176634 aJ;
//   * every division is XIOM Int division truncating toward zero; the stepwise
//     half-life model quantizes elapsed time to whole half-lives.
// All functions are free functions; no FFI, no floating point, no
// Vec[StructType], no Result/Option payloads (documented -1/0 sentinels). The
// isotope dataset is a small built-in illustrative table (see SPEC.md).

module xiom.nuclear

use xiom.convert;

// --- constants --------------------------------------------------------------

// Fraction scale used by the *_permille accessors (1000 = 1.0).
const _PERMILLE: Int = 1000;
// Scale used by *_x1e4 accessors (10000 = 1.0).
const _SCALE_X1E4: Int = 10000;
// ln(2) scaled by 1e6: 0.693147 -> 693147.
const _LN2_X1E6: Int = 693147;
// Avogadro's number divided by 1e15: 6.02214076e23 -> 602214076.
const _NA_X1E15: Int = 602214076;
// One Julian year in seconds (365.25 d).
const _SECONDS_PER_YEAR: Int = 31557600;
// 1 keV in attojoules: 1.602176634e-16 J = 160.2176634 aJ, i.e. the integer
// 1602176634 carries seven implied fractional decimals.
const _KEV_TO_AJ_X1E7: Int = 1602176634;
// Dose-chain coefficient: 1 MeV = 1.602176634e-4 uGy per gram of absorber,
// i.e. 1602176634 with an implied 1e13 denominator (see nuc_dose_microgy).
const _DOSE_COEFF_X1E13: Int = 1602176634;
// Coulomb constant in keV*fm: e^2/(4*pi*eps0) = 1.44 MeV*fm = 1440 keV*fm.
const _COULOMB_KEV_FM: Int = 1440;
// Neutron mass excess in keV (AME-scale rounded value).
const _NEUTRON_EXCESS_KEV: Int = 8071;
// Prompt energy per U-235 fission event in keV (the conventional ~202.5 MeV).
const _FISSION_KEV_PER_EVENT: Int = 202500;

// --- scale + metadata -------------------------------------------------------

/// Fraction scale: 1000 permille = 1.0.
/// Params: none. Returns: 1000. Complexity: O(1).
pub fn nuc_permille() -> Int {
  return _PERMILLE;
}

/// Scale of every *_x1e4 quantity: 10000 = 1.0.
/// Params: none. Returns: 10000. Complexity: O(1).
pub fn nuc_scale_x1e4() -> Int {
  return _SCALE_X1E4;
}

/// ln(2) scaled by 1e6 (0.693147 -> 693147).
/// Params: none. Returns: 693147. Complexity: O(1).
pub fn nuc_ln2_x1e6() -> Int {
  return _LN2_X1E6;
}

/// Avogadro's number divided by 1e15 (602214076).
/// Params: none. Returns: 602214076. Complexity: O(1).
pub fn nuc_avogadro_x1e15() -> Int {
  return _NA_X1E15;
}

/// One Julian year in seconds (365.25 d).
/// Params: none. Returns: 31557600. Complexity: O(1).
pub fn nuc_seconds_per_year() -> Int {
  return _SECONDS_PER_YEAR;
}

/// Neutron mass excess in keV, used to complete fission Q-values.
/// Params: none. Returns: 8071. Complexity: O(1).
pub fn nuc_neutron_excess_kev() -> Int {
  return _NEUTRON_EXCESS_KEV;
}

/// Overflow guard for a product: true when |a| * |b| exceeds Int range.
/// Params: a, b - factors (Int min is outside the envelope). Returns: true
/// iff the product would overflow 64-bit signed Int. Complexity: O(1).
pub fn nuc_mul_overflows(a: Int, b: Int) -> Bool {
  if a == 0 || b == 0 {
    return false;
  }
  var aa = a;
  if aa < 0 {
    aa = 0 - aa;
  }
  var bb = b;
  if bb < 0 {
    bb = 0 - bb;
  }
  return aa > 9223372036854775807 / bb;
}

// --- decay ------------------------------------------------------------------

/// Whole half-lives elapsed: floor(elapsed / half_life); 0 when half_life or
/// elapsed is non-positive. Params: half_life_s, elapsed_s - seconds.
/// Returns: the truncated count. Complexity: O(1).
pub fn nuc_halflives_elapsed(half_life_s: Int, elapsed_s: Int) -> Int {
  if half_life_s <= 0 || elapsed_s <= 0 {
    return 0;
  }
  return elapsed_s / half_life_s;
}

/// Remaining fraction after `elapsed_s`, in permille of the initial amount.
/// Stepwise model: each whole half-life halves it (1000, 500, 250, ...) and
/// the fraction reaches 0 at 10 or more half-lives. Params: half_life_s,
/// elapsed_s - seconds. Returns: 1000 >> floor(elapsed/half_life) permille.
/// Error: non-positive half-life or elapsed returns 1000. Complexity: O(1),
/// at most 10 halving iterations; each iteration halves f and decrements n.
pub fn nuc_decay_factor_permille(half_life_s: Int, elapsed_s: Int) -> Int {
  var n = nuc_halflives_elapsed(half_life_s, elapsed_s);
  var f = _PERMILLE;
  while n > 0 && f > 0 {
    f = f / 2;
    n = n - 1;
  }
  return f;
}

/// Remaining atoms after `elapsed_s` under the stepwise half-life model.
/// Params: atoms (>= 0); half_life_s, elapsed_s - seconds. Returns:
/// atoms * factor_permille / 1000 (truncated); 0 for atoms <= 0.
/// Complexity: O(1).
pub fn nuc_remaining_atoms(atoms: Int, half_life_s: Int, elapsed_s: Int) -> Int {
  if atoms <= 0 {
    return 0;
  }
  return atoms * nuc_decay_factor_permille(half_life_s, elapsed_s) / _PERMILLE;
}

/// Remaining activity in becquerel after `elapsed_s`.
/// Params: activity_bq (>= 0); half_life_s, elapsed_s - seconds. Returns:
/// activity_bq * factor_permille / 1000 (truncated); 0 for activity_bq <= 0.
/// Complexity: O(1).
pub fn nuc_remaining_activity_bq(activity_bq: Int, half_life_s: Int, elapsed_s: Int) -> Int {
  if activity_bq <= 0 {
    return 0;
  }
  return activity_bq * nuc_decay_factor_permille(half_life_s, elapsed_s) / _PERMILLE;
}

/// Decay constant lambda = ln(2) / half_life, scaled by 1e18 per second.
/// Params: half_life_s - seconds (> 0). Returns: 693147 * 1e12 / half_life_s;
/// 0 for half_life_s <= 0. Error: non-positive half-life returns 0.
/// Complexity: O(1).
pub fn nuc_decay_constant_per_s_x1e18(half_life_s: Int) -> Int {
  if half_life_s <= 0 {
    return 0;
  }
  return _LN2_X1E6 * 1000000000000 / half_life_s;
}

/// Mean lifetime tau = half_life / ln(2), in seconds.
/// Params: half_life_s - seconds (> 0). Returns: half_life_s * 1e6 / 693147
/// (truncated); 0 for half_life_s <= 0. Complexity: O(1).
pub fn nuc_mean_lifetime_s(half_life_s: Int) -> Int {
  if half_life_s <= 0 {
    return 0;
  }
  return half_life_s * 1000000 / _LN2_X1E6;
}

/// Atom count in a sample: N = mass * N_A / M, evaluated as
/// (mass_ng * 602214076 / M) * 1e6. Params: mass_ng - mass in nanograms
/// (> 0); molar_mass_g_per_mol (> 0). Returns: atoms (truncated); 0 for
/// non-positive inputs. The intermediate mass_ng * 602214076 must fit Int.
/// Complexity: O(1).
pub fn nuc_atoms_from_mass(mass_ng: Int, molar_mass_g_per_mol: Int) -> Int {
  if mass_ng <= 0 || molar_mass_g_per_mol <= 0 {
    return 0;
  }
  return (mass_ng * _NA_X1E15 / molar_mass_g_per_mol) * 1000000;
}

/// Sample mass in nanograms from an atom count (inverse of
/// nuc_atoms_from_mass); two-step truncation can lose up to 1 ng.
/// Params: atoms (> 0); molar_mass_g_per_mol (> 0). Returns:
/// (atoms / 1e6) * M / 602214076; 0 for non-positive inputs. Complexity: O(1).
pub fn nuc_mass_from_atoms(atoms: Int, molar_mass_g_per_mol: Int) -> Int {
  if atoms <= 0 || molar_mass_g_per_mol <= 0 {
    return 0;
  }
  return (atoms / 1000000) * molar_mass_g_per_mol / _NA_X1E15;
}

/// Activity of a pure nuclide: A = lambda * N = N * ln2 / (half_life * 1e6).
/// The quotient N / half_life is taken first (documented truncation: activity
/// below ~1 Bq quantizes to 0). Params: atoms (> 0); half_life_s (> 0).
/// Returns: Bq (truncated); 0 for non-positive inputs. Complexity: O(1).
pub fn nuc_activity_bq(atoms: Int, half_life_s: Int) -> Int {
  if atoms <= 0 || half_life_s <= 0 {
    return 0;
  }
  let q = atoms / half_life_s;
  return q * _LN2_X1E6 / 1000000;
}

// --- fission ----------------------------------------------------------------

/// Prompt energy per U-235 thermal fission event: 202500 keV (202.5 MeV).
/// Params: none. Returns: 202500. Complexity: O(1).
pub fn nuc_fission_energy_per_event_kev() -> Int {
  return _FISSION_KEV_PER_EVENT;
}

/// Total fission energy in keV for `events` events at `kev_per_event` keV.
/// Params: events (> 0); kev_per_event (> 0). Returns: events *
/// kev_per_event; 0 for non-positive inputs; -1 when the product overflows
/// Int (pre-checked with nuc_mul_overflows). Complexity: O(1).
pub fn nuc_fission_energy_total_kev(events: Int, kev_per_event: Int) -> Int {
  if events <= 0 || kev_per_event <= 0 {
    return 0;
  }
  if nuc_mul_overflows(events, kev_per_event) {
    return -1;
  }
  return events * kev_per_event;
}

/// Reaction Q-value: Q = sum(reactant mass excesses) - sum(product mass
/// excesses), in keV; Q > 0 is exothermic. Params: reactant_excess_kev,
/// product_excess_kev - totals in keV. Returns: signed Q in keV.
/// Complexity: O(1).
pub fn nuc_q_value_kev(reactant_excess_kev: Int, product_excess_kev: Int) -> Int {
  return reactant_excess_kev - product_excess_kev;
}

/// True when a reaction Q-value is energy-releasing (strict Q > 0).
/// Params: q_kev - reaction Q-value in keV. Returns: true iff q_kev > 0.
/// Complexity: O(1).
pub fn nuc_reaction_feasible_kev(q_kev: Int) -> Bool {
  return q_kev > 0;
}

/// keV -> attojoules: 1 keV = 160.2176634 aJ, so the integer result is
/// kev * 1602176634 / 1e7 (truncated to 1 aJ). Params: kev (>= 0); returns 0
/// for kev <= 0. Complexity: O(1).
pub fn nuc_kev_to_aj(kev: Int) -> Int {
  if kev <= 0 {
    return 0;
  }
  return kev * _KEV_TO_AJ_X1E7 / 10000000;
}

// --- fusion -----------------------------------------------------------------

/// Classical Coulomb barrier: V = 1440 keV*fm * Z1 * Z2 / distance_fm.
/// Params: z1, z2 - atomic numbers (>= 0); distance_fm - separation in fm
/// (> 0). Returns: barrier in keV (truncated); -1 for distance_fm <= 0 or a
/// negative atomic number. Error: undefined geometry returns -1. O(1).
pub fn nuc_coulomb_barrier_kev(z1: Int, z2: Int, distance_fm: Int) -> Int {
  if distance_fm <= 0 {
    return -1;
  }
  if z1 < 0 || z2 < 0 {
    return -1;
  }
  return _COULOMB_KEV_FM * z1 * z2 / distance_fm;
}

/// Classical fusion feasibility: the projectile energy must reach the
/// Coulomb barrier (no quantum tunnelling is modeled). Params: z1, z2;
/// distance_fm; projectile_kev - centre-of-mass energy in keV. Returns: true
/// iff the barrier is defined and projectile_kev >= barrier; an undefined
/// barrier (distance_fm <= 0) returns false. Complexity: O(1).
pub fn nuc_fusion_feasible(z1: Int, z2: Int, distance_fm: Int, projectile_kev: Int) -> Bool {
  let barrier = nuc_coulomb_barrier_kev(z1, z2, distance_fm);
  if barrier < 0 {
    return false;
  }
  return projectile_kev >= barrier;
}

/// Fusion energy gain Q/input scaled by 1e4 (10000 = break-even).
/// Params: q_kev - reaction Q-value in keV; input_kev - driver energy (> 0).
/// Returns: 10000 * q_kev / input_kev (truncated); -1 when input_kev <= 0.
/// Complexity: O(1).
pub fn nuc_fusion_gain_x1e4(q_kev: Int, input_kev: Int) -> Int {
  if input_kev <= 0 {
    return -1;
  }
  return _SCALE_X1E4 * q_kev / input_kev;
}

// --- radiation --------------------------------------------------------------

/// Absorbed dose estimate in microgray from a pure nuclide:
/// D = A * t * f * E * 1.602176634e-4 / mass_g, coefficient 1602176634/1e13,
/// truncating at each step. Params: activity_bq (> 0); energy_mev (> 0);
/// fraction_permille (0..1000); seconds (> 0); mass_g (> 0). Returns: uGy
/// (truncated); 0 for a non-positive source/time/energy/fraction; -1 for
/// mass_g <= 0. Complexity: O(1).
pub fn nuc_dose_microgy(activity_bq: Int, energy_mev: Int, fraction_permille: Int, seconds: Int, mass_g: Int) -> Int {
  if mass_g <= 0 {
    return -1;
  }
  if activity_bq <= 0 || energy_mev <= 0 || fraction_permille <= 0 || seconds <= 0 {
    return 0;
  }
  let decays = activity_bq * seconds;
  let effective = decays * fraction_permille / _PERMILLE;
  let e_mev = effective * energy_mev;
  return e_mev * _DOSE_COEFF_X1E13 / 1000000 / 10000000 / mass_g;
}

/// Dose rate in microgray per hour: nuc_dose_microgy over a 3600 s exposure.
/// Params: as nuc_dose_microgy. Returns: uGy/h; -1 for mass_g <= 0.
/// Complexity: O(1).
pub fn nuc_dose_rate_microgy_per_h(activity_bq: Int, energy_mev: Int, fraction_permille: Int, mass_g: Int) -> Int {
  return nuc_dose_microgy(activity_bq, energy_mev, fraction_permille, 3600, mass_g);
}

/// Transmitted intensity in permille through `thickness_mm` of a shield with
/// half-value layer `hvl_mm`. Stepwise model: each whole HVL halves the
/// intensity (1000, 500, 250, ...), reaching 0 at 10 or more HVLs.
/// Params: hvl_mm (> 0); thickness_mm (>= 0). Returns: transmitted permille;
/// 1000 for non-positive HVL or thickness (no attenuation). Complexity: O(1),
/// at most 10 halving iterations; each halves f and decrements the layers.
pub fn nuc_hvl_attenuation_permille(hvl_mm: Int, thickness_mm: Int) -> Int {
  if hvl_mm <= 0 || thickness_mm <= 0 {
    return _PERMILLE;
  }
  var layers = thickness_mm / hvl_mm;
  var f = _PERMILLE;
  while layers > 0 && f > 0 {
    f = f / 2;
    layers = layers - 1;
  }
  return f;
}

// --- cross sections ---------------------------------------------------------

/// Interaction channel code for radiative neutron capture. Returns: 1. O(1).
pub fn nuc_xs_channel_capture() -> Int {
  return 1;
}

/// Interaction channel code for fission. Returns: 2. O(1).
pub fn nuc_xs_channel_fission() -> Int {
  return 2;
}

/// Interaction channel code for (elastic) scattering. Returns: 3. O(1).
pub fn nuc_xs_channel_scatter() -> Int {
  return 3;
}

/// Microscopic cross-section in millibarns from the built-in isotope dataset
/// (thermal/representative values): channel 1 = capture, 2 = fission,
/// 3 = scattering. Params: z, a - atomic and mass number; channel - 1/2/3.
/// Returns: millibarns; -1 when the isotope or channel is not in the dataset
/// (a tabulated zero, e.g. U-238 fission, is returned as 0). Complexity: O(1).
pub fn nuc_xs_millibarns(z: Int, a: Int, channel: Int) -> Int {
  if channel < 1 || channel > 3 {
    return -1;
  }
  if z == 1 && a == 1 {
    if channel == 1 { return 332; }
    if channel == 3 { return 20000; }
    return -1;
  }
  if z == 1 && a == 2 {
    if channel == 3 { return 3300; }
    return -1;
  }
  if z == 2 && a == 4 {
    if channel == 3 { return 800; }
    return -1;
  }
  if z == 5 && a == 10 {
    if channel == 1 { return 3837000; }
    if channel == 3 { return 2000; }
    return -1;
  }
  if z == 6 && a == 12 {
    if channel == 1 { return 3; }
    if channel == 3 { return 3500; }
    return -1;
  }
  if z == 48 && a == 113 {
    if channel == 1 { return 20600000; }
    return -1;
  }
  if z == 54 && a == 135 {
    if channel == 1 { return 2650000000; }
    return -1;
  }
  if z == 92 && a == 235 {
    if channel == 1 { return 99000; }
    if channel == 2 { return 585000; }
    if channel == 3 { return 15000; }
    return -1;
  }
  if z == 92 && a == 238 {
    if channel == 1 { return 2680; }
    if channel == 2 { return 0; }
    if channel == 3 { return 9000; }
    return -1;
  }
  if z == 94 && a == 239 {
    if channel == 1 { return 271000; }
    if channel == 2 { return 750000; }
    return -1;
  }
  return -1;
}

/// Macroscopic cross-section: Sigma = n * sigma, in units of 1e-6 /cm when
/// the density is in 1e21 /cm3 and sigma in millibarns. Params:
/// atoms_per_cm3_e21 (>= 0); xs_millibarns (>= 0). Returns: n * sigma;
/// 0 for non-positive inputs. Complexity: O(1).
pub fn nuc_macro_xs_per_cm_x1e6(atoms_per_cm3_e21: Int, xs_millibarns: Int) -> Int {
  if atoms_per_cm3_e21 <= 0 || xs_millibarns <= 0 {
    return 0;
  }
  return atoms_per_cm3_e21 * xs_millibarns;
}

/// Mean free path: mfp = 1 / Sigma, in nanometres with Sigma in 1e-6 /cm
/// (mfp_nm = 1e13 / Sigma_scaled). Params: macro_xs_x1e6_per_cm (> 0).
/// Returns: mfp in nm (truncated); -1 for a non-positive input.
/// Complexity: O(1).
pub fn nuc_mean_free_path_nm(macro_xs_x1e6_per_cm: Int) -> Int {
  if macro_xs_x1e6_per_cm <= 0 {
    return -1;
  }
  return 10000000000000 / macro_xs_x1e6_per_cm;
}

// --- isotopes ---------------------------------------------------------------

/// Chemical symbol of element `z` (H..Ca plus Fe, Co, Ni, Sr, Cd, I, Xe, Cs,
/// Ra, Th, U, Pu, Am). Params: z - atomic number. Returns: the symbol, or "X"
/// for an unknown element. Complexity: O(1).
pub fn nuc_element_symbol(z: Int) -> Str {
  if z == 1 { return "H"; }
  if z == 2 { return "He"; }
  if z == 3 { return "Li"; }
  if z == 4 { return "Be"; }
  if z == 5 { return "B"; }
  if z == 6 { return "C"; }
  if z == 7 { return "N"; }
  if z == 8 { return "O"; }
  if z == 9 { return "F"; }
  if z == 10 { return "Ne"; }
  if z == 11 { return "Na"; }
  if z == 12 { return "Mg"; }
  if z == 13 { return "Al"; }
  if z == 14 { return "Si"; }
  if z == 15 { return "P"; }
  if z == 16 { return "S"; }
  if z == 17 { return "Cl"; }
  if z == 18 { return "Ar"; }
  if z == 19 { return "K"; }
  if z == 20 { return "Ca"; }
  if z == 26 { return "Fe"; }
  if z == 27 { return "Co"; }
  if z == 28 { return "Ni"; }
  if z == 38 { return "Sr"; }
  if z == 48 { return "Cd"; }
  if z == 53 { return "I"; }
  if z == 54 { return "Xe"; }
  if z == 55 { return "Cs"; }
  if z == 88 { return "Ra"; }
  if z == 90 { return "Th"; }
  if z == 92 { return "U"; }
  if z == 94 { return "Pu"; }
  if z == 95 { return "Am"; }
  return "X";
}

/// Nuclear notation "El-A" (e.g. "U-235"); unknown elements render as "X-A".
/// Params: z, a - atomic and mass number. Returns: the hyphenated symbol.
/// Complexity: O(log a).
pub fn nuc_isotope_symbol(z: Int, a: Int) -> Str {
  return nuc_element_symbol(z) + "-" + convert.int_to_string(a);
}

/// Half-life in seconds from the built-in isotope table. Params: z, a.
/// Returns: seconds; 0 for a tabulated stable nuclide; -1 when the isotope is
/// not in the dataset. Complexity: O(1) (fixed table of 17 entries).
pub fn nuc_isotope_half_life_s(z: Int, a: Int) -> Int {
  if z == 1 && a == 1 { return 0; }
  if z == 1 && a == 2 { return 0; }
  if z == 1 && a == 3 { return 388789632; }
  if z == 2 && a == 4 { return 0; }
  if z == 6 && a == 12 { return 0; }
  if z == 6 && a == 14 { return 180825048000; }
  if z == 19 && a == 40 { return 39383884800000000; }
  if z == 27 && a == 60 { return 166344192; }
  if z == 38 && a == 90 { return 908543304; }
  if z == 53 && a == 131 { return 693377; }
  if z == 55 && a == 137 { return 949252608; }
  if z == 88 && a == 226 { return 50492160000; }
  if z == 90 && a == 232 { return 443384280000000000; }
  if z == 92 && a == 235 { return 22216550400000000; }
  if z == 92 && a == 238 { return 140999356800000000; }
  if z == 94 && a == 239 { return 760853736000; }
  if z == 95 && a == 241 { return 13639194720; }
  return -1;
}

/// Dominant decay mode from the built-in isotope table: "alpha", "beta-",
/// "stable", or "unknown" when the isotope is not in the dataset.
/// Params: z, a - atomic and mass number. Returns: the mode string.
/// Complexity: O(1) (fixed table of 17 entries).
pub fn nuc_isotope_decay_mode(z: Int, a: Int) -> Str {
  if z == 1 && a == 1 { return "stable"; }
  if z == 1 && a == 2 { return "stable"; }
  if z == 1 && a == 3 { return "beta-"; }
  if z == 2 && a == 4 { return "stable"; }
  if z == 6 && a == 12 { return "stable"; }
  if z == 6 && a == 14 { return "beta-"; }
  if z == 19 && a == 40 { return "beta-"; }
  if z == 27 && a == 60 { return "beta-"; }
  if z == 38 && a == 90 { return "beta-"; }
  if z == 53 && a == 131 { return "beta-"; }
  if z == 55 && a == 137 { return "beta-"; }
  if z == 88 && a == 226 { return "alpha"; }
  if z == 90 && a == 232 { return "alpha"; }
  if z == 92 && a == 235 { return "alpha"; }
  if z == 92 && a == 238 { return "alpha"; }
  if z == 94 && a == 239 { return "alpha"; }
  if z == 95 && a == 241 { return "alpha"; }
  return "unknown";
}

/// Whether an isotope is thermally fissile: U-233, U-235, Pu-239, Pu-241.
/// Params: z, a - atomic and mass number. Returns: true for those four.
/// Complexity: O(1).
pub fn nuc_is_fissile(z: Int, a: Int) -> Bool {
  if z == 92 && a == 235 { return true; }
  if z == 92 && a == 233 { return true; }
  if z == 94 && a == 239 { return true; }
  if z == 94 && a == 241 { return true; }
  return false;
}

/// Neutron number N = A - Z. Params: z, a - atomic and mass number.
/// Returns: a - z; 0 when a < z (invalid nuclide). Complexity: O(1).
pub fn nuc_neutron_number(z: Int, a: Int) -> Int {
  if a < z {
    return 0;
  }
  return a - z;
}
