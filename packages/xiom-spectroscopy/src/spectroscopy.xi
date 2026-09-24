// XIOM -- xiom.spectroscopy: electromagnetic-spectrum conversions (pure XIOM,
// no FFI).
// Port task: replace the xiom.spectroscopy placeholder with a tested,
// documented pure-XIOM module -- vacuum wavelength, frequency, wavenumber and
// photon energy over scalar Float64 values.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Conventions (SPEC.md carries the formulas, the boundary convention and the
// test plan):
//   * constants (SI, exact by the 2019 SI definitions), exported below:
//       c  = SPEC_C_M_PER_S = 299792458 m/s       (speed of light in vacuum)
//       h  = SPEC_H_J_S     = 6.62607015e-34 J*s  (Planck constant)
//       eV = SPEC_EV_J      = 1.602176634e-19 J   (electronvolt)
//   * vacuum wavelength only: wavelengths are in vacuum, never in a medium;
//     no refractive index is applied anywhere;
//   * scalar only: no Vec[Float64] (unsupported in this build), no structs,
//     no methods, no lambdas, no FFI of this package;
//   * guard G1 (module-wide, documented per function below and exercised by
//     tests/test_conformance.xi): a numeric input <= 0 returns 0.0 in every
//     conversion function, and spec_band_name returns "" for it. A real zero
//     is therefore indistinguishable from a rejected input in the return
//     value -- validate first when the distinction matters;
//   * band convention: 750 nm belongs to "visible" (matching spec_is_visible,
//     380..750 inclusive); "near-IR" starts strictly above 750 nm, "IR" at
//     2500 nm and "far-IR" at 1e6 nm (both inclusive).

module xiom.spectroscopy

/// Speed of light in vacuum c, 299792458 m/s (exact by the SI definition of
/// the metre).
pub const SPEC_C_M_PER_S: Float64 = 299792458.0;

/// Planck constant h, 6.62607015e-34 J*s (exact by the 2019 SI definition).
pub const SPEC_H_J_S: Float64 = 6.62607015e-34;

/// Electronvolt eV, 1.602176634e-19 J (exact by the 2019 SI definition).
pub const SPEC_EV_J: Float64 = 1.602176634e-19;

/// Vacuum wavelength to frequency: f = c / (nm * 1e-9).
/// Params: nm - vacuum wavelength in nanometres.
/// Returns: the frequency in terahertz, c / (nm*1e-9) / 1e12; 0.0 when
/// nm <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_nm_to_thz(nm: Float64) -> Float64 {
  if nm <= 0.0 { return 0.0; }
  return SPEC_C_M_PER_S / (nm * 1e-9) / 1e12;
}

/// Frequency to vacuum wavelength: nm = c / (thz * 1e12) / 1e-9.
/// Params: thz - frequency in terahertz.
/// Returns: the vacuum wavelength in nanometres; 0.0 when thz <= 0
/// (guard G1). Round-trips spec_nm_to_thz for positive inputs.
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_thz_to_nm(thz: Float64) -> Float64 {
  if thz <= 0.0 { return 0.0; }
  return SPEC_C_M_PER_S / (thz * 1e12) / 1e-9;
}

/// Photon energy from vacuum wavelength: E = h*c / (nm * 1e-9).
/// Params: nm - vacuum wavelength in nanometres.
/// Returns: the photon energy in electronvolts,
/// h * c / (nm*1e-9) / eV; 0.0 when nm <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_nm_to_ev(nm: Float64) -> Float64 {
  if nm <= 0.0 { return 0.0; }
  return SPEC_H_J_S * SPEC_C_M_PER_S / (nm * 1e-9) / SPEC_EV_J;
}

/// Vacuum wavelength from photon energy: nm = h*c / (ev * eV) / 1e-9.
/// Params: ev - photon energy in electronvolts.
/// Returns: the vacuum wavelength in nanometres; 0.0 when ev <= 0
/// (guard G1). Round-trips spec_nm_to_ev for positive inputs.
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_ev_to_nm(ev: Float64) -> Float64 {
  if ev <= 0.0 { return 0.0; }
  return SPEC_H_J_S * SPEC_C_M_PER_S / (ev * SPEC_EV_J) / 1e-9;
}

/// Vacuum wavelength to wavenumber: 1e7 / nm.
/// Params: nm - vacuum wavelength in nanometres.
/// Returns: the wavenumber in reciprocal centimetres (cm^-1); 0.0 when
/// nm <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_nm_to_cm_inv(nm: Float64) -> Float64 {
  if nm <= 0.0 { return 0.0; }
  return 1e7 / nm;
}

/// Wavenumber to vacuum wavelength: 1e7 / cm_inv.
/// Params: cm_inv - wavenumber in reciprocal centimetres.
/// Returns: the vacuum wavelength in nanometres; 0.0 when cm_inv <= 0
/// (guard G1). Round-trips spec_nm_to_cm_inv for positive inputs.
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_cm_inv_to_nm(cm_inv: Float64) -> Float64 {
  if cm_inv <= 0.0 { return 0.0; }
  return 1e7 / cm_inv;
}

/// Photon energy to frequency: f = ev * eV / h.
/// Params: ev - photon energy in electronvolts.
/// Returns: the frequency in terahertz, ev * eV / h / 1e12; 0.0 when
/// ev <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_ev_to_thz(ev: Float64) -> Float64 {
  if ev <= 0.0 { return 0.0; }
  return ev * SPEC_EV_J / SPEC_H_J_S / 1e12;
}

/// Frequency to photon energy: E = thz * 1e12 * h.
/// Params: thz - frequency in terahertz.
/// Returns: the photon energy in electronvolts,
/// thz * 1e12 * h / eV; 0.0 when thz <= 0 (guard G1). Round-trips
/// spec_ev_to_thz for positive inputs.
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_thz_to_ev(thz: Float64) -> Float64 {
  if thz <= 0.0 { return 0.0; }
  return thz * 1e12 * SPEC_H_J_S / SPEC_EV_J;
}

/// Visible-light test on a vacuum wavelength: 380..750 nm inclusive.
/// Params: nm - vacuum wavelength in nanometres.
/// Returns: true when 380.0 <= nm <= 750.0; false otherwise, including
/// nm <= 0 (guard G1 -- a non-positive wavelength is not visible either).
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_is_visible(nm: Float64) -> Bool {
  return nm >= 380.0 && nm <= 750.0;
}

/// Spectral band name for a vacuum wavelength.
/// Params: nm - vacuum wavelength in nanometres.
/// Returns: "" when nm <= 0 (guard G1), else the band whose range contains
/// nm: "UV" (nm < 380), "visible" (380 <= nm <= 750), "near-IR"
/// (750 < nm < 2500), "IR" (2500 <= nm < 1e6), "far-IR" (nm >= 1e6).
/// The 750 nm boundary belongs to "visible" (matching spec_is_visible);
/// 750..2500 and 2500..1e6 are half-open at their lower end, so 2500 nm is
/// "IR" and 1e6 nm is "far-IR".
/// Errors: none (total).
/// Complexity: O(1).
pub fn spec_band_name(nm: Float64) -> Str {
  if nm <= 0.0 { return ""; }
  if nm < 380.0 { return "UV"; }
  if nm <= 750.0 { return "visible"; }
  if nm < 2500.0 { return "near-IR"; }
  if nm < 1e6 { return "IR"; }
  return "far-IR";
}
