// XIOM -- xiom.mechanics: deterministic fixed-point classical mechanics
// Port task: greenfield pure-XIOM package (no FFI, no floats, no Vec[Float64]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   Every physical quantity is a 64-bit signed integer in units of 1e-4: the
//   scale factor is MECH_SCALE = 10000, so a raw value r denotes r / 10000
//   (position m, velocity m/s, time s, acceleration m/s^2, mass kg, force N,
//   energy J, momentum kg*m/s).
//
//   Products and quotients go through _mech_mul / _mech_div, each of which
//   performs exactly one truncating division:
//     _mech_mul(a, b) = (a * b) / MECH_SCALE    (truncated toward zero)
//     _mech_div(a, b) = (a * MECH_SCALE) / b    (truncated toward zero)
//   XIOM Int `/` truncates toward zero, so negative magnitudes round up
//   (toward zero). Every compounding step is documented per function; there
//   is no hidden rounding. Both helpers saturate to the Int64 ends when the
//   intermediate product would overflow, so they are total.
//
//   Integration is semi-implicit (symplectic) Euler on explicit ticks:
//   velocity is advanced first, then position uses the NEW velocity:
//     v1 = v + _mech_mul(a, dt);
//     x1 = x + _mech_mul(v1, dt);
//   For constant acceleration each tick therefore adds the full acceleration
//   term dt^2*a to the position, not the analytic dt^2*a/2: from rest after n
//   ticks x = a*dt^2*n*(n+1)/2. Tests pin the discrete values.
//
//   Collisions use the restitution form with e in basis points (0..10000,
//   where 10000 is a perfectly elastic collision):
//     u1 = ((m1 - e*m2)*v1 + (1 + e)*m2*v2) / (m1 + m2)
//     u2 = ((m2 - e*m1)*v2 + (1 + e)*m1*v1) / (m1 + m2)
//   Each term is evaluated with _mech_mul and the two numerator terms are
//   summed before the single _mech_div, so e = 0 gives the common
//   centre-of-mass velocity and e = 10000 the elastic exchange. Momentum and
//   energy audits allow a few raw units of drift (MECH_MOMENTUM_TOL,
//   MECH_ENERGY_TOL), one per rounded product.
//
//   Spring-damper integration adds the Hooke force and the viscous damping
//   force, then applies semi-implicit Euler. A stability guard rejects steps
//   outside the symplectic stability window: a step is accepted only when
//   dt^2 * (k/m) <= 4, evaluated with the same fixed-point helpers.
//
// Language notes (XIOM v0.62.2): free functions only; no `self`, no lambdas,
// no fn tables, no generics, no Vec at all (so no Vec[Float64],
// Vec[StructType] or Vec[Str]); Ok/Err are constructed only inside the
// _ok_*/_err_* leaf helpers; every public name is `mech_*` (no builtin- or
// stdlib-generic name shadows); Int division truncates toward zero (q/r form
// where a remainder is needed); every product is guarded against overflow.

module xiom.mechanics

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Raw units per unit: every quantity is scaled by 10000 (fixed point 1e-4).
pub const MECH_SCALE: Int = 10000;

/// Restitution of exactly 1.0 (perfectly elastic) in basis points.
pub const MECH_BPS_ONE: Int = 10000;

/// Maximum accepted tick count in mech_particle_step_n (termination bound).
pub const MECH_MAX_TICKS: Int = 1000000;

/// Momentum audit tolerance in raw units (a few rounded products).
pub const MECH_MOMENTUM_TOL: Int = 4;

/// Energy audit tolerance in raw units (a few rounded products).
pub const MECH_ENERGY_TOL: Int = 4;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Linear-motion state: `x` is the position in m and `v` the velocity in
/// m/s, both raw (value * MECH_SCALE).
pub type Particle = {
  x: Int;
  v: Int;
}

/// Post-collision velocities of a 1D two-body collision: `u1` and `u2` are
/// the new velocities in m/s, raw (value * MECH_SCALE).
pub type CollisionPair = {
  u1: Int;
  u2: Int;
}

// ---------------------------------------------------------------------------
// Particle state and constant-acceleration integration
// ---------------------------------------------------------------------------

/// Construct a particle state from raw position and velocity.
/// Params: x - raw position (m); v - raw velocity (m/s).
/// Returns: Particle{ x, v } unchanged.
/// Error case: none.
/// Complexity: O(1).
pub fn mech_particle_new(x: Int, v: Int) -> Particle {
  return Particle{ x: x; v: v; };
}

/// One semi-implicit (symplectic) Euler tick under constant acceleration.
/// Params: p - the state; a - raw acceleration (m/s^2); dt - raw tick (s).
/// Returns: Ok(state after one tick) with
///   v1 = p.v + _mech_mul(a, dt)              (one truncation),
///   x1 = p.x + _mech_mul(v1, dt)             (one truncation),
/// so the position uses the NEW velocity (symplectic order); for a = 0 the
/// tick is exact. Err when dt <= 0.
/// Error case: Err("mechanics: dt must be positive").
/// Complexity: O(1).
pub fn mech_particle_step(p: Particle, a: Int, dt: Int) -> Result[Particle, Str] {
  if dt <= 0 {
    return _err_particle("mechanics: dt must be positive");
  }
  let v1 = p.v + _mech_mul(a, dt);
  let x1 = p.x + _mech_mul(v1, dt);
  return _ok_particle(Particle{ x: x1; v: v1 });
}

/// `ticks` identical semi-implicit Euler ticks under constant acceleration.
/// Params: p - the state; a - raw acceleration (m/s^2); dt - raw tick (s);
/// ticks - number of ticks to apply (0..MECH_MAX_TICKS).
/// Returns: Ok(state after `ticks` ticks); ticks == 0 returns `p` unchanged.
/// Every tick applies mech_particle_step's recurrence, so the per-tick
/// truncations compound (`ticks` rounded velocity steps and `ticks` rounded
/// position steps). Err when dt <= 0 or ticks is outside 0..MECH_MAX_TICKS
/// (the cap is the termination bound: the loop always advances by one tick
/// and can never run longer than MECH_MAX_TICKS).
/// Error case: Err("mechanics: dt must be positive") or
/// Err("mechanics: tick count out of range").
/// Complexity: O(ticks).
pub fn mech_particle_step_n(p: Particle, a: Int, dt: Int, ticks: Int) -> Result[Particle, Str] {
  if dt <= 0 {
    return _err_particle("mechanics: dt must be positive");
  }
  if ticks < 0 || ticks > MECH_MAX_TICKS {
    return _err_particle("mechanics: tick count out of range");
  }
  var x = p.x;
  var v = p.v;
  var i = 0;
  while i < ticks {
    v = v + _mech_mul(a, dt);
    x = x + _mech_mul(v, dt);
    i = i + 1;
  }
  return _ok_particle(Particle{ x: x; v: v });
}

// ---------------------------------------------------------------------------
// Projectile range and apex (equal launch/landing height)
// ---------------------------------------------------------------------------

/// Apex height of a projectile launched with vertical velocity v0y.
/// Params: y0 - raw launch height (m); v0y - raw vertical velocity (m/s);
/// g - raw gravitational acceleration (m/s^2), must be positive.
/// Returns: Ok(y0 + v0y^2 / (2*g)) with a single truncating division (the
/// v0y^2 product is exact through _mech_mul). Err when g <= 0.
/// Error case: Err("mechanics: gravity must be positive").
/// Complexity: O(1).
pub fn mech_projectile_apex(y0: Int, v0y: Int, g: Int) -> Result[Int, Str] {
  if g <= 0 {
    return _err_int("mechanics: gravity must be positive");
  }
  let rise = _mech_div(_mech_mul(v0y, v0y), _mech_mul(g, 2 * MECH_SCALE));
  return _ok_int(y0 + rise);
}

/// Horizontal range of a projectile between equal launch and landing heights.
/// Params: x0 - raw launch position (m); v0x - raw horizontal velocity
/// (m/s); v0y - raw vertical velocity (m/s); g - raw gravitational
/// acceleration (m/s^2), must be positive.
/// Returns: Ok(x0 + v0x * t_flight) where
///   t_flight = _mech_div(_mech_mul(v0y, 2 * MECH_SCALE), g)
/// is the truncated flight time 2*v0y/g; the range multiplies that rounded
/// flight time by v0x (one further truncation). Err when g <= 0.
/// Error case: Err("mechanics: gravity must be positive").
/// Complexity: O(1).
pub fn mech_projectile_range(x0: Int, v0x: Int, v0y: Int, g: Int) -> Result[Int, Str] {
  if g <= 0 {
    return _err_int("mechanics: gravity must be positive");
  }
  let t_flight = _mech_div(_mech_mul(v0y, 2 * MECH_SCALE), g);
  let delta = _mech_mul(v0x, t_flight);
  return _ok_int(x0 + delta);
}

// ---------------------------------------------------------------------------
// 1D collisions with restitution in basis points
// ---------------------------------------------------------------------------

/// 1D two-body collision with restitution `restitution_bps` basis points.
/// Params: m1, m2 - raw masses (kg), each > 0 and with m1 + m2 in range;
/// v1, v2 - raw pre-collision velocities (m/s); restitution_bps - restitution
/// in basis points, 0..10000 (10000 = perfectly elastic, 0 = perfectly
/// inelastic). Returns: Ok(CollisionPair{ u1, u2 }) with
///   u1 = ((m1 - e*m2)*v1 + (1 + e)*m2*v2) / (m1 + m2)
///   u2 = ((m2 - e*m1)*v2 + (1 + e)*m1*v1) / (m1 + m2)
/// where e = restitution_bps / 10000 and each product is rounded by
/// _mech_mul before the single _mech_div per velocity. Err when a mass is
/// non-positive, the mass sum overflows, or the restitution is out of range.
/// Error case: Err("mechanics: mass must be positive"),
/// Err("mechanics: mass sum overflows"),
/// Err("mechanics: restitution must be in 0..10000 bps").
/// Complexity: O(1).
pub fn mech_collide_1d(m1: Int, v1: Int, m2: Int, v2: Int, restitution_bps: Int) -> Result[CollisionPair, Str] {
  let err = _mech_collision_error(m1, m2, restitution_bps);
  if err.len() > 0 {
    return _err_pair(err);
  }
  return _ok_pair(_mech_collide_vel(m1, v1, m2, v2, restitution_bps));
}

/// Perfectly elastic 1D collision (restitution 10000 bps, kinetic energy
/// conserved in exact arithmetic).
/// Params: m1, m2 - raw masses (kg); v1, v2 - raw velocities (m/s).
/// Returns: Ok(CollisionPair) exactly as mech_collide_1d with e = 1.
/// Error case: same guards as mech_collide_1d.
/// Complexity: O(1).
pub fn mech_collide_elastic_1d(m1: Int, v1: Int, m2: Int, v2: Int) -> Result[CollisionPair, Str] {
  return mech_collide_1d(m1, v1, m2, v2, MECH_BPS_ONE);
}

/// Perfectly inelastic 1D collision (restitution 0 bps): both bodies leave
/// with the common centre-of-mass velocity (m1*v1 + m2*v2) / (m1 + m2).
/// Params: m1, m2 - raw masses (kg); v1, v2 - raw velocities (m/s).
/// Returns: Ok(CollisionPair) exactly as mech_collide_1d with e = 0.
/// Error case: same guards as mech_collide_1d.
/// Complexity: O(1).
pub fn mech_collide_inelastic_1d(m1: Int, v1: Int, m2: Int, v2: Int) -> Result[CollisionPair, Str] {
  return mech_collide_1d(m1, v1, m2, v2, 0);
}

// ---------------------------------------------------------------------------
// Spring-damper integration with stability guard
// ---------------------------------------------------------------------------

/// Symplectic stability guard for a spring-damper tick.
/// Params: k - raw spring constant (N/m), must be >= 0; m - raw mass (kg),
/// must be > 0; dt - raw tick (s), must be > 0.
/// Returns: true when dt^2 * (k/m) <= 4 in fixed-point evaluation, i.e.
///   _mech_mul(_mech_mul(dt, dt), _mech_div(k, m)) <= 4 * MECH_SCALE;
/// false when m <= 0, k < 0 or dt <= 0. Damping only increases stability and
/// is not part of the guard. For k == 0 any positive dt is stable.
/// Error case: none (total).
/// Complexity: O(1).
pub fn mech_spring_stable(k: Int, m: Int, dt: Int) -> Bool {
  if m <= 0 {
    return false;
  }
  if k < 0 {
    return false;
  }
  if dt <= 0 {
    return false;
  }
  let omega_sq = _mech_div(k, m);
  let dt_sq = _mech_mul(dt, dt);
  let product = _mech_mul(dt_sq, omega_sq);
  return product <= 4 * MECH_SCALE;
}

/// One semi-implicit Euler tick of a damped spring: x'' = (-k*x - c*v) / m.
/// Params: x - raw displacement (m); v - raw velocity (m/s); k - raw spring
/// constant (N/m), >= 0; c - raw damping coefficient (N*s/m), >= 0; m - raw
/// mass (kg), > 0; dt - raw tick (s), > 0 and inside the stability window.
/// Returns: Ok(Particle{ x1, v1 }) with
///   force = -k*x - c*v, a = force / m,
///   v1 = v + a*dt, x1 = x + v1*dt,
/// each product rounded by _mech_mul and each quotient by _mech_div (the
/// acceleration is the only division). The position uses the NEW velocity.
/// Error case: Err("mechanics: mass must be positive"),
/// Err("mechanics: stiffness must be non-negative"),
/// Err("mechanics: damping must be non-negative"),
/// Err("mechanics: dt must be positive"),
/// Err("mechanics: unstable step: dt^2*k/m exceeds 4").
/// Complexity: O(1).
pub fn mech_spring_step(x: Int, v: Int, k: Int, c: Int, m: Int, dt: Int) -> Result[Particle, Str] {
  if m <= 0 {
    return _err_particle("mechanics: mass must be positive");
  }
  if k < 0 {
    return _err_particle("mechanics: stiffness must be non-negative");
  }
  if c < 0 {
    return _err_particle("mechanics: damping must be non-negative");
  }
  if dt <= 0 {
    return _err_particle("mechanics: dt must be positive");
  }
  if !mech_spring_stable(k, m, dt) {
    return _err_particle("mechanics: unstable step: dt^2*k/m exceeds 4");
  }
  let hooke = _mech_mul(k, x);
  let viscous = _mech_mul(c, v);
  let force = 0 - hooke - viscous;
  let a = _mech_div(force, m);
  let v1 = v + _mech_mul(a, dt);
  let x1 = x + _mech_mul(v1, dt);
  return _ok_particle(Particle{ x: x1; v: v1 });
}

// ---------------------------------------------------------------------------
// Work, energy and momentum accounting
// ---------------------------------------------------------------------------

/// Kinetic energy of a point mass: E_k = m*v^2/2.
/// Params: m - raw mass (kg), must be >= 0; v - raw velocity (m/s), sign
/// irrelevant (v is squared).
/// Returns: Ok(raw kinetic energy in J); the squared product is exact through
/// _mech_mul and a single /2 truncation follows. m == 0 gives 0.
/// Error case: Err("mechanics: mass must be non-negative").
/// Complexity: O(1).
pub fn mech_kinetic_energy(m: Int, v: Int) -> Result[Int, Str] {
  if m < 0 {
    return _err_int("mechanics: mass must be non-negative");
  }
  return _ok_int(_mech_kinetic_energy_raw(m, v));
}

/// Spring potential energy plus kinetic energy in one value:
/// E = k*x^2/2 + m*v^2/2.
/// Params: x - raw displacement (m); v - raw velocity (m/s); k - raw spring
/// constant (N/m), must be >= 0; m - raw mass (kg), must be >= 0.
/// Returns: Ok(raw mechanical energy in J), each half-term truncated by one
/// /2 division, then summed.
/// Error case: Err("mechanics: stiffness must be non-negative"),
/// Err("mechanics: mass must be non-negative").
/// Complexity: O(1).
pub fn mech_spring_energy(x: Int, v: Int, k: Int, m: Int) -> Result[Int, Str] {
  if k < 0 {
    return _err_int("mechanics: stiffness must be non-negative");
  }
  if m < 0 {
    return _err_int("mechanics: mass must be non-negative");
  }
  let pe = _mech_div(_mech_mul(_mech_mul(k, x), x), 2 * MECH_SCALE);
  let ke = _mech_kinetic_energy_raw(m, v);
  return _ok_int(pe + ke);
}

/// Gravitational potential energy near a uniform field: E_p = m*g*h.
/// Params: m - raw mass (kg); g - raw field strength (m/s^2); h - raw height
/// (m). Returns: raw potential energy in J, signed by m, g and h (the
/// reference height is the caller's choice). Two _mech_mul products, no
/// division; no guards (signed values preserved).
/// Error case: none.
/// Complexity: O(1).
pub fn mech_potential_energy(m: Int, g: Int, h: Int) -> Int {
  return _mech_mul(_mech_mul(m, g), h);
}

/// Work done by a constant force along a displacement: W = F*d.
/// Params: force - raw force (N); distance - raw displacement (m).
/// Returns: raw work in J, signed (an opposing force gives negative work).
/// One _mech_mul product, no division; no guards.
/// Error case: none.
/// Complexity: O(1).
pub fn mech_work(force: Int, distance: Int) -> Int {
  return _mech_mul(force, distance);
}

/// Linear momentum: p = m*v.
/// Params: m - raw mass (kg); v - raw velocity (m/s).
/// Returns: raw momentum in kg*m/s, signed by the inputs. One _mech_mul
/// product; no guards.
/// Error case: none.
/// Complexity: O(1).
pub fn mech_momentum(m: Int, v: Int) -> Int {
  return _mech_mul(m, v);
}

/// Total linear momentum of two bodies: m1*v1 + m2*v2.
/// Params: m1, m2 - raw masses (kg); v1, v2 - raw velocities (m/s).
/// Returns: raw total momentum in kg*m/s, signed. Two _mech_mul products and
/// one sum; no guards.
/// Error case: none.
/// Complexity: O(1).
pub fn mech_momentum_total2(m1: Int, v1: Int, m2: Int, v2: Int) -> Int {
  return _mech_mul(m1, v1) + _mech_mul(m2, v2);
}

/// Total mechanical energy accounting helper: ke + pe.
/// Params: ke - raw kinetic energy (J); pe - raw potential energy (J).
/// Returns: the raw sum, signed.
/// Error case: none.
/// Complexity: O(1).
pub fn mech_energy_total(ke: Int, pe: Int) -> Int {
  return ke + pe;
}

// ---------------------------------------------------------------------------
// Conservation checks and invariants
// ---------------------------------------------------------------------------

/// Whether a 1D collision conserves total momentum within tolerance.
/// Params: m1, m2 - raw masses (kg); v1, v2 - raw pre-collision velocities
/// (m/s); restitution_bps - 0..10000.
/// Returns: Ok(true) when |p_after - p_before| <= MECH_MOMENTUM_TOL, where
/// p = m1*v1 + m2*v2 before and p = m1*u1 + m2*u2 after the mech_collide_1d
/// pair; Ok(false) otherwise. Err on the mech_collide_1d guard errors.
/// Error case: Err("mechanics: mass must be positive"),
/// Err("mechanics: mass sum overflows"),
/// Err("mechanics: restitution must be in 0..10000 bps").
/// Complexity: O(1).
pub fn mech_momentum_conserved(m1: Int, v1: Int, m2: Int, v2: Int, restitution_bps: Int) -> Result[Bool, Str] {
  let err = _mech_collision_error(m1, m2, restitution_bps);
  if err.len() > 0 {
    return _err_bool(err);
  }
  let pair = _mech_collide_vel(m1, v1, m2, v2, restitution_bps);
  let before = _mech_mul(m1, v1) + _mech_mul(m2, v2);
  let after = _mech_mul(m1, pair.u1) + _mech_mul(m2, pair.u2);
  if _mech_abs(after - before) <= MECH_MOMENTUM_TOL {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Physical invariants of a 1D collision with restitution <= 1.
/// Params: m1, m2 - raw masses (kg); v1, v2 - raw pre-collision velocities
/// (m/s); restitution_bps - 0..10000.
/// Returns: Ok(true) when all three invariants hold for the mech_collide_1d
/// outcome within the documented tolerances:
///   I1 momentum: |p_after - p_before| <= MECH_MOMENTUM_TOL,
///   I2 energy:   ke_after <= ke_before + MECH_ENERGY_TOL (dissipative),
///   I3 relative speed: |u2 - u1| <= |v2 - v1| + MECH_MOMENTUM_TOL.
/// Ok(false) when any invariant is violated; Err on the mech_collide_1d
/// guard errors.
/// Error case: Err("mechanics: mass must be positive"),
/// Err("mechanics: mass sum overflows"),
/// Err("mechanics: restitution must be in 0..10000 bps").
/// Complexity: O(1).
pub fn mech_invariants_hold(m1: Int, v1: Int, m2: Int, v2: Int, restitution_bps: Int) -> Result[Bool, Str] {
  let err = _mech_collision_error(m1, m2, restitution_bps);
  if err.len() > 0 {
    return _err_bool(err);
  }
  let pair = _mech_collide_vel(m1, v1, m2, v2, restitution_bps);
  let p_before = _mech_mul(m1, v1) + _mech_mul(m2, v2);
  let p_after = _mech_mul(m1, pair.u1) + _mech_mul(m2, pair.u2);
  var ok = true;
  if _mech_abs(p_after - p_before) > MECH_MOMENTUM_TOL {
    ok = false;
  }
  let ke_before = _mech_kinetic_energy_raw(m1, v1) + _mech_kinetic_energy_raw(m2, v2);
  let ke_after = _mech_kinetic_energy_raw(m1, pair.u1) + _mech_kinetic_energy_raw(m2, pair.u2);
  if ke_after > ke_before + MECH_ENERGY_TOL {
    ok = false;
  }
  let rel_before = _mech_abs(v1 - v2);
  let rel_after = _mech_abs(pair.u1 - pair.u2);
  if rel_after > rel_before + MECH_MOMENTUM_TOL {
    ok = false;
  }
  return _ok_bool(ok);
}

// ---------------------------------------------------------------------------
// Private arithmetic helpers
// ---------------------------------------------------------------------------

const _MECH_INT_MAX: Int = 9223372036854775807;
const _MECH_INT_MIN: Int = 0 - 9223372036854775807 - 1;

// Absolute value, total at the Int64 ends (abs(min) saturates to max).
fn _mech_abs(x: Int) -> Int {
  if x < 0 {
    if x == _MECH_INT_MIN {
      return _MECH_INT_MAX;
    }
    return 0 - x;
  }
  return x;
}

// Fixed-point product: (a * b) / MECH_SCALE, truncated toward zero exactly
// once. The product is checked against the Int64 cap first, so saturation at
// the Int64 ends replaces wraparound for hostile inputs.
fn _mech_mul(a: Int, b: Int) -> Int {
  if a == 0 {
    return 0;
  }
  if b == 0 {
    return 0;
  }
  var same_sign = true;
  if a > 0 {
    if b < 0 {
      same_sign = false;
    }
  } else {
    if b > 0 {
      same_sign = false;
    }
  }
  if _mech_abs(a) > _MECH_INT_MAX / _mech_abs(b) {
    if same_sign {
      return _MECH_INT_MAX;
    }
    return _MECH_INT_MIN;
  }
  return (a * b) / MECH_SCALE;
}

// Fixed-point quotient: (a * MECH_SCALE) / b, truncated toward zero exactly
// once. b == 0 returns 0 (callers guard the physical divisions); the scaled
// numerator is checked against the Int64 cap first, with saturating output.
fn _mech_div(a: Int, b: Int) -> Int {
  if a == 0 {
    return 0;
  }
  if b == 0 {
    return 0;
  }
  var same_sign = true;
  if a > 0 {
    if b < 0 {
      same_sign = false;
    }
  } else {
    if b > 0 {
      same_sign = false;
    }
  }
  if _mech_abs(a) > _MECH_INT_MAX / MECH_SCALE {
    if same_sign {
      return _MECH_INT_MAX;
    }
    return _MECH_INT_MIN;
  }
  return (a * MECH_SCALE) / b;
}

// Shared collision validation: "" when usable, else the error message.
fn _mech_collision_error(m1: Int, m2: Int, restitution_bps: Int) -> Str {
  if m1 <= 0 {
    return "mechanics: mass must be positive";
  }
  if m2 <= 0 {
    return "mechanics: mass must be positive";
  }
  if m1 > _MECH_INT_MAX - m2 {
    return "mechanics: mass sum overflows";
  }
  if restitution_bps < 0 || restitution_bps > MECH_BPS_ONE {
    return "mechanics: restitution must be in 0..10000 bps";
  }
  return "";
}

// Restitution collision, validated by the callers. Each term is one _mech_mul
// product; the two numerator terms are summed before the single _mech_div, so
// exact fixtures are exact and e = 0 / e = 1 are the classical limits.
fn _mech_collide_vel(m1: Int, v1: Int, m2: Int, v2: Int, e_bps: Int) -> CollisionPair {
  let one_plus_e = MECH_SCALE + e_bps;
  let den = m1 + m2;
  let em1 = _mech_mul(e_bps, m1);
  let em2 = _mech_mul(e_bps, m2);
  let t1 = _mech_mul(m1 - em2, v1);
  let t2 = _mech_mul(_mech_mul(one_plus_e, m2), v2);
  let t3 = _mech_mul(m2 - em1, v2);
  let t4 = _mech_mul(_mech_mul(one_plus_e, m1), v1);
  let u1 = _mech_div(t1 + t2, den);
  let u2 = _mech_div(t3 + t4, den);
  return CollisionPair{ u1: u1; u2: u2 };
}

// Kinetic energy without guards: m*v^2/2, two _mech_mul products and one /2
// truncating division (callers validate the mass).
fn _mech_kinetic_energy_raw(m: Int, v: Int) -> Int {
  let mv = _mech_mul(m, v);
  let mvv = _mech_mul(mv, v);
  return _mech_div(mvv, 2 * MECH_SCALE);
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_particle(p: Particle) -> Result[Particle, Str] {
  return Ok(p);
}

fn _err_particle(msg: Str) -> Result[Particle, Str] {
  return Err(msg);
}

fn _ok_pair(p: CollisionPair) -> Result[CollisionPair, Str] {
  return Ok(p);
}

fn _err_pair(msg: Str) -> Result[CollisionPair, Str] {
  return Err(msg);
}

fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

fn _err_int(msg: Str) -> Result[Int, Str] {
  return Err(msg);
}

fn _ok_bool(b: Bool) -> Result[Bool, Str] {
  return Ok(b);
}

fn _err_bool(msg: Str) -> Result[Bool, Str] {
  return Err(msg);
}
