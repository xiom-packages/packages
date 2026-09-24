// XIOM -- xiom.quantum: introductory quantum formulas (pure XIOM, no FFI).
// Port task: replace the xiom.quantum placeholder with a tested, documented
// pure-XIOM module -- de Broglie wavelength, photon momentum, hydrogen energy
// levels and transitions, Balmer and Lyman wavelengths, plus two reference
// lengths (Compton wavelength and Bohr radius).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Conventions (SPEC.md carries the formulas, the guard rules and the test
// plan):
//   * pure XIOM, no FFI: every function is free and scalar (Float64, or an
//     Int principal quantum number), in SI units -- metres, kilograms,
//     seconds, joules, electronvolts -- and deterministic;
//   * x as the input of a formula is the SI value in the unit named by the
//     function suffix; the constants below are exported and used directly;
//   * guard G1 (module-wide, documented per function): a non-positive scalar
//     input returns 0.0 in quantum_de_broglie_m and
//     quantum_photon_momentum;
//   * guard G2: an invalid principal quantum number returns 0.0 --
//     quantum_hydrogen_energy_ev n < 1; quantum_hydrogen_transition_ev
//     unless n_from > n_to >= 1; quantum_balmer_wavelength_nm n <= 2;
//     quantum_lyman_wavelength_nm n <= 1. A real zero is therefore
//     indistinguishable from a rejected input in the return value; validate
//     first when the distinction matters;
//   * scalars only: no Vec[Float64] (unsupported in this build), no structs,
//     no methods, no lambdas, no FFI of this package.

module xiom.quantum

use xiom.convert;

/// Planck constant h, 6.62607015e-34 J*s (exact by the 2019 SI definition).
pub const QUANTUM_H_J_S: Float64 = 6.62607015e-34;

/// Speed of light in vacuum c, 299792458 m/s (exact by the SI definition of
/// the metre).
pub const QUANTUM_C_M_PER_S: Float64 = 299792458.0;

/// Rydberg constant R_inf, 1.0973731568160e7 per metre (CODATA 2018), for a
/// nucleus of infinite mass; used by the Balmer and Lyman wavelengths.
pub const QUANTUM_R_INF_PER_M: Float64 = 1.0973731568160e7;

/// Hydrogen ground-state energy magnitude E1, 13.605693122994 eV (CODATA
/// 2018); the level energy is -E1 / n^2.
pub const QUANTUM_E1_EV: Float64 = 13.605693122994;

/// Electron rest mass m_e, 9.1093837015e-31 kg (CODATA 2018); provided for
/// callers of quantum_de_broglie_m (it is not used by the formulas below,
/// which all take their mass or energy as an argument).
pub const QUANTUM_M_E_KG: Float64 = 9.1093837015e-31;

/// De Broglie wavelength: lambda = h / (m*v).
/// Params: mass_kg - mass in kilograms; velocity_m_s - speed in m/s.
/// Returns: the wavelength in metres; 0.0 when mass_kg <= 0 or
/// velocity_m_s <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_de_broglie_m(mass_kg: Float64, velocity_m_s: Float64) -> Float64 {
  if mass_kg <= 0.0 || velocity_m_s <= 0.0 { return 0.0; }
  return QUANTUM_H_J_S / (mass_kg * velocity_m_s);
}

/// Photon momentum: p = E / c.
/// Params: energy_j - photon energy in joules.
/// Returns: the momentum in kg*m/s; 0.0 when energy_j <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_photon_momentum(energy_j: Float64) -> Float64 {
  if energy_j <= 0.0 { return 0.0; }
  return energy_j / QUANTUM_C_M_PER_S;
}

/// Hydrogen level energy: E_n = -E1 / n^2 (Bohr model, infinitely heavy
/// nucleus).
/// Params: n - principal quantum number.
/// Returns: the energy in electronvolts, negative for every valid n; 0.0
/// when n < 1 (guard G2).
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_hydrogen_energy_ev(n: Int) -> Float64 {
  if n < 1 { return 0.0; }
  let nf: Float64 = xiom.convert.int_to_float(n);
  return -QUANTUM_E1_EV / (nf * nf);
}

/// Hydrogen transition energy: delta_E = E1*(1/n_to^2 - 1/n_from^2), the
/// positive energy of the photon emitted when the electron falls from
/// n_from to n_to.
/// Params: n_from - initial principal quantum number; n_to - final principal
/// quantum number.
/// Returns: the transition energy in electronvolts, positive when
/// n_from > n_to >= 1; 0.0 otherwise (guard G2), so the required direction
/// "downward in energy" covers both a forbidden argument order and a bad
/// quantum number.
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_hydrogen_transition_ev(n_from: Int, n_to: Int) -> Float64 {
  if n_to < 1 || n_from <= n_to { return 0.0; }
  let nf: Float64 = xiom.convert.int_to_float(n_from);
  let nt: Float64 = xiom.convert.int_to_float(n_to);
  return QUANTUM_E1_EV * (1.0 / (nt * nt) - 1.0 / (nf * nf));
}

/// Balmer-series vacuum wavelength: 1/lambda = R_inf*(1/4 - 1/n^2), with n
/// the upper level (the series ends at n_to = 2).
/// Params: n - upper principal quantum number.
/// Returns: the vacuum wavelength in nanometres; 0.0 when n <= 2 (guard G2:
/// n = 2 would divide by zero and n = 1 has no Balmer line). n = 3 is
/// H-alpha.
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_balmer_wavelength_nm(n: Int) -> Float64 {
  if n <= 2 { return 0.0; }
  let nf: Float64 = xiom.convert.int_to_float(n);
  return 1e9 / (QUANTUM_R_INF_PER_M * (0.25 - 1.0 / (nf * nf)));
}

/// Lyman-series vacuum wavelength: 1/lambda = R_inf*(1 - 1/n^2), with n the
/// upper level (the series ends at n_to = 1).
/// Params: n - upper principal quantum number.
/// Returns: the vacuum wavelength in nanometres; 0.0 when n <= 1 (guard G2:
/// n = 1 would divide by zero). n = 2 is Lyman-alpha.
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_lyman_wavelength_nm(n: Int) -> Float64 {
  if n <= 1 { return 0.0; }
  let nf: Float64 = xiom.convert.int_to_float(n);
  return 1e9 / (QUANTUM_R_INF_PER_M * (1.0 - 1.0 / (nf * nf)));
}

/// Compton wavelength of the electron, 2.42631023867e-12 m (the CODATA 2018
/// value h/(m_e*c), pinned as the literal).
/// Returns: the Compton wavelength in metres.
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_compton_wavelength_m() -> Float64 {
  return 2.42631023867e-12;
}

/// Bohr radius a0, 5.29177210903e-11 m (the CODATA 2018 value, pinned as the
/// literal).
/// Returns: the Bohr radius in metres.
/// Errors: none (total).
/// Complexity: O(1).
pub fn quantum_rbohr_m() -> Float64 {
  return 5.29177210903e-11;
}
