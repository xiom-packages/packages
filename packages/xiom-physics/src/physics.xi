// XIOM -- xiom.physics: introductory Newtonian mechanics in SI units.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI: every function is scalar Float64 arithmetic on SI units
// (meters, seconds, kilograms, newtons, joules, watts), plus the stdlib
// constant xiom.math.PI for the two geometry helpers. No vectors, no unit
// parsing, no relativity.
//
// Guard rules (module-wide, documented per function below and exercised by
// tests/test_conformance.xi):
//   * G1 duration: a time argument <= 0 returns 0.0 in every function that
//     takes one -- phys_velocity, phys_acceleration, phys_position,
//     phys_velocity_at and phys_power (a non-positive elapsed time is
//     rejected uniformly, so division by zero cannot occur and t == 0 is
//     deterministic);
//   * G2 radius: a radius < 0 returns 0.0 in phys_circle_area and
//     phys_sphere_volume (r == 0 returns 0.0 by the formula);
//   * G3 separation: r_m <= 0 returns 0.0 in phys_gravitational_force;
//   * G4 mass: a mass < 0 returns 0.0 in phys_kinetic_energy (E_k would be
//     negative, which is unphysical).
// Signed results are otherwise preserved: displacement, velocity, momentum,
// work and potential energy may be negative.

module xiom.physics

use xiom.math;

/// Newtonian constant of gravitation G, 6.674e-11 m^3 kg^-1 s^-2 (SI),
/// used by phys_gravitational_force.
pub const PHYS_G: Float64 = 6.674e-11;

/// Average speed: v = distance / time.
/// Params: distance_m - distance travelled in metres; time_s - elapsed time
/// in seconds.
/// Returns: distance_m / time_s in m/s; 0.0 when time_s <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_velocity(distance_m: Float64, time_s: Float64) -> Float64 {
  if time_s <= 0.0 { return 0.0; }
  return distance_m / time_s;
}

/// Average acceleration: a = delta_v / delta_t.
/// Params: delta_v - velocity change in m/s; delta_t - elapsed time in
/// seconds.
/// Returns: delta_v / delta_t in m/s^2; 0.0 when delta_t <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_acceleration(delta_v: Float64, delta_t: Float64) -> Float64 {
  if delta_t <= 0.0 { return 0.0; }
  return delta_v / delta_t;
}

/// SUVAT position at time t: s(t) = s0 + v0*t + a*t*t/2.
/// Params: s0 - initial position in m; v0 - initial velocity in m/s;
/// a - constant acceleration in m/s^2; t - elapsed time in seconds.
/// Returns: the position in m; 0.0 when t <= 0 (guard G1 applies to the
/// polynomial too, so t == 0 returns 0.0 rather than s0 -- read s0 directly
/// when the initial position is needed).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_position(s0: Float64, v0: Float64, a: Float64, t: Float64) -> Float64 {
  if t <= 0.0 { return 0.0; }
  return s0 + v0 * t + a * t * t / 2.0;
}

/// SUVAT velocity at time t: v(t) = v0 + a*t.
/// Params: v0 - initial velocity in m/s; a - constant acceleration in
/// m/s^2; t - elapsed time in seconds.
/// Returns: the velocity in m/s; 0.0 when t <= 0 (guard G1, so t == 0
/// returns 0.0 rather than v0).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_velocity_at(v0: Float64, a: Float64, t: Float64) -> Float64 {
  if t <= 0.0 { return 0.0; }
  return v0 + a * t;
}

/// Kinetic energy: E_k = m*v^2/2.
/// Params: mass_kg - mass in kilograms; velocity - speed in m/s.
/// Returns: the kinetic energy in joules; 0.0 when mass_kg < 0 (guard G4:
/// a negative mass would give a negative energy).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_kinetic_energy(mass_kg: Float64, velocity: Float64) -> Float64 {
  if mass_kg < 0.0 { return 0.0; }
  return 0.5 * mass_kg * velocity * velocity;
}

/// Gravitational potential energy near a uniform field: E_p = m*g*h.
/// Params: mass_kg - mass in kilograms; height_m - height above the chosen
/// reference in metres; g - gravitational field strength in m/s^2.
/// Returns: the potential energy in joules, signed by m, g and h (the
/// reference is the caller's choice, so the value may be negative).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_potential_energy(mass_kg: Float64, height_m: Float64, g: Float64) -> Float64 {
  return mass_kg * g * height_m;
}

/// Linear momentum: p = m*v.
/// Params: mass_kg - mass in kilograms; velocity - velocity in m/s.
/// Returns: the momentum in kg*m/s, signed by the velocity.
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_momentum(mass_kg: Float64, velocity: Float64) -> Float64 {
  return mass_kg * velocity;
}

/// Work done by a constant force along a displacement: W = F*d.
/// Params: force_n - force in newtons; distance_m - displacement in metres.
/// Returns: the work in joules, signed (a force opposing the displacement
/// gives negative work).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_work(force_n: Float64, distance_m: Float64) -> Float64 {
  return force_n * distance_m;
}

/// Average power: P = W/t.
/// Params: work_j - work in joules; time_s - elapsed time in seconds.
/// Returns: work_j / time_s in watts; 0.0 when time_s <= 0 (guard G1).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_power(work_j: Float64, time_s: Float64) -> Float64 {
  if time_s <= 0.0 { return 0.0; }
  return work_j / time_s;
}

/// Newtonian gravitational force magnitude: F = G*m1*m2/r^2 with G = PHYS_G
/// = 6.674e-11 m^3 kg^-1 s^-2 (SI).
/// Params: m1_kg, m2_kg - the two masses in kilograms; r_m - separation of
/// the centres in metres.
/// Returns: the force in newtons, signed by the masses as given; 0.0 when
/// r_m <= 0 (guard G3: the formula would otherwise divide by zero or hide
/// the sign of a negative separation).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_gravitational_force(m1_kg: Float64, m2_kg: Float64, r_m: Float64) -> Float64 {
  if r_m <= 0.0 { return 0.0; }
  return PHYS_G * m1_kg * m2_kg / (r_m * r_m);
}

/// Area of a circle: A = pi*r^2 with pi = xiom.math.PI.
/// Params: r_m - radius in metres.
/// Returns: the area in m^2; 0.0 when r_m < 0 (guard G2; r_m == 0 gives
/// 0.0 by the formula).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_circle_area(r_m: Float64) -> Float64 {
  if r_m < 0.0 { return 0.0; }
  return xiom.math.PI * r_m * r_m;
}

/// Volume of a sphere: V = 4*pi*r^3/3 with pi = xiom.math.PI.
/// Params: r_m - radius in metres.
/// Returns: the volume in m^3; 0.0 when r_m < 0 (guard G2; r_m == 0 gives
/// 0.0 by the formula).
/// Errors: none (total).
/// Complexity: O(1).
pub fn phys_sphere_volume(r_m: Float64) -> Float64 {
  if r_m < 0.0 { return 0.0; }
  return 4.0 / 3.0 * xiom.math.PI * r_m * r_m * r_m;
}
