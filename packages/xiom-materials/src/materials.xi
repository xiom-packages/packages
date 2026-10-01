// XIOM -- xiom.materials: deterministic fixed-point material model
//   isotropic elastic constants (E, nu -> G, K, lambda), 6-component Voigt
//   stress/strain vectors, Hooke's law and its inverse, invariants (I1, von
//   Mises equivalent, max shear), safety factor + yield flags, and a
//   caller-supplied temperature scaling table.
// Port task: replace the xiom.materials placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixed-point convention: every quantity is an Int at scale 1e-4 (10000 = 1.0).
//   * stress / stiffness in MPa            200000.0000 MPa -> 2000000000
//   * strain and engineering shear          dimensionless, 0.0010 -> 10
//   * Poisson ratio                         0.2500 -> 2500
//   * temperature in kelvin                 293.1500 K -> 2931500
//   * tabulated scale factors               1.0000 -> 10000
// Voigt order is [xx, yy, zz, yz, xz, xy]; the last three components are
// engineering shear strains (gamma = 2 * eps) and shear stresses.
// All divisions are XIOM Int divisions that truncate toward zero. See SPEC.md
// for the formulas, the documented rounding, and the overflow envelope.

module xiom.materials

// --------------------------------------------------
//  Scale + unit-consistency metadata
// --------------------------------------------------

/// The fixed-point scale used by every function in this module: 10000 = 1.0.
/// Params: none.
/// Returns: 10000.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_scale() -> Int {
  return 10000;
}

/// Unit-system code: 1 identifies the (MPa, mm, N, 1e-4) system documented above.
/// Params: none.
/// Returns: 1.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_stress_unit_code() -> Int {
  return 1;
}

/// True when `scale` equals the module's fixed-point scale (10000).
/// Params: scale - a candidate scale factor.
/// Returns: true iff scale == 10000.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_unit_consistent(scale: Int) -> Bool {
  return scale == 10000;
}

/// Integer square root, floor(sqrt(n)), via Newton's method.
/// Params: n - a non-negative integer.
/// Returns: floor(sqrt(n)); 0 for n <= 0.
/// Error case: none (non-positive inputs return 0).
/// Complexity: O(log n) iterations; each iteration strictly decreases the
/// estimate, so the loop always terminates.
pub fn mat_isqrt(n: Int) -> Int {
  if n <= 0 {
    return 0;
  }
  var x = n;
  var y = (x + 1) / 2;
  while y < x {
    x = y;
    y = (x + n / x) / 2;
  }
  return x;
}

/// Overflow guard for a product: true when |a| * |b| exceeds Int range.
/// Params: a, b - factors.
/// Returns: true iff the product would overflow 64-bit signed Int.
/// Error case: none for inputs in the documented envelope (excludes Int min).
/// Complexity: O(1).
pub fn mat_mul_overflows(a: Int, b: Int) -> Bool {
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

// --------------------------------------------------
//  Isotropic elastic constants from E and nu
// --------------------------------------------------

/// Shear modulus G = E / (2 * (1 + nu)).
/// Params: e_s - Young's modulus scaled by 1e-4.
///         nu_s - Poisson ratio scaled by 1e-4.
/// Returns: G scaled by 1e-4, division truncated toward zero.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_shear_modulus(e_s: Int, nu_s: Int) -> Int {
  return e_s * 10000 / (2 * (10000 + nu_s));
}

/// Bulk modulus K = E / (3 * (1 - 2 * nu)).
/// Params: e_s - Young's modulus scaled by 1e-4.
///         nu_s - Poisson ratio scaled by 1e-4.
/// Returns: K scaled by 1e-4, division truncated toward zero.
/// Error case: none; nu_s = 5000 makes the denominator zero (undefined).
/// Complexity: O(1).
pub fn mat_bulk_modulus(e_s: Int, nu_s: Int) -> Int {
  return e_s * 10000 / (3 * (10000 - 2 * nu_s));
}

/// Lame's first parameter lambda = E * nu / ((1 + nu) * (1 - 2 * nu)).
/// Params: e_s - Young's modulus scaled by 1e-4.
///         nu_s - Poisson ratio scaled by 1e-4.
/// Returns: lambda scaled by 1e-4, division truncated toward zero.
/// Error case: none; nu_s = 5000 makes the denominator zero (undefined).
/// Complexity: O(1).
pub fn mat_lame_lambda(e_s: Int, nu_s: Int) -> Int {
  return e_s * nu_s * 10000 / ((10000 + nu_s) * (10000 - 2 * nu_s));
}

// --------------------------------------------------
//  Hooke's law (Voigt order xx, yy, zz, yz, xz, xy)
// --------------------------------------------------

/// Normal stress component from a normal strain component:
/// sigma_i = lambda * (eps_xx + eps_yy + eps_zz) + 2 * G * eps_i.
/// Params: lambda_s - Lame lambda scaled by 1e-4.
///         g_s - shear modulus scaled by 1e-4.
///         trace_eps_s - eps_xx + eps_yy + eps_zz, scaled by 1e-4.
///         eps_s - the normal strain component i, scaled by 1e-4.
/// Returns: the normal stress component i, scaled by 1e-4.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_hooke_normal(lambda_s: Int, g_s: Int, trace_eps_s: Int, eps_s: Int) -> Int {
  return (lambda_s * trace_eps_s + 2 * g_s * eps_s) / 10000;
}

/// Shear stress component from an engineering shear strain:
/// tau_ij = G * gamma_ij (gamma = 2 * eps).
/// Params: g_s - shear modulus scaled by 1e-4.
///         gamma_s - engineering shear strain, scaled by 1e-4.
/// Returns: the shear stress component, scaled by 1e-4.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_hooke_shear(g_s: Int, gamma_s: Int) -> Int {
  return g_s * gamma_s / 10000;
}

/// Inverse Hooke normal strain: eps_i = (sigma_i - nu * (sigma_j + sigma_k)) / E.
/// Params: e_s - Young's modulus scaled by 1e-4.
///         nu_s - Poisson ratio scaled by 1e-4.
///         sigma_s - the normal stress component i, scaled by 1e-4.
///         other_sum_s - sigma_j + sigma_k (the two other normal stresses).
/// Returns: the normal strain component i, scaled by 1e-4.
/// Error case: none; e_s = 0 is undefined.
/// Complexity: O(1).
pub fn mat_hooke_inverse_normal(e_s: Int, nu_s: Int, sigma_s: Int, other_sum_s: Int) -> Int {
  return (10000 * sigma_s - nu_s * other_sum_s) / e_s;
}

/// Inverse Hooke shear strain (tensor): eps_ij = tau_ij / (2 * G).
/// Params: g_s - shear modulus scaled by 1e-4.
///         tau_s - shear stress component, scaled by 1e-4.
/// Returns: the tensor shear strain component, scaled by 1e-4
///          (half the engineering shear returned in the forward direction).
/// Error case: none; g_s = 0 is undefined.
/// Complexity: O(1).
pub fn mat_hooke_inverse_shear(g_s: Int, tau_s: Int) -> Int {
  return 10000 * tau_s / (2 * g_s);
}

// --------------------------------------------------
//  Invariants
// --------------------------------------------------

/// First stress invariant I1 = sigma_xx + sigma_yy + sigma_zz.
/// Params: sxx, syy, szz - normal stresses scaled by 1e-4.
/// Returns: I1 scaled by 1e-4.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_invariant_i1(sxx: Int, syy: Int, szz: Int) -> Int {
  return sxx + syy + szz;
}

/// Twice the von Mises stress squared, in scaled units:
/// D2 = (sxx-syy)^2 + (syy-szz)^2 + (szz-sxx)^2
///      + 6 * (syz^2 + sxz^2 + sxy^2).
/// Params: sxx, syy, szz - normal stresses scaled by 1e-4.
///         syz, sxz, sxy - shear stresses scaled by 1e-4.
/// Returns: D2 (units of 1e-8 * MPa^2).
/// Error case: none in the documented envelope; see SPEC.md section 6.
/// Complexity: O(1).
pub fn mat_von_mises_sq(sxx: Int, syy: Int, szz: Int, syz: Int, sxz: Int, sxy: Int) -> Int {
  let dxy = sxx - syy;
  let dyz = syy - szz;
  let dzx = szz - sxx;
  return dxy * dxy + dyz * dyz + dzx * dzx + 6 * (syz * syz + sxz * sxz + sxy * sxy);
}

/// Von Mises equivalent stress: sqrt(D2 / 2), floored.
/// Params: sxx, syy, szz - normal stresses scaled by 1e-4.
///         syz, sxz, sxy - shear stresses scaled by 1e-4.
/// Returns: equivalent stress scaled by 1e-4, floored to an integer.
/// Error case: none.
/// Complexity: O(1) plus mat_isqrt.
pub fn mat_von_mises(sxx: Int, syy: Int, szz: Int, syz: Int, sxz: Int, sxy: Int) -> Int {
  let d2 = mat_von_mises_sq(sxx, syy, szz, syz, sxz, sxy);
  return mat_isqrt(d2 / 2);
}

/// Maximum shear stress from the three principal stresses:
/// tau_max = (max(s1,s2,s3) - min(s1,s2,s3)) / 2.
/// Params: s1, s2, s3 - principal stresses scaled by 1e-4.
/// Returns: tau_max scaled by 1e-4, truncated toward zero.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_principal_max_shear(s1: Int, s2: Int, s3: Int) -> Int {
  var hi = s1;
  if s2 > hi {
    hi = s2;
  }
  if s3 > hi {
    hi = s3;
  }
  var lo = s1;
  if s2 < lo {
    lo = s2;
  }
  if s3 < lo {
    lo = s3;
  }
  return (hi - lo) / 2;
}

/// Von Mises equivalent stress from the three principal stresses, floored.
/// Params: s1, s2, s3 - principal stresses scaled by 1e-4.
/// Returns: equivalent stress scaled by 1e-4.
/// Error case: none.
/// Complexity: O(1) plus mat_isqrt.
pub fn mat_principal_von_mises(s1: Int, s2: Int, s3: Int) -> Int {
  let d12 = s1 - s2;
  let d23 = s2 - s3;
  let d31 = s3 - s1;
  return mat_isqrt((d12 * d12 + d23 * d23 + d31 * d31) / 2);
}

// --------------------------------------------------
//  Yield checks
// --------------------------------------------------

/// Yield flag: 1 when the equivalent stress exceeds the yield strength, else 0.
/// Params: yield_s - yield strength scaled by 1e-4.
///         vm_s - von Mises equivalent stress scaled by 1e-4.
/// Returns: 1 if vm_s > yield_s, otherwise 0.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_yield_flag(yield_s: Int, vm_s: Int) -> Int {
  if vm_s > yield_s {
    return 1;
  }
  return 0;
}

/// True when the equivalent stress is at or below the yield strength.
/// Params: yield_s - yield strength scaled by 1e-4.
///         vm_s - von Mises equivalent stress scaled by 1e-4.
/// Returns: true iff vm_s <= yield_s.
/// Error case: none.
/// Complexity: O(1).
pub fn mat_within_yield(yield_s: Int, vm_s: Int) -> Bool {
  return vm_s <= yield_s;
}

/// Safety factor SF = yield / vm, returned scaled by 1e-4.
/// Params: yield_s - yield strength scaled by 1e-4.
///         vm_s - von Mises equivalent stress scaled by 1e-4.
/// Returns: 10000 * yield_s / vm_s (so 10000 == SF 1.0);
///          -1 when vm_s <= 0 (undefined).
/// Error case: vm_s <= 0 returns the sentinel -1.
/// Complexity: O(1).
pub fn mat_safety_factor_x1e4(yield_s: Int, vm_s: Int) -> Int {
  if vm_s <= 0 {
    return -1;
  }
  return 10000 * yield_s / vm_s;
}

// --------------------------------------------------
//  Caller-supplied temperature scaling table
// --------------------------------------------------

/// Scale a property by a caller-supplied (temperature, factor) table, with
/// linear interpolation between the two bracketing entries. `temps` must be
/// sorted ascending; parallel `factors` hold the scale factor per entry
/// (1.0 -> 10000). Temperatures below the first entry use the first factor;
/// temperatures above the last entry use the last factor.
/// Params: value_s - the property at the reference condition, scaled by 1e-4.
///         temps - ascending temperature breakpoints, scaled by 1e-4.
///         factors - parallel scale factors, scaled by 1e-4.
///         temp_s - the query temperature, scaled by 1e-4.
/// Returns: value_s * interpolated factor / 10000, truncated toward zero.
/// Error case: empty table returns value_s unchanged.
/// Complexity: O(n) in the number of table entries.
/// Progress: the loop index strictly increases to n-1, so it terminates.
pub fn mat_scale_at_temp(value_s: Int, temps: &Vec[Int], factors: &Vec[Int], temp_s: Int) -> Int {
  let n = temps.len();
  if n == 0 {
    return value_s;
  }
  if n == 1 {
    return value_s * factors[0] / 10000;
  }
  if temp_s <= temps[0] {
    return value_s * factors[0] / 10000;
  }
  var i = 0;
  while i < n - 1 {
    let t0 = temps[i];
    let t1 = temps[i + 1];
    if temp_s <= t1 {
      let dt = t1 - t0;
      if dt <= 0 {
        return value_s * factors[i] / 10000;
      }
      let f0 = factors[i];
      let f1 = factors[i + 1];
      let f = f0 + (f1 - f0) * (temp_s - t0) / dt;
      return value_s * f / 10000;
    }
    i = i + 1;
  }
  return value_s * factors[n - 1] / 10000;
}
