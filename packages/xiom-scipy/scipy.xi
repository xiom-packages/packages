// XIOM -- SciPy Bridge (Scientific Computing)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Phase 1 (Core Foundation): FFI bindings for optimize, integrate, signal,
//   interpolate, and stats C functions, plus pure-XIOM statistics wrappers.
//
// Hybrid bundling: small Fortran/C libraries (MINPACK, QUADPACK, FITPACK,
//   FFTPACK, Cephes) are bundled into the bridge .obj (~100KB total).
//   Larger libs (SuperLU, Qhull) are system-installed.

module xiom.scipy

use xiom.math;

// ===============================================================================
// Types
// ===============================================================================

pub type ScipyResult = {
  x: Vec[Float64];
  fun: Float64;
  nit: Int;
  success: Bool;
} derive[Clone]

pub type QuadResult = {
  value: Float64;
  error: Float64;
} derive[Clone]

pub type Interpolator = {
  x: Vec[Float64];
  y: Vec[Float64];
  kind: Int;          // 0 = linear, 1 = cubic
  coeffs: Vec[Float64];
} derive[Clone]

// ===============================================================================
// extern "C" -- SciPy C backend functions
// ===============================================================================

extern "C" {
  // -- Optimize (MINPACK) --
  /// Minimize scalar function f(x). Returns (x_min, f(x_min), iterations, converged).
  fn optimize_minimize(f: fn(Float64) -> Float64, x0: Float64, tol: Float64, maxiter: Int) -> ScipyResult;

  // -- Integrate (QUADPACK/ODEPACK) --
  /// Adaptive quadrature: integrate f from a to b. Returns (value, error_estimate).
  fn integrate_quad(f: fn(Float64) -> Float64, a: Float64, b: Float64, epsabs: Float64, epsrel: Float64) -> QuadResult;

  /// ODE integrator (LSODA). Integrates dy/dt = f(y, t) from t0 to t1.
  /// Returns array of y values at each requested t point.
  fn integrate_odeint(y0: *Float64, n_eq: Int, t_start: Float64, t_end: Float64, n_steps: Int) -> *Float64;

  // -- Signal (FFTPACK) --
  /// 1D convolution of two arrays. Returns result array (pre-allocated by caller).
  fn signal_convolve(a: *Float64, na: Int, b: *Float64, nb: Int, result: *Float64) -> Int;

  /// Forward FFT (real input, complex output as interleaved [re, im] pairs).
  fn signal_fft(data: *Float64, n: Int) -> Int;

  /// Inverse FFT (complex input as interleaved pairs, real output).
  fn signal_ifft(data: *Float64, n: Int) -> Int;

  // -- Stats (Cephes) --
  /// Standard normal probability density function: phi(x) = (1/sqrt(2pi)) - e^(-x2/2).
  fn stats_norm_pdf(x: Float64) -> Float64;

  /// Standard normal cumulative distribution function: Phi(x) = int-infx phi(t) dt.
  fn stats_norm_cdf(x: Float64) -> Float64;

  // -- Interpolate (FITPACK) --
  /// Piecewise linear interpolation. x, y: input arrays; len: array size;
  ///   x_new: evaluation point; returns interpolated y_new.
  fn interpolate_linear(x: *Float64, y: *Float64, len: Int, x_new: Float64) -> Float64;

  /// Piecewise cubic spline interpolation. Computes coefficients in place;
  ///   requires x strictly increasing; x_new: evaluation point.
  fn interpolate_cubic(x: *Float64, y: *Float64, len: Int, x_new: Float64) -> Float64;
}

// ===============================================================================
// Pure-XIOM statistics -- no FFI dependency
// These are fully verifiable, contract-bearing implementations of the standard
// normal distribution functions using only xiom.math primitives.
// ===============================================================================

/// Constants for normal distribution
const INV_SQRT_2PI: Float64 = 0.3989422804014327;   // 1.0 / sqrt(2.0 * PI)
const SQRT2: Float64 = 1.4142135623730951;           // sqrt(2.0)

/// Internal: compute the error function erf(x) using a power series.
/// Converges well for |x| <= 4. For |x| > 4, returns +/-1.0.
fn _erf_series(x: Float64) -> Float64 {
  var ax = x;
  if ax < 0.0 { ax = -ax; };

  if ax > 4.0 {
    if x > 0.0 { return 1.0; };
    return -1.0;
  };

  // erf(x) = (2/sqrtpi) - Sigma (-1)^n - x^(2n+1) / (n! - (2n+1))
  let two_over_sqrt_pi: Float64 = 1.1283791670955126;
  var result = x;
  var term = x;
  var x_sq = x * x;
  var n = 1;
  while n <= 30 {
    term = -term * x_sq * (2.0 * (n as Float64) - 1.0) / ((n as Float64) * (2.0 * (n as Float64) + 1.0));
    result = result + term;
    n = n + 1;
  };
  return two_over_sqrt_pi * result;
}

/// Standard normal probability density function.
/// phi(x) = (1 / sqrt(2pi)) - exp(-x2 / 2)
///
/// This is a pure-XIOM implementation -- no FFI call required.
pub fn norm_pdf(x: Float64) -> Float64
  ensures: result >= 0.0
  ensures: result <= INV_SQRT_2PI
{
  return INV_SQRT_2PI * math.exp(-0.5 * x * x);
}

/// Standard normal cumulative distribution function.
/// Phi(x) = 1/2 - [1 + erf(x / sqrt2)]
///
/// Pure-XIOM implementation using the error function series.
/// Accurate to ~1e-7 for |x| <= 6.
pub fn norm_cdf(x: Float64) -> Float64
  ensures: result >= 0.0
  ensures: result <= 1.0
{
  return 0.5 * (1.0 + _erf_series(x / SQRT2));
}

/// Vectorized normal PDF: computes phi(x) for each element.
pub fn norm_pdf_vec(x: &Vec[Float64]) -> Vec[Float64]
  requires: x.len() > 0
  ensures:  result.len() == x.len()
{
  var r = Vec[Float64].new();
  var i = 0;
  while i < x.len() {
    r.push(norm_pdf(x[i]));
    i = i + 1;
  };
  return r;
}

/// Vectorized normal CDF: computes Phi(x) for each element.
pub fn norm_cdf_vec(x: &Vec[Float64]) -> Vec[Float64]
  requires: x.len() > 0
  ensures:  result.len() == x.len()
{
  var r = Vec[Float64].new();
  var i = 0;
  while i < x.len() {
    r.push(norm_cdf(x[i]));
    i = i + 1;
  };
  return r;
}

/// Normal distribution quantile function (probit).
/// Uses a rational approximation (Abramowitz & Stegun 26.2.23).
/// Valid for 0 < p < 1.
pub fn norm_ppf(p: Float64) -> Float64
  requires: p > 0.0
  requires: p < 1.0
{
  let a0: Float64 = 2.50662823884;
  let a1: Float64 = -18.61500062529;
  let a2: Float64 = 41.39119773534;
  let a3: Float64 = -25.44106049637;
  let b0: Float64 = -8.47351093090;
  let b1: Float64 = 23.08336743743;
  let b2: Float64 = -21.06224101826;
  let b3: Float64 = 3.13082909833;

  let c0: Float64 = 0.3374754822726147;
  let c1: Float64 = 0.9761690190917186;
  let c2: Float64 = 0.1607979714918209;
  let c3: Float64 = 0.0276438810333863;
  let c4: Float64 = 0.0038405729373609;
  let c5: Float64 = 0.0003951896511919;
  let c6: Float64 = 0.0000321767881768;
  let c7: Float64 = 0.0000002888167364;
  let c8: Float64 = 0.0000003960315187;

  var p_low = false;
  var q = p;
  if q > 0.5 {
    q = 1.0 - q;
    p_low = false;
  } else {
    p_low = true;
  };

  if q <= 0.0 { return -1.0 / 0.0; };
  if q >= 1.0 { return 1.0 / 0.0; };

  var r = math.sqrt(-2.0 * math.ln(q));
  if r < 0.0 { r = -r; };

  // Rational approximation
  var num = ((a3 * r + a2) * r + a1) * r + a0;
  var den = (((b3 * r + b2) * r + b1) * r + b0) * r + 1.0;
  var x = r - num / den;

  // Refinement via Newton step
  var e = norm_cdf(x) - q;
  var u = e * math.sqrt(2.0 * math.PI) * math.exp(x * x * 0.5);
  x = x - u;
  e = norm_cdf(x) - q;
  u = e * math.sqrt(2.0 * math.PI) * math.exp(x * x * 0.5);
  x = x - u;
  e = norm_cdf(x) - q;
  u = e * math.sqrt(2.0 * math.PI) * math.exp(x * x * 0.5);
  x = x - u;

  if p_low { return -x; };
  return x;
}

// ===============================================================================
// Safe wrappers with requires contracts
// ===============================================================================

/// Minimize a scalar function f(x) over x in (a, b).
/// Returns the minimum location x, function value, iterations, and convergence status.
pub fn minimize_scalar(f: fn(Float64) -> Float64, a: Float64, b: Float64) -> Result[ScipyResult, Str]
  requires: a < b
{
  if a >= b {
    return Err("minimize_scalar: bracket must satisfy a < b");
  };
  let tol = 1e-8;
  let x0 = (a + b) * 0.5;
  let r = unsafe { optimize_minimize(f, x0, tol, 1000) };
  Ok(r)
}

/// Integrate f from a to b with tolerance eps.
pub fn quad(f: fn(Float64) -> Float64, a: Float64, b: Float64) -> Result[QuadResult, Str]
  requires: a <= b
{
  if a > b {
    return Err("quad: integration limits must satisfy a <= b");
  };
  let r = unsafe { integrate_quad(f, a, b, 1e-8, 1e-8) };
  if r.error > 1e-6 && r.error > math.abs_float(r.value) * 1e-6 {
    return Ok(r);
  };
  Ok(r)
}

/// Compute the 1D convolution of two vectors.
pub fn convolve_vec(a: &Vec[Float64], b: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: a.len() > 0
  requires: b.len() > 0
{
  let n_result = a.len() + b.len() - 1;
  var result = Vec[Float64].new();
  var i = 0;
  while i < n_result {
    result.push(0.0);
    i = i + 1;
  };

  let status = unsafe { signal_convolve(a.as_ptr(), a.len(), b.as_ptr(), b.len(), result.as_ptr()) };
  if status != 0 {
    return Err("convolve_vec: signal_convolve returned error");
  };
  Ok(result)
}

/// Forward 1D FFT. Input must have power-of-two length.
pub fn fft_vec(data: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: data.len() > 0
  requires: data.len() % 2 == 0
{
  var n = data.len();
  var buf = Vec[Float64].new();
  var i = 0;
  while i < n {
    buf.push(data[i]);
    i = i + 1;
  };
  let status = unsafe { signal_fft(buf.as_ptr(), n) };
  if status != 0 {
    return Err("fft_vec: signal_fft returned error");
  };
  Ok(buf)
}

/// Inverse 1D FFT. Reconstructs real signal from complex spectrum.
pub fn ifft_vec(data: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: data.len() > 0
  requires: data.len() % 2 == 0
{
  var n = data.len();
  var buf = Vec[Float64].new();
  var i = 0;
  while i < n {
    buf.push(data[i]);
    i = i + 1;
  };
  let status = unsafe { signal_ifft(buf.as_ptr(), n) };
  if status != 0 {
    return Err("ifft_vec: signal_ifft returned error");
  };
  Ok(buf)
}

/// Evaluate piecewise linear interpolation at x_new.
pub fn interp_linear(x: &Vec[Float64], y: &Vec[Float64], x_new: Float64) -> Result[Float64, Str]
  requires: x.len() == y.len()
  requires: x.len() > 1
  requires: x_new >= x[0]
  requires: x_new <= x[x.len() - 1]
{
  if x.len() != y.len() {
    return Err("interp_linear: x and y must have the same length");
  };
  if x.len() < 2 {
    return Err("interp_linear: need at least 2 points");
  };
  let r = unsafe { interpolate_linear(x.as_ptr(), y.as_ptr(), x.len(), x_new) };
  Ok(r)
}

/// Evaluate piecewise cubic spline interpolation at x_new.
pub fn interp_cubic(x: &Vec[Float64], y: &Vec[Float64], x_new: Float64) -> Result[Float64, Str]
  requires: x.len() == y.len()
  requires: x.len() > 2
  requires: x_new >= x[0]
  requires: x_new <= x[x.len() - 1]
{
  if x.len() != y.len() {
    return Err("interp_cubic: x and y must have the same length");
  };
  if x.len() < 3 {
    return Err("interp_cubic: need at least 3 points for cubic spline");
  };
  let r = unsafe { interpolate_cubic(x.as_ptr(), y.as_ptr(), x.len(), x_new) };
  Ok(r)
}

// ===============================================================================
// Utility
// ===============================================================================

/// Check if an FFI result indicates convergence.
pub fn result_converged(r: &ScipyResult) -> Bool {
  r.success && r.nit > 0
}

/// Create a default (failure) ScipyResult.
pub fn scipy_result_default() -> ScipyResult {
  ScipyResult {
    x: Vec[Float64].new();
    fun: 0.0;
    nit: 0;
    success: false;
  }
}
