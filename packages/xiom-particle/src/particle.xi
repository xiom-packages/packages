// XIOM -- xiom.particle: fixed-capacity particle pool with integer kinematics
// Port task: replace the xiom.particle placeholder with a pure-XIOM module
// (no FFI, no rendering, no collisions).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Units (micro-units): positions and velocities are integer micro-units and
// micro-units per second; lifetimes are milliseconds. `dt_ms` milliseconds of
// motion add trunc(v * dt_ms / 1000) micro-units to a position, where trunc
// rounds toward zero. The pool is a struct of six parallel Vec[Int] arenas:
// slot i is live exactly when alive[i] != 0. Slots are never removed; a dead
// slot is simply overwritten by the next spawn. Free functions only --
// XIOM v0.61.x has no methods, and no Vec[StructType] is used anywhere.

module xiom.particle

/// Fixed-capacity particle pool backed by six parallel Vec[Int] arenas.
///
/// Every field is an internal implementation detail; callers must go through
/// the free functions below. All six vectors have the same length
/// (`particle_capacity`). Slot i is alive exactly when `alive[i] != 0`;
/// spawning writes the six fields of the first dead slot, and killing or
/// expiring clears `alive[i]` so the slot becomes reusable.
pub type ParticlePool = {
  xs: Vec[Int];
  ys: Vec[Int];
  vx: Vec[Int];
  vy: Vec[Int];
  life_ms: Vec[Int];
  alive: Vec[Int];
}

/// Create a pool with `capacity` zeroed slots.
/// Params: capacity - requested slot count, clamped to at least 1 so a pool
///         always has at least one slot.
/// Returns: a fresh ParticlePool with every slot dead and all fields zero.
/// Errors: none. Complexity: O(capacity).
pub fn particle_pool_new(capacity: Int) -> ParticlePool {
  var cap = capacity;
  if cap < 1 {
    cap = 1;
  }
  var xs = Vec[Int].new();
  var ys = Vec[Int].new();
  var vx = Vec[Int].new();
  var vy = Vec[Int].new();
  var life_ms = Vec[Int].new();
  var alive = Vec[Int].new();
  var i = 0;
  while i < cap {
    xs.push(0);
    ys.push(0);
    vx.push(0);
    vy.push(0);
    life_ms.push(0);
    alive.push(0);
    i = i + 1;
  }
  return ParticlePool{ xs: xs; ys: ys; vx: vx; vy: vy; life_ms: life_ms; alive: alive; };
}

/// Number of slots in the pool (the capacity passed to particle_pool_new,
/// clamped to at least 1). Complexity: O(1).
pub fn particle_capacity(p: &ParticlePool) -> Int {
  return p.xs.len();
}

/// Number of currently live slots. Complexity: O(capacity).
pub fn particle_alive_count(p: &ParticlePool) -> Int {
  var count = 0;
  var i = 0;
  while i < p.alive.len() {
    let a: Int = p.alive[i];
    if a != 0 {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Whether slot `i` holds a live particle.
/// Params: p - the pool; i - slot index.
/// Returns: true when i is in range and slot i is live; false otherwise
/// (including every out-of-range index). Complexity: O(1).
pub fn particle_is_alive(p: &ParticlePool, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= p.alive.len() {
    return false;
  }
  let a: Int = p.alive[i];
  return a != 0;
}

/// Spawn a particle into the first dead slot.
/// Params: p - the pool; x, y - initial position in micro-units; vx, vy -
///         velocity in micro-units per second; life_ms - lifetime in
///         milliseconds, clamped to at least 1.
/// Returns: the slot index that received the particle, or -1 when every slot
/// is live (the pool is unchanged then).
/// Errors: none. Complexity: O(capacity) first-fit scan.
pub fn particle_spawn(p: &mut ParticlePool, x: Int, y: Int, vx: Int, vy: Int, life_ms: Int) -> Int {
  var life = life_ms;
  if life < 1 {
    life = 1;
  }
  var i = 0;
  while i < p.alive.len() {
    let a: Int = p.alive[i];
    if a == 0 {
      p.xs[i] = x;
      p.ys[i] = y;
      p.vx[i] = vx;
      p.vy[i] = vy;
      p.life_ms[i] = life;
      p.alive[i] = 1;
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Advance every live slot by `dt_ms` milliseconds.
/// Params: p - the pool; dt_ms - elapsed time in milliseconds.
/// Semantics per live slot: x += vx * dt_ms / 1000 and
/// y += vy * dt_ms / 1000, each quotient truncated toward zero (so
/// -2997 / 1000 == -2 and 2999 / 1000 == 2); then life_ms -= dt_ms, and the
/// slot is cleared when the remaining life is <= 0. Motion is applied before
/// expiry, so a particle that dies on this update still moved on it, and each
/// update truncates independently (no fractional carry between updates).
/// dt_ms <= 0 is a no-op: negative dt would otherwise move particles
/// backwards and resurrect them.
/// Errors: none. Complexity: O(capacity).
pub fn particle_update(p: &mut ParticlePool, dt_ms: Int) {
  if dt_ms <= 0 {
    return;
  }
  var i = 0;
  while i < p.alive.len() {
    let a: Int = p.alive[i];
    if a != 0 {
      let px: Int = p.xs[i];
      let py: Int = p.ys[i];
      let vvx: Int = p.vx[i];
      let vvy: Int = p.vy[i];
      let life: Int = p.life_ms[i];
      let dx: Int = vvx * dt_ms / 1000;
      let dy: Int = vvy * dt_ms / 1000;
      p.xs[i] = px + dx;
      p.ys[i] = py + dy;
      let remaining: Int = life - dt_ms;
      p.life_ms[i] = remaining;
      if remaining <= 0 {
        p.alive[i] = 0;
      }
    }
    i = i + 1;
  }
}

/// Kill the particle in slot `i`.
/// Params: p - the pool; i - slot index.
/// Returns: true when slot i held a live particle and was cleared; false when
/// i is out of range or the slot was already dead. A killed slot has
/// alive = 0 and life_ms = 0 and is immediately reusable.
/// Errors: none. Complexity: O(1).
pub fn particle_kill(p: &mut ParticlePool, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= p.alive.len() {
    return false;
  }
  let a: Int = p.alive[i];
  if a == 0 {
    return false;
  }
  p.alive[i] = 0;
  p.life_ms[i] = 0;
  return true;
}

/// Clear the whole pool: every slot becomes dead and every field is zeroed,
/// so the pool is immediately reusable from slot 0.
/// Errors: none. Complexity: O(capacity).
pub fn particle_clear(p: &mut ParticlePool) {
  var i = 0;
  while i < p.alive.len() {
    p.xs[i] = 0;
    p.ys[i] = 0;
    p.vx[i] = 0;
    p.vy[i] = 0;
    p.life_ms[i] = 0;
    p.alive[i] = 0;
    i = i + 1;
  }
}

/// Position x of slot `i` in micro-units, or 0 when i is out of range.
/// Complexity: O(1).
pub fn particle_x(p: &ParticlePool, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= p.xs.len() {
    return 0;
  }
  let v: Int = p.xs[i];
  return v;
}

/// Position y of slot `i` in micro-units, or 0 when i is out of range.
/// Complexity: O(1).
pub fn particle_y(p: &ParticlePool, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= p.ys.len() {
    return 0;
  }
  let v: Int = p.ys[i];
  return v;
}

/// Remaining life of slot `i` in milliseconds, or 0 when i is out of range.
/// A dead slot reports its last stored value: 0 for a killed or exactly
/// expired slot, or a negative leftover when a large dt overshot its life.
/// Complexity: O(1).
pub fn particle_life_ms(p: &ParticlePool, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= p.life_ms.len() {
    return 0;
  }
  let v: Int = p.life_ms[i];
  return v;
}
