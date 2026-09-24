// XIOM -- xiom.relativity: special-relativity scalar helpers (pure XIOM, no FFI)
// Port task: replace the xiom.relativity placeholder with a tested pure-XIOM
// module -- Lorentz factor, time dilation, length contraction, velocity
// addition, and relativistic energy/momentum over scalars.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Conventions (SPEC.md carries the formulas, rounding rules and test plan):
//   * c = 299792458 m/s (exact by the SI definition of the metre);
//   * speeds are permille integers: beta = beta_permille / 1000, so the
//     representable range is -0.999 c .. +0.999 c;
//   * "invalid beta" means beta_permille <= -1000 or beta_permille >= 1000
//     (|beta| >= 1, i.e. beta outside the open interval (-1000, 1000));
//     every beta-taking entry point returns 0.0 for invalid beta;
//   * rel_velocity_add_permille clamps its inputs to [-999, 999] and uses
//     integer arithmetic that truncates toward zero (see SPEC.md);
//   * scalars only: no Vec[Float64] (unsupported in this build), no structs,
//     no methods, no lambdas, no FFI of this package.

module xiom.relativity

use xiom.convert; use xiom.math;

// Speed of light in vacuum, m/s (exact by the SI definition of the metre).
const _REL_C_M_PER_S: Float64 = 299792458.0;

/// Lorentz factor gamma = 1/sqrt(1 - beta^2), from a permille speed.
/// Params: beta_permille - speed as beta * 1000; valid for -999 .. 999.
/// Returns: the scalar Float64 gamma = 1/sqrt(1 - (beta_permille/1000)^2),
/// which is >= 1 for every valid input. For |beta_permille| >= 1000, i.e.
/// beta outside the open interval (-1000, 1000) so |beta| >= 1, the input
/// is invalid and the result is 0.0. Invalid input never returns NaN and
/// never panics.
/// Error case: invalid beta yields 0.0 (documented sentinel).
/// Complexity: O(1).
pub fn rel_lorentz_permille(beta_permille: Int) -> Float64 {
  if beta_permille <= -1000 || beta_permille >= 1000 {
    return 0.0;
  }
  let beta: Float64 = xiom.convert.int_to_float(beta_permille) / 1000.0;
  let s: Float64 = 1.0 - beta * beta;
  return 1.0 / xiom.math.sqrt(s);
}

/// Relativistic time dilation: coordinate time = gamma * proper time.
/// Params: proper_s - proper time in seconds; beta_permille - speed in
/// permille (valid -999 .. 999).
/// Returns: proper_s * gamma(beta_permille) in seconds; 0.0 for invalid
/// beta (|beta_permille| >= 1000). The result is linear in proper_s, so
/// proper_s == 0.0 yields 0.0 for every valid beta.
/// Error case: invalid beta yields 0.0.
/// Complexity: O(1).
pub fn rel_time_dilation_s(proper_s: Float64, beta_permille: Int) -> Float64 {
  if beta_permille <= -1000 || beta_permille >= 1000 {
    return 0.0;
  }
  let gamma: Float64 = rel_lorentz_permille(beta_permille);
  return proper_s * gamma;
}

/// Relativistic length contraction: moving length = proper length / gamma.
/// Params: proper_m - proper (rest-frame) length in metres; beta_permille -
/// speed in permille (valid -999 .. 999).
/// Returns: proper_m / gamma(beta_permille) in metres, so the moving length
/// is at most the proper length (1/gamma is in (0, 1]); 0.0 for invalid
/// beta (|beta_permille| >= 1000).
/// Error case: invalid beta yields 0.0.
/// Complexity: O(1).
pub fn rel_length_contraction_m(proper_m: Float64, beta_permille: Int) -> Float64 {
  if beta_permille <= -1000 || beta_permille >= 1000 {
    return 0.0;
  }
  let gamma: Float64 = rel_lorentz_permille(beta_permille);
  return proper_m / gamma;
}

/// Relativistic velocity addition in permille units.
/// Params: u_permille, v_permille - the two collinear speeds as beta * 1000;
/// both are first clamped into [-999, 999] with rel_beta_from_bits.
/// Returns: the summed speed in permille as an Int, computed with integer
/// arithmetic that truncates toward zero at both divisions:
///   result = 1000 * (u + v) / (1000 + (u * v) / 1000)
/// with u, v already clamped. This approximates
/// 1000 * (u + v) / (1000 + u * v / 1000) = 1000 * (bu + bv)/(1 + bu*bv)
/// on the permille grid; 500 + 500 -> 800 exactly. Because the intermediate
/// (u * v) / 1000 division truncates toward zero, the documented edge
/// 999 + 999 yields 1000 (the exact rational value is 999.9995 permille).
/// Results never leave [-1000, 1000]. The addition is commutative.
/// Error case: none (inputs are clamped, never rejected).
/// Complexity: O(1).
pub fn rel_velocity_add_permille(u_permille: Int, v_permille: Int) -> Int {
  let u: Int = rel_beta_from_bits(u_permille);
  let v: Int = rel_beta_from_bits(v_permille);
  let num: Int = 1000 * (u + v);
  let den: Int = 1000 + (u * v) / 1000;
  return num / den;
}

/// Rest energy E = m * c^2.
/// Params: mass_kg - rest mass in kilograms.
/// Returns: the rest energy in joules, with c = 299792458 m/s, so
/// mass_kg == 1.0 yields c^2 = 8.987551787368176e16 J. Linear in mass.
/// Error case: none.
/// Complexity: O(1).
pub fn rel_energy_j(mass_kg: Float64) -> Float64 {
  return mass_kg * _REL_C_M_PER_S * _REL_C_M_PER_S;
}

/// Relativistic kinetic energy K = (gamma - 1) * m * c^2.
/// Params: mass_kg - rest mass in kilograms; beta_permille - speed in
/// permille (valid -999 .. 999).
/// Returns: the kinetic energy in joules; exactly 0.0 at beta == 0 (where
/// gamma == 1) and 0.0 for invalid beta (|beta_permille| >= 1000). At
/// beta = 0.6 the factor gamma - 1 is 0.25, so 1 kg carries 0.25 * c^2 J.
/// Time dilation and kinetic energy depend on beta^2, so the result is
/// even in beta.
/// Error case: invalid beta yields 0.0.
/// Complexity: O(1).
pub fn rel_kinetic_energy_j(mass_kg: Float64, beta_permille: Int) -> Float64 {
  if beta_permille <= -1000 || beta_permille >= 1000 {
    return 0.0;
  }
  let gamma: Float64 = rel_lorentz_permille(beta_permille);
  return (gamma - 1.0) * mass_kg * _REL_C_M_PER_S * _REL_C_M_PER_S;
}

/// Relativistic momentum p = gamma * m * v with v = beta * c.
/// Params: mass_kg - rest mass in kilograms; beta_permille - speed in
/// permille (valid -999 .. 999).
/// Returns: the momentum in kg*m/s (equivalently N*s); exactly 0.0 at
/// beta == 0 (v == 0) and 0.0 for invalid beta (|beta_permille| >= 1000).
/// At beta = 0.6, 1 kg carries p = 1.25 * 0.6 * c = 224844343.5 kg*m/s.
/// The momentum is odd in beta: negating beta negates the result.
/// Error case: invalid beta yields 0.0.
/// Complexity: O(1).
pub fn rel_momentum_ns(mass_kg: Float64, beta_permille: Int) -> Float64 {
  if beta_permille <= -1000 || beta_permille >= 1000 {
    return 0.0;
  }
  let gamma: Float64 = rel_lorentz_permille(beta_permille);
  let beta: Float64 = xiom.convert.int_to_float(beta_permille) / 1000.0;
  let v: Float64 = beta * _REL_C_M_PER_S;
  return gamma * mass_kg * v;
}

/// Clamp a raw speed value into the permille range.
/// Params: bits - any Int, intended to be a beta value in permille.
/// Returns: bits clamped into [-999, 999]: the input unchanged when it is
/// already in range, -999 when bits < -999, 999 when bits > 999. This is
/// the clamping helper used by rel_velocity_add_permille.
/// Error case: none (total function).
/// Complexity: O(1).
pub fn rel_beta_from_bits(bits: Int) -> Int {
  if bits < -999 {
    return -999;
  }
  if bits > 999 {
    return 999;
  }
  return bits;
}
